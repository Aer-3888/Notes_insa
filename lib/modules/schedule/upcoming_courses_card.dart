import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/time.dart';
import '../../theme/tokens.dart';
import 'schedule_day_index.dart';
import 'schedule_event.dart';
import 'schedule_provider.dart';
import 'schedule_timeline.dart';

/// Half of the third row stays on show, so the preview reads as scrollable
/// rather than as a box that happens to hold two sessions.
const double _visibleRows = 2.5;

/// The sessions still to come, read from the timetable cache. Costs no extra
/// request and renders offline; shows nothing at all until a group has been
/// chosen.
class UpcomingCoursesCard extends ConsumerWidget {
  const UpcomingCoursesCard({super.key, this.onOpenEvent});

  /// Called with the session a row was tapped for. Null makes the rows inert.
  final void Function(ScheduleEvent event)? onOpenEvent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(upcomingCoursesProvider);
    if (events.isEmpty) return const SizedBox.shrink();

    final rows = _rows(events, today: campusNow());
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        CampusSpacing.gutter,
        CampusSpacing.x1,
        CampusSpacing.gutter,
        CampusSpacing.x2,
      ),
      child: Card(
        // The rows scroll under the rounded corners otherwise.
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          height: scheduleEventRowHeight(context) * _visibleRows,
          child: ListView.builder(
            padding: EdgeInsets.zero,
            itemCount: rows.length,
            itemExtentBuilder: (i, _) => scheduleRowHeight(context, rows[i]),
            itemBuilder: (context, i) => _row(context, rows[i]),
          ),
        ),
      ),
    );
  }

  /// A day header before every day other than [today], so tomorrow's first
  /// session is never read as one of today's.
  static List<ScheduleRow> _rows(
    List<ScheduleEvent> events, {
    required DateTime today,
  }) {
    final rows = <ScheduleRow>[];
    DateTime? previous;
    for (final event in events) {
      final day = DateTime(
        event.start.year,
        event.start.month,
        event.start.day,
      );
      if (day != previous) {
        if (!_isSameDay(day, today)) rows.add(ScheduleRow.dayHeader(day));
        previous = day;
      }
      rows.add(ScheduleRow.event(day, event));
    }
    return rows;
  }

  Widget _row(BuildContext context, ScheduleRow row) {
    if (row.kind == ScheduleRowKind.dayHeader) {
      return ScheduleDayHeader(day: row.day);
    }
    final event = row.event!;
    final now = campusNow();
    final child = ScheduleEventRow(
      event: event,
      inProgress: !now.isBefore(event.start) && now.isBefore(event.end),
    );
    final open = onOpenEvent;
    if (open == null) return child;
    return InkWell(onTap: () => open(event), child: child);
  }

  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}
