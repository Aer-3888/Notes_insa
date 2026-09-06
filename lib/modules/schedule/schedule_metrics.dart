import 'schedule_day_index.dart';

typedef RowHeight = double Function(ScheduleRow row);

/// Scroll geometry for the timeline.
///
/// Every row's height is known before layout, so a row's offset is a prefix
/// sum rather than something measured after the fact. That is what lets the
/// week strip follow the list without a scroll-position package.
class ScheduleMetrics {
  ScheduleMetrics(this.index, RowHeight heightOf)
    : _offsets = _prefixSums(index, heightOf);

  final ScheduleDayIndex index;

  /// Cumulative offsets, length `rows.length + 1`; the last entry is the total.
  final List<double> _offsets;

  double get totalHeight => _offsets.last;

  double offsetOfRow(int row) => _offsets[row];

  double? offsetOfDay(DateTime day) {
    final row = index.rowOfDay(day);
    return row == null ? null : _offsets[row];
  }

  /// The row containing [offset], clamped to the list at both ends.
  int rowAtOffset(double offset) {
    if (offset <= 0) return 0;
    final last = index.rows.length - 1;
    if (offset >= _offsets[last]) return last;

    var low = 0;
    var high = last;
    while (low < high) {
      final mid = (low + high + 1) ~/ 2;
      if (_offsets[mid] <= offset) {
        low = mid;
      } else {
        high = mid - 1;
      }
    }
    return low;
  }

  DateTime dayAtOffset(double offset) => index.rows[rowAtOffset(offset)].day;

  static List<double> _prefixSums(ScheduleDayIndex index, RowHeight heightOf) {
    final offsets = <double>[0];
    var total = 0.0;
    for (final row in index.rows) {
      total += heightOf(row);
      offsets.add(total);
    }
    return offsets;
  }
}
