import 'schedule_event.dart';

/// Where one event sits when classes run in parallel: which lane, and how
/// many lanes the column is divided into.
typedef EventLane = ({int lane, int lanes});

/// Parallel classes split a column, so a student in several groups sees both
/// rather than one hiding the other.
///
/// [events] must already be sorted by start then end, which is what
/// `ScheduleDayIndex` produces.
List<EventLane> assignLanes(List<ScheduleEvent> events) {
  final result = <EventLane>[];
  for (var i = 0; i < events.length; i++) {
    var lane = 0;
    var lanes = 1;
    for (var j = 0; j < events.length; j++) {
      if (i == j) continue;
      final overlaps =
          events[i].start.isBefore(events[j].end) &&
          events[j].start.isBefore(events[i].end);
      if (!overlaps) continue;
      lanes++;
      if (events[j].start.isBefore(events[i].start)) lane++;
    }
    result.add((lane: lane, lanes: lanes));
  }
  return result;
}
