import 'schedule_event.dart';

/// Where one event sits when classes run in parallel: which lane it starts in,
/// how many lanes the column is divided into, and how many it covers.
typedef EventLane = ({int lane, int lanes, int span});

bool _overlap(ScheduleEvent a, ScheduleEvent b) =>
    a.start.isBefore(b.end) && b.start.isBefore(a.end);

/// Parallel classes split a column, so a student in several groups sees both
/// rather than one hiding the other.
///
/// The column count is decided per run of chained events, not per event: with
/// 8-10, 9-11 and 10-12 the first and last never meet, but measuring them
/// separately would put three different widths on one column and let the
/// blocks overlap.
///
/// [events] must already be sorted by start then end, which is what
/// `ScheduleDayIndex` produces.
List<EventLane> assignLanes(List<ScheduleEvent> events) {
  final result = List<EventLane>.filled(events.length, (
    lane: 0,
    lanes: 1,
    span: 1,
  ));

  var runStart = 0;
  while (runStart < events.length) {
    var runEnd = runStart + 1;
    var latest = events[runStart].end;
    while (runEnd < events.length && events[runEnd].start.isBefore(latest)) {
      if (events[runEnd].end.isAfter(latest)) latest = events[runEnd].end;
      runEnd++;
    }

    final lanes = <List<int>>[];
    for (var i = runStart; i < runEnd; i++) {
      var placed = false;
      for (final lane in lanes) {
        if (lane.every((j) => !_overlap(events[i], events[j]))) {
          lane.add(i);
          placed = true;
          break;
        }
      }
      if (!placed) lanes.add(<int>[i]);
    }

    for (var lane = 0; lane < lanes.length; lane++) {
      for (final i in lanes[lane]) {
        // Widen into every following lane that stays free for the whole event.
        var span = 1;
        while (lane + span < lanes.length &&
            lanes[lane + span].every((j) => !_overlap(events[i], events[j]))) {
          span++;
        }
        result[i] = (lane: lane, lanes: lanes.length, span: span);
      }
    }

    runStart = runEnd;
  }
  return result;
}
