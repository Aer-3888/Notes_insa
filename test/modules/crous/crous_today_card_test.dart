import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/core/campus_navigation.dart';
import 'package:notes_insa/core/module_cache.dart';
import 'package:notes_insa/core/time.dart';
import 'package:notes_insa/modules/crous/crous_provider.dart';
import 'package:notes_insa/modules/crous/crous_restaurant.dart';
import 'package:notes_insa/modules/crous/crous_today_card.dart';
import 'package:notes_insa/theme/campus_theme.dart';

void main() {
  setUpAll(initCampusTime);

  const restaurants = <CrousRestaurant>[
    CrousRestaurant(
      id: 915,
      name: 'Resto U’ Étoile',
      shortName: 'Étoile',
      mapCode: 'RU-E',
      officialUrl: 'https://www.crous-rennes.fr/restaurant/resto-u-letoile-3/',
      declaredClosed: false,
      openingPeriods: <CrousOpeningPeriod>[
        CrousOpeningPeriod(
          days: <int>{1, 2, 3, 4, 5},
          opensAtMinute: 675,
          closesAtMinute: 825,
        ),
        CrousOpeningPeriod(
          days: <int>{1, 2, 3, 4},
          opensAtMinute: 1095,
          closesAtMinute: 1200,
        ),
      ],
    ),
    CrousRestaurant(
      id: 916,
      name: "Resto U' Astrolabe",
      shortName: 'Astrolabe',
      mapCode: 'RU-A',
      officialUrl:
          'https://www.crous-rennes.fr/restaurant/resto-u-lastrolabe-3/',
      declaredClosed: false,
      openingPeriods: <CrousOpeningPeriod>[
        CrousOpeningPeriod(
          days: <int>{1, 2, 3, 4, 5},
          opensAtMinute: 675,
          closesAtMinute: 825,
        ),
      ],
    ),
  ];

  Future<void> pumpCard(
    WidgetTester tester, {
    required ValueChanged<String> onOpenMap,
  }) async {
    final mapFocus = CampusMapFocus();
    addTearDown(mapFocus.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          crousRestaurantsProvider.overrideWith(
            (ref) => Stream<CachedEntry<List<CrousRestaurant>>>.value(
              CachedEntry<List<CrousRestaurant>>(
                data: restaurants,
                cachedAt: DateTime.now(),
              ),
            ),
          ),
        ],
        child: MaterialApp(
          theme: campusTheme(Brightness.light),
          home: Scaffold(
            body: CampusNavigationScope(
              mapFocus: mapFocus,
              onOpenMap: (code, {startGuidance = false}) => onOpenMap(code),
              child: const SingleChildScrollView(child: CrousTodayCard()),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('shows Étoile and Astrolabe, not the former INSA selection', (
    tester,
  ) async {
    await pumpCard(tester, onOpenMap: (_) {});

    expect(find.text('Restos U’ proches'), findsOneWidget);
    expect(find.text('Étoile'), findsOneWidget);
    expect(find.text('Astrolabe'), findsOneWidget);
    expect(find.text('INSA'), findsNothing);
    expect(find.textContaining('Source Crous'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('opens the selected restaurant on the campus map', (
    tester,
  ) async {
    String? openedCode;
    await pumpCard(tester, onOpenMap: (code) => openedCode = code);

    await tester.tap(find.text('Étoile'));
    expect(openedCode, 'RU-E');
  });
}
