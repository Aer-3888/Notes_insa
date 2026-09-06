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
    super.key,
  });

  final ScheduleViewMode mode;
  final DateTime day;
  final DateTime today;

  /// Called with -1 or 1.
  final ValueChanged<int> onShift;
  final VoidCallback onToday;

  @override
  Widget build(BuildContext context) {
    final onScreen = containsDay(periodRange(mode, day), today);
    return Padding(
      padding: const EdgeInsets.only(left: CampusSpacing.gutter),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              periodLabel(mode, day),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.text.titleMedium,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_left),
            tooltip: 'Période précédente',
            onPressed: () => onShift(-1),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            tooltip: 'Période suivante',
            onPressed: () => onShift(1),
          ),
          // Last, so the arrows keep their place when it appears.
          if (!onScreen)
            IconButton(
              icon: const Icon(Icons.today_outlined),
              tooltip: 'Aujourd’hui',
              onPressed: onToday,
            ),
        ],
      ),
    );
  }
}
