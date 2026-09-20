import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/modules/schedule/ade_groups.dart';
import 'package:notes_insa/modules/schedule/ade_groups_provider.dart';
import 'package:notes_insa/modules/schedule/group_wizard/group_wizard_screen.dart';
import 'package:notes_insa/modules/schedule/schedule_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The shapes the wizard has to survive, in miniature:
///   INFO  > S7-INFO > S7-INFO-G1 > G1-1, G1-2      (a base three levels down)
///                   > S7-INFO-OPTION > SECU        (an elective branch)
///                   > S7-INFO-langues              (a flat elective)
///   STPI  > S9-INFO-like promo with TD and TP as siblings
const _rows = <AdeGroup>[
  AdeGroup(id: 1, name: 'INFO'),
  AdeGroup(id: 2, name: 'S7-INFO', parentId: 1),
  AdeGroup(id: 3, name: 'S7-INFO-G1', parentId: 2),
  AdeGroup(id: 4, name: 'S7-INFO-G1-1', parentId: 3),
  AdeGroup(id: 5, name: 'S7-INFO-G1-2', parentId: 3),
  AdeGroup(id: 6, name: 'S7-INFO-OPTION', parentId: 2),
  AdeGroup(id: 7, name: 'S7-INFO-SECU', parentId: 6),
  AdeGroup(id: 8, name: 'S7-INFO-langues', parentId: 2),
  AdeGroup(id: 12, name: 'S8-INFO', parentId: 1),
  AdeGroup(id: 13, name: 'S8-INFO-G1', parentId: 12),
  AdeGroup(id: 14, name: 'S8-INFO-OPTION', parentId: 12),
  AdeGroup(id: 15, name: 'S10-INFO', parentId: 1),
  AdeGroup(id: 16, name: 'S10-INFO-A', parentId: 15),
  AdeGroup(id: 9, name: 'STPI'),
  AdeGroup(id: 10, name: 'S1-STPI', parentId: 9),
  AdeGroup(id: 11, name: 'S1-STPI-A', parentId: 10),
  AdeGroup(id: 17, name: 'S2-STPI', parentId: 9),
  AdeGroup(id: 18, name: 'S2-STPI-A', parentId: 17),
  // A master's: its own cohort, but no semester level to ask about.
  AdeGroup(id: 20, name: 'MASTER-EO'),
  AdeGroup(id: 21, name: 'MASTER-EO-Grp1', parentId: 20),
  AdeGroup(id: 22, name: 'MASTER-EO-Grp2', parentId: 20),
  // Cross-cutting: a pool, never a starting point.
  AdeGroup(id: 30, name: 'HUMA'),
  AdeGroup(id: 31, name: 'LV2- LV3', parentId: 30),
  AdeGroup(id: 32, name: 'ANGLAIS-TRANSVERSAL', parentId: 30),
  AdeGroup(id: 99, name: 'Étudiant 4242'),
];

