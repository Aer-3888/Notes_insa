import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/modules/schedule/ade_groups.dart';
import 'package:notes_insa/modules/schedule/ade_tree_list.dart';

/// A miniature of the real tree: a department, a promo, a group branch with
/// two leaves, and an elective branch beside it.
const _rows = <AdeGroup>[
  AdeGroup(id: 1, name: 'INFO'),
  AdeGroup(id: 2, name: 'S7-INFO', parentId: 1),
  AdeGroup(id: 3, name: 'S7-INFO-G1', parentId: 2),
  AdeGroup(id: 4, name: 'S7-INFO-G1-1', parentId: 3),
  AdeGroup(id: 5, name: 'S7-INFO-G1-2', parentId: 3),
  AdeGroup(id: 6, name: 'S7-INFO-ROBO', parentId: 2),
  AdeGroup(id: 7, name: 'S7-INFO-OPTION', parentId: 2),
  AdeGroup(id: 8, name: 'S7-INFO-SECU', parentId: 7),
];

Widget _host({
  required List<AdeGroup> visible,
  Set<int> selected = const <int>{},
  AdeTreeSelection mode = AdeTreeSelection.check,
  bool drillable = true,
  bool showPath = false,
  String? Function(AdeGroup)? headerBefore,
  void Function(AdeGroup)? onToggle,
  void Function(AdeGroup)? onDrill,
}) => MaterialApp(
  home: Scaffold(
    body: AdeTreeList(
      rows: _rows,
      visible: visible,
      selected: selected,
      mode: mode,
      drillable: drillable,
      showPath: showPath,
      headerBefore: headerBefore,
      onToggle: onToggle ?? (_) {},
      onDrill: onDrill ?? (_) {},
    ),
  ),
);

void main() {
  testWidgets('a branch offers no control, only a way in', (tester) async {
    await tester.pumpWidget(
      _host(visible: <AdeGroup>[_rows[2]]), // S7-INFO-G1
    );
    expect(find.text('S7-INFO-G1'), findsOneWidget);
    expect(find.byType(Checkbox), findsNothing);
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
  });

  testWidgets('a branch says how much sits under it', (tester) async {
    await tester.pumpWidget(_host(visible: <AdeGroup>[_rows[1]])); // S7-INFO
    expect(find.text('6 groupes'), findsOneWidget);
  });

  testWidgets('a branch holding one row says so in the singular', (
    tester,
  ) async {
    await tester.pumpWidget(_host(visible: <AdeGroup>[_rows[6]])); // OPTION
    expect(find.text('1 groupe'), findsOneWidget);
  });

  testWidgets('drillable false makes a branch selectable in its own right', (
    tester,
  ) async {
    final toggled = <int>[];
    final drilled = <int>[];
    await tester.pumpWidget(
      _host(
        visible: <AdeGroup>[_rows[2]], // S7-INFO-G1, a branch
        drillable: false,
        mode: AdeTreeSelection.radio,
        onToggle: (g) => toggled.add(g.id),
        onDrill: (g) => drilled.add(g.id),
      ),
    );
    expect(find.byType(Radio<int>), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsNothing);
    await tester.tap(find.text('S7-INFO-G1'));
    expect(toggled, <int>[3]);
    expect(drilled, isEmpty);
  });

  testWidgets('a leaf carries the checkbox in check mode', (tester) async {
    await tester.pumpWidget(_host(visible: <AdeGroup>[_rows[3]]));
    expect(find.byType(Checkbox), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsNothing);
  });

  testWidgets('a leaf carries a radio in radio mode', (tester) async {
    await tester.pumpWidget(
      _host(visible: <AdeGroup>[_rows[3]], mode: AdeTreeSelection.radio),
    );
    expect(find.byType(Radio<int>), findsOneWidget);
    expect(find.byType(Checkbox), findsNothing);
  });

  testWidgets('tapping a branch drills rather than selecting it', (
    tester,
  ) async {
    final drilled = <int>[];
    final toggled = <int>[];
    await tester.pumpWidget(
      _host(
        visible: <AdeGroup>[_rows[2]],
        onDrill: (g) => drilled.add(g.id),
        onToggle: (g) => toggled.add(g.id),
      ),
    );
    await tester.tap(find.text('S7-INFO-G1'));
    expect(drilled, <int>[3]);
    expect(toggled, isEmpty);
  });

  testWidgets('tapping a leaf row selects it', (tester) async {
    final toggled = <int>[];
    await tester.pumpWidget(
      _host(visible: <AdeGroup>[_rows[3]], onToggle: (g) => toggled.add(g.id)),
    );
    await tester.tap(find.text('S7-INFO-G1-1'));
    expect(toggled, <int>[4]);
  });

  testWidgets('a selected leaf reads as checked', (tester) async {
    await tester.pumpWidget(
      _host(visible: <AdeGroup>[_rows[3]], selected: const <int>{4}),
    );
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
  });

  testWidgets('showPath names the ancestors so duplicates can be told apart', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(visible: <AdeGroup>[_rows[3]], showPath: true),
    );
    expect(find.text('INFO › S7-INFO › S7-INFO-G1'), findsOneWidget);
  });

  testWidgets('headerBefore breaks the list into named sections', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        visible: <AdeGroup>[_rows[3], _rows[6]],
        headerBefore: (g) => g.id == 4 ? 'FORMATIONS' : 'AUTRES',
      ),
    );
    expect(find.text('FORMATIONS'), findsOneWidget);
    expect(find.text('AUTRES'), findsOneWidget);
  });

  testWidgets('a row with no header keeps its section running', (tester) async {
    await tester.pumpWidget(
      _host(
        visible: <AdeGroup>[_rows[3], _rows[4]],
        headerBefore: (g) => g.id == 4 ? 'FORMATIONS' : null,
      ),
    );
    expect(find.text('FORMATIONS'), findsOneWidget);
    expect(find.text('S7-INFO-G1-2'), findsOneWidget);
  });

  testWidgets('an empty list explains itself rather than going blank', (
    tester,
  ) async {
    await tester.pumpWidget(_host(visible: const <AdeGroup>[]));
    expect(find.text('Aucun résultat'), findsOneWidget);
  });
}
