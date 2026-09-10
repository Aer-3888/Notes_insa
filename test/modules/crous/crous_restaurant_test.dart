import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/modules/crous/crous_restaurant.dart';

void main() {
  const weekdays = <int>{
    DateTime.monday,
    DateTime.tuesday,
    DateTime.wednesday,
    DateTime.thursday,
    DateTime.friday,
  };
  const mondayToThursday = <int>{
    DateTime.monday,
    DateTime.tuesday,
    DateTime.wednesday,
    DateTime.thursday,
  };

  CrousRestaurant restaurant({bool declaredClosed = false}) => CrousRestaurant(
    id: 915,
    name: 'Resto U’ Étoile',
    shortName: 'Étoile',
    mapCode: 'RU-E',
    officialUrl: 'https://www.crous-rennes.fr/restaurant/resto-u-letoile-3/',
    declaredClosed: declaredClosed,
    openingPeriods: const <CrousOpeningPeriod>[
      CrousOpeningPeriod(
        days: weekdays,
        opensAtMinute: 11 * 60 + 15,
        closesAtMinute: 13 * 60 + 45,
      ),
      CrousOpeningPeriod(
        days: mondayToThursday,
        opensAtMinute: 18 * 60 + 15,
        closesAtMinute: 20 * 60,
      ),
    ],
    syncedAt: DateTime.utc(2026, 9, 10, 20, 35),
  );

  test('reports opening, closing, and the gap between services', () {
    expect(restaurant().statusAt(DateTime(2026, 9, 10, 12)).label, 'Ouvert');

    final afternoon = restaurant().statusAt(DateTime(2026, 9, 10, 15));
    expect(afternoon.availability, CrousAvailability.opensLater);
    expect(afternoon.detail, 'Ouvre à 18 h 15');

    final evening = restaurant().statusAt(DateTime(2026, 9, 10, 19));
    expect(evening.isOpen, isTrue);
    expect(evening.detail, 'Ferme à 20 h');
  });

  test('the CROUS closure flag takes priority over normal hours', () {
    final status = restaurant(
      declaredClosed: true,
    ).statusAt(DateTime(2026, 9, 10, 12));
    expect(status.availability, CrousAvailability.closedByCrous);
    expect(status.label, 'Fermé par le Crous');
  });

  test('recognises moving French public holidays', () {
    final status = restaurant().statusAt(DateTime(2026, 5, 14, 12));
    expect(status.availability, CrousAvailability.publicHoliday);
    expect(status.detail, contains('Ascension'));
  });

  test('warns when tomorrow is a public holiday', () {
    final status = restaurant().statusAt(DateTime(2026, 5, 13, 12));
    expect(status.notice, 'Fermé demain · Ascension');
  });

  test('cache representation round-trips every service period', () {
    final original = restaurant();
    final restored = CrousRestaurant.fromJson(original.toJson());
    expect(restored.name, original.name);
    expect(restored.openingPeriods, hasLength(2));
    expect(restored.openingPeriods.last.opensAtMinute, 18 * 60 + 15);
    expect(
      restored.openingPeriods.last.usualHoursLabel,
      'Lun–jeu · 18 h 15–20 h',
    );
    expect(restored.syncedAt, original.syncedAt);
  });
}
