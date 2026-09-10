import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/core/module_cache.dart';
import 'package:notes_insa/core/time.dart';
import 'package:notes_insa/modules/crous/crous_map_details.dart';
import 'package:notes_insa/modules/crous/crous_provider.dart';
import 'package:notes_insa/modules/crous/crous_restaurant.dart';
import 'package:notes_insa/theme/campus_theme.dart';

void main() {
  setUpAll(initCampusTime);

  const etoile = CrousRestaurant(
    id: 915,
    name: 'Resto U’ Étoile',
    shortName: 'Étoile',
    mapCode: 'RU-E',
    officialUrl: 'https://www.crous-rennes.fr/restaurant/resto-u-letoile-3/',
    declaredClosed: true,
    openingPeriods: <CrousOpeningPeriod>[
      CrousOpeningPeriod(
        days: <int>{1, 2, 3, 4, 5},
        opensAtMinute: 11 * 60 + 15,
        closesAtMinute: 13 * 60 + 45,
      ),
      CrousOpeningPeriod(
        days: <int>{1, 2, 3, 4},
        opensAtMinute: 18 * 60 + 15,
        closesAtMinute: 20 * 60,
      ),
    ],
  );

  Future<void> pumpDetails(
    WidgetTester tester,
    CachedEntry<List<CrousRestaurant>> entry,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          crousRestaurantsProvider.overrideWith(
            (ref) => Stream<CachedEntry<List<CrousRestaurant>>>.value(entry),
          ),
        ],
        child: MaterialApp(
          theme: campusTheme(Brightness.light),
          home: const Scaffold(body: CrousMapDetails(mapCode: 'RU-E')),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('shows the live exception and the usual schedule together', (
    tester,
  ) async {
    await pumpDetails(
      tester,
      const CachedEntry<List<CrousRestaurant>>(data: <CrousRestaurant>[etoile]),
    );

    expect(find.text('Fermé par le Crous'), findsOneWidget);
    expect(find.text('Midi · Lun–ven · 11 h 15–13 h 45'), findsOneWidget);
    expect(find.text('Soir · Lun–jeu · 18 h 15–20 h'), findsOneWidget);
    expect(find.textContaining('jours fériés'), findsOneWidget);
  });

  testWidgets('keeps usual hours visible when live status is unavailable', (
    tester,
  ) async {
    await pumpDetails(tester, const CachedEntry<List<CrousRestaurant>>());

    expect(find.text('Statut en direct indisponible'), findsOneWidget);
    expect(find.text('Midi · Lun–ven · 11 h 15–13 h 45'), findsOneWidget);
  });
}
