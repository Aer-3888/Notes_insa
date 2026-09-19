import 'schedule_event.dart';

enum ScheduleRowKind { dayHeader, event, gap, emptyDay, allHidden, rangeEnd }

/// One row of the timeline. Every row belongs to a day, so the week strip can
/// be driven from whichever row is on screen.
class ScheduleRow {
  const ScheduleRow._(
    this.kind,
    this.day, {
    this.event,
    this.from,
    this.to,
    this.hiddenCount = 0,
  });

  const ScheduleRow.dayHeader(DateTime day)
    : this._(ScheduleRowKind.dayHeader, day);

  const ScheduleRow.event(DateTime day, ScheduleEvent event)
    : this._(ScheduleRowKind.event, day, event: event);

  const ScheduleRow.gap(DateTime day, DateTime from, DateTime to)
    : this._(ScheduleRowKind.gap, day, from: from, to: to);

  const ScheduleRow.emptyDay(DateTime day)
    : this._(ScheduleRowKind.emptyDay, day);

  const ScheduleRow.allHidden(DateTime day, int count)
    : this._(ScheduleRowKind.allHidden, day, hiddenCount: count);

  const ScheduleRow.rangeEnd(DateTime day)
    : this._(ScheduleRowKind.rangeEnd, day);

  final ScheduleRowKind kind;

  /// Midnight of the day this row belongs to.
  final DateTime day;

  /// Set only when [kind] is `event`.
  final ScheduleEvent? event;

  /// Set only when [kind] is `gap`: the free window's bounds.
  final DateTime? from;
  final DateTime? to;

  /// Set only when [kind] is `allHidden`: how many sessions a rule took out.
  final int hiddenCount;

  Duration? get gap => from == null ? null : to!.difference(from!);
}

/// Turns the cached event list into the flat row list the timeline renders.
/// Pure: no widgets, no context, no clock.
class ScheduleDayIndex {
  const ScheduleDayIndex._(this.rows, this._headerOfDay, this._eventsByDay);

  /// Below this, the space between two classes is a corridor walk rather than
  /// free time, and showing it as a gap is noise.
  static const Duration minGap = Duration(minutes: 30);

  final List<ScheduleRow> rows;
  final Map<DateTime, int> _headerOfDay;
  final Map<DateTime, List<ScheduleEvent>> _eventsByDay;

  factory ScheduleDayIndex.build({
    required List<ScheduleEvent> events,
    required DateTime from,
    required DateTime to,
    List<ScheduleEvent> hidden = const <ScheduleEvent>[],
  }) {
    final hiddenPerDay = <DateTime, int>{};
    for (final event in hidden) {
      final day = _midnight(event.start);
      hiddenPerDay[day] = (hiddenPerDay[day] ?? 0) + 1;
    }

    final byDay = <DateTime, List<ScheduleEvent>>{};
    for (final event in events) {
      final day = _midnight(event.start);
      if (day.isBefore(from) || day.isAfter(to)) continue;
      (byDay[day] ??= <ScheduleEvent>[]).add(event);
    }
    for (final list in byDay.values) {
      list.sort((a, b) {
        final byStart = a.start.compareTo(b.start);
        return byStart != 0 ? byStart : a.end.compareTo(b.end);
      });
    }

    final rows = <ScheduleRow>[];
    final headers = <DateTime, int>{};
    for (var day = _midnight(from); !day.isAfter(to); day = _nextDay(day)) {
      headers[day] = rows.length;
      rows.add(ScheduleRow.dayHeader(day));

      final dayEvents = byDay[day] ?? const <ScheduleEvent>[];
      if (dayEvents.isEmpty) {
        // A day emptied by a rule must never read as a free one.
        final count = hiddenPerDay[day] ?? 0;
        rows.add(
          count == 0
              ? ScheduleRow.emptyDay(day)
              : ScheduleRow.allHidden(day, count),
        );
        continue;
      }

      var latestEnd = dayEvents.first.end;
      for (var i = 0; i < dayEvents.length; i++) {
        if (i > 0) {
          final start = dayEvents[i].start;
          if (start.difference(latestEnd) >= minGap) {
            rows.add(ScheduleRow.gap(day, latestEnd, start));
          }
          if (dayEvents[i].end.isAfter(latestEnd)) latestEnd = dayEvents[i].end;
        }
        rows.add(ScheduleRow.event(day, dayEvents[i]));
      }
    }
    rows.add(ScheduleRow.rangeEnd(_midnight(to)));
    return ScheduleDayIndex._(rows, headers, byDay);
  }

  /// Index of [day]'s header row, or null when it is outside the range.
  int? rowOfDay(DateTime day) => _headerOfDay[_midnight(day)];

  List<ScheduleEvent> eventsOn(DateTime day) =>
      _eventsByDay[_midnight(day)] ?? const <ScheduleEvent>[];

  static DateTime _midnight(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Adding a Duration would be an hour wrong across a DST boundary.
  static DateTime _nextDay(DateTime d) => DateTime(d.year, d.month, d.day + 1);
}
