import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/freshness.dart' as freshness;
import '../../core/module_cache.dart';
import '../../core/time.dart';
import '../../theme/campus_context.dart';
import '../../theme/state_view.dart';
import 'group_picker_screen.dart';
import 'schedule_day_index.dart';
import 'schedule_event.dart';
import 'schedule_provider.dart';
import 'schedule_timeline.dart';
import 'week_strip.dart';

String scheduleFreshnessLabel(CachedEntry<List<ScheduleEvent>> entry) =>
    freshness.freshnessLabel(entry.refreshState, entry.cachedAt);

/// A continuous timeline of the loaded window under a week strip. Days follow
/// one another, so the end of a day is never a dead end.
class ScheduleScreen extends ConsumerStatefulWidget {
  const ScheduleScreen({super.key});

  @override
  ConsumerState<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends ConsumerState<ScheduleScreen> {
  late DateTime _day;
  final ScrollController _controller = ScrollController();

  @override
  void initState() {
    super.initState();
    _day = _today();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  static DateTime _today() {
    final now = campusNow();
    return DateTime(now.year, now.month, now.day);
  }

  /// The window the provider actually fetches, so the timeline never scrolls
  /// into days the feed does not cover.
  DateTime get _rangeStart => _today().subtract(kScheduleLookback);
  DateTime get _rangeEnd => _today().add(kScheduleLookahead);

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
                index: ScheduleDayIndex.build(
                  events: entry.data ?? const <ScheduleEvent>[],
                  from: _rangeStart,
                  to: _rangeEnd,
                ),
                controller: _controller,
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
    required this.index,
    required this.controller,
    required this.onDayChanged,
    required this.sameDay,
  });

  final CachedEntry<List<ScheduleEvent>> entry;
  final DateTime day;
  final ScheduleDayIndex index;
  final ScrollController controller;
  final ValueChanged<DateTime> onDayChanged;
  final bool Function(DateTime, DateTime) sameDay;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        WeekStrip(
          index: index,
          weekOf: day,
          currentDay: day,
          today: campusNow(),
          onDayTap: onDayChanged,
        ),
        const Divider(height: 1),
        Expanded(
          child: ScheduleTimeline(
            index: index,
            controller: controller,
            now: campusNow(),
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
