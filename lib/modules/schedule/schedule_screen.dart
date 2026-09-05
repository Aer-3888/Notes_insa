import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/freshness.dart' as freshness;
import '../../core/module_cache.dart';
import '../../core/time.dart';
import '../../theme/campus_context.dart';
import '../../theme/state_view.dart';
import '../../theme/tokens.dart';
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
      appBar: AppBar(
        title: const Text('Emploi du temps'),
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
          ? StateView(
              icon: Icons.group_outlined,
              title: 'Choisissez votre groupe',
              body:
                  'Votre emploi du temps s\u2019affichera ici, m\u00eame hors ligne.',
              action: FilledButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const GroupPickerScreen(),
                  ),
                ),
                child: const Text('Choisir mon groupe'),
              ),
            )
          : async.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => StateView(
                icon: Icons.cloud_off_outlined,
                title: 'Emploi du temps indisponible',
                body:
                    'Impossible de joindre ADE. V\u00e9rifiez la connexion, '
                    'puis r\u00e9essayez.',
                action: FilledButton.tonalIcon(
                  onPressed: () => ref.invalidate(scheduleProvider),
                  icon: const Icon(Icons.refresh),
                  label: const Text('R\u00e9essayer'),
                ),
              ),
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
          height: 72,
          child: Row(
            children: [
              for (var i = 0; i < 7; i++)
                Builder(
                  builder: (_) {
                    final d = monday.add(Duration(days: i));
                    final selected = sameDay(d, day);
                    final has = events.any((e) => sameDay(e.start, d));
                    return Expanded(
                      child: Semantics(
                        button: true,
                        selected: selected,
                        label: '${_weekdays[i]} ${d.day}',
                        excludeSemantics: true,
                        child: InkWell(
                          onTap: () => onDayChanged(d),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                _weekdays[i].substring(0, 3),
                                style: context.text.labelMedium?.copyWith(
                                  color: context.scheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: CampusSpacing.x1),
                              Container(
                                width: CampusSpacing.touchTarget,
                                height: CampusSpacing.x8,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: selected
                                      ? context.campus.now
                                      : Colors.transparent,
                                  borderRadius: CampusRadii.controlRadius,
                                ),
                                child: Text(
                                  '${d.day}',
                                  style: context.campusType.numeral.copyWith(
                                    color: selected
                                        ? context.campus.onNow
                                        : context.scheme.onSurface,
                                    fontWeight: has
                                        ? FontWeight.w700
                                        : FontWeight.w400,
                                  ),
                                ),
                              ),
                            ],
                          ),
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
                          'Rien de pr\u00e9vu ${_dayLabel(day)}.',
                          style: context.text.bodyMedium?.copyWith(
                            color: context.scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(
                      horizontal: CampusSpacing.gutter,
                      vertical: CampusSpacing.x2,
                    ),
                    itemCount: today.length,
                    separatorBuilder: (_, _) => const Divider(),
                    itemBuilder: (_, i) => _EventCard(event: today[i]),
                  ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(
            scheduleFreshnessLabel(entry),
            style: context.text.labelMedium?.copyWith(
              color: context.scheme.onSurfaceVariant,
            ),
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
    final scheme = context.scheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: CampusSpacing.x2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 56,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_hm(event.start), style: context.campusType.numeral),
                Text(
                  _hm(event.end),
                  style: context.text.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: CampusSpacing.x4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.module ?? event.title,
                  style: context.text.titleMedium,
                ),
                if (event.room != null) ...[
                  const SizedBox(height: CampusSpacing.x1),
                  Row(
                    children: [
                      Icon(
                        Icons.place_outlined,
                        size: 18,
                        color: scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: CampusSpacing.x1),
                      Expanded(
                        child: Text(
                          event.room!,
                          style: context.text.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                if (event.teachers.isNotEmpty)
                  Text(
                    event.teachers.join(', '),
                    style: context.text.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
