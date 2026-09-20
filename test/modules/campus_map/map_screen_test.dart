import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/modules/campus_map/campus_geo.dart';
import 'package:notes_insa/modules/campus_map/campus_heading.dart';
import 'package:notes_insa/modules/campus_map/campus_location.dart';
import 'package:notes_insa/modules/campus_map/campus_places.dart';
import 'package:notes_insa/modules/campus_map/map_painter.dart';
import 'package:notes_insa/modules/campus_map/map_screen.dart';
import 'package:notes_insa/modules/rooms/rooms_screen.dart';
import 'package:notes_insa/theme/campus_theme.dart';
import 'package:notes_insa/theme/tokens.dart';

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
  CampusLocationSource? locationSource,
  CampusHeadingSource? headingSource,
  String? initialBuildingCode,
  bool startGuidance = false,
  Size? size,
}) async {
  if (size != null) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        campusPlacesProvider.overrideWith((ref) async => places),
        campusGeoProvider.overrideWith((ref) async => geo ?? geoFixture),
        campusLocationSourceProvider.overrideWithValue(
          locationSource ?? const _NoLocationSource(),
        ),
        if (headingSource != null)
          campusHeadingSourceProvider.overrideWithValue(headingSource),
      ],
      child: MaterialApp(
        theme: campusTheme(Brightness.light),
        home: MapScreen(
          initialBuildingCode: initialBuildingCode,
          startGuidance: startGuidance,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The map asks for a fix as soon as it opens, so every test states what
/// the phone answers.
class _NoLocationSource implements CampusLocationSource {
  const _NoLocationSource();

  @override
  Future<CampusPosition> current() async =>
      throw const CampusLocationException(CampusLocationFailure.unavailable);

  @override
  Stream<CampusPosition> watch() => const Stream<CampusPosition>.empty();
}

class _LocationSource implements CampusLocationSource {
  const _LocationSource(this.position);

  final CampusPosition position;

  @override
  Future<CampusPosition> current() async => position;

  @override
  Stream<CampusPosition> watch() => const Stream<CampusPosition>.empty();
}

class _StreamLocationSource implements CampusLocationSource {
  _StreamLocationSource(this.position);

  final CampusPosition position;
  final StreamController<CampusPosition> controller =
      StreamController<CampusPosition>.broadcast();

  @override
  Future<CampusPosition> current() async => position;

  @override
  Stream<CampusPosition> watch() => controller.stream;
}

class _StreamHeadingSource implements CampusHeadingSource {
  final StreamController<CampusHeading> controller =
      StreamController<CampusHeading>.broadcast();

  @override
  Stream<CampusHeading> watch() => controller.stream;
}

class _HeadingSource implements CampusHeadingSource {
  const _HeadingSource(this.heading, {this.accuracy});

  final double? heading;
  final double? accuracy;

  @override
  Stream<CampusHeading> watch() => Stream<CampusHeading>.value(
    CampusHeading(degrees: heading, accuracyDegrees: accuracy),
  );
}

Future<void> openSearch(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Rechercher un lieu'));
  await tester.pumpAndSettle();
}

void main() {
  test('rotated camera keeps screen and world coordinates reversible', () {
    const camera = MapCamera(
      center: Offset.zero,
      metersPerPixel: 1,
      bearingDegrees: 90,
    );
    const size = Size(100, 100);
    final screen = camera.toScreen(const Offset(10, 0), size);
    expect(screen.dx, closeTo(50, 0.001));
    expect(screen.dy, closeTo(40, 0.001));
    expect(camera.toWorld(screen, size).dx, closeTo(10, 0.001));
    expect(camera.toWorld(screen, size).dy, closeTo(0, 0.001));
  });

  testWidgets('draws the campus and keeps the plan link', (tester) async {
    await pumpMap(tester, fixture);
    expect(find.text('Carte'), findsOneWidget);
    expect(find.byTooltip('Ouvrir le plan officiel'), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
    expect(find.byTooltip('Afficher ma position'), findsOneWidget);
    expect(find.byTooltip('Orienter selon ma direction'), findsOneWidget);
    expect(find.byTooltip('Rechercher un lieu'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.textContaining('OpenStreetMap'), findsOneWidget);
  });

  testWidgets('switches between direction-up and north-up', (tester) async {
    await pumpMap(tester, fixture, headingSource: const _HeadingSource(90));

    await tester.tap(find.byTooltip('Orienter selon ma direction'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Revenir au nord'), findsOneWidget);
    var painter = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((paint) => paint.painter)
        .whereType<CampusMapPainter>()
        .single;
    expect(painter.camera.bearingDegrees, closeTo(90, 0.001));

    await tester.tap(find.byTooltip('Revenir au nord'));
    await tester.pumpAndSettle();
    painter = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((paint) => paint.painter)
        .whereType<CampusMapPainter>()
        .single;
    expect(painter.camera.bearingDegrees, 0);
  });

  testWidgets('the map opens on the walker with the accuracy it has', (
    tester,
  ) async {
    await pumpMap(
      tester,
      fixture,
      locationSource: const _LocationSource(
        CampusPosition(latitude: 48.122, longitude: -1.635, accuracyMeters: 12),
      ),
    );

    final painter = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((paint) => paint.painter)
        .whereType<CampusMapPainter>()
        .single;
    expect(painter.currentLocation, geoFixture.toLocal(48.122, -1.635));
    expect(painter.currentAccuracyMeters, 12);
    expect(painter.camera.center, painter.currentLocation);
    expect(find.byTooltip('Ne plus suivre ma position'), findsOneWidget);
  });

  testWidgets('a walker off campus keeps the whole site framed', (
    tester,
  ) async {
    await pumpMap(
      tester,
      fixture,
      locationSource: const _LocationSource(
        CampusPosition(latitude: 48.2, longitude: -1.5),
      ),
    );

    final painter = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((paint) => paint.painter)
        .whereType<CampusMapPainter>()
        .single;
    expect(painter.currentLocation, isNotNull);
    expect(painter.camera.center, geoFixture.siteBounds.inflate(30).center);
    expect(find.byTooltip('Afficher ma position'), findsOneWidget);
  });

  testWidgets('compass mode leaves the map where the user put it', (
    tester,
  ) async {
    final location = _StreamLocationSource(
      const CampusPosition(latitude: 48.122, longitude: -1.635),
    );
    final heading = _StreamHeadingSource();
    addTearDown(location.controller.close);
    addTearDown(heading.controller.close);
    await pumpMap(
      tester,
      fixture,
      locationSource: location,
      headingSource: heading,
    );

    expect(find.byTooltip('Ne plus suivre ma position'), findsOneWidget);
    await tester.tap(find.byTooltip('Orienter selon ma direction'));
    await tester.pumpAndSettle();
    heading.controller.add(const CampusHeading(degrees: 0));
    await tester.pumpAndSettle();

    await openSearch(tester);
    await tester.enterText(find.byType(TextField), 'amphi b');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Amphi B'));
    await tester.pumpAndSettle();

    // A new fix and a new heading may turn the map, but must not drag it
    // back onto the walker once they have gone looking elsewhere.
    heading.controller.add(const CampusHeading(degrees: 90));
    location.controller.add(
      const CampusPosition(latitude: 48.1225, longitude: -1.6355),
    );
    await tester.pumpAndSettle();

    final painter = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((paint) => paint.painter)
        .whereType<CampusMapPainter>()
        .single;
    expect(painter.camera.center, geoFixture.byCode('3')!.centroid);
    expect(painter.camera.bearingDegrees, closeTo(90, 0.001));
    expect(find.byTooltip('Afficher ma position'), findsOneWidget);
  });

  testWidgets('the map eases into a new heading instead of snapping', (
    tester,
  ) async {
    final heading = _StreamHeadingSource();
    addTearDown(heading.controller.close);
    await pumpMap(tester, fixture, headingSource: heading);

    await tester.tap(find.byTooltip('Orienter selon ma direction'));
    await tester.pumpAndSettle();
    heading.controller.add(const CampusHeading(degrees: 0));
    await tester.pumpAndSettle();

    heading.controller.add(const CampusHeading(degrees: 120));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    final easing = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((paint) => paint.painter)
        .whereType<CampusMapPainter>()
        .single
        .camera
        .bearingDegrees;
    expect(easing, greaterThan(0));
    expect(easing, lessThan(45));

    await tester.pumpAndSettle();
    expect(
      tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((paint) => paint.painter)
          .whereType<CampusMapPainter>()
          .single
          .camera
          .bearingDegrees,
      closeTo(120, 0.001),
    );
  });

  testWidgets('a disturbed compass says how to fix it', (tester) async {
    await pumpMap(
      tester,
      fixture,
      headingSource: const _HeadingSource(90, accuracy: 45),
    );

    await tester.tap(find.byTooltip('Orienter selon ma direction'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Boussole imprécise'), findsOneWidget);
  });

  testWidgets('foreground location draws a route to the building entrance', (
    tester,
  ) async {
    const source = _LocationSource(
      CampusPosition(latitude: 48.122 - 5 / 111320, longitude: -1.635),
    );
    await pumpMap(
      tester,
      fixture,
      locationSource: source,
      initialBuildingCode: '19',
      startGuidance: true,
    );

    final painter = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((paint) => paint.painter)
        .whereType<CampusMapPainter>()
        .single;
    expect(painter.selected, '19');
    expect(painter.currentLocation, isNotNull);
    expect(painter.route, isNotEmpty);
    expect(find.text('Guidage en cours'), findsOneWidget);
    expect(find.textContaining('≈ 1 min'), findsOneWidget);

    await tester.tap(find.byTooltip('Afficher ma position'));
    await tester.pumpAndSettle();
    expect(find.text('Guidage en cours'), findsOneWidget);
    expect(
      tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((paint) => paint.painter)
          .whereType<CampusMapPainter>()
          .single
          .route,
      isNotEmpty,
    );

    await tester.tap(find.byTooltip('Mettre le guidage en pause'));
    await tester.pumpAndSettle();
    expect(find.text('Guidage en pause'), findsOneWidget);
    expect(find.byTooltip('Reprendre le guidage'), findsOneWidget);

    await tester.tap(find.byTooltip('Reprendre le guidage'));
    await tester.pumpAndSettle();
    expect(find.text('Guidage en cours'), findsOneWidget);

    await tester.tap(find.byTooltip('Arrêter le guidage'));
    await tester.pumpAndSettle();
    expect(find.text('Guidage en cours'), findsNothing);
    expect(
      tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((paint) => paint.painter)
          .whereType<CampusMapPainter>()
          .single
          .route,
      isEmpty,
    );
  });

  testWidgets('search finds a place and opens its building', (tester) async {
    await pumpMap(tester, fixture);
    await openSearch(tester);
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
    await openSearch(tester);
    await tester.enterText(find.byType(TextField), 'amphi a');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Amphi A').last);
    await tester.pumpAndSettle();
    expect(find.text('Amphi A'), findsWidgets);
    expect(find.text('Amphi B'), findsOneWidget);
  });

  testWidgets('the building sheet uses the full width and shared text gutter', (
    tester,
  ) async {
    await pumpMap(tester, fixture, size: const Size(900, 800));
    await openSearch(tester);
    await tester.enterText(find.byType(TextField), 'amphi a');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Amphi A').last);
    await tester.pumpAndSettle();

    expect(tester.getSize(find.byType(BottomSheet)).width, 900);
    expect(tester.getTopLeft(find.text('Bâtiment 3')).dx, CampusSpacing.gutter);
  });

  testWidgets('a building with levels says so', (tester) async {
    await pumpMap(tester, fixture);
    await openSearch(tester);
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

  testWidgets('toggles free room counts on the map', (tester) async {
    await pumpMap(tester, fixture);
    final action = find.byTooltip('Afficher les salles libres');
    expect(action, findsOneWidget);
    await tester.tap(action);
    await tester.pump();
    expect(find.byTooltip('Masquer les salles libres'), findsOneWidget);
    await openSearch(tester);
    await tester.enterText(find.byType(TextField), 'amphi a');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Amphi A').last);
    await tester.pumpAndSettle();
    expect(find.text('Voir les salles libres'), findsOneWidget);
    await tester.tap(find.text('Voir les salles libres'));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.byType(RoomsScreen), findsOneWidget);
  });

  testWidgets('meets the tap target and contrast guidelines', (tester) async {
    await pumpMap(tester, fixture);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  });
}
