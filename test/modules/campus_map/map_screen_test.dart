import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/modules/campus_map/campus_places.dart';
import 'package:notes_insa/modules/campus_map/map_screen.dart';
import 'package:notes_insa/theme/campus_theme.dart';

const List<CampusPlace> fixture = <CampusPlace>[
  CampusPlace(code: '19', name: 'Bibliothèque', kind: PlaceKind.bu),
  CampusPlace(code: '3', name: 'Amphi A', kind: PlaceKind.amphi),
  CampusPlace(code: '3', name: 'Amphi B', kind: PlaceKind.amphi),
];

Future<void> pumpMap(WidgetTester tester, List<CampusPlace> places) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [campusPlacesProvider.overrideWith((ref) async => places)],
      child: MaterialApp(
        theme: campusTheme(Brightness.light),
        home: const MapScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the plan button and the grouped places', (tester) async {
    await pumpMap(tester, fixture);
    expect(find.text('Carte'), findsOneWidget);
    expect(find.text('Ouvrir le plan officiel'), findsOneWidget);
    expect(find.text('Amphis'), findsOneWidget);
    expect(find.text('Bibliothèque'), findsNWidgets(2));
    expect(find.text('Amphi A'), findsOneWidget);
  });

  testWidgets('typing filters the list', (tester) async {
    await pumpMap(tester, fixture);
    await tester.enterText(find.byType(TextField), 'amphi b');
    await tester.pump();
    expect(find.text('Amphi B'), findsOneWidget);
    expect(find.text('Amphi A'), findsNothing);
    expect(find.text('Bibliothèque'), findsNothing);
  });

  testWidgets('an empty dataset hides the search and the list', (tester) async {
    await pumpMap(tester, const <CampusPlace>[]);
    expect(find.text('Ouvrir le plan officiel'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('meets the tap target and contrast guidelines', (tester) async {
    await pumpMap(tester, fixture);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  });
}
