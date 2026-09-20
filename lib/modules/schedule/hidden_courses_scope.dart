import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'hide_rule.dart';
import 'schedule_event.dart';

/// Gives the leaf widgets of the timetable the hide rules and the way to add
/// one, without threading a callback through every grid and list between.
class HiddenCoursesScope extends InheritedWidget {
  const HiddenCoursesScope({
    required this.rules,
    required this.onHide,
    required super.child,
    super.key,
  });

  final List<HideRule> rules;

  /// Opens the chooser for [event].
  final void Function(BuildContext context, ScheduleEvent event) onHide;

  bool hides(ScheduleEvent event) => isHidden(event, rules);

  static HiddenCoursesScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<HiddenCoursesScope>();

  @override
  bool updateShouldNotify(HiddenCoursesScope old) =>
      !listEquals(rules, old.rules);
}
