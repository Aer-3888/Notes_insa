import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/core/module_cache.dart';
import 'package:notes_insa/core/time.dart';
import 'package:notes_insa/modules/schedule/grid_block.dart';
import 'package:notes_insa/modules/schedule/hidden_courses_provider.dart';
import 'package:notes_insa/modules/schedule/hide_rule.dart';
import 'package:notes_insa/modules/schedule/schedule_event.dart';
import 'package:notes_insa/modules/schedule/schedule_provider.dart';
import 'package:notes_insa/modules/schedule/schedule_screen.dart';
import 'package:notes_insa/modules/schedule/schedule_view_mode.dart';
import 'package:notes_insa/theme/campus_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _PickedGroups extends SelectedGroups {
  @override
  List<int> build() => const <int>[1214];
}

/// Two sessions today, so the grid shows them whatever hour the suite runs.
ScheduleEvent _event(
  String module, {
  required int hour,
  required String activityId,
  String room = 'Amphi C',
}) {
  final now = campusNow();
  final start = DateTime(now.year, now.month, now.day, hour);
  return ScheduleEvent(
    title: module,
    start: start,
    end: start.add(const Duration(hours: 2)),
    groups: const <String>[],
    teachers: const <String>['LEY OLIVIER'],
    module: module,
    room: room,
    uid: 'ADE60-$activityId-$hour',
    activityId: activityId,
  );
}

List<ScheduleEvent> _events() => <ScheduleEvent>[
  _event('Analyse 3', hour: 10, activityId: '4276'),
  _event('Anglais 3', hour: 14, activityId: '422', room: '*111 (VPI)'),
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
      selectedGroupsProvider.overrideWith(_PickedGroups.new),
      scheduleProvider.overrideWith(
        (ref) => Stream<CachedEntry<List<ScheduleEvent>>>.value(
          CachedEntry<List<ScheduleEvent>>(data: events ?? _events()),
        ),
      ),
    ],
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: campusTheme(Brightness.light),
        home: const ScheduleScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

Future<void> hide(ProviderContainer container, HideRule rule) async {
  await container.read(hiddenRulesProvider.notifier).add(rule);
}

