import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/modules/schedule/event_lanes.dart';
import 'package:notes_insa/modules/schedule/schedule_event.dart';

ScheduleEvent _event(int startHour, int endHour) => ScheduleEvent(
  title: 'x',
  start: DateTime(2026, 9, 7, startHour),
  end: DateTime(2026, 9, 7, endHour),
  groups: const <String>[],
  teachers: const <String>[],
);

/// Where a lane puts a block across the column, 0 to 1.
({double left, double right}) _span(EventLane l) =>
    (left: l.lane / l.lanes, right: (l.lane + l.span) / l.lanes);

void main() {
  test('a lone event fills its column', () {
    expect(assignLanes(<ScheduleEvent>[_event(8, 10)]), <EventLane>[
      (lane: 0, lanes: 1, span: 1),
    ]);
  });

  test('two overlapping events split the column', () {
    final lanes = assignLanes(<ScheduleEvent>[_event(8, 10), _event(9, 11)]);
    expect(lanes, <EventLane>[
      (lane: 0, lanes: 2, span: 1),
      (lane: 1, lanes: 2, span: 1),
    ]);
  });

  test('touching events each keep the whole column', () {
    final lanes = assignLanes(<ScheduleEvent>[_event(8, 10), _event(10, 12)]);
    expect(lanes, <EventLane>[
      (lane: 0, lanes: 1, span: 1),
      (lane: 0, lanes: 1, span: 1),
    ]);
  });

  test('three mutually overlapping events split three ways', () {
    final lanes = assignLanes(<ScheduleEvent>[
      _event(8, 12),
      _event(9, 12),
      _event(10, 12),
    ]);
    expect(lanes.map((l) => l.lanes).toSet(), <int>{3});
    expect(lanes.map((l) => l.lane).toList(), <int>[0, 1, 2]);
  });

  test('a chain of overlaps is divided once, not per event', () {
    // 8-10 meets 9-11 meets 10-12: the first and last never overlap, but they
    // belong to one run and must be measured against the same column count.
    final lanes = assignLanes(<ScheduleEvent>[
      _event(8, 10),
      _event(9, 11),
      _event(10, 12),
    ]);
    expect(lanes.map((l) => l.lanes).toSet(), <int>{2});
  });

  test('blocks in a chain never sit on top of one another', () {
    final events = <ScheduleEvent>[
      _event(8, 10),
      _event(9, 11),
      _event(10, 12),
    ];
    final lanes = assignLanes(events);
    for (var i = 0; i < events.length; i++) {
      for (var j = i + 1; j < events.length; j++) {
        final inTime =
            events[i].start.isBefore(events[j].end) &&
            events[j].start.isBefore(events[i].end);
        if (!inTime) continue;
        final a = _span(lanes[i]);
        final b = _span(lanes[j]);
        expect(
          a.left < b.right && b.left < a.right,
          isFalse,
          reason: 'events $i and $j overlap on screen',
        );
      }
    }
  });

  test('a block widens into a lane that is free for its whole span', () {
    // 8-12 holds lane 0, 8-10 and 8-9 fill lanes 1 and 2. The 10-12 that
    // follows can have both of those back.
    final lanes = assignLanes(<ScheduleEvent>[
      _event(8, 12),
      _event(8, 10),
      _event(8, 9),
      _event(10, 12),
    ]);
    expect(lanes.map((l) => l.lanes).toSet(), <int>{3});
    expect(lanes.last, (lane: 1, lanes: 3, span: 2));
  });

  test('an empty list yields no lanes', () {
    expect(assignLanes(const <ScheduleEvent>[]), isEmpty);
  });
}
