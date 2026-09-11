import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:notes_insa/core/time.dart';
import 'package:notes_insa/modules/library/library_service.dart';
import 'package:notes_insa/modules/library/library_site.dart';

void main() {
  setUpAll(initCampusTime);

  DateTime now() => campusInstant(DateTime(2026, 9, 11, 14));

  String liveData({required bool isOpen, required int occupancy}) =>
      jsonEncode(<String, dynamic>{
        'data': <String, dynamic>{
          'status': <String, dynamic>{
            'isOpen': isOpen,
            'closingText': 'Ferme à 18:00',
            'closingAt': '2026-09-11 18:00:00',
          },
          'notices': <Object?>[],
          'liveAttendance': <String, dynamic>{'occupancy': occupancy},
          'todayForecasts': <Object?>[],
        },
      });

  http.Response json(String body, {int status = 200}) => http.Response.bytes(
    utf8.encode(body),
    status,
    headers: <String, String>{'content-type': 'application/json'},
  );

  test('reads a recorded Affluences response', () async {
    // test/fixtures/affluences_live_data.json is a real capture of
    // /app/v4/sites/biblinsa/live-data?lang=fr (2026-09-11, 14:05 campus time).
    final recorded = File(
      'test/fixtures/affluences_live_data.json',
    ).readAsStringSync();
    final service = LibraryService(
      client: MockClient((_) async => json(recorded)),
    );

    final status = (await service.fetch(
      sites: kLibrarySites.take(1).toList(),
      now: campusInstant(DateTime(2026, 9, 11, 14, 5)),
    )).single;

    expect(status.site.slug, 'biblinsa');
    expect(status.isOpen, isTrue);
    expect(status.occupancy, 15);
    expect(status.crowd, LibraryCrowd.calm);
    expect(status.statusLabel, 'Ferme à 18:00');
    expect(status.closingAt, campusInstant(DateTime(2026, 9, 11, 18)));
    expect(status.notices, isEmpty);
    expect(status.forecastHint, 'plus calme après 14:30');
  });

  test('reads every site, one request each', () async {
    final asked = <String>[];
    final service = LibraryService(
      client: MockClient((request) async {
        asked.add(request.url.path);
        return json(liveData(isOpen: true, occupancy: 35));
      }),
    );

    final statuses = await service.fetch(now: now());

    expect(statuses, hasLength(kLibrarySites.length));
    expect(statuses.first.occupancy, 35);
    expect(asked, <String>[
      '/app/v4/sites/biblinsa/live-data',
      '/app/v4/sites/bu-beaulieu-1/live-data',
    ]);
  });

  test('asks for French labels', () async {
    Uri? seen;
    await LibraryService(
      client: MockClient((request) async {
        seen ??= request.url;
        return json(liveData(isOpen: true, occupancy: 10));
      }),
    ).fetch(sites: kLibrarySites.take(1).toList(), now: now());

    expect(seen!.queryParameters['lang'], 'fr');
  });

  test('keeps the site that answered when the other fails', () async {
    final service = LibraryService(
      client: MockClient((request) async {
        if (request.url.path.contains('biblinsa')) {
          return json('{"message":"boom"}', status: 500);
        }
        return json(liveData(isOpen: true, occupancy: 35));
      }),
    );

    final statuses = await service.fetch(now: now());

    expect(statuses, hasLength(1));
    expect(statuses.single.site.slug, 'bu-beaulieu-1');
  });

  test('throws when no site answered', () async {
    final service = LibraryService(
      client: MockClient((_) async => http.Response('<html>nope</html>', 502)),
    );

    await expectLater(service.fetch(now: now()), throwsA(isA<Exception>()));
  });

  test('rejects a body that is not the expected JSON', () async {
    final service = LibraryService(
      client: MockClient((_) async => json('<html>hijacked</html>')),
    );

    await expectLater(service.fetch(now: now()), throwsA(isA<Exception>()));
  });

  group('rate limiting', () {
    test('stops at the first 429 and reports the delay', () async {
      var calls = 0;
      final service = LibraryService(
        client: MockClient((_) async {
          calls++;
          return http.Response(
            'slow down',
            429,
            headers: <String, String>{'retry-after': '90'},
          );
        }),
      );

      await expectLater(
        service.fetch(now: now()),
        throwsA(
          isA<LibraryRateLimited>().having(
            (e) => e.retryAfter,
            'retryAfter',
            const Duration(seconds: 90),
          ),
        ),
      );
      expect(calls, 1, reason: 'the second site must not be asked');
    });

    test('falls back to a long cooldown when no delay is given', () async {
      final service = LibraryService(
        client: MockClient((_) async => http.Response('slow down', 429)),
      );

      await expectLater(
        service.fetch(now: now()),
        throwsA(
          isA<LibraryRateLimited>().having(
            (e) => e.retryAfter,
            'retryAfter',
            kLibraryDefaultCooldown,
          ),
        ),
      );
    });

    test('reads an HTTP-date delay', () async {
      final service = LibraryService(
        client: MockClient(
          (_) async => http.Response(
            'slow down',
            429,
            headers: <String, String>{
              'retry-after': HttpDate.format(
                DateTime.now().toUtc().add(const Duration(minutes: 5)),
              ),
            },
          ),
        ),
      );

      await expectLater(
        service.fetch(now: now()),
        throwsA(
          isA<LibraryRateLimited>().having(
            (e) => e.retryAfter.inMinutes,
            'retryAfter',
            inInclusiveRange(4, 5),
          ),
        ),
      );
    });
  });
}