Future<ProviderContainer> _pump(WidgetTester tester) async {
  final container = ProviderContainer(
    overrides: [adeGroupsProvider.overrideWith((ref) async => _rows)],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: GroupWizardScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

/// Taps a row and lets the radio settle.
Future<void> _pick(WidgetTester tester, String name) async {
  await tester.tap(find.text(name));
  await tester.pumpAndSettle();
}

Future<void> _next(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(FilledButton, 'Continuer'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets('opens on the formations, without the junk student node', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.text('INFO'), findsOneWidget);
    expect(find.text('STPI'), findsOneWidget);
    expect(find.text('Étudiant 4242'), findsNothing);
  });

  testWidgets('separates formations from masters and parcours', (tester) async {
    await _pump(tester);
    expect(find.text('Formations'), findsOneWidget);
    expect(find.text('Autres parcours'), findsOneWidget);
    expect(find.text('MASTER-EO'), findsOneWidget);
  });

  testWidgets('HUMA is not a place to start', (tester) async {
    await _pump(tester);
    expect(find.text('HUMA'), findsNothing);
  });

  testWidgets('semesters are listed in reading order, S8 before S10', (
    tester,
  ) async {
    await _pump(tester);
    await _pick(tester, 'INFO');
    await _next(tester);
    final ys = <String, double>{
      for (final n in <String>['S7-INFO', 'S8-INFO', 'S10-INFO'])
        n: tester.getTopLeft(find.text(n)).dy,
    };
    expect(ys['S7-INFO']!, lessThan(ys['S8-INFO']!));
    expect(ys['S8-INFO']!, lessThan(ys['S10-INFO']!));
  });

  testWidgets('a whole year: two semesters, one group in each', (tester) async {
    final container = await _pump(tester);
    await _pick(tester, 'INFO');
    await _next(tester);

    // Multi-select: both semesters of the year.
    await _pick(tester, 'S7-INFO');
    await _pick(tester, 'S8-INFO');
    await _next(tester);

    // One group step per semester, in the order they were chosen.
    expect(find.text('Votre groupe en S7-INFO'), findsOneWidget);
    await tester.tap(find.text('S7-INFO-G1'));
    await tester.pumpAndSettle();
    await _pick(tester, 'S7-INFO-G1-1');
    await _next(tester);

    expect(find.text('Votre groupe en S8-INFO'), findsOneWidget);
    await _pick(tester, 'S8-INFO-G1');
    await _next(tester);

    // Options come from both semesters.
    expect(find.text('S7-INFO-OPTION'), findsOneWidget);
    expect(find.text('S8-INFO-OPTION'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Terminer'));
    await tester.pumpAndSettle();
    expect(container.read(selectedGroupsProvider), <int>[4, 13]);
  });

  testWidgets('dropping a semester drops the group picked in it', (
    tester,
  ) async {
    final container = await _pump(tester);
    await _pick(tester, 'INFO');
    await _next(tester);
    await _pick(tester, 'S7-INFO');
    await _pick(tester, 'S8-INFO');
    await _next(tester);
    await tester.tap(find.text('S7-INFO-G1'));
    await tester.pumpAndSettle();
    await _pick(tester, 'S7-INFO-G1-1');
    await _next(tester);
    await _pick(tester, 'S8-INFO-G1');

    // Back to the semesters, drop S7.
    await tester.tap(find.byTooltip('Retour'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Retour'));
    await tester.pumpAndSettle();
    await _pick(tester, 'S7-INFO');
    await _next(tester);

    expect(find.text('Votre groupe en S8-INFO'), findsOneWidget);
    await _next(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Terminer'));
    await tester.pumpAndSettle();
    expect(container.read(selectedGroupsProvider), <int>[13]);
  });

  testWidgets('a master has no semester step to ask about', (tester) async {
    final container = await _pump(tester);
    await _pick(tester, 'MASTER-EO');
    await _next(tester);
    // Straight to the groups.
    expect(find.text('MASTER-EO-Grp1'), findsOneWidget);
    await _pick(tester, 'MASTER-EO-Grp1');
    await _next(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Terminer'));
    await tester.pumpAndSettle();
    expect(container.read(selectedGroupsProvider), <int>[21]);
  });

  testWidgets('everyone can add the langues branches', (tester) async {
    final container = await _pump(tester);
    await _pick(tester, 'INFO');
    await _next(tester);
    await _pick(tester, 'S7-INFO');
    await _next(tester);
    await tester.tap(find.text('S7-INFO-G1'));
    await tester.pumpAndSettle();
    await _pick(tester, 'S7-INFO-G1-1');
    await _next(tester);

    expect(find.text('Langues et humanités'), findsOneWidget);
    await _pick(tester, 'LV2- LV3');
    await tester.tap(find.widgetWithText(FilledButton, 'Terminer'));
    await tester.pumpAndSettle();
    expect(container.read(selectedGroupsProvider), <int>[4, 31]);
  });

  testWidgets('cannot continue before something is picked', (tester) async {
    await _pump(tester);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Continuer'))
          .onPressed,
      isNull,
    );
    await _pick(tester, 'INFO');
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Continuer'))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('walks département → semestre → groupe → options', (
    tester,
  ) async {
    final container = await _pump(tester);

    await _pick(tester, 'INFO');
    await _next(tester);
    expect(find.text('S7-INFO'), findsOneWidget);

    await _pick(tester, 'S7-INFO');
    await _next(tester);
    // The group step drills: G1 is a branch, so it navigates rather than
    // selecting, and its leaves are what can be picked.
    expect(find.text('S7-INFO-G1'), findsOneWidget);
    await tester.tap(find.text('S7-INFO-G1'));
    await tester.pumpAndSettle();
    expect(find.text('S7-INFO-G1-1'), findsOneWidget);

    await _pick(tester, 'S7-INFO-G1-1');
    await _next(tester);

    // Options: the branches beside the base, never the base's own branch.
    expect(find.text('S7-INFO-OPTION'), findsOneWidget);
    expect(find.text('S7-INFO-langues'), findsOneWidget);
    expect(find.text('S7-INFO-G1'), findsNothing);

    await _pick(tester, 'S7-INFO-langues');
    await tester.tap(find.widgetWithText(FilledButton, 'Terminer'));
    await tester.pumpAndSettle();

    expect(container.read(selectedGroupsProvider), <int>[4, 8]);
  });

  testWidgets('skipping the options commits the base alone', (tester) async {
    final container = await _pump(tester);
    await _pick(tester, 'INFO');
    await _next(tester);
    await _pick(tester, 'S7-INFO');
    await _next(tester);
    await tester.tap(find.text('S7-INFO-G1'));
    await tester.pumpAndSettle();
    await _pick(tester, 'S7-INFO-G1-1');
    await _next(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Terminer'));
    await tester.pumpAndSettle();
    expect(container.read(selectedGroupsProvider), <int>[4]);
  });

  testWidgets('a promo whose groups are leaves needs no drill', (tester) async {
    final container = await _pump(tester);
    await _pick(tester, 'STPI');
    await _next(tester);
    await _pick(tester, 'S1-STPI');
    await _next(tester);
    await _pick(tester, 'S1-STPI-A');
    await _next(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Terminer'));
    await tester.pumpAndSettle();
    expect(container.read(selectedGroupsProvider), <int>[11]);
  });

  testWidgets('back returns to the previous step and keeps the pick', (
    tester,
  ) async {
    await _pump(tester);
    await _pick(tester, 'INFO');
    await _next(tester);
    expect(find.text('S7-INFO'), findsOneWidget);

    await tester.tap(find.byTooltip('Retour'));
    await tester.pumpAndSettle();
    expect(find.text('STPI'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Continuer'))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('inside the group step, back climbs before it leaves', (
    tester,
  ) async {
    await _pump(tester);
    await _pick(tester, 'INFO');
    await _next(tester);
    await _pick(tester, 'S7-INFO');
    await _next(tester);

    await tester.tap(find.text('S7-INFO-G1'));
    await tester.pumpAndSettle();
    expect(find.text('S7-INFO-G1-1'), findsOneWidget);

    await tester.tap(find.byTooltip('Retour'));
    await tester.pumpAndSettle();
    // Back out of the drill, still on the group step.
    expect(find.text('S7-INFO-G1'), findsOneWidget);
    expect(find.text('S7-INFO-G1-1'), findsNothing);
  });

  testWidgets('changing the département clears the stale semestre', (
    tester,
  ) async {
    await _pump(tester);
    await _pick(tester, 'INFO');
    await _next(tester);
    await _pick(tester, 'S7-INFO');

    await tester.tap(find.byTooltip('Retour'));
    await tester.pumpAndSettle();
    await _pick(tester, 'STPI');
    await _next(tester);

    expect(find.text('S1-STPI'), findsOneWidget);
    expect(find.text('S7-INFO'), findsNothing);
    // The old promo must not carry over as an already-valid answer.
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Continuer'))
          .onPressed,
      isNull,
    );
  });
}
