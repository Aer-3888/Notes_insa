import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../core/module_cache.dart';
import '../../core/module_cache_provider.dart';
import '../../core/time.dart';
import '../campus_map/campus_places.dart';
import '../schedule/ade_groups.dart';
import '../schedule/ade_groups_provider.dart';
import '../schedule/ade_link.dart';
import '../schedule/ade_tree.dart';
import '../schedule/room_lookup.dart';
import '../schedule/schedule_event.dart';
import '../schedule/schedule_provider.dart';
import 'room_filter.dart';
import 'room_status.dart';

const String kRoomsModuleId = 'salles';
const int kRoomsSchemaVersion = 2;

/// Rooms with a known campus building.
final listableRoomsProvider = FutureProvider<List<AdeGroup>>((ref) async {
  final rooms = AdeGroups.ofCategory(
    await ref.watch(adeGroupsProvider.future),
    AdeCategory.room,
  );
  final places = await ref.watch(campusPlacesProvider.future);
  return rooms
      .where((r) => !AdeTree.hasChildren(rooms, r.id))
      .where((r) => resolveRoom(r.name, places).isResolved)
      .toList();
});

final roomBuildingsProvider = FutureProvider<Map<int, String>>((ref) async {
  final rooms = ref.watch(listableRoomsProvider.future);
  final places = ref.watch(campusPlacesProvider.future);
  final resolved = await places;
  return <int, String>{
    for (final room in await rooms)
      room.id: ?resolveRoom(room.name, resolved).buildingCode,
  };
});

final roomStatusesProvider = Provider<List<RoomStatus>?>((ref) {
  final entry = ref.watch(roomsProvider).value;
  final rooms = ref.watch(listableRoomsProvider).value;
  if (entry?.data == null || rooms == null) return null;
  return roomStatuses(rooms: rooms, events: entry!.data!, now: campusNow());
});

final freeRoomsProvider = Provider<List<RoomStatus>?>((ref) {
  final statuses = ref.watch(roomStatusesProvider);
  final minimum = ref.watch(roomFreeDurationProvider).minimum;
  if (statuses == null) return null;
  return statuses
      .where(
        (status) =>
            status.isFree &&
            (status.freeFor == null || status.freeFor! >= minimum),
      )
      .toList();
});

/// Today's room bookings, from cache then ADE.
final roomsProvider = StreamProvider<CachedEntry<List<ScheduleEvent>>>((
  ref,
) async* {
  // Watch before await so Riverpod tracks both providers.
  final roomList = ref.watch(listableRoomsProvider.future);
  final cacheOpen = ref.watch(moduleCacheProvider.future);

  final rooms = await roomList;
  if (rooms.isEmpty) {
    yield const CachedEntry<List<ScheduleEvent>>();
    return;
  }

  final cache = await cacheOpen;
  final cached = await cache.read(
    kRoomsModuleId,
    schemaVersion: kRoomsSchemaVersion,
  );

  CachedEntry<List<ScheduleEvent>>? previous;
  final day = cached.data?['day'] as String?;
  if (cached.data != null && day == _dayKey(campusNow())) {
    final events = <ScheduleEvent>[
      for (final e in cached.data!['events'] as List<dynamic>)
        ScheduleEvent.fromJson(e as Map<String, dynamic>, campusFromEpochMs),
    ];
    previous = CachedEntry<List<ScheduleEvent>>(
      data: events,
      cachedAt: cached.cachedAt,
      refreshState: RefreshState.refreshing,
    );
    yield previous;
  }

  try {
    final now = campusNow();
    final events = await _fetchAll(ref, rooms, now);
    await cache.write(
      kRoomsModuleId,
      schemaVersion: kRoomsSchemaVersion,
      data: <String, dynamic>{
        'day': _dayKey(now),
        'events': <Map<String, dynamic>>[for (final e in events) e.toJson()],
      },
    );
    yield CachedEntry<List<ScheduleEvent>>(
      data: events,
      cachedAt: DateTime.now(),
    );
  } catch (e) {
    final state = e is SocketException || e is http.ClientException
        ? RefreshState.failedOffline
        : RefreshState.failedUpstream;
    yield previous?.withState(state) ??
        CachedEntry<List<ScheduleEvent>>(refreshState: state);
  }
});

Future<List<ScheduleEvent>> _fetchAll(
  Ref ref,
  List<AdeGroup> rooms,
  DateTime now,
) async {
  final service = ref.read(adeServiceProvider);
  final from = DateTime(now.year, now.month, now.day);
  final to = from.add(const Duration(days: 1));

  final batches = <List<int>>[];
  for (var i = 0; i < rooms.length; i += AdeLink.maxIds) {
    batches.add(<int>[
      for (final r in rooms.skip(i).take(AdeLink.maxIds)) r.id,
    ]);
  }

  final results = await Future.wait(<Future<List<ScheduleEvent>>>[
    for (final ids in batches)
      service.fetch(resourceIds: ids, from: from, to: to),
  ]);

  // Events recur across batches. Merge their rooms.
  final byUid = <String, ScheduleEvent>{};
  final extras = <ScheduleEvent>[];
  for (final event in results.expand((e) => e)) {
    final uid = event.uid;
    if (uid == null) {
      extras.add(event);
    } else {
      final earlier = byUid[uid];
      byUid[uid] = earlier == null ? event : _mergeRooms(earlier, event);
    }
  }
  return <ScheduleEvent>[...byUid.values, ...extras];
}

ScheduleEvent _mergeRooms(ScheduleEvent first, ScheduleEvent second) {
  final names = <String>[];
  final seen = <String>{};
  for (final raw in <String?>[first.room, second.room]) {
    for (final name in (raw ?? '').split(',')) {
      final trimmed = name.trim();
      final key = trimmed.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
      if (key.isNotEmpty && seen.add(key)) names.add(trimmed);
    }
  }
  final room = names.isEmpty ? null : names.join(', ');
  if (room == first.room) return first;
  return ScheduleEvent(
    title: first.title,
    start: first.start,
    end: first.end,
    groups: first.groups,
    teachers: first.teachers,
    module: first.module,
    room: room,
    uid: first.uid,
    activityId: first.activityId,
  );
}

String _dayKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';
