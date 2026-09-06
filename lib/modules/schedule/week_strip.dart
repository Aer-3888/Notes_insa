import 'package:flutter/material.dart';

import '../../theme/campus_context.dart';
import '../../theme/tokens.dart';
import 'event_lanes.dart';
import 'module_palette.dart';
import 'schedule_day_index.dart';
import 'schedule_event.dart';

const List<String> _short = <String>[
  'lun',
  'mar',
  'mer',
  'jeu',
  'ven',
  'sam',
  'dim',
];

const List<String> _long = <String>[
  'lundi',
  'mardi',
  'mercredi',
  'jeudi',
  'vendredi',
  'samedi',
  'dimanche',
];

/// Fallback bounds for a week with nothing in it, so the axis is never zero
/// height and the columns keep their shape.
const int _fallbackFirstHour = 8;
const int _fallbackLastHour = 18;

/// The week as duration-proportional bars, one column per day.
///
/// This is the surface that carries the shape of time; the timeline below it
/// carries the content, so neither repeats the other.
class WeekStrip extends StatelessWidget {
  const WeekStrip({
    required this.index,
    required this.weekOf,
    required this.currentDay,
    required this.onDayTap,
    this.today,
    this.palette,
    super.key,
  });

  final ScheduleDayIndex index;

  /// Any day in the week to show; the strip renders that Monday to Sunday.
  final DateTime weekOf;
  final DateTime currentDay;
  final DateTime? today;
  final ValueChanged<DateTime> onDayTap;

  /// Defaults to an untinted palette, which is what ships until the OKLCH
  /// ramps of direction 3 exist.
  final ModulePalette? palette;

  static const double height = 140;

  @override
  Widget build(BuildContext context) {
    final monday = _mondayOf(weekOf);
    final days = <DateTime>[
      for (var i = 0; i < 7; i++)
        DateTime(monday.year, monday.month, monday.day + i),
    ];

    // The axis spans the week's real extent, so an 08:15 to 17:00 week uses
    // the whole track instead of the middle third of a 24 hour axis.
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

    return SizedBox(
      height: height * MediaQuery.textScalerOf(context).scale(1),
      child: Row(
        children: <Widget>[
          for (final day in days)
            Expanded(
              child: _DayColumn(
                day: day,
                events: index.eventsOn(day),
                firstHour: first,
                lastHour: last,
                selected: _sameDay(day, currentDay),
                isToday: today != null && _sameDay(day, today!),
                palette: palette,
                onTap: () => onDayTap(day),
              ),
            ),
        ],
      ),
    );
  }

  static DateTime _mondayOf(DateTime d) =>
      DateTime(d.year, d.month, d.day - (d.weekday - 1));

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

class _DayColumn extends StatelessWidget {
  const _DayColumn({
    required this.day,
    required this.events,
    required this.firstHour,
    required this.lastHour,
    required this.selected,
    required this.isToday,
    required this.palette,
    required this.onTap,
  });

  final DateTime day;
  final List<ScheduleEvent> events;
  final int firstHour;
  final int lastHour;
  final bool selected;
  final bool isToday;
  final ModulePalette? palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final campus = context.campus;
    return Semantics(
      button: true,
      selected: selected,
      label: _semanticsLabel(),
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: Column(
          children: <Widget>[
            Text(
              _short[day.weekday - 1],
              style: context.text.labelMedium?.copyWith(
                color: context.scheme.onSurfaceVariant,
              ),
              maxLines: 1,
            ),
            const SizedBox(height: CampusSpacing.x1),
            Container(
              width: CampusSpacing.touchTarget,
              height: CampusSpacing.x6,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? campus.now : Colors.transparent,
                borderRadius: CampusRadii.controlRadius,
              ),
              child: Text(
                '${day.day}',
                style: context.campusType.numeral.copyWith(
                  color: selected ? campus.onNow : context.scheme.onSurface,
                ),
                maxLines: 1,
              ),
            ),
            SizedBox(
              height: CampusSpacing.x2,
              // Today is marked under its number, per direction 5.3. The dot
              // and rule of NowLine would crowd a 50 dp column, so this is a
              // plain underline in the same colour.
              child: isToday
                  ? Center(
                      child: Container(
                        width: CampusSpacing.x4,
                        height: 2,
                        color: campus.now,
                      ),
                    )
                  : null,
            ),
            Expanded(child: _track(context)),
          ],
        ),
      ),
    );
  }

  Widget _track(BuildContext context) {
    if (events.isEmpty) return const SizedBox.shrink();
    final span = (lastHour - firstHour) * 60;
    final placements = assignLanes(events);
    return LayoutBuilder(
      builder: (context, constraints) => Stack(
        children: <Widget>[
          for (var i = 0; i < events.length; i++)
            _positioned(context, constraints, events[i], span, placements[i]),
        ],
      ),
    );
  }

  Widget _positioned(
    BuildContext context,
    BoxConstraints constraints,
    ScheduleEvent event,
    int span,
    EventLane placement,
  ) {
    final startMinutes =
        (event.start.hour - firstHour) * 60 + event.start.minute;
    final endMinutes = (event.end.hour - firstHour) * 60 + event.end.minute;
    final top = (startMinutes / span) * constraints.maxHeight;
    final bottom = (endMinutes / span) * constraints.maxHeight;
    final width = constraints.maxWidth / placement.lanes;

    return Positioned(
      top: top.clamp(0.0, constraints.maxHeight),
      height: (bottom - top).clamp(2.0, constraints.maxHeight),
      left: placement.lane * width,
      width: width,
      child: WeekStripBar(
        color:
            palette?.colorFor(
              ModulePalette.normalize(event.module ?? event.title),
              fallback: context.scheme.onSurfaceVariant,
            ) ??
            context.scheme.onSurfaceVariant,
      ),
    );
  }

  String _semanticsLabel() {
    final name = '${_long[day.weekday - 1]} ${day.day}';
    if (events.isEmpty) return '$name, rien de prévu';
    var first = events.first.start;
    var last = events.first.end;
    for (final event in events) {
      if (event.start.isBefore(first)) first = event.start;
      if (event.end.isAfter(last)) last = event.end;
    }
    final count = events.length == 1 ? '1 cours' : '${events.length} cours';
    return '$name, $count, de ${first.hour} h à ${last.hour} h';
  }
}

/// Public so tests can count bars by type.
class WeekStripBar extends StatelessWidget {
  const WeekStripBar({required this.color, super.key});

  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 1),
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(CampusRadii.bar),
      ),
    ),
  );
}
