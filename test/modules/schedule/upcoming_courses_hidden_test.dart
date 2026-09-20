import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/core/module_cache.dart';
import 'package:notes_insa/core/time.dart';
import 'package:notes_insa/modules/schedule/hidden_courses_provider.dart';
import 'package:notes_insa/modules/schedule/hide_rule.dart';
import 'package:notes_insa/modules/schedule/schedule_event.dart';
import 'package:notes_insa/modules/schedule/schedule_provider.dart';
import 'package:notes_insa/modules/schedule/upcoming_courses_card.dart';
import 'package:notes_insa/theme/campus_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

ScheduleEvent _at(Duration fromNow, String title) {
  final start = campusNow().add(fromNow);
  return ScheduleEvent(
    title: title,
    start: start,
    end: start.add(const Duration(hours: 2)),
    groups: const <String>[],
    teachers: const <String>[],
    module: title,
    room: 'Amphi C',
  );
}

void main() {
  setUpAll(initCampusTime);
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  /// The card built against the real provider chain, with the timetable
  /// arriving after the first frame the way the network does.
  testWidgets('the card survives the timetable arriving mid build', (
    tester,
  ) async {
    final controller =
        StreamController<CachedEntry<List<ScheduleEvent>>>.broadcast();
    addTearDown(controller.close);

    final container = ProviderContainer.test(
      overrides: [scheduleProvider.overrideWith((ref) => controller.stream)],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: campusTheme(Brightness.light),
          home: const Scaffold(body: UpcomingCoursesCard()),
        ),
      ),
    );
    await tester.pump();

    controller.add(
      CachedEntry<List<ScheduleEvent>>(
        data: <ScheduleEvent>[
          _at(const Duration(hours: 1), 'Analyse 3'),
          _at(const Duration(hours: 4), 'Anglais 3'),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Analyse 3'), findsOneWidget);
  });

  testWidgets('a rule added while the card is on screen just removes a row', (
    tester,
  ) async {
    final container = ProviderContainer.test(
      overrides: [
        scheduleProvider.overrideWith(
          (ref) => Stream<CachedEntry<List<ScheduleEvent>>>.value(
            CachedEntry<List<ScheduleEvent>>(
              data: <ScheduleEvent>[
                _at(const Duration(hours: 1), 'Analyse 3'),
                _at(const Duration(hours: 4), 'Anglais 3'),
              ],
            ),
          ),
        ),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: campusTheme(Brightness.light),
          home: const Scaffold(body: UpcomingCoursesCard()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Anglais 3'), findsOneWidget);

    await container
        .read(hiddenRulesProvider.notifier)
        .add(HideRule.titleContains('anglais'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Anglais 3'), findsNothing);
    expect(find.text('Analyse 3'), findsOneWidget);
  });
}
