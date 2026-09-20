import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/module_cache.dart';
import '../../core/time.dart';
import '../../core/module_cache_provider.dart';
import 'ade_service.dart';
import 'hidden_courses_provider.dart';
import 'hide_rule.dart';
import 'schedule_event.dart';

const String kScheduleModuleId = 'edt';
const int kScheduleSchemaVersion = 2;

/// Small scalar, so it stays in shared_preferences rather than the file cache.
const String kSelectedGroupsKey = 'schedule_resource_ids';

/// How far around today the timetable is fetched. ADE windows this server-side.
const Duration kScheduleLookback = Duration(days: 7);
const Duration kScheduleLookahead = Duration(days: 56);

/// Cached ADE coverage, separate from events.
class ScheduleRange {
  ScheduleRange(DateTime from, DateTime to)
    : from = DateTime(from.year, from.month, from.day),
      to = DateTime(to.year, to.month, to.day);

  final DateTime from;
  final DateTime to;

  @override
  bool operator ==(Object other) =>
      other is ScheduleRange && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);

  bool contains(ScheduleRange other) =>
      !other.from.isBefore(from) && !other.to.isAfter(to);

  Map<String, dynamic> toJson() => <String, dynamic>{
    'from': from.millisecondsSinceEpoch,
    'to': to.millisecondsSinceEpoch,
  };

  factory ScheduleRange.fromJson(Map<String, dynamic> json) => ScheduleRange(
    campusFromEpochMs(json['from'] as int),
    campusFromEpochMs(json['to'] as int),
  );
}

class ScheduleRangeData {
  const ScheduleRangeData({
    required this.range,
    required this.events,
    required this.state,
  });

  final ScheduleRange range;
  final List<ScheduleEvent> events;
  final RefreshState state;

  bool get isCovered => state == RefreshState.fresh;
}

/// Cache-backed ADE request for one visible range.
final scheduleRangeProvider = FutureProvider.autoDispose
    .family<ScheduleRangeData, ({List<int> resourceIds, ScheduleRange range})>((
      ref,
      request,
    ) async {
      final ids = request.resourceIds;
      if (ids.isEmpty) {
        return ScheduleRangeData(
          range: request.range,
          events: const <ScheduleEvent>[],
          state: RefreshState.fresh,
        );
      }

      final cache = await ref.watch(moduleCacheProvider.future);
      var snapshot = await _readSnapshot(cache, ids);
      if (_covers(snapshot.coverage, request.range)) {
        return ScheduleRangeData(
          range: request.range,
          events: _eventsIn(snapshot.events, request.range),
          state: RefreshState.fresh,
        );
      }

      try {
        for (final missing in _uncovered(snapshot.coverage, request.range)) {
          final fetched = await ref
              .read(adeServiceProvider)
              .fetch(resourceIds: ids, from: missing.from, to: missing.to);
          snapshot = _ScheduleSnapshot(
            events: _replaceEvents(snapshot.events, fetched, missing),
            coverage: _mergeRanges(<ScheduleRange>[
              ...snapshot.coverage,
              missing,
            ]),
          );
        }
        await _writeSnapshot(cache, ids, snapshot);
        return ScheduleRangeData(
          range: request.range,
          events: _eventsIn(snapshot.events, request.range),
          state: RefreshState.fresh,
        );
      } catch (e) {
        return ScheduleRangeData(
          range: request.range,
          events: _eventsIn(snapshot.events, request.range),
          state: e is SocketException || e is http.ClientException
              ? RefreshState.failedOffline
              : RefreshState.failedUpstream,
        );
      }
    });

final resourceScheduleRangeProvider =
    FutureProvider.family<
      ScheduleRangeData,
      ({int resourceId, ScheduleRange range})
    >(
      (ref, request) => _loadRange(
        ref,
        <int>[request.resourceId],
        request.range,
        'edt_resource_${request.resourceId}',
      ),
    );

