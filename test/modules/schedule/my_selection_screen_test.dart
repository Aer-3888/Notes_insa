import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/modules/schedule/ade_groups.dart';
import 'package:notes_insa/modules/schedule/ade_groups_provider.dart';
import 'package:notes_insa/modules/schedule/my_selection_screen.dart';
import 'package:notes_insa/modules/schedule/schedule_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _rows = <AdeGroup>[
  AdeGroup(id: 1, name: 'INFO'),
  AdeGroup(id: 2, name: 'S7-INFO', parentId: 1),
  AdeGroup(id: 3, name: 'S7-INFO-G1', parentId: 2),
  AdeGroup(id: 4, name: 'S7-INFO-G1-1', parentId: 3),
  AdeGroup(id: 8, name: 'S7-INFO-langues', parentId: 2),
  AdeGroup(id: 12, name: 'S8-INFO', parentId: 1),
  AdeGroup(id: 13, name: 'S8-INFO-G1', parentId: 12),
  AdeGroup(id: 30, name: 'HUMA'),
  AdeGroup(id: 31, name: 'LV2- LV3', parentId: 30),
];

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required List<int> ids,
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
      child: const MaterialApp(home: MySelectionScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('names each group and where it sits', (tester) async {
    await _pump(tester, ids: <int>[4]);
    expect(find.text('S7-INFO-G1-1'), findsOneWidget);
    // Trimmed to the part below the S7-INFO heading, which says the rest.
    expect(find.text('S7-INFO-G1'), findsOneWidget);
    expect(find.text('INFO › S7-INFO › S7-INFO-G1'), findsNothing);
  });

  testWidgets('groups the selection by semester', (tester) async {
    await _pump(tester, ids: <int>[4, 8, 13]);
    // One heading per semester, so two semesters of a year read as two
    // blocks rather than one undifferentiated list.
    expect(find.text('S7-INFO'), findsOneWidget);
    expect(find.text('S8-INFO'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('S7-INFO-langues')).dy,
      lessThan(tester.getTopLeft(find.text('S8-INFO')).dy),
    );
  });

  testWidgets('a cross-cutting branch gets its own heading', (tester) async {
    await _pump(tester, ids: <int>[4, 31]);
    expect(find.text('LV2- LV3'), findsOneWidget);
    expect(find.text('HUMA'), findsOneWidget);
  });

  testWidgets('every row can be removed, including the first', (tester) async {
    final container = await _pump(tester, ids: <int>[4, 8]);
    await tester.tap(find.byTooltip('Retirer S7-INFO-G1-1'));
    await tester.pumpAndSettle();
    expect(container.read(selectedGroupsProvider), <int>[8]);
    expect(find.text('S7-INFO-G1-1'), findsNothing);
  });

  testWidgets('removing the last row falls back to the invitation', (
    tester,
  ) async {
    await _pump(tester, ids: <int>[4]);
    await tester.tap(find.byTooltip('Retirer S7-INFO-G1-1'));
    await tester.pumpAndSettle();
    expect(find.text('Aucun groupe choisi'), findsOneWidget);
  });

  testWidgets('an empty selection invites the wizard instead of listing', (
    tester,
  ) async {
    await _pump(tester, ids: <int>[]);
    expect(find.text('Aucun groupe choisi'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Choisir mon groupe'), findsOne);
  });

  testWidgets('an id the list does not know still shows, by number', (
    tester,
  ) async {
    await _pump(tester, ids: <int>[4, 77777]);
    expect(find.text('Ressource 77777'), findsOneWidget);
    expect(find.text('Autres'), findsOneWidget);
  });

  testWidgets('sharing copies a link the importer can read back', (
    tester,
  ) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await _pump(tester, ids: <int>[4, 8]);
    await tester.tap(find.text('Partager ma sélection'));
    await tester.pumpAndSettle();
    expect(copied, 'https://ade-planning.insa-rennes.fr/view/4,8/');
  });

  testWidgets('sharing is unavailable with nothing selected', (tester) async {
    await _pump(tester, ids: <int>[]);
    expect(find.text('Partager ma sélection'), findsNothing);
  });

  testWidgets('changing the group opens the wizard', (tester) async {
    await _pump(tester, ids: <int>[4]);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Refaire le choix'));
    await tester.pumpAndSettle();
    expect(find.text('Votre formation'), findsOneWidget);
  });

  testWidgets('adding an option opens the full tree', (tester) async {
    await _pump(tester, ids: <int>[4]);
    await tester.tap(find.text('Ajouter un groupe ou une option'));
    await tester.pumpAndSettle();
    expect(find.text('Parcourir les groupes'), findsOneWidget);
  });

  testWidgets('the advanced entry reaches the same tree', (tester) async {
    await _pump(tester, ids: <int>[4]);
    await tester.tap(find.text('Parcourir tout ADE'));
    await tester.pumpAndSettle();
    expect(find.text('Parcourir les groupes'), findsOneWidget);
  });

  testWidgets('importing a link replaces the selection', (tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => call.method == 'Clipboard.getData'
          ? <String, dynamic>{
              'text': 'https://ade-planning.insa-rennes.fr/view/8,4/',
            }
          : null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    final container = await _pump(tester, ids: <int>[4]);
    await tester.tap(find.byTooltip('Importer un lien ADE'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Importer'));
    await tester.pumpAndSettle();
    expect(container.read(selectedGroupsProvider), <int>[8, 4]);
  });
}
