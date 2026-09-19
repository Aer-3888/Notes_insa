import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'hide_rule.dart';
import 'module_palette.dart';
import 'schedule_event.dart';
import 'schedule_provider.dart';
import 'schedule_view_mode.dart';
import 'session_type.dart';

/// Small scalars, so they live in shared_preferences beside the group ids.
const String kHiddenRulesKey = 'schedule_hidden_rules';
const String kScheduleRevealHiddenKey = 'schedule_reveal_hidden';

/// The rules a student has set, in the order they set them.
///
/// A storage failure keeps whatever is in memory, the same policy as
/// ScheduleTintNotifier.
class HiddenRulesNotifier extends Notifier<List<HideRule>> {
  Future<void>? _loaded;

  @visibleForTesting
  Future<void> get loaded => _loaded ?? Future<void>.value();

  @override
  List<HideRule> build() {
    _loaded = _load();
    return const <HideRule>[];
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(kHiddenRulesKey) ?? const <String>[];
      state = <HideRule>[
        for (final entry in raw)
          if (_decode(entry) case final HideRule rule) rule,
      ];
    } catch (e) {
      if (kDebugMode) debugPrint('[HiddenRules] load failed: $e');
    }
  }

  static HideRule? _decode(String entry) {
    try {
      final json = jsonDecode(entry);
      return json is Map<String, dynamic> ? HideRule.fromJson(json) : null;
    } on FormatException {
      return null;
    }
  }

  Future<void> add(HideRule rule) async {
    if (state.contains(rule)) return;
    await _write(<HideRule>[...state, rule]);
  }

  Future<void> remove(HideRule rule) async =>
      _write(<HideRule>[...state.where((r) => r != rule)]);

  Future<void> clear() async => _write(const <HideRule>[]);

  Future<void> _write(List<HideRule> rules) async {
    state = rules;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(kHiddenRulesKey, <String>[
        for (final rule in rules) jsonEncode(rule.toJson()),
      ]);
    } catch (e) {
      if (kDebugMode) debugPrint('[HiddenRules] save failed: $e');
    }
  }
}

final hiddenRulesProvider =
    NotifierProvider<HiddenRulesNotifier, List<HideRule>>(
      HiddenRulesNotifier.new,
    );

/// Whether the timetable shows hidden sessions, dimmed, instead of dropping
/// them. Off by default.
class ScheduleRevealHiddenNotifier extends ScheduleFlagNotifier {
  ScheduleRevealHiddenNotifier() : super(kScheduleRevealHiddenKey, false);
}

final scheduleRevealHiddenProvider =
    NotifierProvider<ScheduleFlagNotifier, bool>(
      ScheduleRevealHiddenNotifier.new,
    );

/// One course series in the loaded window, as the management list shows it.
class CourseSeries {
  const CourseSeries({
    required this.rule,
    required this.label,
    required this.events,
    this.module,
    this.type,
  });

  /// What hiding this series stores.
  final HideRule rule;

  /// The summary ADE prints on the block.
  final String label;
  final List<ScheduleEvent> events;
  final String? module;
  final SessionType? type;

  int get count => events.length;

  /// True once nothing of this series is left on the timetable, whichever
  /// rule did it.
  bool isHiddenBy(List<HideRule> rules) =>
      events.every((e) => isHidden(e, rules));

  /// Every rule that takes out part of this series, so turning it back on
  /// can say what it removed.
  List<HideRule> rulesAffecting(List<HideRule> rules) => <HideRule>[
    for (final rule in rules)
      if (events.any(rule.matches)) rule,
  ];
}

/// One module in the loaded window, with the series ADE splits it into.
class CourseModule {
  const CourseModule({
    required this.name,
    required this.rule,
    required this.series,
  });

  /// The module name, or the summary when ADE gave none.
  final String name;

  /// Stable across rebuilds, so the picker can remember what is unfolded.
  String get key => rule.value;

  /// What hiding the whole module stores.
  final HideRule rule;
  final List<CourseSeries> series;

  int get count => series.fold(0, (total, s) => total + s.count);

  /// A module ADE did not split. It renders as one row rather than a parent
  /// with a single child under it.
  bool get isSingle => series.length == 1;

  bool isHiddenBy(List<HideRule> rules) =>
      series.every((s) => s.isHiddenBy(rules));

  /// How many of the series are off, which is what a folded row has to say
  /// for itself: the parent switch alone cannot tell part from none.
  int hiddenCount(List<HideRule> rules) =>
      series.where((s) => s.isHiddenBy(rules)).length;

  List<HideRule> rulesAffecting(List<HideRule> rules) => <HideRule>[
    for (final rule in rules)
      if (series.any((s) => s.events.any(rule.matches))) rule,
  ];
}

/// The window's series grouped by module, for the picker.
///
/// Reads the unfiltered timetable, or hiding a course would take it out of
/// the list that unhides it.
///
/// One provider over the feed rather than a chain of them: the series were
/// only ever grouped on the way to the modules, and nothing else read them.
final courseModulesProvider = Provider<List<CourseModule>>((ref) {
  final events = ref.watch(scheduleProvider).value?.data;
  if (events == null) return const <CourseModule>[];
  return courseModulesOf(events);
});

/// Groups [events] into series, then series into modules. Pure, so the
/// grouping can be read and tested without a container.
List<CourseModule> courseModulesOf(List<ScheduleEvent> events) {
  final bySeries = <String, List<ScheduleEvent>>{};
  for (final event in events) {
    final key =
        event.activityId ??
        ModulePalette.normalize(event.module ?? event.title);
    (bySeries[key] ??= <ScheduleEvent>[]).add(event);
  }

  final series = <CourseSeries>[
    for (final group in bySeries.values)
      CourseSeries(
        rule: HideRule.series(group.first) ?? HideRule.module(group.first),
        label: group.first.title,
        events: group,
        module: group.first.module,
        type: guessSessionType(group.first),
      ),
  ];
  series.sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));

  final byModule = <String, List<CourseSeries>>{};
  for (final one in series) {
    final key = ModulePalette.normalize(one.module ?? one.label);
    (byModule[key] ??= <CourseSeries>[]).add(one);
  }

  final modules = <CourseModule>[
    for (final group in byModule.values)
      CourseModule(
        name: group.first.module ?? group.first.label,
        rule: HideRule.module(group.first.events.first),
        series: group,
      ),
  ];
  modules.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return modules;
}

/// How many series are off across the whole catalogue.
int hiddenSeriesCount(List<CourseModule> modules, List<HideRule> rules) =>
    modules.fold(0, (total, m) => total + m.hiddenCount(rules));

/// Every session in the loaded window, so a rule can report its reach.
List<ScheduleEvent> eventsOfModules(List<CourseModule> modules) =>
    <ScheduleEvent>[
      for (final module in modules)
        for (final series in module.series) ...series.events,
    ];