Future<ScheduleRangeData> _loadRange(
  Ref ref,
  List<int> ids,
  ScheduleRange range,
  String moduleId,
) async {
  final cache = await ref.watch(moduleCacheProvider.future);
  var snapshot = await _readSnapshot(cache, ids, moduleId: moduleId);
  if (_covers(snapshot.coverage, range)) {
    return ScheduleRangeData(
      range: range,
      events: _eventsIn(snapshot.events, range),
      state: RefreshState.fresh,
    );
  }
  try {
    for (final missing in _uncovered(snapshot.coverage, range)) {
      final fetched = await ref
          .read(adeServiceProvider)
          .fetch(resourceIds: ids, from: missing.from, to: missing.to);
      snapshot = _ScheduleSnapshot(
        events: _replaceEvents(snapshot.events, fetched, missing),
        coverage: _mergeRanges(<ScheduleRange>[...snapshot.coverage, missing]),
      );
    }
    await _writeSnapshot(cache, ids, snapshot, moduleId: moduleId);
    return ScheduleRangeData(
      range: range,
      events: _eventsIn(snapshot.events, range),
      state: RefreshState.fresh,
    );
  } catch (e) {
    return ScheduleRangeData(
      range: range,
      events: _eventsIn(snapshot.events, range),
      state: e is SocketException || e is http.ClientException
          ? RefreshState.failedOffline
          : RefreshState.failedUpstream,
    );
  }
}

class _ScheduleSnapshot {
  const _ScheduleSnapshot({required this.events, required this.coverage});

  final List<ScheduleEvent> events;
  final List<ScheduleRange> coverage;
}

Future<_ScheduleSnapshot> _readSnapshot(
  ModuleCache cache,
  List<int> ids, {
  String moduleId = kScheduleModuleId,
}) async {
  final cached = await cache.read(
    moduleId,
    schemaVersion: kScheduleSchemaVersion,
  );
  final data = cached.data;
  if (data == null || !_sameIds(data['ids'], ids)) {
    return const _ScheduleSnapshot(
      events: <ScheduleEvent>[],
      coverage: <ScheduleRange>[],
    );
  }
  return _ScheduleSnapshot(
    events: <ScheduleEvent>[
      for (final e in data['events'] as List<dynamic>)
        ScheduleEvent.fromJson(e as Map<String, dynamic>, campusFromEpochMs),
    ],
    coverage: <ScheduleRange>[
      for (final r in (data['coverage'] as List<dynamic>? ?? const <dynamic>[]))
        ScheduleRange.fromJson(r as Map<String, dynamic>),
    ],
  );
}

Future<void> _writeSnapshot(
  ModuleCache cache,
  List<int> ids,
  _ScheduleSnapshot snapshot, {
  String moduleId = kScheduleModuleId,
}) => cache.write(
  moduleId,
  schemaVersion: kScheduleSchemaVersion,
  data: <String, dynamic>{
    'ids': ids,
    'events': <Map<String, dynamic>>[
      for (final e in snapshot.events) e.toJson(),
    ],
    'coverage': <Map<String, dynamic>>[
      for (final r in snapshot.coverage) r.toJson(),
    ],
  },
);

bool _sameIds(Object? raw, List<int> ids) {
  if (raw is! List<dynamic> || raw.length != ids.length) return false;
  for (var i = 0; i < ids.length; i++) {
    if (raw[i] != ids[i]) return false;
  }
  return true;
}

bool _covers(List<ScheduleRange> coverage, ScheduleRange wanted) =>
    coverage.any((range) => range.contains(wanted));

List<ScheduleRange> _uncovered(
  List<ScheduleRange> coverage,
  ScheduleRange wanted,
) {
  var cursor = wanted.from;
  final missing = <ScheduleRange>[];
  for (final range in _mergeRanges(coverage)) {
    if (range.to.isBefore(cursor)) continue;
    if (range.from.isAfter(wanted.to)) break;
    if (range.from.isAfter(cursor)) {
      missing.add(
        ScheduleRange(
          cursor,
          DateTime(range.from.year, range.from.month, range.from.day - 1),
        ),
      );
    }
    if (!range.to.isBefore(cursor)) {
      cursor = DateTime(range.to.year, range.to.month, range.to.day + 1);
    }
  }
  if (!cursor.isAfter(wanted.to)) missing.add(ScheduleRange(cursor, wanted.to));
  return missing;
}

