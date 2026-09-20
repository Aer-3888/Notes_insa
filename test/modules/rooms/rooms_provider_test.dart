import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:notes_insa/core/module_cache.dart';
import 'package:notes_insa/core/module_cache_provider.dart';
import 'package:notes_insa/core/time.dart';
import 'package:notes_insa/modules/rooms/rooms_provider.dart';
import 'package:notes_insa/modules/schedule/ade_groups.dart';
import 'package:notes_insa/modules/schedule/ade_groups_provider.dart';
import 'package:notes_insa/modules/schedule/ade_service.dart';
import 'package:notes_insa/modules/schedule/schedule_provider.dart';

const _rooms = <AdeGroup>[
  AdeGroup(id: 1, name: 'Amphi B Bât 12', category: AdeCategory.room),
  AdeGroup(id: 2, name: 'Amphi C Bât 12', category: AdeCategory.room),
  AdeGroup(id: 3, name: '... MOODLE', category: AdeCategory.room),
  AdeGroup(id: 4, name: 'AMPHIS', category: AdeCategory.room),
  AdeGroup(
    id: 5,
    name: 'Amphi D Bât 12',
    category: AdeCategory.room,
    parentId: 4,
  ),
  AdeGroup(id: 6, name: 'S7-INFO'),
];

String _ics(List<String> uids) => <String>[
  'BEGIN:VCALENDAR\r\n',
  for (final uid in uids)
    'BEGIN:VEVENT\r\nUID:$uid\r\n'
        'DTSTART:20260921T080000Z\r\nDTEND:20260921T100000Z\r\n'
        'SUMMARY:CPOO2\r\nLOCATION:Amphi B Bât 12\r\n'
        'END:VEVENT\r\n',
  'END:VCALENDAR\r\n',
].join();

String _eventIcs({required String uid, required String room}) => <String>[
  'BEGIN:VCALENDAR\r\n',
  'BEGIN:VEVENT\r\nUID:$uid\r\n'
      'DTSTART:20260921T080000Z\r\nDTEND:20260921T100000Z\r\n'
      'SUMMARY:CPOO2\r\nLOCATION:$room\r\n'
      'END:VEVENT\r\n',
  'END:VCALENDAR\r\n',
].join();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(initCampusTime);

  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('rooms_provider_test');
  });
  tearDown(() => root.delete(recursive: true));

  ProviderContainer container({
    required List<Uri> asked,
    List<String> uids = const <String>['e1'],
  }) {
    final c = ProviderContainer(
      overrides: [
        adeGroupsProvider.overrideWith((ref) async => _rooms),
        moduleCacheProvider.overrideWith((ref) async => ModuleCache(root)),
        adeServiceProvider.overrideWithValue(
          AdeService(
            client: MockClient((request) async {
              asked.add(request.url);
              return http.Response(_ics(uids), 200);
            }),
          ),
        ),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('lists only rooms it can place on the map', () async {
    final c = container(asked: <Uri>[]);
    final rooms = await c.read(listableRoomsProvider.future);
    expect(rooms.map((r) => r.name), <String>[
      'Amphi B Bât 12',
      'Amphi C Bât 12',
      'Amphi D Bât 12',
    ]);
    expect(rooms.map((r) => r.name), isNot(contains('... MOODLE')));
    expect(rooms.map((r) => r.name), isNot(contains('AMPHIS')));
    expect(rooms.map((r) => r.name), isNot(contains('S7-INFO')));
  });

  test('asks ADE for exactly those rooms', () async {
    final asked = <Uri>[];
    final c = container(asked: asked);
    await _settle(c);
    expect(asked, hasLength(1));
    expect(asked.single.queryParameters['resources'], '1,2,5');
  });

  test('asks only for today', () async {
    final asked = <Uri>[];
    final c = container(asked: asked);
    await _settle(c);
    final q = asked.single.queryParameters;
    final now = campusNow();
    final today =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    expect(q['firstDate'], today);
  });

  test('a session returned by two batches is kept once', () async {
    final c = container(asked: <Uri>[], uids: <String>['e1', 'e1', 'e2']);
    final entry = await _settle(c);
    expect(entry.data, hasLength(2));
  });

  test(
    'keeps every room when one session is returned by two batches',
    () async {
      final rooms = <AdeGroup>[
        for (var i = 1; i <= 101; i++)
          AdeGroup(id: i, name: 'Salle $i Bât 12', category: AdeCategory.room),
      ];
      final c = ProviderContainer(
        overrides: [
          adeGroupsProvider.overrideWith((ref) async => rooms),
          moduleCacheProvider.overrideWith((ref) async => ModuleCache(root)),
          adeServiceProvider.overrideWithValue(
            AdeService(
              client: MockClient((request) async {
                final ids = request.url.queryParameters['resources']!;
                final room = ids.startsWith('1,')
                    ? 'Salle 1 Bât 12'
                    : 'Salle 101 Bât 12';
                return http.Response(_eventIcs(uid: 'shared', room: room), 200);
              }),
            ),
          ),
        ],
      );
      addTearDown(c.dispose);

      final entry = await _settle(c);
      expect(entry.data, hasLength(1));
      expect(entry.data.single.room, 'Salle 1 Bât 12, Salle 101 Bât 12');
    },
  );

  test('a second read is served from the cache before refreshing', () async {
    final asked = <Uri>[];
    await _settle(container(asked: asked));
    expect(asked, hasLength(1));

    final states = <CachedEntry<dynamic>>[];
    final c = container(asked: asked);
    final sub = c.listen(roomsProvider, (prev, next) {
      if (next.hasValue) states.add(next.value!);
    }, fireImmediately: true);
    addTearDown(sub.close);
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(states.first.refreshState, RefreshState.refreshing);
    expect(states.first.data, isNotNull);
    expect(states.last.refreshState, RefreshState.fresh);
  });

  test(
    'an upstream failure still yields a state the screen can show',
    () async {
      final c = ProviderContainer(
        overrides: [
          adeGroupsProvider.overrideWith((ref) async => _rooms),
          moduleCacheProvider.overrideWith((ref) async => ModuleCache(root)),
          adeServiceProvider.overrideWithValue(
            AdeService(
              client: MockClient((_) async => http.Response('nope', 503)),
            ),
          ),
        ],
      );
      addTearDown(c.dispose);
      final entry = await _settle(c);
      expect(entry.data, isNull);
      expect(entry.refreshState, RefreshState.failedOffline);
    },
  );
}

Future<CachedEntry<dynamic>> _settle(ProviderContainer c) async {
  CachedEntry<dynamic>? last;
  final sub = c.listen(roomsProvider, (prev, next) {
    if (next.hasValue) last = next.value;
  }, fireImmediately: true);
  await Future<void>.delayed(const Duration(milliseconds: 300));
  sub.close();
  return last!;
}
