import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/modules/schedule/schedule_day_index.dart';
import 'package:notes_insa/modules/schedule/schedule_event.dart';

ScheduleEvent _event(String title, DateTime start, DateTime end) =>
    ScheduleEvent(
      title: title,
      start: start,
      end: end,
      groups: const <String>[],
      teachers: const <String>[],
    );

void main() {
  final monday = DateTime(2026, 9, 7);
  final tuesday = DateTime(2026, 9, 8);

  test('a day with no events gets a header and one empty row', () {
    final index = ScheduleDayIndex.build(
      events: const <ScheduleEvent>[],
      from: monday,
      to: monday,
    );
    expect(index.rows.map((r) => r.kind).toList(), <ScheduleRowKind>[
      ScheduleRowKind.dayHeader,
      ScheduleRowKind.emptyDay,
      ScheduleRowKind.rangeEnd,
    ]);
  });

  test('a gap of exactly 30 minutes produces a gap row', () {
    final index = ScheduleDayIndex.build(
      events: <ScheduleEvent>[
        _event('A', DateTime(2026, 9, 7, 8), DateTime(2026, 9, 7, 10)),
        _event('B', DateTime(2026, 9, 7, 10, 30), DateTime(2026, 9, 7, 12)),
      ],
      from: monday,
      to: monday,
    );
    final gaps = index.rows.where((r) => r.kind == ScheduleRowKind.gap);
    expect(gaps, hasLength(1));
    expect(gaps.first.gap, const Duration(minutes: 30));
  });

  test('a gap of 29 minutes produces no gap row', () {
    final index = ScheduleDayIndex.build(
      events: <ScheduleEvent>[
        _event('A', DateTime(2026, 9, 7, 8), DateTime(2026, 9, 7, 10)),
        _event('B', DateTime(2026, 9, 7, 10, 29), DateTime(2026, 9, 7, 12)),
      ],
      from: monday,
      to: monday,
    );
    expect(index.rows.any((r) => r.kind == ScheduleRowKind.gap), isFalse);
  });

  test('overnight is never a gap', () {
    final index = ScheduleDayIndex.build(
      events: <ScheduleEvent>[
        _event('A', DateTime(2026, 9, 7, 16), DateTime(2026, 9, 7, 18)),
        _event('B', DateTime(2026, 9, 8, 8), DateTime(2026, 9, 8, 10)),
      ],
      from: monday,
      to: tuesday,
    );
    expect(index.rows.any((r) => r.kind == ScheduleRowKind.gap), isFalse);
  });

  test('overlapping events do not create a gap and are ordered by start', () {
    final index = ScheduleDayIndex.build(
      events: <ScheduleEvent>[
        _event('late', DateTime(2026, 9, 7, 9), DateTime(2026, 9, 7, 11)),
        _event('early', DateTime(2026, 9, 7, 8), DateTime(2026, 9, 7, 12)),
        _event('after', DateTime(2026, 9, 7, 13), DateTime(2026, 9, 7, 14)),
      ],
      from: monday,
      to: monday,
    );
    final events = index.rows
        .where((r) => r.kind == ScheduleRowKind.event)
        .map((r) => r.event!.title)
        .toList();
    expect(events, <String>['early', 'late', 'after']);

    // The gap is measured from the latest end so far (12:00), not from the
    // previous row's end (11:00), so 13:00 is one hour later, not two.
    final gap = index.rows.firstWhere((r) => r.kind == ScheduleRowKind.gap);
    expect(gap.gap, const Duration(hours: 1));
  });

  test('events outside the range are dropped', () {
    final index = ScheduleDayIndex.build(
      events: <ScheduleEvent>[
        _event('before', DateTime(2026, 9, 6, 8), DateTime(2026, 9, 6, 10)),
        _event('inside', DateTime(2026, 9, 7, 8), DateTime(2026, 9, 7, 10)),
      ],
      from: monday,
      to: monday,
    );
    expect(
      index.rows
          .where((r) => r.kind == ScheduleRowKind.event)
          .single
          .event!
          .title,
      'inside',
    );
  });

  test('rowOfDay points at that day header', () {
    final index = ScheduleDayIndex.build(
      events: const <ScheduleEvent>[],
      from: monday,
      to: tuesday,
    );
    final row = index.rowOfDay(tuesday)!;
    expect(index.rows[row].kind, ScheduleRowKind.dayHeader);
    expect(index.rows[row].day, tuesday);
  });
}