List<ScheduleRange> _mergeRanges(List<ScheduleRange> ranges) {
  if (ranges.isEmpty) return const <ScheduleRange>[];
  final sorted = <ScheduleRange>[...ranges]
    ..sort((a, b) => a.from.compareTo(b.from));
  final merged = <ScheduleRange>[sorted.first];
  for (final range in sorted.skip(1)) {
    final previous = merged.last;
    final adjacent = DateTime(
      previous.to.year,
      previous.to.month,
      previous.to.day + 1,
    );
    if (!range.from.isAfter(adjacent)) {
      if (range.to.isAfter(previous.to)) {
        merged[merged.length - 1] = ScheduleRange(previous.from, range.to);
      }
    } else {
      merged.add(range);
    }
  }
  return merged;
}

List<ScheduleEvent> _eventsIn(
  List<ScheduleEvent> events,
  ScheduleRange range,
) => events.where((event) {
  final day = DateTime(event.start.year, event.start.month, event.start.day);
  return !day.isBefore(range.from) && !day.isAfter(range.to);
}).toList();

List<ScheduleEvent> _replaceEvents(
  List<ScheduleEvent> existing,
  List<ScheduleEvent> fetched,
  ScheduleRange range,
) {
  final byKey = <String, ScheduleEvent>{};
  for (final event in existing) {
    final day = DateTime(event.start.year, event.start.month, event.start.day);
    if (day.isBefore(range.from) || day.isAfter(range.to)) {
      byKey[_eventKey(event)] = event;
    }
  }
  for (final event in fetched) {
    byKey[_eventKey(event)] = event;
  }
  final all = byKey.values.toList()..sort((a, b) => a.start.compareTo(b.start));
  return all;
}

String _eventKey(ScheduleEvent event) =>
    event.uid ??
    '${event.start.millisecondsSinceEpoch}:${event.end.millisecondsSinceEpoch}:${event.title}';

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
  var snapshot = await _readSnapshot(cache, ids);
  CachedEntry<List<ScheduleEvent>>? previous;
  if (snapshot.events.isNotEmpty || snapshot.coverage.isNotEmpty) {
    previous = CachedEntry<List<ScheduleEvent>>(
      data: snapshot.events,
      refreshState: RefreshState.refreshing,
    );
    yield previous;
  }

  try {
    final now = campusNow();
    final range = ScheduleRange(
      now.subtract(kScheduleLookback),
      now.add(kScheduleLookahead),
    );
    final events = await ref
        .read(adeServiceProvider)
        .fetch(resourceIds: ids, from: range.from, to: range.to);
    snapshot = _ScheduleSnapshot(
      events: _replaceEvents(snapshot.events, events, range),
      coverage: _mergeRanges(<ScheduleRange>[...snapshot.coverage, range]),
    );
    await _writeSnapshot(cache, ids, snapshot);
    yield CachedEntry<List<ScheduleEvent>>(
      data: snapshot.events,
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

/// How many sessions the hub preview holds. Enough to scroll past today
/// without carrying the rest of the semester into the hub.
const int kUpcomingPreviewCount = 8;

/// The sessions still to come, for the hub preview. Reads the same cache, so
/// it costs no extra request and works offline. Hidden courses never reach it.
final upcomingCoursesProvider = Provider<List<ScheduleEvent>>((ref) {
  final events = ref.watch(scheduleProvider).value?.data;
  if (events == null) return const <ScheduleEvent>[];
  // Filtered here rather than through a derived provider: an extra provider
  // between the stream and the card invalidates itself mid build.
  final rules = ref.watch(hiddenRulesProvider);
  final now = campusNow();
  final upcoming = <ScheduleEvent>[];
  for (final e in events) {
    if (!e.end.isAfter(now)) continue;
    if (isHidden(e, rules)) continue;
    upcoming.add(e);
    if (upcoming.length == kUpcomingPreviewCount) break;
  }
  return upcoming;
});
