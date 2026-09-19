import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/search_text.dart';
import '../../theme/campus_context.dart';
import '../../theme/state_view.dart';
import '../../theme/tokens.dart';
import 'hidden_courses_provider.dart';
import 'hide_course_sheet.dart';
import 'hide_rule.dart';

/// Which slice of the catalogue the list shows.
enum CourseFilter {
  all('Tous'),
  hidden('Masqués'),
  visible('Affichés');

  const CourseFilter(this.label);

  final String label;
}

/// Browse everything ADE published for the chosen groups and switch off what
/// is not yours.
///
/// Its own screen rather than a section of the settings list: a semester runs
/// to a couple of dozen series, which is several screens of switches above the
/// four rows that are actually reviewed.
///
/// Modules start folded, so the screen opens on the list of modules rather
/// than on every series at once. A folded row still carries its own switch and
/// says how many of its series are off, or folding would hide the answer the
/// screen exists to give.
class CoursePickerScreen extends ConsumerStatefulWidget {
  const CoursePickerScreen({super.key, this.initialFilter = CourseFilter.all});

  /// What the screen opens on, so the hidden courses screen can land straight
  /// on what it counted.
  final CourseFilter initialFilter;

  @override
  ConsumerState<CoursePickerScreen> createState() => _CoursePickerScreenState();
}

/// A module and the series to draw under it, which a search or a filter can
/// narrow to part of the module.
typedef _Shown = ({CourseModule module, List<CourseSeries> series});

class _CoursePickerScreenState extends ConsumerState<CoursePickerScreen> {
  final TextEditingController _search = TextEditingController();

  /// Keyed by CourseModule.key, so unfolding survives the rebuild every
  /// switch triggers.
  final Set<String> _unfolded = <String>{};

  late CourseFilter _filter = widget.initialFilter;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// Matches the summary ADE prints and the teachers, so a series can be
  /// found by whichever of those the student remembers.
  bool _seriesMatches(CourseSeries series, String query) {
    if (query.isEmpty) return true;
    final haystack = StringBuffer('${series.label} ${series.module ?? ''}');
    for (final event in series.events) {
      haystack.write(' ${event.teachers.join(' ')}');
    }
    return foldForSearch(haystack.toString()).contains(query);
  }

  bool _passesFilter(CourseSeries series, List<HideRule> rules) =>
      switch (_filter) {
        CourseFilter.all => true,
        CourseFilter.hidden => series.isHiddenBy(rules),
        CourseFilter.visible => !series.isHiddenBy(rules),
      };

  List<_Shown> _shown(List<CourseModule> modules, List<HideRule> rules) {
    final query = foldForSearch(_search.text);
    final shown = <_Shown>[];
    for (final module in modules) {
      // A hit on the module name keeps the whole module, so its series are
      // not silently cut down to the ones spelling the query out.
      final named = query.isEmpty || foldForSearch(module.name).contains(query);
      final series = <CourseSeries>[
        for (final s in module.series)
          if ((named || _seriesMatches(s, query)) && _passesFilter(s, rules)) s,
      ];
      if (series.isEmpty) continue;
      shown.add((module: module, series: series));
    }
    return shown;
  }

  /// Narrowing the list unfolds it: a match inside a folded module would
  /// otherwise look like no match at all.
  bool get _forceUnfold =>
      _search.text.isNotEmpty || _filter != CourseFilter.all;

  @override
  Widget build(BuildContext context) {
    final modules = ref.watch(courseModulesProvider);
    final rules = ref.watch(hiddenRulesProvider);
    final shown = _shown(modules, rules);

    // Its own messenger, so a snackbar raised here leaves with the screen
    // instead of floating over the one behind it.
    return ScaffoldMessenger(
      child: Scaffold(
        appBar: AppBar(title: const Text('Cours de la période')),
        body: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                CampusSpacing.gutter,
                CampusSpacing.x2,
                CampusSpacing.gutter,
                CampusSpacing.x2,
              ),
              child: TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: 'Chercher un cours ou un enseignant',
                  border: const OutlineInputBorder(),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close),
                          tooltip: 'Effacer',
                          onPressed: () => setState(_search.clear),
                        ),
                ),
              ),
            ),
            if (modules.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: CampusSpacing.x2),
                child: SegmentedButton<CourseFilter>(
                  segments: <ButtonSegment<CourseFilter>>[
                    for (final filter in CourseFilter.values)
                      ButtonSegment<CourseFilter>(
                        value: filter,
                        label: Text(filter.label),
                      ),
                  ],
                  selected: <CourseFilter>{_filter},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => setState(() => _filter = s.first),
                ),
              ),
            Expanded(
              child: modules.isEmpty
                  ? const StateView(
                      icon: Icons.event_busy_outlined,
                      title: 'Aucun cours chargé',
                      body:
                          'Choisissez un groupe, puis revenez ici pour masquer '
                          'ce que vous ne suivez pas.',
                    )
                  : shown.isEmpty
                  ? _emptyResult()
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: CampusSpacing.x8),
                      itemCount: shown.length,
                      itemBuilder: (context, i) => _ModuleTile(
                        module: shown[i].module,
                        series: shown[i].series,
                        rules: rules,
                        unfolded:
                            _forceUnfold ||
                            _unfolded.contains(shown[i].module.key),
                        onFold: () => setState(() {
                          final key = shown[i].module.key;
                          if (!_unfolded.remove(key)) _unfolded.add(key);
                        }),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyResult() {
    if (_search.text.isNotEmpty) {
      return StateView(
        icon: Icons.search_off_outlined,
        title: 'Aucun résultat',
        body: 'Rien ne correspond à « ${_search.text.trim()} ».',
      );
    }
    return switch (_filter) {
      CourseFilter.hidden => const StateView(
        icon: Icons.visibility_outlined,
        title: 'Rien n’est masqué',
        body: 'Tous les cours de la période sont sur l’emploi du temps.',
      ),
      _ => const StateView(
        icon: Icons.visibility_off_outlined,
        title: 'Tout est masqué',
        body: 'Aucun cours de la période n’est affiché.',
      ),
    };
  }
}

