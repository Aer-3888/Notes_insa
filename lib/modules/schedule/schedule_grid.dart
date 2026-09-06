import 'package:flutter/material.dart';

import '../../theme/campus_context.dart';
import '../../theme/now_line.dart';
import '../../theme/tokens.dart';
import 'event_lanes.dart';
import 'grid_block.dart';
import 'schedule_day_index.dart';
import 'schedule_event.dart';
import 'schedule_period.dart';

/// Fallback bounds for a period with nothing in it, so the axis is never zero
/// height and the gutter keeps its shape.
const int _fallbackFirstHour = 8;
const int _fallbackLastHour = 18;

/// Height of one hour. The whole grid scrolls vertically, so this can be
/// generous enough to read rather than squeezed to fit a screen.
const double _hourHeight = 64;

/// A 30 minute class is 32 dp at the hour height above, under the 48 dp
/// minimum target (CP-10). Short blocks are floored to it and so run slightly
/// past their real end, which is what platform calendars do: a block you
/// cannot reliably tap is worse than one a few minutes too tall.
const double _minBlockHeight = 48;

/// The time grid behind Jour, 3 jours and Semaine.
///
/// The three modes differ only in how many days are passed in, which is why
/// there is one of these rather than three widgets.
class ScheduleGrid extends StatelessWidget {
  const ScheduleGrid({
    required this.index,
    required this.days,
    required this.onTapEvent,
    this.onPickDay,
    this.now,
    super.key,
  });

  final ScheduleDayIndex index;
  final List<DateTime> days;
  final ValueChanged<ScheduleEvent> onTapEvent;

  /// Tapping a column heading opens that day alone.
  final ValueChanged<DateTime>? onPickDay;
  final DateTime? now;

  static const double gutterWidth = 40;

