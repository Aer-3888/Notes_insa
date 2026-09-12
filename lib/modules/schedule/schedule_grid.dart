import 'dart:math' as math;

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

/// Narrowest a column may be unless the reader asks for narrower. Below this
/// a block cannot hold its module name, so the grid scrolls sideways instead
/// of drawing bare bars.
const double kDefaultColumnWidth = 104;

/// The time grid behind Jour, 3 jours and Semaine. The modes differ only in
/// how many days are passed in.
class ScheduleGrid extends StatefulWidget {
  const ScheduleGrid({
    required this.index,
    required this.days,
    required this.onTapEvent,
    this.now,
    this.minColumnWidth = kDefaultColumnWidth,
    super.key,
  });

  final ScheduleDayIndex index;
  final List<DateTime> days;
  final ValueChanged<ScheduleEvent> onTapEvent;
  final DateTime? now;

  /// Floor for a column before the track scrolls sideways. Columns still
  /// stretch past it when the period has room to spare.
  final double minColumnWidth;

  static const double gutterWidth = 40;

  @override
  State<ScheduleGrid> createState() => _ScheduleGridState();
}

class _ScheduleGridState extends State<ScheduleGrid> {
  final ScrollController _headings = ScrollController();
  final ScrollController _columns = ScrollController();

  @override
  void initState() {
    super.initState();
    _columns.addListener(_followColumns);
  }

  @override
  void dispose() {
    _columns
      ..removeListener(_followColumns)
      ..dispose();
    _headings.dispose();
    super.dispose();
  }

  void _followColumns() {
    if (_headings.hasClients) _headings.jumpTo(_columns.offset);
  }

  @override
  Widget build(BuildContext context) {
    final index = widget.index;
    final days = widget.days;
    final now = widget.now;
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

    final gutter = ScheduleGrid.gutterWidth * scale;

    return LayoutBuilder(
      builder: (context, constraints) {
        final rules = (days.length - 1).toDouble();
        final free = constraints.maxWidth - gutter - rules;
        final columnWidth = math.max(
          widget.minColumnWidth * scale,
          free / days.length,
        );
        final trackWidth = columnWidth * days.length + rules;
        // A track that fits must not claim horizontal drags: the screen reads
        // those as "next period".
        final physics = trackWidth > constraints.maxWidth - gutter
            ? const ClampingScrollPhysics()
            : const NeverScrollableScrollPhysics();

        return Column(
          children: <Widget>[
            if (headed)
              Row(
                children: <Widget>[
                  SizedBox(width: gutter),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      controller: _headings,
                      physics: const NeverScrollableScrollPhysics(),
                      child: SizedBox(
                        width: trackWidth,
                        child: _HeadingRow(
                          days: days,
                          columnWidth: columnWidth,
                          today: now,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            Expanded(
              child: SingleChildScrollView(
                child: SizedBox(
                  height: bodyHeight,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      _Gutter(
                        firstHour: first,
                        lastHour: last,
                        hourHeight: hourHeight,
                        width: gutter,
                      ),
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          controller: _columns,
                          physics: physics,
                          child: SizedBox(
                            width: trackWidth,
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: <Widget>[
                                for (
                                  var i = 0;
                                  i < days.length;
                                  i++
                                ) ...<Widget>[
                                  if (i > 0) const ScheduleColumnRule(),
                                  SizedBox(
                                    width: columnWidth,
                                    child: _DayColumn(
                                      events: index.eventsOn(days[i]),
                                      firstHour: first,
                                      hourHeight: hourHeight,
                                      minBlockHeight: _minBlockHeight * scale,
                                      now: _nowFor(days[i]),
                                      onTapEvent: widget.onTapEvent,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Non-null only for today's column, so the line is drawn once.
  DateTime? _nowFor(DateTime day) {
    final n = widget.now;
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
    required this.columnWidth,
    required this.today,
  });

  final List<DateTime> days;
  final double columnWidth;
  final DateTime? today;

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
        for (var i = 0; i < days.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(width: 1),
          SizedBox(
            width: columnWidth,
            child: ScheduleDayHeading(day: days[i], isToday: _isToday(days[i])),
          ),
        ],
      ],
    ),
  );
}

/// One column's name and date, above the time grid.
class ScheduleDayHeading extends StatelessWidget {
  const ScheduleDayHeading({
    required this.day,
    required this.isToday,
    super.key,
  });

  final DateTime day;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final campus = context.campus;
    return Semantics(
      label: frenchDayLabel(day),
      excludeSemantics: true,
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
            Text('${day.day}', maxLines: 1, style: context.campusType.numeral),
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
              width: lanes[i].span * (constraints.maxWidth / lanes[i].lanes),
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