void main() {
  setUpAll(initCampusTime);
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets('nothing is hidden until a rule says so', (tester) async {
    await pump(tester);
    expect(find.text('Analyse 3'), findsOneWidget);
    expect(find.text('Anglais 3'), findsOneWidget);
    expect(find.byTooltip('Afficher les cours masqués'), findsNothing);
  });

  testWidgets('a hidden series leaves the grid', (tester) async {
    final container = await pump(tester);
    await hide(container, HideRule.titleContains('anglais'));
    await tester.pumpAndSettle();

    expect(find.text('Analyse 3'), findsOneWidget);
    expect(find.text('Anglais 3'), findsNothing);
  });

  testWidgets('the eye appears once something is hidden and brings it back', (
    tester,
  ) async {
    final container = await pump(tester);
    await hide(container, HideRule.titleContains('anglais'));
    await tester.pumpAndSettle();

    final reveal = find.byTooltip('Afficher les cours masqués');
    expect(reveal, findsOneWidget);
    await tester.tap(reveal);
    await tester.pumpAndSettle();

    expect(find.text('Anglais 3'), findsOneWidget);
    expect(find.byTooltip('Masquer les cours filtrés'), findsOneWidget);
  });

  testWidgets('a revealed session is dimmed and struck through', (
    tester,
  ) async {
    final container = await pump(tester);
    await hide(container, HideRule.titleContains('anglais'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Afficher les cours masqués'));
    await tester.pumpAndSettle();

    final dimmed = tester.widgetList<Opacity>(
      find.ancestor(of: find.text('Anglais 3'), matching: find.byType(Opacity)),
    );
    expect(dimmed.any((o) => o.opacity < 1), isTrue);

    final struck = tester.widget<Text>(find.text('Anglais 3'));
    expect(struck.style?.decoration, TextDecoration.lineThrough);
  });

  testWidgets('long pressing a block offers the three levels', (tester) async {
    await pump(tester);
    await tester.longPress(
      find.ancestor(
        of: find.text('Anglais 3'),
        matching: find.byType(GridBlock),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Cette séance'), findsOneWidget);
    expect(find.text('Les TD · Anglais 3'), findsOneWidget);
    expect(find.text('Tout Anglais 3'), findsOneWidget);
  });

  testWidgets('hiding from the chooser can be undone', (tester) async {
    final container = await pump(tester);
    await tester.longPress(
      find.ancestor(
        of: find.text('Anglais 3'),
        matching: find.byType(GridBlock),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Les TD · Anglais 3'));
    await tester.pumpAndSettle();

    expect(find.text('Anglais 3'), findsNothing);
    expect(container.read(hiddenRulesProvider), hasLength(1));

    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();

    expect(container.read(hiddenRulesProvider), isEmpty);
    expect(find.text('Anglais 3'), findsOneWidget);
  });

  testWidgets('the confirmation goes away on its own', (tester) async {
    await pump(tester);
    await tester.longPress(
      find.ancestor(
        of: find.text('Anglais 3'),
        matching: find.byType(GridBlock),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Les TD · Anglais 3'));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsOneWidget);

    // A SnackBar carrying an action persists unless it is told not to.
    await tester.pump(const Duration(milliseconds: 1600));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('a day emptied by a rule says so instead of looking free', (
    tester,
  ) async {
    final container = await pump(
      tester,
      events: <ScheduleEvent>[_event('Anglais 3', hour: 10, activityId: '422')],
    );
    await tester.tap(find.byType(PopupMenuButton<ScheduleViewMode>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Liste').last);
    await tester.pumpAndSettle();

    await hide(container, HideRule.titleContains('anglais'));
    await tester.pumpAndSettle();

    expect(find.text('1 cours masqué'), findsOneWidget);
  });
  group('with the hidden sessions revealed', () {
    Future<ProviderContainer> revealed(
      WidgetTester tester,
      List<HideRule> rules,
    ) async {
      final container = await pump(tester);
      for (final rule in rules) {
        await hide(container, rule);
      }
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Afficher les cours masqués'));
      await tester.pumpAndSettle();
      return container;
    }

    Finder block(String title) =>
        find.ancestor(of: find.text(title), matching: find.byType(GridBlock));

    testWidgets('long pressing a hidden session brings it back', (
      tester,
    ) async {
      final container = await revealed(tester, <HideRule>[
        HideRule.titleContains('anglais'),
      ]);

      await tester.longPress(block('Anglais 3'));
      await tester.pumpAndSettle();

      // One rule hides it, so there is nothing to choose between.
      expect(find.text('Masquer'), findsNothing);
      expect(container.read(hiddenRulesProvider), isEmpty);
      expect(find.text('Filtre « anglais » retiré'), findsOneWidget);
    });

    testWidgets('bringing it back can be undone', (tester) async {
      final container = await revealed(tester, <HideRule>[
        HideRule.titleContains('anglais'),
      ]);
      await tester.longPress(block('Anglais 3'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(container.read(hiddenRulesProvider), hasLength(1));
    });

    testWidgets('two rules on one session ask which one to lift', (
      tester,
    ) async {
      final container = await revealed(tester, <HideRule>[
        HideRule.titleContains('anglais'),
        HideRule.room('*111'),
      ]);

      await tester.longPress(block('Anglais 3'));
      await tester.pumpAndSettle();

      expect(find.text('Afficher'), findsOneWidget);
      expect(find.text('Plusieurs règles masquent ce cours.'), findsOneWidget);
      expect(find.text('anglais'), findsOneWidget);
      expect(find.text('*111'), findsOneWidget);

      await tester.tap(find.text('*111'));
      await tester.pumpAndSettle();
      expect(container.read(hiddenRulesProvider), <HideRule>[
        HideRule.titleContains('anglais'),
      ]);
    });

    testWidgets('a session still visible is offered the hide chooser', (
      tester,
    ) async {
      await revealed(tester, <HideRule>[HideRule.titleContains('anglais')]);

      await tester.longPress(block('Analyse 3'));
      await tester.pumpAndSettle();
      expect(find.text('Masquer'), findsOneWidget);
      expect(find.text('Cette séance'), findsOneWidget);
    });

    testWidgets('a narrow rule reports the course, not the rule', (
      tester,
    ) async {
      await pump(tester);
      await tester.longPress(block('Anglais 3'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Les TD · Anglais 3'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Afficher les cours masqués'));
      await tester.pumpAndSettle();

      await tester.longPress(block('Anglais 3'));
      await tester.pumpAndSettle();
      expect(find.text('Anglais 3 affiché'), findsOneWidget);
    });
  });
  group('the app bar', () {
    testWidgets('the eye never moves the buttons already there', (
      tester,
    ) async {
      final container = await pump(tester);
      final groups = find.byTooltip('Ma sélection');
      final strip = find.byTooltip('Afficher l\'aperçu de la semaine');
      final groupsBefore = tester.getCenter(groups);
      final stripBefore = tester.getCenter(strip);

      await hide(container, HideRule.titleContains('anglais'));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Afficher les cours masqués'), findsOneWidget);
      expect(tester.getCenter(groups), groupsBefore);
      expect(tester.getCenter(strip), stripBefore);
    });

    testWidgets('the eye sits left of the buttons it joins', (tester) async {
      final container = await pump(tester);
      await hide(container, HideRule.titleContains('anglais'));
      await tester.pumpAndSettle();

      final eye = tester.getCenter(
        find.byTooltip('Afficher les cours masqués'),
      );
      expect(
        eye.dx,
        lessThan(tester.getCenter(find.byTooltip('Ma sélection')).dx),
      );
      expect(
        eye.dx,
        lessThan(
          tester
              .getCenter(find.byTooltip('Afficher l\'aperçu de la semaine'))
              .dx,
        ),
      );
    });

    testWidgets('the eye does not hand its element to another action', (
      tester,
    ) async {
      final container = await pump(tester);
      final groups = tester.element(find.byTooltip('Ma sélection'));
      final strip = tester.element(
        find.byTooltip('Afficher l\'aperçu de la semaine'),
      );

      await hide(container, HideRule.titleContains('anglais'));
      await tester.pumpAndSettle();

      expect(tester.element(find.byTooltip('Ma sélection')), groups);
      expect(
        tester.element(find.byTooltip('Afficher l\'aperçu de la semaine')),
        strip,
      );
    });

    testWidgets('toggling the eye leaves it where it is', (tester) async {
      final container = await pump(tester);
      await hide(container, HideRule.titleContains('anglais'));
      await tester.pumpAndSettle();

      final before = tester.getCenter(
        find.byTooltip('Afficher les cours masqués'),
      );
      await tester.tap(find.byTooltip('Afficher les cours masqués'));
      await tester.pumpAndSettle();

      expect(
        tester.getCenter(find.byTooltip('Masquer les cours filtrés')),
        before,
      );
    });
  });
}
