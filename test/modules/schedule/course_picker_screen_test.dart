import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/core/module_cache.dart';
import 'package:notes_insa/core/time.dart';
import 'package:notes_insa/modules/schedule/course_picker_screen.dart';
import 'package:notes_insa/modules/schedule/hidden_courses_provider.dart';
import 'package:notes_insa/modules/schedule/hide_rule.dart';
import 'package:notes_insa/modules/schedule/schedule_event.dart';
import 'package:notes_insa/modules/schedule/schedule_provider.dart';
import 'package:notes_insa/theme/campus_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

ScheduleEvent _event({
  required String module,
  required String title,
  required String activityId,
  required int day,
  String room = '*111 (VPI)',
  List<String> teachers = const <String>['LEY OLIVIER'],
}) => ScheduleEvent(
  title: title,
  start: DateTime(2026, 9, day, 10),
  end: DateTime(2026, 9, day, 12),
  groups: const <String>[],
  teachers: teachers,
  module: module,
  room: room,
  uid: 'ADE60-$activityId-$day',
  activityId: activityId,
);

/// Anglais is split into a TD and a TP series, Analyse is not split. The TP
/// has its own teacher, so a search can match one series of a module.
final _events = <ScheduleEvent>[
  _event(module: 'Anglais 3', title: 'ANGLAIS_L', activityId: '422', day: 7),
  _event(module: 'Anglais 3', title: 'ANGLAIS_L', activityId: '422', day: 14),
  _event(
    module: 'Anglais 3',
    title: 'ANGLAIS_TP',
    activityId: '423',
    day: 9,
    room: 'Salle TP 2 A',
    teachers: const <String>['MARTIN CLAIRE'],
  ),
  _event(
    module: 'Analyse 3',
    title: 'Analyse 3_GHIJKL',
    activityId: '4276',
    day: 8,
    room: 'Amphi C',
    teachers: const <String>['CAMAR-EDDINE MOHAMED'],
  ),
];

ProviderContainer _container(List<ScheduleEvent> events) =>
    ProviderContainer.test(
      overrides: [
        scheduleProvider.overrideWith(
          (ref) => Stream<CachedEntry<List<ScheduleEvent>>>.value(
            CachedEntry<List<ScheduleEvent>>(data: events),
          ),
        ),
      ],
    );

void _sizeView(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Future<ProviderContainer> pump(
  WidgetTester tester, {
  List<ScheduleEvent>? events,
  CourseFilter filter = CourseFilter.all,
}) async {
  _sizeView(tester);
  final container = _container(events ?? _events);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: campusTheme(Brightness.light),
        home: CoursePickerScreen(initialFilter: filter),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

/// The picker pushed onto another screen, for what happens when it is popped.
Future<ProviderContainer> pushed(WidgetTester tester) async {
  _sizeView(tester);
  final container = _container(_events);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: campusTheme(Brightness.light),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const CoursePickerScreen(),
                ),
              ),
              child: const Text('ouvrir'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('ouvrir'));
  await tester.pumpAndSettle();
  return container;
}

/// A series row, which carries its switch itself.
Finder rowFor(String title) =>
    find.ancestor(of: find.text(title), matching: find.byType(SwitchListTile));

/// A module row, whose switch sits beside the body that folds it.
Finder moduleRow(String title) =>
    find.ancestor(of: find.text(title), matching: find.byType(ListTile)).first;

Finder switchIn(Finder row) =>
    find.descendant(of: row, matching: find.byType(Switch));

bool switchIsOn(WidgetTester tester, Finder row) =>
    tester.widget<Switch>(switchIn(row)).value;

Future<void> unfold(WidgetTester tester, String module) async {
  await tester.tap(find.text(module));
  await tester.pumpAndSettle();
}

Future<void> type(WidgetTester tester, String query) async {
  await tester.enterText(find.byType(TextField), query);
  await tester.pumpAndSettle();
}

