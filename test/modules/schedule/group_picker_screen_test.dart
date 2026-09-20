import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/modules/schedule/ade_groups.dart';
import 'package:notes_insa/modules/schedule/ade_groups_provider.dart';
import 'package:notes_insa/modules/schedule/group_picker_screen.dart';
import 'package:notes_insa/modules/schedule/schedule_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Two branches carrying a same-named child, which is what the real tree does
/// and why search results have to name their ancestors.
const _rows = <AdeGroup>[
  AdeGroup(id: 1, name: 'INFO'),
  AdeGroup(id: 2, name: 'S7-INFO', parentId: 1),
  AdeGroup(id: 3, name: 'S7-INFO-G1', parentId: 2),
  AdeGroup(id: 4, name: '2 GROUPES TP', parentId: 3),
  AdeGroup(id: 5, name: 'S7-INFO-G2', parentId: 2),
  AdeGroup(id: 6, name: '2 GROUPES TP', parentId: 5),
  AdeGroup(id: 7, name: 'S7-INFO-ROBO', parentId: 2),
  AdeGroup(id: 8, name: 'salle 101', category: AdeCategory.room),
];

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  List<int> ids = const <int>[],
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    kSelectedGroupsKey: ids.map((i) => '$i').toList(),
  });
  final container = ProviderContainer(
    overrides: [adeGroupsProvider.overrideWith((ref) async => _rows)],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const GroupPickerScreen(),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return container;
}

Future<void> _search(WidgetTester tester, String q) async {
  await tester.enterText(find.byType(TextField), q);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('offers groups only, not rooms or modules', (tester) async {
    await _pump(tester);
    expect(find.text('INFO'), findsOneWidget);
    expect(find.text('salle 101'), findsNothing);
    expect(find.byType(ChoiceChip), findsNothing);
  });

  testWidgets('a branch cannot be checked, only entered', (tester) async {
    await _pump(tester);
    expect(find.text('INFO'), findsOneWidget);
    expect(find.byType(Checkbox), findsNothing);
    await tester.tap(find.text('INFO'));
    await tester.pumpAndSettle();
    expect(find.text('S7-INFO'), findsOneWidget);
  });

  testWidgets('the breadcrumb climbs back out', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('INFO'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('S7-INFO'));
    await tester.pumpAndSettle();
    expect(find.text('S7-INFO-ROBO'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Tout'));
    await tester.pumpAndSettle();
    expect(find.text('INFO'), findsWidgets);
    expect(find.text('S7-INFO-ROBO'), findsNothing);
  });

  testWidgets('back leaves the screen instead of climbing the tree', (
    tester,
  ) async {
    await _pump(tester);
    await tester.tap(find.text('INFO'));
    await tester.pumpAndSettle();

    await tester.pageBack();
    await tester.pumpAndSettle();
    // All the way out in one press, from two levels deep.
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('leaving with unsaved changes asks before dropping them', (
    tester,
  ) async {
    final container = await _pump(tester);
    await tester.tap(find.text('INFO'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('S7-INFO'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('S7-INFO-ROBO'));
    await tester.pumpAndSettle();

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Garder les modifications ?'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Abandonner'));
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
    expect(container.read(selectedGroupsProvider), isEmpty);
  });

  testWidgets('keeping the changes saves them on the way out', (tester) async {
    final container = await _pump(tester);
    await tester.tap(find.text('INFO'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('S7-INFO'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('S7-INFO-ROBO'));
    await tester.pumpAndSettle();

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Enregistrer'));
    await tester.pumpAndSettle();
    expect(container.read(selectedGroupsProvider), <int>[7]);
  });

  testWidgets('search names the ancestors of each result', (tester) async {
    await _pump(tester);
    await _search(tester, '2 GROUPES');
    expect(find.text('2 GROUPES TP'), findsNWidgets(2));
    expect(find.text('INFO › S7-INFO › S7-INFO-G1'), findsOneWidget);
    expect(find.text('INFO › S7-INFO › S7-INFO-G2'), findsOneWidget);
  });

  testWidgets('a search result is selectable even though it has a parent', (
    tester,
  ) async {
    await _pump(tester);
    await _search(tester, 'ROBO');
    expect(find.byType(Checkbox), findsOneWidget);
  });

  testWidgets('the selection stays visible while drilling', (tester) async {
    await _pump(tester, ids: <int>[7]);
    expect(find.widgetWithText(InputChip, 'S7-INFO-ROBO'), findsOneWidget);
    await tester.tap(find.text('INFO'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(InputChip, 'S7-INFO-ROBO'), findsOneWidget);
  });

  testWidgets('a chip drops its group', (tester) async {
    await _pump(tester, ids: <int>[7]);
    await tester.tap(find.byTooltip('Retirer S7-INFO-ROBO'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(InputChip, 'S7-INFO-ROBO'), findsNothing);
  });

  testWidgets('going past the cap says so rather than doing nothing', (
    tester,
  ) async {
    await _pump(
      tester,
      ids: List<int>.generate(GroupPickerScreen.maxSelection, (i) => 1000 + i),
    );
    await tester.tap(find.text('INFO'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('S7-INFO'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('S7-INFO-ROBO'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('${GroupPickerScreen.maxSelection} groupes'),
      findsOneWidget,
    );
  });
}