/// A module ADE split into several series folds open into a switch per
/// series, which is the module and series level of a rule side by side.
class _ModuleTile extends ConsumerWidget {
  const _ModuleTile({
    required this.module,
    required this.series,
    required this.rules,
    required this.unfolded,
    required this.onFold,
  });

  final CourseModule module;

  /// What a search or a filter left of the module, which is all of it when
  /// neither is narrowing.
  final List<CourseSeries> series;
  final List<HideRule> rules;
  final bool unfolded;
  final VoidCallback onFold;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (module.isSingle) {
      final single = series.single;
      return _Row(
        title: single.label,
        subtitle: seriesSubtitle(single),
        visible: !single.isHiddenBy(rules),
        onChanged: (visible) => unawaited(
          _set(
            context,
            ref,
            visible: visible,
            rule: single.rule,
            affecting: single.rulesAffecting(rules),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // The row body folds and the switch hides, so reaching for one cannot
        // fire the other: only the switch takes the module off the timetable.
        ListTile(
          contentPadding: const EdgeInsets.only(
            left: CampusSpacing.x2,
            right: CampusSpacing.gutter,
          ),
          leading: AnimatedRotation(
            turns: unfolded ? 0.5 : 0,
            duration: CampusMotion.of(context, CampusMotion.fast),
            child: const Icon(Icons.expand_more),
          ),
          title: Text(
            module.name,
            style: context.text.titleMedium,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            moduleSubtitle(module, rules),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Switch(
            value: !module.isHiddenBy(rules),
            onChanged: (visible) => unawaited(
              _set(
                context,
                ref,
                visible: visible,
                rule: module.rule,
                affecting: module.rulesAffecting(rules),
              ),
            ),
          ),
          onTap: onFold,
        ),
        if (unfolded)
          for (final s in series)
            _Row(
              title: s.label,
              subtitle: seriesSubtitle(s),
              visible: !s.isHiddenBy(rules),
              indented: true,
              onChanged: (visible) => unawaited(
                _set(
                  context,
                  ref,
                  visible: visible,
                  rule: s.rule,
                  affecting: s.rulesAffecting(rules),
                ),
              ),
            ),
      ],
    );
  }

  Future<void> _set(
    BuildContext context,
    WidgetRef ref, {
    required bool visible,
    required HideRule rule,
    required List<HideRule> affecting,
  }) async {
    final notifier = ref.read(hiddenRulesProvider.notifier);
    if (!visible) {
      await notifier.add(rule);
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    for (final active in affecting) {
      await notifier.remove(active);
    }
    // Rules this switch did not set are lifted with it, which brings back more
    // than the row promised. A folded module does that to its series without
    // showing them, so what went is named and can be put back.
    final lifted = <HideRule>[
      for (final active in affecting)
        if (active != rule) active,
    ];
    if (lifted.isEmpty) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          lifted.length == 1
              ? unhideMessage(lifted.first)
              : '${lifted.length} règles retirées',
        ),
        duration: kHideMessageDuration,
        persist: kHideMessagePersists,
        action: SnackBarAction(
          label: 'Annuler',
          onPressed: () => unawaited(_restore(notifier, affecting)),
        ),
      ),
    );
  }

  Future<void> _restore(
    HiddenRulesNotifier notifier,
    List<HideRule> rules,
  ) async {
    for (final rule in rules) {
      await notifier.add(rule);
    }
  }
}

String seriesSubtitle(CourseSeries series) => <String>[
  ?series.type?.label,
  ?series.module,
  frenchSessionCount(series.count),
].join(' · ');

/// What a folded module says about itself. Part hidden is the state the
/// parent switch cannot show, so it takes the line.
String moduleSubtitle(CourseModule module, List<HideRule> rules) {
  final hidden = module.hiddenCount(rules);
  final count = '${module.series.length} séries';
  if (hidden == 0 || hidden == module.series.length) {
    return '$count · ${frenchSessionCount(module.count)}';
  }
  return '$count · $hidden masquée${hidden > 1 ? 's' : ''}';
}

String frenchSessionCount(int count) =>
    count == 1 ? '1 séance' : '$count séances';

class _Row extends StatelessWidget {
  const _Row({
    required this.title,
    required this.subtitle,
    required this.visible,
    required this.onChanged,
    this.indented = false,
  });

  final String title;
  final String subtitle;
  final bool visible;
  final ValueChanged<bool> onChanged;
  final bool indented;

  @override
  Widget build(BuildContext context) => SwitchListTile(
    contentPadding: EdgeInsets.only(
      left: CampusSpacing.gutter + (indented ? CampusSpacing.x6 : 0),
      right: CampusSpacing.gutter,
    ),
    title: Text(
      title,
      style: indented ? null : context.text.titleMedium,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),
    subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
    value: visible,
    onChanged: onChanged,
  );
}