Future<void> filterBy(WidgetTester tester, CourseFilter filter) async {
  await tester.tap(find.text(filter.label));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(initCampusTime);
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  group('folding', () {
    testWidgets('a split module opens folded', (tester) async {
      await pump(tester);
      expect(find.text('Anglais 3'), findsOneWidget);
      expect(find.text('ANGLAIS_L'), findsNothing);
      expect(find.text('ANGLAIS_TP'), findsNothing);
    });

    testWidgets('tapping the row unfolds it', (tester) async {
      await pump(tester);
      await unfold(tester, 'Anglais 3');
      expect(find.text('ANGLAIS_L'), findsOneWidget);
      expect(find.text('ANGLAIS_TP'), findsOneWidget);
    });

    testWidgets('tapping it again folds it back', (tester) async {
      await pump(tester);
      await unfold(tester, 'Anglais 3');
      await unfold(tester, 'Anglais 3');
      expect(find.text('ANGLAIS_L'), findsNothing);
    });

    testWidgets('a module ADE did not split has nothing to unfold', (
      tester,
    ) async {
      await pump(tester);
      expect(find.text('Analyse 3_GHIJKL'), findsOneWidget);
      expect(find.text('Analyse 3'), findsNothing);
      expect(find.text('CM · Analyse 3 · 1 séance'), findsOneWidget);
    });

    testWidgets('the folded row counts what it holds', (tester) async {
      await pump(tester);
      expect(find.text('2 séries · 3 séances'), findsOneWidget);
    });

    testWidgets('the series rows carry their guessed type', (tester) async {
      await pump(tester);
      await unfold(tester, 'Anglais 3');
      expect(find.text('TD · Anglais 3 · 2 séances'), findsOneWidget);
      expect(find.text('TP · Anglais 3 · 1 séance'), findsOneWidget);
    });

    testWidgets('a switch does not fold the row it is on', (tester) async {
      await pump(tester);
      await unfold(tester, 'Anglais 3');
      await tester.tap(switchIn(rowFor('ANGLAIS_TP')));
      await tester.pumpAndSettle();
      expect(find.text('ANGLAIS_L'), findsOneWidget);
    });
  });

  group('the folded row says what the switch cannot', () {
    testWidgets('part of a module hidden is named on the parent', (
      tester,
    ) async {
      final container = await pump(tester);
      await container
          .read(hiddenRulesProvider.notifier)
          .add(
            const HideRule(
              field: HideField.series,
              value: '423',
              label: 'ANGLAIS_TP',
            ),
          );
      await tester.pumpAndSettle();

      expect(find.text('2 séries · 1 masquée'), findsOneWidget);
      // The parent switch is still on, which is why the subtitle has to say it.
      expect(switchIsOn(tester, moduleRow('Anglais 3')), isTrue);
    });

    testWidgets('all of it hidden is the switch, not the subtitle', (
      tester,
    ) async {
      final container = await pump(tester);
      await container
          .read(hiddenRulesProvider.notifier)
          .add(HideRule.module(_events.first));
      await tester.pumpAndSettle();

      expect(find.text('2 séries · 3 séances'), findsOneWidget);
      expect(switchIsOn(tester, moduleRow('Anglais 3')), isFalse);
    });
  });

  group('switching', () {
    testWidgets('the parent hides the whole module while folded', (
      tester,
    ) async {
      final container = await pump(tester);
      await tester.tap(switchIn(moduleRow('Anglais 3')));
      await tester.pumpAndSettle();

      final rules = container.read(hiddenRulesProvider);
      expect(rules.single.field, HideField.module);
      expect(rules.single.value, 'anglais 3');
    });

    testWidgets('hiding the module switches its series off too', (
      tester,
    ) async {
      await pump(tester);
      await tester.tap(switchIn(moduleRow('Anglais 3')));
      await tester.pumpAndSettle();
      await unfold(tester, 'Anglais 3');

      for (final title in <String>['ANGLAIS_L', 'ANGLAIS_TP']) {
        expect(switchIsOn(tester, rowFor(title)), isFalse);
      }
    });

    testWidgets('one series can go without the rest of the module', (
      tester,
    ) async {
      final container = await pump(tester);
      await unfold(tester, 'Anglais 3');
      await tester.tap(switchIn(rowFor('ANGLAIS_TP')));
      await tester.pumpAndSettle();

      expect(container.read(hiddenRulesProvider).single.value, '423');
      expect(switchIsOn(tester, rowFor('ANGLAIS_L')), isTrue);
      expect(switchIsOn(tester, moduleRow('Anglais 3')), isTrue);
    });
  });

  group('lifting more than the row promised', () {
    testWidgets('a series hidden on its own is named when the parent lifts it', (
      tester,
    ) async {
      final container = await pump(tester);
      final notifier = container.read(hiddenRulesProvider.notifier);
      await notifier.add(
        const HideRule(
          field: HideField.series,
          value: '423',
          label: 'ANGLAIS_TP',
        ),
      );
      await tester.pumpAndSettle();

      // Off, then on again: the module rule goes, and the series rule with it.
      await tester.tap(switchIn(moduleRow('Anglais 3')));
      await tester.pumpAndSettle();
      await tester.tap(switchIn(moduleRow('Anglais 3')));
      await tester.pumpAndSettle();

      expect(container.read(hiddenRulesProvider), isEmpty);
      expect(find.text('ANGLAIS_TP affiché'), findsOneWidget);
    });

    testWidgets('and can be put back', (tester) async {
      final container = await pump(tester);
      const hidden = HideRule(
        field: HideField.series,
        value: '423',
        label: 'ANGLAIS_TP',
      );
      await container.read(hiddenRulesProvider.notifier).add(hidden);
      await tester.pumpAndSettle();

      await tester.tap(switchIn(moduleRow('Anglais 3')));
      await tester.pumpAndSettle();
      await tester.tap(switchIn(moduleRow('Anglais 3')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();

      expect(container.read(hiddenRulesProvider), contains(hidden));
    });

    testWidgets('a broader rule is named when it is lifted', (tester) async {
      final container = await pump(tester);
      await container
          .read(hiddenRulesProvider.notifier)
          .add(HideRule.teacher('LEY OLIVIER'));
      await tester.pumpAndSettle();

      await unfold(tester, 'Anglais 3');
      await tester.tap(switchIn(rowFor('ANGLAIS_L')));
      await tester.pumpAndSettle();

      expect(find.textContaining('LEY OLIVIER'), findsWidgets);
      expect(container.read(hiddenRulesProvider), isEmpty);
    });

    testWidgets('a plain toggle says nothing', (tester) async {
      await pump(tester);
      await unfold(tester, 'Anglais 3');
      await tester.tap(switchIn(rowFor('ANGLAIS_TP')));
      await tester.pumpAndSettle();
      await tester.tap(switchIn(rowFor('ANGLAIS_TP')));
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('the message goes on its own, quickly', (tester) async {
      final container = await pump(tester);
      await container
          .read(hiddenRulesProvider.notifier)
          .add(HideRule.teacher('LEY OLIVIER'));
      await tester.pumpAndSettle();

      await unfold(tester, 'Anglais 3');
      await tester.tap(switchIn(rowFor('ANGLAIS_L')));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 1600));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('the message leaves with the screen', (tester) async {
      final container = await pushed(tester);
      await container
          .read(hiddenRulesProvider.notifier)
          .add(HideRule.teacher('LEY OLIVIER'));
      await tester.pumpAndSettle();

      await unfold(tester, 'Anglais 3');
      await tester.tap(switchIn(rowFor('ANGLAIS_L')));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
    });
  });

  group('filtering', () {
    testWidgets('masqués keeps only what is off, unfolded', (tester) async {
      final container = await pump(tester);
      await container
          .read(hiddenRulesProvider.notifier)
          .add(
            const HideRule(
              field: HideField.series,
              value: '423',
              label: 'ANGLAIS_TP',
            ),
          );
      await tester.pumpAndSettle();
      await filterBy(tester, CourseFilter.hidden);

      expect(find.text('ANGLAIS_TP'), findsOneWidget);
      expect(find.text('ANGLAIS_L'), findsNothing);
      expect(find.text('Analyse 3_GHIJKL'), findsNothing);
    });

    testWidgets('affichés drops what is off', (tester) async {
      final container = await pump(tester);
      await container
          .read(hiddenRulesProvider.notifier)
          .add(
            const HideRule(
              field: HideField.series,
              value: '423',
              label: 'ANGLAIS_TP',
            ),
          );
      await tester.pumpAndSettle();
      await filterBy(tester, CourseFilter.visible);

      expect(find.text('ANGLAIS_L'), findsOneWidget);
      expect(find.text('ANGLAIS_TP'), findsNothing);
    });

    testWidgets('with nothing hidden masqués says so', (tester) async {
      await pump(tester);
      await filterBy(tester, CourseFilter.hidden);
      expect(find.text('Rien n’est masqué'), findsOneWidget);
    });

    testWidgets('the screen can open on the hidden ones', (tester) async {
      final container = _container(_events);
      await container
          .read(hiddenRulesProvider.notifier)
          .add(
            const HideRule(
              field: HideField.series,
              value: '423',
              label: 'ANGLAIS_TP',
            ),
          );
      _sizeView(tester);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: campusTheme(Brightness.light),
            home: const CoursePickerScreen(initialFilter: CourseFilter.hidden),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('ANGLAIS_TP'), findsOneWidget);
      expect(find.text('Analyse 3_GHIJKL'), findsNothing);
    });
  });

  group('search', () {
    testWidgets('narrows to the matching module', (tester) async {
      await pump(tester);
      await type(tester, 'anglais');
      expect(find.text('ANGLAIS_L'), findsOneWidget);
      expect(find.text('Analyse 3_GHIJKL'), findsNothing);
    });

    testWidgets('a hit inside a folded module unfolds it', (tester) async {
      await pump(tester);
      await type(tester, 'martin');
      expect(find.text('Anglais 3'), findsOneWidget);
      expect(find.text('ANGLAIS_TP'), findsOneWidget);
      // The other series of the module does not match, so it stays out.
      expect(find.text('ANGLAIS_L'), findsNothing);
    });

    testWidgets('a hit on the module name keeps all of its series', (
      tester,
    ) async {
      await pump(tester);
      await type(tester, 'anglais 3');
      expect(find.text('ANGLAIS_L'), findsOneWidget);
      expect(find.text('ANGLAIS_TP'), findsOneWidget);
    });

    testWidgets('ignores accents and case', (tester) async {
      await pump(tester);
      await type(tester, 'ANALYSE');
      expect(find.text('Analyse 3_GHIJKL'), findsOneWidget);
    });

    testWidgets('finds a course by its teacher', (tester) async {
      await pump(tester);
      await type(tester, 'camar');
      expect(find.text('Analyse 3_GHIJKL'), findsOneWidget);
      expect(find.text('Anglais 3'), findsNothing);
    });

    testWidgets('says so when nothing matches', (tester) async {
      await pump(tester);
      await type(tester, 'zzz');
      expect(find.text('Aucun résultat'), findsOneWidget);
    });

    testWidgets('clearing brings everything back, folded', (tester) async {
      await pump(tester);
      await type(tester, 'martin');
      await tester.tap(find.byTooltip('Effacer'));
      await tester.pumpAndSettle();
      expect(find.text('Analyse 3_GHIJKL'), findsOneWidget);
      expect(find.text('ANGLAIS_TP'), findsNothing);
    });
  });

  testWidgets('the header fits a narrow phone', (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: _container(_events),
        child: MaterialApp(
          theme: campusTheme(Brightness.light),
          home: const CoursePickerScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('with no timetable it says what to do first', (tester) async {
    await pump(tester, events: const <ScheduleEvent>[]);
    expect(find.text('Aucun cours chargé'), findsOneWidget);
  });
}
