import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/modules/campus_map/campus_geo.dart';
import 'package:notes_insa/modules/campus_map/campus_places.dart';
import 'package:notes_insa/modules/campus_map/map_screen.dart';
import 'package:notes_insa/theme/campus_theme.dart';

const List<CampusPlace> fixture = <CampusPlace>[
  CampusPlace(code: '19', name: 'Bibliothèque', kind: PlaceKind.bu),
  CampusPlace(code: '3', name: 'Amphi A', kind: PlaceKind.amphi),
  CampusPlace(code: '3', name: 'Amphi B', kind: PlaceKind.amphi),
];

CampusBuilding _square(String code, double x, {int? levels}) => CampusBuilding(
  code: code,
  name: 'Bâtiment $code',
  levels: levels,
  ring: [
    Offset(x, 0),
    Offset(x + 20, 0),
    Offset(x + 20, 20),
    Offset(x, 20),
    Offset(x, 0),
  ],
);

final CampusGeo geoFixture = CampusGeo(
  originLat: 48.122,
  originLon: -1.635,
  mPerDegLat: 111320,
  mPerDegLon: 74000,
  buildings: [_square('19', 0, levels: 2), _square('3', 40)],
  entrances: const [
    CampusEntrance(code: '19', kind: 'main', node: 0, p: Offset(10, 0)),
  ],
  graph: const CampusGraph(
    nodes: [Offset(10, -5), Offset(50, -5)],
    edges: [
      [0, 1, 40],
    ],
  ),
  unmapped: const {'8': 'not on the plan'},
  attribution: '© OpenStreetMap contributors, ODbL',
);

Future<void> pumpMap(
  WidgetTester tester,
  List<CampusPlace> places, {
  CampusGeo? geo,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        campusPlacesProvider.overrideWith((ref) async => places),
        campusGeoProvider.overrideWith((ref) async => geo ?? geoFixture),
      ],
      child: MaterialApp(
        theme: campusTheme(Brightness.light),
        home: const MapScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('draws the campus and keeps the plan link', (tester) async {
    await pumpMap(tester, fixture);
    expect(find.text('Carte'), findsOneWidget);
    expect(find.byTooltip('Ouvrir le plan officiel'), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
    expect(find.textContaining('OpenStreetMap'), findsOneWidget);
  });

  testWidgets('search finds a place and opens its building', (tester) async {
    await pumpMap(tester, fixture);
    await tester.enterText(find.byType(TextField), 'amphi b');
    await tester.pumpAndSettle();
    expect(find.text('Amphi B'), findsOneWidget);
    expect(find.text('Amphi A'), findsNothing);

    await tester.tap(find.text('Amphi B'));
    await tester.pumpAndSettle();
    expect(find.text('Bâtiment 3'), findsOneWidget);
  });

  testWidgets('the sheet lists every place in the building', (tester) async {
    await pumpMap(tester, fixture);
    await tester.enterText(find.byType(TextField), 'amphi a');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Amphi A').last);
    await tester.pumpAndSettle();
    expect(find.text('Amphi A'), findsWidgets);
    expect(find.text('Amphi B'), findsOneWidget);
  });

  testWidgets('a building with levels says so', (tester) async {
    await pumpMap(tester, fixture);
    await tester.enterText(find.byType(TextField), 'biblio');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bibliothèque').last);
    await tester.pumpAndSettle();
    expect(find.text('2 niveaux'), findsOneWidget);
  });

  testWidgets('unreadable geometry falls back to the list', (tester) async {
    await pumpMap(tester, fixture, geo: CampusGeo.empty);
    expect(find.textContaining('n’a pas pu se charger'), findsOneWidget);
    expect(find.text('Ouvrir le plan officiel'), findsOneWidget);
    expect(find.text('Amphi A'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('meets the tap target and contrast guidelines', (tester) async {
    await pumpMap(tester, fixture);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  });
}
