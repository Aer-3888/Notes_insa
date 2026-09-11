import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:notes_insa/core/module_cache.dart';
import 'package:notes_insa/core/module_cache_provider.dart';
import 'package:notes_insa/core/time.dart';
import 'package:notes_insa/modules/library/library_provider.dart';
import 'package:notes_insa/modules/library/library_service.dart';
import 'package:notes_insa/modules/library/library_site.dart';

void main() {
  setUpAll(initCampusTime);

  late Directory root;
  late ModuleCache cache;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('library_provider_test');
    cache = ModuleCache(root);
  });

  tearDown(() async {
    if (root.existsSync()) await root.delete(recursive: true);
  });

  LibraryStatus status(
    LibrarySite site, {
    bool isOpen = true,
    int occupancy = 20,
    DateTime? openingAt,
  }) => LibraryStatus(
    site: site,
    isOpen: isOpen,
    occupancy: occupancy,
    statusLabel: isOpen ? 'Ferme à 18:00' : 'Ouvre à 9:00',
    openingAt: openingAt,
  );

  /// Seeds the module cache the way the provider writes it.
  Future<void> seed({
    required Duration age,
    Duration? cooldown,
    List<LibraryStatus>? sites,
  }) async {
    final now = campusNow();
    await cache.write(
      kLibraryModuleId,
      schemaVersion: kLibrarySchemaVersion,
      data: <String, dynamic>{
        'syncedAtMs': now.subtract(age).millisecondsSinceEpoch,
        'cooldownUntilMs': cooldown == null
            ? null
            : now.add(cooldown).millisecondsSinceEpoch,
        'sites': <Map<String, dynamic>>[
          for (final site in sites ?? kLibrarySites.map(status).toList())
            site.toJson(),
        ],
      },
    );
  }

  http.Response liveData({int occupancy = 35}) => http.Response.bytes(
    utf8.encode(
      jsonEncode(<String, dynamic>{
        'data': <String, dynamic>{
          'status': <String, dynamic>{
            'isOpen': true,
            'closingText': 'Ferme à 18:00',
            'closingAt': '2026-09-11 18:00:00',
          },
          'notices': <Object?>[],
          'liveAttendance': <String, dynamic>{'occupancy': occupancy},
          'todayForecasts': <Object?>[],
        },
      }),
    ),
    200,
    headers: <String, String>{'content-type': 'application/json'},
  );

  /// Runs the provider to completion and reports what it emitted and what it
  /// cost upstream.
  Future<({CachedEntry<List<LibraryStatus>> entry, int calls})> run({
    int tick = 0,
    http.Response Function()? respond,
  }) async {
    var calls = 0;
    final container = ProviderContainer(
      overrides: [
        moduleCacheProvider.overrideWith((ref) async => cache),
        libraryServiceProvider.overrideWithValue(
          LibraryService(
            client: MockClient((_) async {
              calls++;
              return (respond ?? liveData)();
            }),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    final seen = <CachedEntry<List<LibraryStatus>>>[];
    container.listen(libraryStatusProvider, (_, next) {
      final value = next.value;
      if (value != null) seen.add(value);
    }, fireImmediately: true);

    // The provider yields the cached snapshot before the refreshed one, and
    // writing the cache is real file I/O, so wait for the settled emission
    // rather than for a fixed number of event loop turns.
    Future<void> settle() async {
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      do {
        await pumpEventQueue();
      } while ((seen.isEmpty ||
              seen.last.refreshState == RefreshState.refreshing) &&
          DateTime.now().isBefore(deadline));
    }

    await settle();

    // A tap on the card's refresh button, which re-runs the provider.
    for (var i = 0; i < tick; i++) {
      container.read(libraryRefreshTickProvider.notifier).bump();
      await settle();
    }

    return (entry: seen.last, calls: calls);
  }

  test('fetches every site when nothing is cached', () async {
    final result = await run();

    expect(result.calls, kLibrarySites.length);
    expect(result.entry.data, hasLength(kLibrarySites.length));
    expect(result.entry.refreshState, RefreshState.fresh);
    expect(result.entry.data!.first.occupancy, 35);
  });

  test('writes what it read, so the next launch can start from it', () async {
    await run();

    final stored = await cache.read(
      kLibraryModuleId,
      schemaVersion: kLibrarySchemaVersion,
    );
    expect(stored.data!['sites'], hasLength(kLibrarySites.length));
    expect(stored.data!['syncedAtMs'], isA<int>());
    expect(stored.data!['cooldownUntilMs'], isNull);
  });

  group('rate limit', () {
    test('a cache younger than the interval costs no request', () async {
      await seed(age: const Duration(minutes: 3));

      final result = await run();

      expect(result.calls, 0);
      expect(result.entry.refreshState, RefreshState.fresh);
      expect(result.entry.data, hasLength(kLibrarySites.length));
      expect(
        result.entry.data!.first.occupancy,
        20,
        reason: 'served from cache',
      );
    });

    test('a cache older than the interval refreshes', () async {
      await seed(age: kLibraryMinRefreshInterval + const Duration(minutes: 1));

      final result = await run();

      expect(result.calls, kLibrarySites.length);
      expect(result.entry.data!.first.occupancy, 35);
    });

    test('closed libraries are left alone until they reopen', () async {
      await seed(
        age: const Duration(hours: 8),
        sites: <LibraryStatus>[
          for (final site in kLibrarySites)
            status(
              site,
              isOpen: false,
              occupancy: 0,
              openingAt: campusNow().add(const Duration(hours: 3)),
            ),
        ],
      );

      final result = await run();

      expect(result.calls, 0);
      expect(result.entry.data!.every((s) => !s.isOpen), isTrue);
    });

    test('a library that should have reopened is refreshed', () async {
      await seed(
        age: const Duration(hours: 8),
        sites: <LibraryStatus>[
          for (final site in kLibrarySites)
            status(
              site,
              isOpen: false,
              occupancy: 0,
              openingAt: campusNow().subtract(const Duration(minutes: 10)),
            ),
        ],
      );

      final result = await run();

      expect(result.calls, kLibrarySites.length);
    });

    test('a manual refresh beats the interval', () async {
      await seed(age: const Duration(minutes: 1));

      final result = await run(tick: 1);

      expect(result.calls, kLibrarySites.length);
    });

    test('a 429 is remembered and holds even a manual refresh', () async {
      await seed(age: kLibraryMinRefreshInterval + const Duration(minutes: 1));

      final limited = await run(
        respond: () => http.Response(
          'slow down',
          429,
          headers: <String, String>{'retry-after': '600'},
        ),
      );

      expect(limited.calls, 1, reason: 'stops at the first refusal');
      expect(limited.entry.refreshState, RefreshState.failedUpstream);
      expect(limited.entry.data, hasLength(kLibrarySites.length));

      final stored = await cache.read(
        kLibraryModuleId,
        schemaVersion: kLibrarySchemaVersion,
      );
      expect(stored.data!['cooldownUntilMs'], isA<int>());

      final during = await run(tick: 1);
      expect(during.calls, 0, reason: 'the cooldown is not negotiable');
    });

    test('the cached snapshot keeps its own age through a 429', () async {
      await seed(age: const Duration(hours: 2));

      final limited = await run(respond: () => http.Response('slow down', 429));

      final stored = await cache.read(
        kLibraryModuleId,
        schemaVersion: kLibrarySchemaVersion,
      );
      final syncedAt = campusFromEpochMs(stored.data!['syncedAtMs'] as int);
      expect(
        campusNow().difference(syncedAt).inMinutes,
        greaterThanOrEqualTo(119),
      );
      expect(limited.entry.cachedAt, syncedAt);
    });
  });

  group('failures keep the card', () {
    test('being offline shows the cached snapshot', () async {
      await seed(age: const Duration(hours: 2));

      final result = await run(
        respond: () => throw const SocketException('no route'),
      );

      expect(result.entry.refreshState, RefreshState.failedOffline);
      expect(result.entry.data, hasLength(kLibrarySites.length));
    });

    test('an upstream error with no cache yields an empty entry', () async {
      final result = await run(respond: () => http.Response('nope', 503));

      expect(result.entry.refreshState, RefreshState.failedUpstream);
      expect(result.entry.isEmpty, isTrue);
    });
  });
}
