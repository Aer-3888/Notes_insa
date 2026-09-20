import 'french_dates.dart';
import 'schedule_view_mode.dart';

// The vocabulary stays a plain file so models can name a date too. It is
// re-exported so its readers keep importing this one file.
export 'french_dates.dart';

typedef PeriodRange = ({DateTime from, DateTime to});

PeriodRange academicYearRange(DateTime date) {
  final startYear = date.month >= 9 ? date.year : date.year - 1;
  return (from: DateTime(startYear, 9, 1), to: DateTime(startYear + 1, 8, 31));
}

DateTime _mondayOf(DateTime d) =>
    DateTime(d.year, d.month, d.day - (d.weekday - 1));

/// The days a mode shows around [day], first to last inclusive.
PeriodRange periodRange(ScheduleViewMode mode, DateTime day) {
  final start = DateTime(day.year, day.month, day.day);
  return switch (mode) {
    ScheduleViewMode.jour => (from: start, to: start),
    ScheduleViewMode.troisJours => (
      from: start,
      to: DateTime(start.year, start.month, start.day + 2),
    ),
    // Liste scrolls a week at a time, so it reads as a week like Semaine.
    ScheduleViewMode.semaine || ScheduleViewMode.liste => () {
      final monday = _mondayOf(start);
      return (
        from: monday,
        to: DateTime(monday.year, monday.month, monday.day + 6),
      );
    }(),
    ScheduleViewMode.mois => (
      from: DateTime(start.year, start.month),
      to: DateTime(start.year, start.month + 1, 0),
    ),
  };
}

/// What the header says the screen is showing.
String periodLabel(ScheduleViewMode mode, DateTime day) {
  if (mode == ScheduleViewMode.mois) {
    return '${frenchMonths[day.month - 1]} ${day.year}';
  }
  final range = periodRange(mode, day);
  if (range.from == range.to) return frenchDayLabel(range.from);
  final fromMonth = frenchMonths[range.from.month - 1];
  final toMonth = frenchMonths[range.to.month - 1];
  return range.from.month == range.to.month
      ? 'du ${range.from.day} au ${range.to.day} $toMonth'
      : 'du ${range.from.day} $fromMonth au ${range.to.day} $toMonth';
}

/// The day one period away. The step comes from the range, so the arrows and
/// the body cannot disagree.
DateTime shiftPeriod(ScheduleViewMode mode, DateTime day, int direction) {
  if (mode == ScheduleViewMode.mois) {
    return DateTime(day.year, day.month + direction);
  }
  final range = periodRange(mode, day);
  final span = range.to.difference(range.from).inDays + 1;
  return DateTime(day.year, day.month, day.day + direction * span);
}

bool containsDay(PeriodRange range, DateTime day) {
  final d = DateTime(day.year, day.month, day.day);
  return !d.isBefore(range.from) && !d.isAfter(range.to);
}
