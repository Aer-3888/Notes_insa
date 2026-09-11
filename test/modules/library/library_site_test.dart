import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/core/time.dart';
import 'package:notes_insa/modules/library/library_site.dart';

void main() {
  setUpAll(initCampusTime);

  LibrarySite site() => kLibrarySites.first;

  Map<String, dynamic> liveData({
    bool isOpen = true,
    int? occupancy = 10,
    String? closingText = 'Ferme à 18:00',
    String? closingAt = '2026-09-11 18:00:00',
    String? openingText,
    String? openingAt,
    List<Object?> notices = const <Object?>[],
    List<Map<String, Object?>> forecasts = const <Map<String, Object?>>[],
  }) => <String, dynamic>{
    'data': <String, dynamic>{
      'status': <String, dynamic>{
        'isOpen': isOpen,
        'openingText': openingText,
        'openingAt': openingAt,
        'closingText': closingText,
        'closingAt': closingAt,
      },
      'notices': notices,
      'liveAttendance': <String, dynamic>{'occupancy': occupancy},
      'todayForecasts': forecasts,
    },
  };

  group('site list', () {
    test('covers both libraries with their booking pages', () {
      expect(kLibrarySites.map((s) => s.slug), <String>[
        'biblinsa',
        'bu-beaulieu-1',
      ]);
      for (final s in kLibrarySites) {
        expect(
          s.bookingUrl,
          'https://affluences.com/fr/sites/${s.slug}/reservation',
        );
      }
    });
  });

  group('crowd bands', () {
    LibraryStatus statusAt(int occupancy, {bool isOpen = true}) =>
        LibraryStatus.fromLiveData(
          site(),
          liveData(occupancy: occupancy, isOpen: isOpen),
          now: campusInstant(DateTime(2026, 9, 11, 14)),
        );

    test('reads calm below 40', () {
      expect(statusAt(39).crowd, LibraryCrowd.calm);
      expect(statusAt(39).occupancyLabel, 'Calme · 39 %');
    });

    test('reads busy from 40 to 74', () {
      expect(statusAt(40).crowd, LibraryCrowd.busy);
      expect(statusAt(74).crowd, LibraryCrowd.busy);
      expect(statusAt(40).occupancyLabel, 'Fréquentée · 40 %');
    });

    test('reads packed from 75', () {
      expect(statusAt(75).crowd, LibraryCrowd.packed);
      expect(statusAt(75).occupancyLabel, 'Bondée · 75 %');
    });

    test('a closed library reports closed whatever the counter says', () {
      final closed = statusAt(60, isOpen: false);
      expect(closed.crowd, LibraryCrowd.closed);
      expect(closed.occupancyLabel, 'Fermée');
      expect(closed.gauge, isNull);
    });

    test('a missing counter is unknown, not zero', () {
      final status = LibraryStatus.fromLiveData(
        site(),
        liveData(occupancy: null),
        now: campusInstant(DateTime(2026, 9, 11, 14)),
      );
      expect(status.crowd, LibraryCrowd.unknown);
      expect(status.gauge, isNull);
    });

    test('the gauge is the occupancy as a fraction', () {
      expect(statusAt(35).gauge, closeTo(0.35, 0.001));
    });
  });

  group('status line', () {
    test('keeps the closing sentence the API already localised', () {
      final status = LibraryStatus.fromLiveData(
        site(),
        liveData(),
        now: campusInstant(DateTime(2026, 9, 11, 14)),
      );
      expect(status.statusLabel, 'Ferme à 18:00');
      expect(status.isOpen, isTrue);
      expect(status.closingAt, campusInstant(DateTime(2026, 9, 11, 18)));
    });

    test('falls back to the opening sentence when closed', () {
      final status = LibraryStatus.fromLiveData(
        site(),
        liveData(
          isOpen: false,
          closingText: null,
          closingAt: null,
          openingText: 'Ouvre à 9:00',
          openingAt: '2026-09-12 09:00:00',
        ),
        now: campusInstant(DateTime(2026, 9, 11, 22)),
      );
      expect(status.statusLabel, 'Ouvre à 9:00');
      expect(status.openingAt, campusInstant(DateTime(2026, 9, 12, 9)));
    });
  });

  group('forecast hint', () {
    Map<String, Object?> bucket(
      String start,
      int occupancy,
      String evolution,
    ) => <String, Object?>{
      'hourRange': <String>[start, '2026-09-11 23:00:00'],
      'occupancy': occupancy,
      'occupancyEvolution': evolution,
    };

    LibraryStatus withForecasts(List<Map<String, Object?>> buckets) =>
        LibraryStatus.fromLiveData(
          site(),
          liveData(forecasts: buckets),
          now: campusInstant(DateTime(2026, 9, 11, 14)),
        );

    test('announces the next rise', () {
      final status = withForecasts(<Map<String, Object?>>[
        bucket('2026-09-11 14:00:00', 10, 'STABLE'),
        bucket('2026-09-11 15:30:00', 15, 'INCREASE'),
      ]);
      expect(status.forecastHint, 'se remplit vers 15:30');
    });

    test('announces the next lull', () {
      final status = withForecasts(<Map<String, Object?>>[
        bucket('2026-09-11 17:00:00', 5, 'DECREASE'),
      ]);
      expect(status.forecastHint, 'plus calme après 17:00');
    });

    test('ignores buckets that already started and stable ones', () {
      expect(
        withForecasts(<Map<String, Object?>>[
          bucket('2026-09-11 12:00:00', 90, 'INCREASE'),
          bucket('2026-09-11 16:00:00', 10, 'STABLE'),
        ]).forecastHint,
        isNull,
      );
    });

    test('says nothing when the library is closed', () {
      final status = LibraryStatus.fromLiveData(
        site(),
        liveData(
          isOpen: false,
          forecasts: <Map<String, Object?>>[
            bucket('2026-09-11 15:30:00', 15, 'INCREASE'),
          ],
        ),
        now: campusInstant(DateTime(2026, 9, 11, 14)),
      );
      expect(status.forecastHint, isNull);
    });
  });

  group('notices', () {
    test('accepts plain strings and objects, and drops the rest', () {
      final status = LibraryStatus.fromLiveData(
        site(),
        liveData(
          notices: <Object?>[
            'Fermeture exceptionnelle',
            <String, Object?>{'title': 'Travaux au 1er étage'},
            <String, Object?>{'unexpected': 1},
            42,
          ],
        ),
        now: campusInstant(DateTime(2026, 9, 11, 14)),
      );
      expect(status.notices, <String>[
        'Fermeture exceptionnelle',
        'Travaux au 1er étage',
      ]);
    });
  });

  group('cache round trip', () {
    test('survives toJson/fromJson', () {
      final status = LibraryStatus.fromLiveData(
        site(),
        liveData(
          forecasts: <Map<String, Object?>>[
            <String, Object?>{
              'hourRange': <String>[
                '2026-09-11 15:30:00',
                '2026-09-11 17:00:00',
              ],
              'occupancy': 15,
              'occupancyEvolution': 'INCREASE',
            },
          ],
          notices: <Object?>['Travaux'],
        ),
        now: campusInstant(DateTime(2026, 9, 11, 14)),
      );
      final restored = LibraryStatus.fromJson(status.toJson());
      expect(restored, isNotNull);
      expect(restored!.site.slug, status.site.slug);
      expect(restored.occupancy, status.occupancy);
      expect(restored.isOpen, status.isOpen);
      expect(restored.statusLabel, status.statusLabel);
      expect(restored.closingAt, status.closingAt);
      expect(restored.notices, status.notices);
      expect(restored.forecastHint, status.forecastHint);
    });

    test('rejects a payload whose site is no longer known', () {
      final json = LibraryStatus.fromLiveData(
        site(),
        liveData(),
        now: campusInstant(DateTime(2026, 9, 11, 14)),
      ).toJson();
      json['slug'] = 'bu-disparue';
      expect(LibraryStatus.fromJson(json), isNull);
    });
  });
}