  @override
  Widget build(BuildContext context) {
    var first = 24;
    var last = 0;
    for (final day in days) {
      for (final event in index.eventsOn(day)) {
        if (event.start.hour < first) first = event.start.hour;
        final endHour = event.end.minute > 0
            ? event.end.hour + 1
            : event.end.hour;
        if (endHour > last) last = endHour;
      }
    }
    if (first >= last) {
      first = _fallbackFirstHour;
      last = _fallbackLastHour;
    }

    final scale = MediaQuery.textScalerOf(context).scale(1);
    final hourHeight = _hourHeight * scale;
    final bodyHeight = (last - first) * hourHeight;

    // One column needs no heading: the page header already names that day.
    final headed = days.length > 1;

    return Column(
      children: <Widget>[
        if (headed)
          _HeadingRow(
            days: days,
            gutterWidth: gutterWidth * scale,
            today: now,
            onPickDay: onPickDay,
          ),
        Expanded(
          child: SingleChildScrollView(
            child: SizedBox(
              height: bodyHeight,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Gutter(
                    firstHour: first,
                    lastHour: last,
                    hourHeight: hourHeight,
                    width: gutterWidth * scale,
                  ),
                  for (var i = 0; i < days.length; i++) ...<Widget>[
                    if (i > 0) const ScheduleColumnRule(),
                    Expanded(
                      child: _DayColumn(
                        events: index.eventsOn(days[i]),
                        firstHour: first,
                        hourHeight: hourHeight,
                        minBlockHeight: _minBlockHeight * scale,
                        now: _nowFor(days[i]),
                        onTapEvent: onTapEvent,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Non-null only for the column that is actually today, so the line is drawn
  /// once rather than in every column.
  DateTime? _nowFor(DateTime day) {
    final n = now;
    if (n == null) return null;
    return n.year == day.year && n.month == day.month && n.day == day.day
        ? n
        : null;
  }
}

/// Hairline between two day columns.
class ScheduleColumnRule extends StatelessWidget {
  const ScheduleColumnRule({super.key});

  @override
  Widget build(BuildContext context) =>
      Container(width: 1, color: context.scheme.outlineVariant);
}

class _HeadingRow extends StatelessWidget {
  const _HeadingRow({
    required this.days,
    required this.gutterWidth,
    required this.today,
    required this.onPickDay,
  });

  final List<DateTime> days;
  final double gutterWidth;
  final DateTime? today;
  final ValueChanged<DateTime>? onPickDay;

  bool _isToday(DateTime day) {
    final t = today;
    return t != null &&
        t.year == day.year &&
        t.month == day.month &&
        t.day == day.day;
  }

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: context.scheme.outlineVariant)),
    ),
    child: Row(
      children: <Widget>[
        SizedBox(width: gutterWidth),
        for (final day in days)
          Expanded(
            child: ScheduleDayHeading(
              day: day,
              isToday: _isToday(day),
              onTap: onPickDay == null ? null : () => onPickDay!(day),
            ),
          ),
      ],
    ),
  );
}

/// One column's name and date, above the time grid.
class ScheduleDayHeading extends StatelessWidget {
  const ScheduleDayHeading({
    required this.day,
    required this.isToday,
    this.onTap,
    super.key,
  });

  final DateTime day;
  final bool isToday;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final campus = context.campus;
    return Semantics(
      button: onTap != null,
      label: frenchDayLabel(day),
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: CampusSpacing.x2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                frenchWeekdaysShort[day.weekday - 1],
                maxLines: 1,
                style: context.text.labelMedium?.copyWith(
                  color: context.scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: CampusSpacing.x1),
              Text(
                '${day.day}',
                maxLines: 1,
                style: context.campusType.numeral,
              ),
              const SizedBox(height: CampusSpacing.x1),
              // Today keeps the underline the week strip uses, not a fill.
              SizedBox(
                height: 2,
                width: CampusSpacing.x5,
                child: isToday
                    ? DecoratedBox(decoration: BoxDecoration(color: campus.now))
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Gutter extends StatelessWidget {
  const _Gutter({
    required this.firstHour,
    required this.lastHour,
    required this.hourHeight,
    required this.width,
  });

  final int firstHour;
  final int lastHour;
  final double hourHeight;
  final double width;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: Column(
      children: [
        for (var h = firstHour; h < lastHour; h++)
          SizedBox(
            height: hourHeight,
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.only(right: CampusSpacing.x1),
                child: Text(
                  h.toString().padLeft(2, '0'),
                  style: context.text.labelMedium?.copyWith(
                    color: context.scheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

class _DayColumn extends StatelessWidget {
  const _DayColumn({
    required this.events,
    required this.firstHour,
    required this.hourHeight,
    required this.minBlockHeight,
    required this.now,
    required this.onTapEvent,
  });

  final List<ScheduleEvent> events;
  final int firstHour;
  final double hourHeight;
  final double minBlockHeight;
  final DateTime? now;
  final ValueChanged<ScheduleEvent> onTapEvent;

  double _offsetOf(DateTime t) =>
      ((t.hour - firstHour) * 60 + t.minute) / 60 * hourHeight;

  @override
  Widget build(BuildContext context) {
    final lanes = assignLanes(events);
    return LayoutBuilder(
      builder: (context, constraints) => Stack(
        children: <Widget>[
          for (var i = 0; i < events.length; i++)
            Positioned(
              top: _offsetOf(events[i].start),
              height: (_offsetOf(events[i].end) - _offsetOf(events[i].start))
                  .clamp(minBlockHeight, double.infinity),
              left: lanes[i].lane * (constraints.maxWidth / lanes[i].lanes),
              width: constraints.maxWidth / lanes[i].lanes,
              child: GridBlock(
                event: events[i],
                onTap: () => onTapEvent(events[i]),
              ),
            ),
          if (now != null)
            Positioned(
              top: _offsetOf(now!) - NowLine.dot / 2,
              left: 0,
              right: 0,
              child: const NowLine(),
            ),
        ],
      ),
    );
  }
}
