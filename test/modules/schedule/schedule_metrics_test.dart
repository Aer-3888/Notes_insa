import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/modules/schedule/schedule_day_index.dart';
import 'package:notes_insa/modules/schedule/schedule_event.dart';
import 'package:notes_insa/modules/schedule/schedule_metrics.dart';

void main() {
  final monday = DateTime(2026, 9, 7);
  final wednesday = DateTime(2026, 9, 9);

  // Every row is 10 high, so offsets are just the row number times ten and the
  // arithmetic under test is obvious by inspection.
  double flat(ScheduleRow row) => 10;

  ScheduleMetrics build() => ScheduleMetrics(
    ScheduleDayIndex.build(
      events: const <ScheduleEvent>[],
      from: monday,
      to: wednesday,
    ),
    flat,
  );

  test('total height is every row', () {
    final metrics = build();
    expect(metrics.totalHeight, metrics.index.rows.length * 10);
  });

  test('offsetOfDay lands on that day header', () {
    final metrics = build();
    final offset = metrics.offsetOfDay(wednesday)!;
    expect(metrics.rowAtOffset(offset), metrics.index.rowOfDay(wednesday));
  });

  test('an offset inside a row resolves to that row', () {
    final metrics = build();
    expect(metrics.rowAtOffset(0), 0);
    expect(metrics.rowAtOffset(9.9), 0);
    expect(metrics.rowAtOffset(10), 1);
    expect(metrics.rowAtOffset(25), 2);
  });

  test('offsets outside the list clamp to the ends', () {
    final metrics = build();
    expect(metrics.rowAtOffset(-50), 0);
    expect(metrics.rowAtOffset(99999), metrics.index.rows.length - 1);
  });

  test('dayAtOffset round-trips through offsetOfDay for every day', () {
    final metrics = build();
    for (final day in <DateTime>[monday, DateTime(2026, 9, 8), wednesday]) {
      expect(metrics.dayAtOffset(metrics.offsetOfDay(day)!), day);
    }
  });

  test('offsetOfDay is null outside the range', () {
    expect(build().offsetOfDay(DateTime(2026, 10, 1)), isNull);
  });
}
