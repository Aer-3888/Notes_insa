import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/campus_context.dart';
import '../../theme/tokens.dart';
import 'grid_block.dart';
import 'module_palette.dart';
import 'schedule_day_index.dart';
import 'schedule_event.dart';

const List<String> _initials = <String>['L', 'M', 'M', 'J', 'V', 'S', 'D'];

/// One class chip in a cell, and the gap under it.
const double _chipHeight = CampusSpacing.x4;
const double _chipGap = CampusSpacing.x1;

/// Most chips a cell will draw, however tall it is. Past this the cell is a
/// list, and Liste is the view for reading a list.
const int _maxChips = 4;

/// Mois is a picker first: tapping a day opens it. With the preview on it also
/// shows each day's classes as chips, the way the phone calendars do.
class MonthGrid extends StatelessWidget {
  const MonthGrid({
    required this.index,
    required this.month,
    required this.onPickDay,
    this.today,
    this.showPreview = true,
    super.key,
  });

  final ScheduleDayIndex index;

  /// Any day in the month to render.
  final DateTime month;
  final ValueChanged<DateTime> onPickDay;
  final DateTime? today;

  /// Whether a cell carries its classes as well as its number.
  final bool showPreview;

  @override
  Widget build(BuildContext context) {
    final first = DateTime(month.year, month.month);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    // Monday is column 0, so a Monday first-of-month leads with no blanks.
    final leading = first.weekday - 1;
    final weeks = ((leading + daysInMonth) / 7).ceil();

    return Column(
      children: [
        Row(
          children: [
            for (final initial in _initials)
              Expanded(
                child: Center(
                  child: Text(
                    initial,
                    style: context.text.labelMedium?.copyWith(
                      color: context.scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: CampusSpacing.x2),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) => GridView.count(
              crossAxisCount: 7,
              physics: const NeverScrollableScrollPhysics(),
              // Cells fill the month exactly, so a preview gets the height the
              // month has rather than a square cell's worth of it.
              childAspectRatio:
                  (constraints.maxWidth / 7) /
                  math.max(constraints.maxHeight / weeks, 1),
              children: <Widget>[
                for (var i = 0; i < leading; i++) const SizedBox.shrink(),
                for (var d = 1; d <= daysInMonth; d++)
                  _DayCell(
                    day: DateTime(month.year, month.month, d),
                    events: index.eventsOn(
                      DateTime(month.year, month.month, d),
                    ),
                    isToday: _sameDay(
                      DateTime(month.year, month.month, d),
                      today,
                    ),
                    showPreview: showPreview,
                    onTap: onPickDay,
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static bool _sameDay(DateTime a, DateTime? b) =>
      b != null && a.year == b.year && a.month == b.month && a.day == b.day;
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.events,
    required this.isToday,
    required this.showPreview,
    required this.onTap,
  });

  final DateTime day;
  final List<ScheduleEvent> events;
  final bool isToday;
  final bool showPreview;
  final ValueChanged<DateTime> onTap;

  @override
  Widget build(BuildContext context) {
    final number = Text(
      '${day.day}',
      style: context.campusType.numeral.copyWith(
        color: isToday
            ? context.campus.now
            : events.isEmpty
            ? context.scheme.onSurfaceVariant
            : context.scheme.onSurface,
      ),
      maxLines: 1,
    );

    return InkWell(
      onTap: () => onTap(day),
      child: showPreview && events.isNotEmpty
          ? _preview(context, number)
          : Center(child: number),
    );
  }

  Widget _preview(BuildContext context, Widget number) => LayoutBuilder(
    builder: (context, constraints) {
      final scale = MediaQuery.textScalerOf(context).scale(1);
      final chip = _chipHeight * scale;
      final free = constraints.maxHeight - chip - CampusSpacing.x1;
      final fits = (free / (chip + _chipGap)).floor().clamp(0, _maxChips);
      // An overflow count is only worth a row when it stands for more than the
      // one chip it replaces.
      final shown = fits < events.length ? math.max(fits - 1, 0) : fits;

      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: CampusSpacing.x1),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Center(child: number),
            for (final ScheduleEvent event in events.take(shown))
              Padding(
                padding: const EdgeInsets.only(top: _chipGap),
                child: _Chip(event: event, height: chip),
              ),
            if (shown < events.length)
              Padding(
                padding: const EdgeInsets.only(top: _chipGap),
                child: SizedBox(
                  height: chip,
                  child: Text(
                    '+${events.length - shown}',
                    textAlign: TextAlign.center,
                    style: context.text.labelSmall?.copyWith(
                      color: context.scheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
}

class _Chip extends StatelessWidget {
  const _Chip({required this.event, required this.height});

  final ScheduleEvent event;
  final double height;

  @override
  Widget build(BuildContext context) {
    // The block ramp, not the bolder strip-bar one: a chip carries text, and
    // the bar tints are weighted for a bare bar.
    final tint = ModulePalette.blocksOf(context).colorFor(
      ModulePalette.normalize(event.module ?? event.title),
      fallback: context.campus.surfaceContainerHighest,
    );

    return LayoutBuilder(
      builder: (context, constraints) => Container(
        height: height,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: CampusSpacing.x1),
        decoration: BoxDecoration(
          color: tint,
          borderRadius: BorderRadius.circular(CampusRadii.bar),
        ),
        child: constraints.maxWidth < kMinTruncatedLabelWidth
            ? null
            : Text(
                event.module ?? event.title,
                style: context.text.labelSmall?.copyWith(
                  color: context.campus.onModuleBlockTint,
                ),
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.fade,
              ),
      ),
    );
  }
}
