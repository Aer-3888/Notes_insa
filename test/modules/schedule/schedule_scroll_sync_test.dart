import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/modules/schedule/schedule_day_index.dart';
import 'package:notes_insa/modules/schedule/schedule_event.dart';
import 'package:notes_insa/modules/schedule/schedule_metrics.dart';

void main() {
  final monday = DateTime(2026, 9, 7);

  // The same shape the widget uses, with fixed values so the test needs no
  // BuildContext. If these drift from scheduleRowHeight the strip desyncs.
  double heightOf(ScheduleRow row) => switch (row.kind) {
    ScheduleRowKind.dayHeader => 48,
    ScheduleRowKind.event => 72,
    ScheduleRowKind.gap => 40,
    ScheduleRowKind.allHidden => 44,
    ScheduleRowKind.emptyDay => 44,
    ScheduleRowKind.rangeEnd => 56,
  };

  test('scrolling to a day offset resolves back to that day', () {
    final index = ScheduleDayIndex.build(
      events: <ScheduleEvent>[
        ScheduleEvent(
          title: 'A',
          start: DateTime(2026, 9, 9, 8),
          end: DateTime(2026, 9, 9, 10),
          groups: const <String>[],
          teachers: const <String>[],
        ),
        ScheduleEvent(
          title: 'B',
          start: DateTime(2026, 9, 9, 14),
          end: DateTime(2026, 9, 9, 16),
          groups: const <String>[],
          teachers: const <String>[],
        ),
      ],
      from: monday,
      to: DateTime(2026, 9, 30),
    );
    final metrics = ScheduleMetrics(index, heightOf);

    for (var i = 0; i < 24; i++) {
      final day = DateTime(2026, 9, 7 + i);
      expect(
        metrics.dayAtOffset(metrics.offsetOfDay(day)!),
        day,
        reason: 'day $day did not round-trip through its offset',
      );
    }
  });

  test('a week jump clamps to the loaded range', () {
    final from = DateTime(2026, 9, 7);
    final to = DateTime(2026, 9, 30);
    DateTime clamp(DateTime d) =>
        d.isBefore(from) ? from : (d.isAfter(to) ? to : d);
    expect(clamp(DateTime(2026, 10, 5)), to);
    expect(clamp(DateTime(2026, 9, 1)), from);
    expect(clamp(DateTime(2026, 9, 14)), DateTime(2026, 9, 14));
  });
}
