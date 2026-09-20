import '../../core/search_text.dart';
import '../schedule/ade_groups.dart';
import '../schedule/ade_tree.dart';
import '../schedule/schedule_event.dart';

/// A room's current availability.
class RoomStatus {
  const RoomStatus({
    required this.room,
    required this.isFree,
    required this.now,
    this.until,
    this.current,
  });

  final AdeGroup room;
  final bool isFree;
  final DateTime now;

  /// Null when nothing else is booked today.
  final DateTime? until;

  /// The current or next session.
  final ScheduleEvent? current;

  /// Null when nothing else is booked.
  Duration? get freeFor => until?.difference(now);
}

/// Finds each room's availability from ADE locations.
List<RoomStatus> roomStatuses({
  required List<AdeGroup> rooms,
  required List<ScheduleEvent> events,
  required DateTime now,
}) {
  final byName = <String, List<ScheduleEvent>>{};
  for (final event in events) {
    for (final name in (event.room ?? '').split(',')) {
      final key = _key(name);
      if (key.isEmpty) continue;
      byName.putIfAbsent(key, () => <ScheduleEvent>[]).add(event);
    }
  }

  final out = <RoomStatus>[
    for (final room in rooms)
      _statusOf(room, byName[_key(room.name)] ?? const <ScheduleEvent>[], now),
  ];
  out.sort(_byUsefulness);
  return out;
}

RoomStatus _statusOf(AdeGroup room, List<ScheduleEvent> booked, DateTime now) {
  final today = booked.where((e) => e.end.isAfter(e.start)).toList()
    ..sort((a, b) => a.start.compareTo(b.start));

  final running = today
      .where((e) => !e.start.isAfter(now) && e.end.isAfter(now))
      .toList();
  if (running.isNotEmpty) {
    // Treat overlapping and adjacent bookings as one busy stretch.
    var current = running.reduce(
      (longest, event) => event.end.isAfter(longest.end) ? event : longest,
    );
    var end = current.end;
    for (final e in today) {
      if (!e.start.isAfter(end) && e.end.isAfter(end)) {
        end = e.end;
        current = e;
      }
    }
    return RoomStatus(
      room: room,
      isFree: false,
      now: now,
      until: end,
      current: current,
    );
  }

  final next = today.where((e) => e.start.isAfter(now)).firstOrNull;
  return RoomStatus(
    room: room,
    isFree: true,
    now: now,
    until: next?.start,
    current: next,
  );
}

typedef RoomBuilding = ({String building, List<RoomStatus> rooms});

/// Groups known rooms by building.
List<RoomBuilding> groupByBuilding(
  List<RoomStatus> statuses,
  String? Function(AdeGroup) buildingOf,
) {
  final byBuilding = <String, List<RoomStatus>>{};
  for (final status in statuses) {
    final building = buildingOf(status.room);
    if (building == null) continue;
    byBuilding.putIfAbsent(building, () => <RoomStatus>[]).add(status);
  }
  final names = byBuilding.keys.toList()..sort(AdeTree.compareNatural);
  return <RoomBuilding>[
    for (final name in names) (building: name, rooms: byBuilding[name]!),
  ];
}

int _byUsefulness(RoomStatus a, RoomStatus b) {
  if (a.isFree != b.isFree) return a.isFree ? -1 : 1;
  final ua = a.until;
  final ub = b.until;
  if (ua == null && ub == null) return a.room.name.compareTo(b.room.name);
  if (ua == null) return a.isFree ? -1 : 1;
  if (ub == null) return b.isFree ? 1 : -1;
  final cmp = a.isFree ? ub.compareTo(ua) : ua.compareTo(ub);
  return cmp != 0 ? cmp : a.room.name.compareTo(b.room.name);
}

/// Normalizes ADE room names for matching.
String _key(String name) =>
    foldForSearch(name).replaceAll(RegExp(r'\s+'), ' ').trim();
