import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_colors.dart';
import '../../core/freshness.dart' as freshness;
import '../../core/module_cache.dart';
import '../../core/time.dart';
import 'group_picker_screen.dart';
import 'schedule_event.dart';
import 'schedule_provider.dart';

const List<String> _weekdays = [
  'lundi',
  'mardi',
  'mercredi',
  'jeudi',
  'vendredi',
  'samedi',
  'dimanche',
];

const List<String> _months = [
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

String _dayLabel(DateTime d) =>
    '${_weekdays[d.weekday - 1]} ${d.day} ${_months[d.month - 1]}';

String _hm(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

String scheduleFreshnessLabel(CachedEntry<List<ScheduleEvent>> entry) =>
    freshness.freshnessLabel(entry.refreshState, entry.cachedAt);

/// Day view with a week strip. A seven-column grid of small text does not
/// survive contact with a phone, so days are swiped instead.
class ScheduleScreen extends ConsumerStatefulWidget {
  const ScheduleScreen({super.key});

  @override
  ConsumerState<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends ConsumerState<ScheduleScreen> {
  late DateTime _day;

  @override
  void initState() {
    super.initState();
    final now = campusNow();
    _day = DateTime(now.year, now.month, now.day);
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    final ids = ref.watch(selectedGroupsProvider);
    final async = ref.watch(scheduleProvider);

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: const Text('Emploi du temps'),
        foregroundColor: Colors.white,
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: AppColors.headerGradient,
            ),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.group_outlined),
            tooltip: 'Changer de groupe',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const GroupPickerScreen(),
              ),
            ),
          ),
        ],
      ),
      body: ids.isEmpty
          ? _EmptyState(
              onPick: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const GroupPickerScreen(),
                ),
              ),
            )
          : async.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) =>
                  const Center(child: Text('Emploi du temps indisponible.')),
              data: (entry) => _DayView(
                entry: entry,
                day: _day,
                onDayChanged: (d) => setState(() => _day = d),
                sameDay: _sameDay,
              ),
            ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onPick});

  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.calendar_month_outlined,
            size: 56,
            color: AppColors.textMuted,
          ),
          const SizedBox(height: 16),
          const Text(
            'Choisissez votre groupe pour voir votre emploi du temps.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 20),
          FilledButton(onPressed: onPick, child: const Text('Choisir')),
        ],
      ),
    ),
  );
}

class _DayView extends StatelessWidget {
  const _DayView({
    required this.entry,
    required this.day,
    required this.onDayChanged,
    required this.sameDay,
  });

  final CachedEntry<List<ScheduleEvent>> entry;
  final DateTime day;
  final ValueChanged<DateTime> onDayChanged;
  final bool Function(DateTime, DateTime) sameDay;

  @override
  Widget build(BuildContext context) {
    final events = entry.data ?? const <ScheduleEvent>[];
    final today = events.where((e) => sameDay(e.start, day)).toList();
    final monday = day.subtract(Duration(days: day.weekday - 1));

    return Column(
      children: [
        SizedBox(
          height: 64,
          child: Row(
            children: [
              for (var i = 0; i < 7; i++)
                Builder(
                  builder: (_) {
                    final d = monday.add(Duration(days: i));
                    final selected = sameDay(d, day);
                    final has = events.any((e) => sameDay(e.start, d));
                    return Expanded(
                      child: InkWell(
                        onTap: () => onDayChanged(d),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              _weekdays[i].substring(0, 3),
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textMuted,
                              ),
                            ),
                            const SizedBox(height: 4),
                            CircleAvatar(
                              radius: 14,
                              backgroundColor: selected
                                  ? AppColors.primary
                                  : Colors.transparent,
                              child: Text(
                                '${d.day}',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: selected
                                      ? Colors.white
                                      : AppColors.textDark,
                                  fontWeight: has
                                      ? FontWeight.w700
                                      : FontWeight.normal,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: GestureDetector(
            onHorizontalDragEnd: (d) {
              final v = d.primaryVelocity ?? 0;
              if (v < -200) onDayChanged(day.add(const Duration(days: 1)));
              if (v > 200) onDayChanged(day.subtract(const Duration(days: 1)));
            },
            child: today.isEmpty
                ? ListView(
                    children: [
                      const SizedBox(height: 60),
                      Center(
                        child: Text(
                          'Rien de prévu ${_dayLabel(day)}.',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: today.length,
                    itemBuilder: (_, i) => _EventCard(event: today[i]),
                  ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(
            scheduleFreshnessLabel(entry),
            style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
          ),
        ),
      ],
    );
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({required this.event});

  final ScheduleEvent event;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _hm(event.start),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
                Text(
                  _hm(event.end),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.module ?? event.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textDark,
                    ),
                  ),
                  if (event.room != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(
                          Icons.place_outlined,
                          size: 14,
                          color: AppColors.textMuted,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            event.room!,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (event.teachers.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      event.teachers.join(', '),
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
