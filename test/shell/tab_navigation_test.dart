import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/core/module_cache.dart';
import 'package:notes_insa/core/time.dart';
import 'package:notes_insa/modules/campus_map/campus_geo.dart';
import 'package:notes_insa/modules/campus_map/campus_places.dart';
import 'package:notes_insa/modules/campus_map/map_painter.dart';
import 'package:notes_insa/modules/schedule/event_sheet.dart';
import 'package:notes_insa/modules/schedule/schedule_event.dart';
import 'package:notes_insa/modules/weather/weather_model.dart';
import 'package:notes_insa/modules/weather/weather_provider.dart';
import 'package:notes_insa/modules/schedule/schedule_focus.dart';
import 'package:notes_insa/shell/campus_shell.dart';
import 'package:notes_insa/shell/module_card.dart';
import 'package:notes_insa/theme/campus_theme.dart';

void main() {
  setUpAll(initCampusTime);

  Future<void> pumpShell(
    WidgetTester tester, {
    CampusGeo? campusGeo,
    List<CampusPlace>? campusPlaces,
  }) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        // Left unresolved the weather screen spins forever and pumpAndSettle
        // never returns; the failed state is static.
        overrides: [
          weatherProvider.overrideWith(
            (ref) => Stream<CachedEntry<WeatherSnapshot>>.value(
              const CachedEntry<WeatherSnapshot>(
                refreshState: RefreshState.failedUpstream,
              ),
            ),
          ),
          if (campusGeo != null)
            campusGeoProvider.overrideWith((ref) async => campusGeo),
          if (campusPlaces != null)
            campusPlacesProvider.overrideWith((ref) async => campusPlaces),
        ],
        child: MaterialApp(
          theme: campusTheme(Brightness.light),
          home: const CampusShell(),
        ),
      ),
    );
    await tester.pump();
  }

  /// The navigator of whichever destination is on screen. There is one per
  /// destination, below the shell's own Scaffold.
  NavigatorState tabNavigator(WidgetTester tester) =>
      tester.state<NavigatorState>(
        find
            .descendant(
              of: find.byType(IndexedStack),
              matching: find.byType(Navigator),
            )
            .first,
      );

  /// The bar's own label; module names also appear on the hub cards.
  Finder destination(String label) => find.descendant(
    of: find.byType(NavigationBar),
    matching: find.text(label),
  );

  int selectedIndex(WidgetTester tester) =>
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex;

  Future<void> openDetail(WidgetTester tester) async {
    // The route outlives the helper; the test drives it with pumpAndSettle.
    unawaited(
      tabNavigator(tester).push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('détail')),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  final mapGeo = CampusGeo(
    originLat: 48.122,
    originLon: -1.635,
    mPerDegLat: 111320,
    mPerDegLon: 74000,
    buildings: [
      CampusBuilding(
        code: '3',
        name: 'Bâtiment 3',
        levels: null,
        ring: const [
          Offset(0, 0),
          Offset(20, 0),
          Offset(20, 20),
          Offset(0, 20),
          Offset(0, 0),
        ],
      ),
    ],
    entrances: const [],
    graph: const CampusGraph(nodes: [], edges: []),
    unmapped: const {},
    attribution: '© OpenStreetMap contributors, ODbL',
  );

  const mapPlaces = <CampusPlace>[
    CampusPlace(code: '3', name: 'Amphi C', kind: PlaceKind.amphi),
  ];

  final mapEvent = ScheduleEvent(
    title: 'Algèbre',
    start: DateTime(2026, 9, 7, 8),
    end: DateTime(2026, 9, 7, 10),
    groups: const [],
    teachers: const [],
    room: 'Amphi C (V)',
  );

  Future<void> openEventSheet(WidgetTester tester) async {
    unawaited(
      tabNavigator(tester).push(
        MaterialPageRoute<void>(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showEventSheet(context, mapEvent),
                child: const Text('ouvrir le cours'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('ouvrir le cours'));
    await tester.pumpAndSettle();
  }

  testWidgets('a page opened from a tab keeps the bottom bar', (tester) async {
    await pumpShell(tester);
    await openDetail(tester);
    expect(find.text('détail'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('the schedule map action selects and focuses the map tab', (
    tester,
  ) async {
    await pumpShell(tester, campusGeo: mapGeo, campusPlaces: mapPlaces);
    await openEventSheet(tester);

    await tester.tap(find.text('Voir sur la carte'));
    await tester.pumpAndSettle();

    expect(selectedIndex(tester), 3);
    expect(find.text('Bâtiment 3'), findsOneWidget);
    final painter = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((paint) => paint.painter)
        .whereType<CampusMapPainter>()
        .single;
    expect(painter.selected, '3');
  });

  testWidgets('system back closes the page before leaving the tab', (
    tester,
  ) async {
    await pumpShell(tester);
    await openDetail(tester);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('détail'), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(selectedIndex(tester), 2);
  });

  testWidgets('system back from another tab returns to Aujourd’hui', (
    tester,
  ) async {
    await pumpShell(tester);
    await tester.tap(destination('Carte'));
    await tester.pumpAndSettle();
    expect(selectedIndex(tester), 3);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(selectedIndex(tester), 2);
  });

  testWidgets('each destination keeps its own stack', (tester) async {
    await pumpShell(tester);
    await openDetail(tester);

    await tester.tap(destination('Carte'));
    await tester.pumpAndSettle();
    expect(find.text('détail'), findsNothing);

    await tester.tap(destination('Aujourd’hui'));
    await tester.pumpAndSettle();
    expect(find.text('détail'), findsOneWidget);
  });

  testWidgets('a hub module card selects that destination', (tester) async {
    await pumpShell(tester);
    final card = find.widgetWithText(ModuleCard, 'Emploi du temps');
    expect(card, findsOneWidget);

    await tester.tap(card);
    await tester.pumpAndSettle();

    expect(selectedIndex(tester), 0);
  });

  testWidgets('returning to Cours requests today without changing its mode', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        weatherProvider.overrideWith(
          (ref) => Stream<CachedEntry<WeatherSnapshot>>.value(
            const CachedEntry<WeatherSnapshot>(
              refreshState: RefreshState.failedUpstream,
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: campusTheme(Brightness.light),
          home: const CampusShell(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(destination('Cours'));
    await tester.pumpAndSettle();
    expect(container.read(scheduleTodayRequestProvider), 1);

    await tester.tap(destination('Carte'));
    await tester.pumpAndSettle();
    await tester.tap(destination('Cours'));
    await tester.pumpAndSettle();
    expect(container.read(scheduleTodayRequestProvider), 2);
  });

  testWidgets('a hub card with no destination opens under the bar', (
    tester,
  ) async {
    await pumpShell(tester);
    final card = find.widgetWithText(ModuleCard, 'Météo');
    expect(card, findsOneWidget);

    await tester.tap(card);
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'Météo'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(selectedIndex(tester), 2);
  });
}
