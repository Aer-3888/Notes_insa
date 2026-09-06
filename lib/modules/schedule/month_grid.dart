import 'package:flutter/material.dart';

import '../../theme/campus_context.dart';
import '../../theme/tokens.dart';
import 'schedule_day_index.dart';

const List<String> _initials = <String>['L', 'M', 'M', 'J', 'V', 'S', 'D'];

/// Mois is a picker, not a reading surface: a phone month cell cannot carry an
/// event, and Liste already answers "what is coming up".
class MonthGrid extends StatelessWidget {
  const MonthGrid({
    required this.index,
    required this.month,
    required this.onPickDay,
    this.today,
    super.key,
  });

  final ScheduleDayIndex index;

  /// Any day in the month to render.
  final DateTime month;
  final ValueChanged<DateTime> onPickDay;
  final DateTime? today;

  @override
  Widget build(BuildContext context) {
    final first = DateTime(month.year, month.month);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    // Monday is column 0, so a Monday first-of-month leads with no blanks.
    final leading = first.weekday - 1;

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
          child: GridView.count(
            crossAxisCount: 7,
            children: <Widget>[
              for (var i = 0; i < leading; i++) const SizedBox.shrink(),
              for (var d = 1; d <= daysInMonth; d++)
                _DayCell(
                  day: DateTime(month.year, month.month, d),
                  hasEvents: index
                      .eventsOn(DateTime(month.year, month.month, d))
                      .isNotEmpty,
                  isToday: _sameDay(
                    DateTime(month.year, month.month, d),
                    today,
                  ),
                  onTap: onPickDay,
                ),
            ],
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
    required this.hasEvents,
    required this.isToday,
    required this.onTap,
  });

  final DateTime day;
  final bool hasEvents;
  final bool isToday;
  final ValueChanged<DateTime> onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () => onTap(day),
    child: Center(
      child: Text(
        '${day.day}',
        style: context.campusType.numeral.copyWith(
          color: isToday
              ? context.campus.now
              : hasEvents
              ? context.scheme.onSurface
              : context.scheme.onSurfaceVariant,
        ),
        maxLines: 1,
      ),
    ),
  );
}
