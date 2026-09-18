import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/modules/schedule/schedule_day_index.dart';
import 'package:notes_insa/modules/schedule/schedule_event.dart';
import 'package:notes_insa/modules/schedule/schedule_grid.dart';

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

  final index = ScheduleDayIndex.build(
    events: <ScheduleEvent>[
      _event(
        'Morning Class',
        DateTime(2026, 9, 7, 8),
        DateTime(2026, 9, 7, 10),
      ),
      _event(
        'Afternoon Class',
        DateTime(2026, 9, 7, 14),
        DateTime(2026, 9, 7, 16),
      ),
      _event(
        'Early Exam',
        DateTime(2026, 9, 8, 6, 15),
        DateTime(2026, 9, 8, 8),
      ),
    ],
    from: monday,
    to: DateTime(2026, 9, 13),
  );

  group('calculateInitialGridScrollOffset', () {
    test('today in afternoon anchors 45 min before now', () {
      final now = DateTime(2026, 9, 7, 14, 15);
      final offset = calculateInitialGridScrollOffset(
        day: monday,
        now: now,
        index: index,
        hourHeight: 64,
        viewportHeight: 600,
      );
      // 14h15 - 45 min = 13h30 = 13.5 h -> 13.5 * 64 = 864 dp
      expect(offset, 13.5 * 64);
    });

    test(
      'today in early morning floors at 07:00 when first class is at 08:00',
      () {
        final now = DateTime(2026, 9, 7, 5, 30);
        final offset = calculateInitialGridScrollOffset(
          day: monday,
          now: now,
          index: index,
          hourHeight: 64,
          viewportHeight: 600,
        );
        // Floored at 7h -> 7 * 64 = 448 dp
        expect(offset, 7.0 * 64);
      },
    );

    test('future day defaults to 07:00 when first class is 08:00', () {
      final now = DateTime(2026, 9, 6, 12);
      final offset = calculateInitialGridScrollOffset(
        day: monday,
        now: now,
        index: index,
        hourHeight: 64,
        viewportHeight: 600,
      );
      expect(offset, 7.0 * 64);
    });

    test('future day with early exam at 06:15 anchors at 06:15', () {
      final now = DateTime(2026, 9, 6, 12);
      final offset = calculateInitialGridScrollOffset(
        day: tuesday,
        now: now,
        index: index,
        hourHeight: 64,
        viewportHeight: 600,
      );
      // 6h15 = 6.25 h -> 6.25 * 64 = 400 dp
      expect(offset, 6.25 * 64);
    });

    test('empty day defaults to 07:00', () {
      final now = DateTime(2026, 9, 6, 12);
      final emptyDay = DateTime(2026, 9, 12);
      final offset = calculateInitialGridScrollOffset(
        day: emptyDay,
        now: now,
        index: index,
        hourHeight: 64,
        viewportHeight: 600,
      );
      expect(offset, 7.0 * 64);
    });

    test('clamps offset to viewport bounds late at night', () {
      final now = DateTime(2026, 9, 7, 23, 50);
      const hourHeight = 64.0;
      const viewportHeight = 600.0;
      final offset = calculateInitialGridScrollOffset(
        day: monday,
        now: now,
        index: index,
        hourHeight: hourHeight,
        viewportHeight: viewportHeight,
      );
      const maxExpected = 24.0 * hourHeight - viewportHeight;
      expect(offset, maxExpected);
    });

    test('period containing today anchors around current time', () {
      final now = DateTime(2026, 9, 7, 10, 30);
      final weekDays = <DateTime>[
        for (var i = 0; i < 7; i++) DateTime(2026, 9, 7 + i),
      ];
      final offset = calculateInitialGridScrollOffset(
        day: monday,
        now: now,
        index: index,
        days: weekDays,
        hourHeight: 64,
        viewportHeight: 600,
      );
      // 10h30 - 45 min = 9h45 = 9.75 h -> 9.75 * 64 = 624 dp
      expect(offset, 9.75 * 64);
    });
  });
}
