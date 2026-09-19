import 'package:flutter/material.dart';

import '../../theme/campus_context.dart';
import '../../theme/now_line.dart';
import '../../theme/tokens.dart';
import 'hidden_courses_scope.dart';
import 'module_palette.dart';
import 'schedule_day_index.dart';
import 'schedule_event.dart';
import 'schedule_period.dart';

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

/// One session row, at the current text size. The hub preview sizes its
/// viewport from this so it shows whole rows rather than an arbitrary height.
double scheduleEventRowHeight(BuildContext context) =>
    _eventHeight * MediaQuery.textScalerOf(context).scale(1);

double scheduleRowHeight(BuildContext context, ScheduleRow row) {
  final scale = MediaQuery.textScalerOf(context).scale(1);
  final base = switch (row.kind) {
    ScheduleRowKind.dayHeader => _headerHeight,
    ScheduleRowKind.event => _eventHeight,
    ScheduleRowKind.gap => _gapHeight,
    ScheduleRowKind.emptyDay => _emptyHeight,
    ScheduleRowKind.allHidden => _emptyHeight,
    ScheduleRowKind.rangeEnd => _rangeEndHeight,
  };
  return base * scale;
}

class ScheduleTimeline extends StatelessWidget {
  const ScheduleTimeline({
    required this.index,
    required this.controller,
    this.now,
    this.onTapEvent,
    super.key,
  });

  final ScheduleDayIndex index;
  final ScrollController controller;

  /// Campus-local now. Null in tests that do not exercise the now treatment.
  final DateTime? now;

  /// Called when an event row is tapped.
  final ValueChanged<ScheduleEvent>? onTapEvent;

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
    ScheduleRowKind.dayHeader => ScheduleDayHeader(
      day: row.day,
      isToday: _isToday(row.day),
    ),
    ScheduleRowKind.event => ScheduleEventRow(
      event: row.event!,
      inProgress: _nowFallsIn(row.event!.start, row.event!.end),
      onTap: onTapEvent != null ? () => onTapEvent!(row.event!) : null,
    ),
    ScheduleRowKind.gap => _GapRow(
      from: row.from!,
      to: row.to!,
      showNow: _nowFallsIn(row.from!, row.to!),
    ),
    ScheduleRowKind.emptyDay => const _EmptyDayRow(),
    ScheduleRowKind.allHidden => _AllHiddenRow(count: row.hiddenCount),
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

/// Public so the hub preview dates its days the way the list does.
class ScheduleDayHeader extends StatelessWidget {
  const ScheduleDayHeader({required this.day, this.isToday = false, super.key});

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
    this.onTap,
    super.key,
  });

  final ScheduleEvent event;

  /// True when now falls inside this class. Shown beside the module name, not
  /// on a line of its own, so the row height never changes.
  final bool inProgress;

  /// Optional callback when the row is tapped.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final secondary = <String>[
      if (event.room != null) event.room!,
      if (event.teachers.isNotEmpty) event.teachers.join(', '),
    ].join(' · ');

    final tint = ModulePalette.spinesOf(context).colorFor(
      ModulePalette.normalize(event.module ?? event.title),
      fallback: scheme.outlineVariant,
    );
    final scope = HiddenCoursesScope.maybeOf(context);
    final hidden = scope?.hides(event) ?? false;

    final rowContent = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: CampusSpacing.gutter,
        vertical: CampusSpacing.x2,
      ),
      child: Row(
        // The ListView gives the row a fixed extent, so the spine can stretch
        // to it without an IntrinsicHeight measuring pass.
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // A spine rather than a filled row: eight pastel bands down the list
          // would drown the text the list exists to carry.
          Padding(
            padding: const EdgeInsets.only(right: CampusSpacing.x3),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(CampusRadii.bar),
              child: SizedBox(width: 3, child: ColoredBox(color: tint)),
            ),
          ),
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
                        style: context.text.titleMedium?.copyWith(
                          decoration: hidden
                              ? TextDecoration.lineThrough
                              : null,
                        ),
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

    final row = onTap == null
        ? rowContent
        : Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              onLongPress: scope == null
                  ? null
                  : () => scope.onHide(context, event),
              child: rowContent,
            ),
          );
    if (!hidden) return row;
    return Opacity(opacity: CampusOpacity.hidden, child: row);
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

/// French plural for a count of hidden sessions.
String frenchHiddenLabel(int count) =>
    count == 1 ? '1 cours masqué' : '$count cours masqués';

class _AllHiddenRow extends StatelessWidget {
  const _AllHiddenRow({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: CampusSpacing.gutter),
    child: Row(
      children: <Widget>[
        Icon(
          Icons.visibility_off_outlined,
          size: 16,
          color: context.scheme.onSurfaceVariant,
        ),
        const SizedBox(width: CampusSpacing.x2),
        Text(
          frenchHiddenLabel(count),
          style: context.text.bodyMedium?.copyWith(
            color: context.scheme.onSurfaceVariant,
          ),
        ),
      ],
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
