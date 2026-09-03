import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/module_cache.dart';
import '../../core/time.dart';
import '../../core/module_cache_provider.dart';
import 'ade_service.dart';
import 'schedule_event.dart';

const String kScheduleModuleId = 'edt';
const int kScheduleSchemaVersion = 1;

/// Small scalar, so it stays in shared_preferences rather than the file cache.
const String kSelectedGroupsKey = 'schedule_resource_ids';

/// How far around today the timetable is fetched. ADE windows this server-side.
const Duration kScheduleLookback = Duration(days: 7);
const Duration kScheduleLookahead = Duration(days: 56);

/// The user's chosen ADE group ids, empty until they pick.
class SelectedGroups extends Notifier<List<int>> {
  @override
  List<int> build() {
    unawaited(_restore());
    return const <int>[];
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(kSelectedGroupsKey) ?? const <String>[];
    final ids = raw.map(int.tryParse).whereType<int>().toList();
    if (ids.isNotEmpty) state = ids;
  }

  Future<void> set(List<int> ids) async {
    state = ids;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      kSelectedGroupsKey,
      ids.map((i) => '$i').toList(),
    );
  }
}

final selectedGroupsProvider = NotifierProvider<SelectedGroups, List<int>>(
  SelectedGroups.new,
);

/// Injected so tests can drive the real screens against a recorded calendar
/// instead of the network.
final adeServiceProvider = Provider<AdeService>((ref) => const AdeService());

/// Cache-first timetable. Emits the cached week immediately so the screen
/// paints offline, then the refreshed one.
final scheduleProvider = StreamProvider<CachedEntry<List<ScheduleEvent>>>((
  ref,
) async* {
  final ids = ref.watch(selectedGroupsProvider);
  if (ids.isEmpty) {
    yield const CachedEntry<List<ScheduleEvent>>();
    return;
  }

  final cache = await ref.watch(moduleCacheProvider.future);
  final cached = await cache.read(
    kScheduleModuleId,
    schemaVersion: kScheduleSchemaVersion,
  );

  CachedEntry<List<ScheduleEvent>>? previous;
  if (cached.data != null) {
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
    final events = await ref
        .read(adeServiceProvider)
        .fetch(
          resourceIds: ids,
          from: now.subtract(kScheduleLookback),
          to: now.add(kScheduleLookahead),
        );
    await cache.write(
      kScheduleModuleId,
      schemaVersion: kScheduleSchemaVersion,
      data: <String, dynamic>{
        'ids': ids,
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

/// The next session starting from now, for the hub card. Reads the same cache,
/// so it costs no extra request and works offline.
final nextCourseProvider = Provider<ScheduleEvent?>((ref) {
  final events = ref.watch(scheduleProvider).value?.data;
  if (events == null) return null;
  final now = campusNow();
  for (final e in events) {
    if (e.end.isAfter(now)) return e;
  }
  return null;
});
