import 'package:flutter/material.dart';

import '../../theme/campus_context.dart';
import '../../theme/now_line.dart';
import '../../theme/tokens.dart';
import 'schedule_day_index.dart';
import 'schedule_event.dart';

const List<String> _weekdays = <String>[
  'lundi',
  'mardi',
  'mercredi',
  'jeudi',
  'vendredi',
  'samedi',
  'dimanche',
];

const List<String> _months = <String>[
  'janvier',
  'février',
  'mars',
  'avril',
  'mai',
  'juin',
  'juillet',
  'août',
  'septembre',
  'octobre',
  'novembre',
  'décembre',
];

String frenchDayLabel(DateTime d) =>
    '${_weekdays[d.weekday - 1]} ${d.day} ${_months[d.month - 1]}';

String _hm(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// French duration for a gap: `45 min`, `2 h`, `1 h 30`.
String frenchGapLabel(Duration d) {
  final hours = d.inHours;
  final minutes = d.inMinutes % 60;
  if (hours == 0) return '$minutes min de libre';
  if (minutes == 0) return '$hours h de libre';
  return '$hours h $minutes de libre';
}

/// Base heights, before text scaling. Every row's height must be knowable
/// without laying it out, because ScheduleMetrics sums them to find offsets.
const double _headerHeight = 48;
const double _eventHeight = 72;
const double _gapHeight = 40;
const double _emptyHeight = 44;
const double _rangeEndHeight = 56;

/// Wide enough for `08:15` in the shipped font at the default text size.
const double _timeColumnWidth = 56;

double scheduleRowHeight(BuildContext context, ScheduleRow row) {
  final scale = MediaQuery.textScalerOf(context).scale(1);
  final base = switch (row.kind) {
    ScheduleRowKind.dayHeader => _headerHeight,
    ScheduleRowKind.event => _eventHeight,
    ScheduleRowKind.gap => _gapHeight,
    ScheduleRowKind.emptyDay => _emptyHeight,
    ScheduleRowKind.rangeEnd => _rangeEndHeight,
  };
  return base * scale;
}

class ScheduleTimeline extends StatelessWidget {
  const ScheduleTimeline({
    required this.index,
    required this.controller,
    this.now,
    super.key,
  });

  final ScheduleDayIndex index;
  final ScrollController controller;

  /// Campus-local now. Null in tests that do not exercise the now treatment.
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: controller,
      padding: EdgeInsets.zero,
      itemCount: index.rows.length,
      itemExtentBuilder: (i, _) => scheduleRowHeight(context, index.rows[i]),
      itemBuilder: (context, i) => _row(context, index.rows[i]),
    );
  }

  Widget _row(BuildContext context, ScheduleRow row) => switch (row.kind) {
    ScheduleRowKind.dayHeader => _DayHeader(
      day: row.day,
      isToday: _isToday(row.day),
    ),
    ScheduleRowKind.event => ScheduleEventRow(
      event: row.event!,
      inProgress: _nowFallsIn(row.event!.start, row.event!.end),
    ),
    ScheduleRowKind.gap => _GapRow(
      from: row.from!,
      to: row.to!,
      showNow: _nowFallsIn(row.from!, row.to!),
    ),
    ScheduleRowKind.emptyDay => const _EmptyDayRow(),
    ScheduleRowKind.rangeEnd => const _RangeEndRow(),
  };

  bool _nowFallsIn(DateTime from, DateTime to) {
    final n = now;
    return n != null && !n.isBefore(from) && n.isBefore(to);
  }

  bool _isToday(DateTime day) {
    final n = now;
    return n != null &&
        n.year == day.year &&
        n.month == day.month &&
        n.day == day.day;
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.day, required this.isToday});

  final DateTime day;
  final bool isToday;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      CampusSpacing.gutter,
      CampusSpacing.x4,
      CampusSpacing.gutter,
      CampusSpacing.x2,
    ),
    // Today's header is the one place in this list that takes the accent:
    // "now" is exactly what that colour is reserved for.
    child: Text(
      frenchDayLabel(day),
      style: context.text.titleMedium?.copyWith(
        color: isToday ? context.campus.now : null,
      ),
    ),
  );
}

/// Public so the height-invariance test can find it by type.
class ScheduleEventRow extends StatelessWidget {
  const ScheduleEventRow({
    required this.event,
    this.inProgress = false,
    super.key,
  });

  final ScheduleEvent event;

  /// True when now falls inside this class. Shown beside the module name, not
  /// on a line of its own, so the row height never changes.
  final bool inProgress;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final secondary = <String>[
      if (event.room != null) event.room!,
      if (event.teachers.isNotEmpty) event.teachers.join(', '),
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: CampusSpacing.gutter,
        vertical: CampusSpacing.x2,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            // Scales with the text, or a time truncates at large text sizes
            // while the row around it grows.
            width: _timeColumnWidth * MediaQuery.textScalerOf(context).scale(1),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _hm(event.start),
                  style: context.campusType.numeral,
                  maxLines: 1,
                ),
                Text(
                  _hm(event.end),
                  style: context.text.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                ),
              ],
            ),
          ),
          const SizedBox(width: CampusSpacing.x4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        event.module ?? event.title,
                        style: context.text.titleMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (inProgress)
                      Text(
                        'en cours',
                        style: context.text.labelMedium?.copyWith(
                          color: context.campus.now,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: CampusSpacing.x1),
                Text(
                  secondary,
                  style: context.text.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GapRow extends StatelessWidget {
  const _GapRow({required this.from, required this.to, this.showNow = false});

  final DateTime from;
  final DateTime to;
  final bool showNow;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: CampusSpacing.gutter),
    child: showNow
        ? const Center(child: NowLine())
        : Row(
            children: [
              const Expanded(child: Divider()),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: CampusSpacing.x3,
                ),
                child: Text(
                  frenchGapLabel(to.difference(from)),
                  style: context.text.labelMedium?.copyWith(
                    color: context.scheme.onSurfaceVariant,
                  ),
                ),
              ),
              const Expanded(child: Divider()),
            ],
          ),
  );
}

class _EmptyDayRow extends StatelessWidget {
  const _EmptyDayRow();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: CampusSpacing.gutter),
    child: Align(
      alignment: Alignment.centerLeft,
      child: Text(
        'Rien de prévu',
        style: context.text.bodyMedium?.copyWith(
          color: context.scheme.onSurfaceVariant,
        ),
      ),
    ),
  );
}

class _RangeEndRow extends StatelessWidget {
  const _RangeEndRow();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(CampusSpacing.gutter),
    child: Text(
      'Fin de l’emploi du temps publié',
      style: context.text.labelMedium?.copyWith(
        color: context.scheme.onSurfaceVariant,
      ),
    ),
  );
}
