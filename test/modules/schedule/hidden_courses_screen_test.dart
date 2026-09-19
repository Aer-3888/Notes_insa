import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/core/module_cache.dart';
import 'package:notes_insa/core/time.dart';
import 'package:notes_insa/modules/schedule/course_picker_screen.dart';
import 'package:notes_insa/modules/schedule/hidden_courses_provider.dart';
import 'package:notes_insa/modules/schedule/hidden_courses_screen.dart';
import 'package:notes_insa/modules/schedule/hide_rule.dart';
import 'package:notes_insa/modules/schedule/schedule_event.dart';
import 'package:notes_insa/modules/schedule/schedule_provider.dart';
import 'package:notes_insa/theme/campus_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

ScheduleEvent _event(
  String module, {
  required int day,
  required String activityId,
  String room = '*111 (VPI)',
  String? title,
}) => ScheduleEvent(
  title: title ?? module,
  start: DateTime(2026, 9, day, 10),
  end: DateTime(2026, 9, day, 12),
  groups: const <String>[],
  teachers: const <String>['LEY OLIVIER'],
  module: module,
  room: room,
  uid: 'ADE60-$activityId-$day',
  activityId: activityId,
);

final _events = <ScheduleEvent>[
  _event('Anglais 3', day: 7, activityId: '422', title: 'ANGLAIS_L'),
  _event('Anglais 3', day: 14, activityId: '422', title: 'ANGLAIS_L'),
  _event('Analyse 3', day: 8, activityId: '4276', room: 'Amphi C'),
  ScheduleEvent(
    title: 'Reunion Info',
    start: DateTime(2026, 9, 9, 16),
    end: DateTime(2026, 9, 9, 17),
    groups: const <String>[],
    teachers: const <String>[],
    room: 'Amphi A',
  ),
];

Future<ProviderContainer> pump(
  WidgetTester tester, {
  List<ScheduleEvent>? events,
}) async {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final container = ProviderContainer.test(
    overrides: [
      scheduleProvider.overrideWith(
        (ref) => Stream<CachedEntry<List<ScheduleEvent>>>.value(
          CachedEntry<List<ScheduleEvent>>(data: events ?? _events),
        ),
      ),
    ],
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: campusTheme(Brightness.light),
        home: const HiddenCoursesScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  setUpAll(initCampusTime);
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets('the hors cours preset hides what has no module', (tester) async {
    final container = await pump(tester);
    await tester.tap(
      find.ancestor(
        of: find.text('Masquer les événements hors cours'),
        matching: find.byType(SwitchListTile),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      container.read(hiddenRulesProvider),
      contains(const HideRule.nonCourse()),
    );
  });

  testWidgets('a custom rule can be written by hand', (tester) async {
    final container = await pump(tester);
    await tester.tap(find.text('Ajouter un filtre'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'calculatrice');
    await tester.tap(find.text('Masquer'));
    await tester.pumpAndSettle();

    final rules = container.read(hiddenRulesProvider);
    expect(rules.single.field, HideField.titleContains);
    expect(rules.single.value, 'calculatrice');
  });

  testWidgets('an empty custom rule is refused', (tester) async {
    final container = await pump(tester);
    await tester.tap(find.text('Ajouter un filtre'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Masquer'));
    await tester.pumpAndSettle();
    expect(container.read(hiddenRulesProvider), isEmpty);
  });

  testWidgets('tout afficher clears every rule', (tester) async {
    final container = await pump(tester);
    await container
        .read(hiddenRulesProvider.notifier)
        .add(HideRule.teacher('LEY OLIVIER'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Tout afficher'));
    await tester.pumpAndSettle();
    expect(container.read(hiddenRulesProvider), isEmpty);
  });

  group('the rules list', () {
    testWidgets('a rule row says its kind and how far it reaches', (
      tester,
    ) async {
      final container = await pump(tester);
      await container
          .read(hiddenRulesProvider.notifier)
          .add(HideRule.room('amphi'));
      await tester.pumpAndSettle();
      // Analyse and the Réunion both sit in an amphi in this fixture.
      expect(find.text('Salle · 2 séances masquées'), findsOneWidget);
    });

    testWidgets('a broad rule shows its real reach', (tester) async {
      final container = await pump(tester);
      await container
          .read(hiddenRulesProvider.notifier)
          .add(HideRule.teacher('LEY OLIVIER'));
      await tester.pumpAndSettle();
      expect(find.text('Enseignant · 3 séances masquées'), findsOneWidget);
    });

    testWidgets('the preset is not repeated as a rule row', (tester) async {
      final container = await pump(tester);
      await container
          .read(hiddenRulesProvider.notifier)
          .add(const HideRule.nonCourse());
      await tester.pumpAndSettle();
      expect(find.text('Événements hors cours'), findsNothing);
      expect(find.text('1 séance masquée'), findsOneWidget);
    });

    testWidgets('with nothing hidden it teaches the gesture', (tester) async {
      await pump(tester);
      expect(find.textContaining('Appuyez longuement'), findsOneWidget);
    });

    testWidgets('a filter matching nothing loaded says so rather than zero', (
      tester,
    ) async {
      final container = await pump(tester);
      await container
          .read(hiddenRulesProvider.notifier)
          .add(HideRule.teacher('INCONNU'));
      await tester.pumpAndSettle();
      expect(
        find.text('Enseignant · Aucune séance dans la période chargée'),
        findsOneWidget,
      );
    });
  });

  group('the catalogue section', () {
    const hiddenSeries = HideRule(
      field: HideField.series,
      value: '422',
      label: 'ANGLAIS_L',
    );

    testWidgets('a series switched off there is counted, not listed', (
      tester,
    ) async {
      final container = await pump(tester);
      await container.read(hiddenRulesProvider.notifier).add(hiddenSeries);
      await tester.pumpAndSettle();

      expect(find.text('ANGLAIS_L'), findsNothing);
      expect(find.text('1 série masquée'), findsOneWidget);
    });

    testWidgets('the count opens the picker on what is hidden', (tester) async {
      final container = await pump(tester);
      await container.read(hiddenRulesProvider.notifier).add(hiddenSeries);
      await tester.pumpAndSettle();

      await tester.tap(find.text('1 série masquée'));
      await tester.pumpAndSettle();

      expect(find.byType(CoursePickerScreen), findsOneWidget);
      expect(find.text('ANGLAIS_L'), findsOneWidget);
      expect(find.text('Analyse 3'), findsNothing);
    });
  });

  group('the catalogue row', () {
    testWidgets('counts the modules and series behind it', (tester) async {
      await pump(tester);
      expect(find.text('Parcourir les cours de la période'), findsOneWidget);
      expect(find.text('3 modules · 3 séries'), findsOneWidget);
    });

    testWidgets('no course list is on this screen any more', (tester) async {
      await pump(tester);
      expect(find.text('ANGLAIS_L'), findsNothing);
      expect(find.byType(SwitchListTile), findsOneWidget);
    });

    testWidgets('opens the picker', (tester) async {
      await pump(tester);
      await tester.tap(find.text('Parcourir les cours de la période'));
      await tester.pumpAndSettle();
      expect(find.byType(CoursePickerScreen), findsOneWidget);
    });

    testWidgets('says so when no timetable is loaded', (tester) async {
      await pump(tester, events: const <ScheduleEvent>[]);
      expect(find.text('Aucun cours chargé'), findsOneWidget);
    });
  });
}
