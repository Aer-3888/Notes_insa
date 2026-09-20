import 'package:flutter/material.dart';

import '../../theme/campus_context.dart';
import '../../theme/tokens.dart';
import 'schedule_period.dart';
import 'schedule_view_mode.dart';

/// Names the span on screen and moves between spans; the swipe is invisible.
class SchedulePeriodHeader extends StatelessWidget {
  const SchedulePeriodHeader({
    required this.mode,
    required this.day,
    required this.today,
    required this.onShift,
    required this.onToday,
    required this.onPickDate,
    super.key,
  });

  final ScheduleViewMode mode;
  final DateTime day;
  final DateTime today;

  /// Called with -1 or 1.
  final ValueChanged<int> onShift;
  final VoidCallback onToday;
  final VoidCallback onPickDate;

  @override
  Widget build(BuildContext context) {
    final onScreen = containsDay(periodRange(mode, day), today);
    final label = periodLabel(mode, day);
    return Padding(
      padding: const EdgeInsets.only(left: CampusSpacing.gutter),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Semantics(
              button: true,
              label: 'Choisir une date, $label',
              excludeSemantics: true,
              child: Tooltip(
                message: 'Choisir une date',
                child: InkWell(
                  onTap: onPickDate,
                  borderRadius: BorderRadius.circular(CampusRadii.bar),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: CampusSpacing.x2,
                    ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.titleMedium,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Before the arrows, not after. The label takes the slack, so a
          // button appended here would slide both arrows one place left and
          // put the next arrow where the previous one was.
          //
          // Keyed, or the arrows inherit one another's element when this one
          // comes and goes, and the tap ripple plays on the wrong icon.
          if (!onScreen)
            IconButton(
              key: const ValueKey<String>('schedule-today'),
              icon: const Icon(Icons.today_outlined),
              tooltip: 'Aujourd’hui',
              onPressed: onToday,
            ),
          IconButton(
            key: const ValueKey<String>('schedule-previous-period'),
            icon: const Icon(Icons.chevron_left),
            tooltip: 'Période précédente',
            onPressed: () => onShift(-1),
          ),
          IconButton(
            key: const ValueKey<String>('schedule-next-period'),
            icon: const Icon(Icons.chevron_right),
            tooltip: 'Période suivante',
            onPressed: () => onShift(1),
          ),
        ],
      ),
    );
  }
}
