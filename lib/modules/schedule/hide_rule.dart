import 'french_dates.dart';
import 'module_palette.dart';
import 'schedule_event.dart';

/// What a rule matches on.
enum HideField {
  /// One ADE course series. The default, and the only exact one.
  series,

  /// Every series sharing a module name.
  module,

  /// A single session.
  occurrence,
  teacher,
  titleContains,
  room,

  /// Announcements and handouts, which ADE publishes without a module.
  nonCourse,
}

/// One reason an event is not shown.
///
/// Every hide is stored as a rule, so a one tap hide and a hand written filter
/// are the same thing to everything downstream.
class HideRule {
  const HideRule({
    required this.field,
    required this.value,
    required this.label,
  });

  const HideRule.nonCourse()
    : field = HideField.nonCourse,
      value = '',
      label = 'Événements hors cours';

  HideRule.teacher(String name)
    : field = HideField.teacher,
      value = name.toLowerCase(),
      label = name;

  HideRule.titleContains(String text)
    : field = HideField.titleContains,
      value = text.toLowerCase(),
      label = text;

  HideRule.room(String text)
    : field = HideField.room,
      value = text.toLowerCase(),
      label = text;

  /// Null when ADE gave no activity id, which leaves nothing exact to key on.
  static HideRule? series(ScheduleEvent event) {
    final id = event.activityId;
    if (id == null) return null;
    return HideRule(field: HideField.series, value: id, label: event.title);
  }

  static HideRule module(ScheduleEvent event) {
    final name = event.module ?? event.title;
    return HideRule(
      field: HideField.module,
      value: ModulePalette.normalize(name),
      label: name,
    );
  }

  /// The date is part of the label: without it the row reads exactly like
  /// the module rule in the filter list.
  static HideRule? occurrence(ScheduleEvent event) {
    final uid = event.uid;
    if (uid == null) return null;
    return HideRule(
      field: HideField.occurrence,
      value: uid,
      label: '${event.module ?? event.title} · ${frenchDayMonth(event.start)}',
    );
  }

  final HideField field;

  /// Already lowercased for the fields that match loosely.
  final String value;

  /// What to call this rule in the list.
  final String label;

  bool matches(ScheduleEvent event) => switch (field) {
    HideField.series => event.activityId == value,
    HideField.module =>
      ModulePalette.normalize(event.module ?? event.title) == value,
    HideField.occurrence => event.uid == value,
    HideField.teacher => event.teachers.any(
      (t) => t.toLowerCase().contains(value),
    ),
    HideField.titleContains =>
      '${event.title} ${event.module ?? ''}'.toLowerCase().contains(value),
    HideField.room => event.room?.toLowerCase().contains(value) ?? false,
    HideField.nonCourse => event.module == null,
  };

  Map<String, dynamic> toJson() => <String, dynamic>{
    'field': field.name,
    'value': value,
    'label': label,
  };

  /// Null for anything unreadable, so a rule removed in a later release cannot
  /// brick a launch.
  static HideRule? fromJson(Map<String, dynamic> json) {
    final name = json['field'];
    final value = json['value'];
    final label = json['label'];
    if (name is! String || value is! String || label is! String) return null;
    for (final field in HideField.values) {
      if (field.name == name) {
        return HideRule(field: field, value: value, label: label);
      }
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is HideRule &&
      other.field == field &&
      other.value == value &&
      other.label == label;

  @override
  int get hashCode => Object.hash(field, value, label);
}

/// True when the catalogue already shows this rule as an off switch, so the
/// filter list does not list it a second time.
bool isCatalogueRule(HideRule rule) =>
    rule.field == HideField.series || rule.field == HideField.module;

bool isHidden(ScheduleEvent event, List<HideRule> rules) =>
    rules.any((r) => r.matches(event));

/// Every rule keeping [event] off the timetable, in the order they were set.
List<HideRule> rulesHiding(ScheduleEvent event, List<HideRule> rules) =>
    <HideRule>[
      for (final rule in rules)
        if (rule.matches(event)) rule,
    ];

List<ScheduleEvent> visibleEvents(
  List<ScheduleEvent> events,
  List<HideRule> rules,
) {
  if (rules.isEmpty) return events;
  return <ScheduleEvent>[
    for (final e in events)
      if (!isHidden(e, rules)) e,
  ];
}

List<ScheduleEvent> hiddenEvents(
  List<ScheduleEvent> events,
  List<HideRule> rules,
) => <ScheduleEvent>[
  for (final e in events)
    if (isHidden(e, rules)) e,
];
