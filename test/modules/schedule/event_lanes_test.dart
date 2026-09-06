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

void main() {
  test('a lone event fills its column', () {
    expect(assignLanes(<ScheduleEvent>[_event(8, 10)]), <EventLane>[
      (lane: 0, lanes: 1),
    ]);
  });

  test('two overlapping events split the column', () {
    final lanes = assignLanes(<ScheduleEvent>[_event(8, 10), _event(9, 11)]);
    expect(lanes, <EventLane>[(lane: 0, lanes: 2), (lane: 1, lanes: 2)]);
  });

  test('touching events do not overlap', () {
    final lanes = assignLanes(<ScheduleEvent>[_event(8, 10), _event(10, 12)]);
    expect(lanes, <EventLane>[(lane: 0, lanes: 1), (lane: 0, lanes: 1)]);
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

  test('an empty list yields no lanes', () {
    expect(assignLanes(const <ScheduleEvent>[]), isEmpty);
  });
}
