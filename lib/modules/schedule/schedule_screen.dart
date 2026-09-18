import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/freshness.dart' as freshness;
import '../../core/module_cache.dart';
import '../../core/time.dart';
import '../../theme/campus_context.dart';
import '../../theme/state_view.dart';
import '../../theme/tokens.dart';
import 'group_picker_screen.dart';
import 'month_grid.dart';
import 'schedule_day_index.dart';
import 'event_sheet.dart';
import 'schedule_event.dart';
import 'schedule_focus.dart';
import 'schedule_grid.dart';
import 'schedule_metrics.dart';
import 'schedule_period.dart';
import 'schedule_period_header.dart';
import 'schedule_provider.dart';
import 'schedule_view_mode.dart';
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

  ScheduleMetrics? _metrics;

  /// A day asked for before the timeline had been measured. Applied on the
  /// next frame that has metrics, then dropped.
  DateTime? _pendingScroll;

  @override
  void initState() {
    super.initState();
    _day = _today();
    _controller.addListener(_onScroll);
    // A request filed before this screen existed has no listener to catch it.
    WidgetsBinding.instance.addPostFrameCallback((_) => _consumeFocus());
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  /// The current day is derived from scroll position, never set directly, so
  /// the strip and the timeline cannot disagree about which day is showing.
  void _onScroll() {
    final metrics = _metrics;
    if (metrics == null || !_controller.hasClients) return;
    final day = metrics.dayAtOffset(_controller.offset);
    if (day != _day) setState(() => _day = day);
  }

  /// Liste derives `_day` from scroll position, so it moves by scrolling; the
  /// grids own `_day` and set it. Every day change goes through here.
  void _goTo(DateTime day) {
    final mode = ref.read(scheduleViewModeProvider);
    final target = mode == ScheduleViewMode.liste
        ? _clampToRange(DateTime(day.year, day.month, day.day))
        : DateTime(day.year, day.month, day.day);
    if (mode != ScheduleViewMode.liste) {
      setState(() => _day = target);
      return;
    }
    final offset = _metrics?.offsetOfDay(target);
    if (offset == null || !_controller.hasClients) {
      _pendingScroll = target;
      return;
    }
    _pendingScroll = null;
    _animateTo(offset);
  }

  void _animateTo(double offset) => unawaited(
    _controller.animateTo(
      offset,
      duration: CampusMotion.of(context, CampusMotion.enter),
      curve: CampusMotion.standard,
    ),
  );

  /// Always clears the request, so a timeline that never attaches a controller
  /// cannot leave a day queued for every later frame.
  void _flushPendingScroll() {
    final day = _pendingScroll;
    _pendingScroll = null;
    if (day == null || !mounted) return;
    final offset = _metrics?.offsetOfDay(day);
    if (offset == null || !_controller.hasClients) return;
    _animateTo(offset);
  }

  /// Opens the session another surface asked for: the hub preview files it,
  /// the shell selects this tab, and this is where it lands.
  void _consumeFocus() {
    if (!mounted) return;
    final focus = ref.read(scheduleFocusProvider.notifier).consume();
    if (focus == null) return;
    _goTo(focus.day);
    unawaited(showEventSheet(context, focus.event));
  }

  void _shiftPeriod(int direction) =>
      _goTo(shiftPeriod(ref.read(scheduleViewModeProvider), _day, direction));

  /// Semaine starts on Monday; 3 jours starts on the current day, which is
  /// what makes it read as "the next few days" rather than a fixed page.
  List<DateTime> _daysFor(ScheduleViewMode mode) {
    if (mode.dayColumns <= 1) return <DateTime>[_day];
    final start = mode == ScheduleViewMode.semaine
        ? DateTime(_day.year, _day.month, _day.day - (_day.weekday - 1))
        : _day;
    return <DateTime>[
      for (var i = 0; i < mode.dayColumns; i++)
        DateTime(start.year, start.month, start.day + i),
    ];
  }

  DateTime _clampToRange(DateTime day) {
    if (day.isBefore(_rangeStart)) return _rangeStart;
    if (day.isAfter(_rangeEnd)) return _rangeEnd;
    return day;
  }

  /// Opens one day on its own, from a month cell or a grid column heading.
  void _openDay(DateTime day) {
    _goTo(day);
    unawaited(
      ref.read(scheduleViewModeProvider.notifier).set(ScheduleViewMode.jour),
    );
  }

  static DateTime _today() {
    final now = campusNow();
    return DateTime(now.year, now.month, now.day);
  }

  /// The window the provider actually fetches, so the timeline never scrolls
  /// into days the feed does not cover.
  DateTime get _rangeStart => _today().subtract(kScheduleLookback);
  DateTime get _rangeEnd => _today().add(kScheduleLookahead);

  @override
  Widget build(BuildContext context) {
    final ids = ref.watch(selectedGroupsProvider);
    final async = ref.watch(scheduleProvider);
    final mode = ref.watch(scheduleViewModeProvider);
    // Liste and Jour remember the strip separately: Liste's body already runs
    // across days, so the two views want opposite defaults.
    final stripProvider = mode == ScheduleViewMode.liste
        ? scheduleListWeekStripProvider
        : scheduleDayWeekStripProvider;
    final showStrip = ref.watch(stripProvider);
    final showMonthPreview = ref.watch(scheduleMonthPreviewProvider);
    final dayWidth = ref.watch(scheduleDayWidthProvider);

    ref.listen<ScheduleFocus?>(scheduleFocusProvider, (_, next) {
      if (next == null) return;
      WidgetsBinding.instance.addPostFrameCallback((_) => _consumeFocus());
    });
    ref.listen<int>(scheduleTodayRequestProvider, (_, _) => _goTo(_today()));
    ref.listen<ScheduleViewMode>(scheduleViewModeProvider, (_, next) {
      if (next == ScheduleViewMode.liste) {
        if (_day.isBefore(_rangeStart)) {
          _goTo(_rangeStart);
        } else if (_day.isAfter(_rangeEnd)) {
          _goTo(_rangeEnd);
        }
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: PopupMenuButton<ScheduleViewMode>(
          tooltip: 'Changer d’affichage',
          initialValue: mode,
          onSelected: (m) =>
              unawaited(ref.read(scheduleViewModeProvider.notifier).set(m)),
          itemBuilder: (context) => <PopupMenuEntry<ScheduleViewMode>>[
            for (final m in ScheduleViewMode.values)
              PopupMenuItem<ScheduleViewMode>(value: m, child: Text(m.label)),
          ],
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(mode.label, style: context.text.titleLarge),
              const Icon(Icons.arrow_drop_down),
            ],
          ),
        ),
        actions: [
          if (mode.showsStrip)
            IconButton(
              icon: Icon(
                showStrip
                    ? Icons.calendar_view_week_outlined
                    : Icons.calendar_view_day_outlined,
              ),
              tooltip: showStrip
                  ? 'Masquer l\'aper\u00e7u de la semaine'
                  : 'Afficher l\'aper\u00e7u de la semaine',
              onPressed: () =>
                  unawaited(ref.read(stripProvider.notifier).toggle()),
            ),
          if (mode == ScheduleViewMode.mois)
            IconButton(
              icon: Icon(
                showMonthPreview
                    ? Icons.view_agenda_outlined
                    : Icons.calendar_today_outlined,
              ),
              tooltip: showMonthPreview
                  ? 'Masquer les cours dans les cases'
                  : 'Afficher les cours dans les cases',
              onPressed: () => unawaited(
                ref.read(scheduleMonthPreviewProvider.notifier).toggle(),
              ),
            ),
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
              data: (entry) {
                final index = ScheduleDayIndex.build(
                  events: entry.data ?? const <ScheduleEvent>[],
                  from: _rangeStart,
                  to: _rangeEnd,
                );
                // Both surfaces measure with the same function, or the strip
                // drifts from the list.
                _metrics = ScheduleMetrics(
                  index,
                  (row) => scheduleRowHeight(context, row),
                );
                if (_pendingScroll != null) {
                  WidgetsBinding.instance.addPostFrameCallback(
                    (_) => _flushPendingScroll(),
                  );
                }
                final body = switch (mode) {
                  ScheduleViewMode.jour ||
                  ScheduleViewMode.troisJours ||
                  ScheduleViewMode.semaine => _GridView(
                    entry: entry,
                    mode: mode,
                    day: _day,
                    index: index,
                    days: _daysFor(mode),
                    showStrip: mode.showsStrip && showStrip,
                    // Only Semaine is tight enough for the choice to change
                    // anything, and only Semaine offers it.
                    minColumnWidth: mode == ScheduleViewMode.semaine
                        ? dayWidth
                        : kDefaultColumnWidth,
                    onDayTap: _goTo,
                    onShiftPeriod: _shiftPeriod,
                    onTapEvent: (e) => showEventSheet(context, e),
                    rangeStart: _rangeStart,
                    rangeEnd: _rangeEnd,
                  ),
                  ScheduleViewMode.mois => _MonthView(
                    day: _day,
                    index: index,
                    showPreview: showMonthPreview,
                    rangeStart: _rangeStart,
                    rangeEnd: _rangeEnd,
                    onPageChanged: _goTo,
                    onPickDay: _openDay,
                  ),
                  _ => _DayView(
                    entry: entry,
                    day: _day,
                    index: index,
                    controller: _controller,
                    showStrip: mode.showsStrip && showStrip,
                    onDayTap: _goTo,
                    onShiftPeriod: _shiftPeriod,
                    onTapEvent: (e) => showEventSheet(context, e),
                  ),
                };
                return Column(
                  children: <Widget>[
                    SchedulePeriodHeader(
                      mode: mode,
                      day: _day,
                      today: campusNow(),
                      onShift: _shiftPeriod,
                      onToday: () => _goTo(_today()),
                    ),
                    Expanded(child: body),
                  ],
                );
              },
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
    required this.showStrip,
    required this.onDayTap,
    required this.onShiftPeriod,
    required this.onTapEvent,
  });

  final CachedEntry<List<ScheduleEvent>> entry;
  final DateTime day;
  final ScheduleDayIndex index;
  final ScrollController controller;
  final bool showStrip;
  final ValueChanged<DateTime> onDayTap;
  final ValueChanged<int> onShiftPeriod;
  final ValueChanged<ScheduleEvent> onTapEvent;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (showStrip)
          GestureDetector(
            onHorizontalDragEnd: (details) {
              final velocity = details.primaryVelocity ?? 0;
              if (velocity.abs() < 200) return;
              onShiftPeriod(velocity < 0 ? 1 : -1);
            },
            child: WeekStrip(
              index: index,
              weekOf: day,
              currentDay: day,
              today: campusNow(),
              onDayTap: onDayTap,
            ),
          ),
        const Divider(height: 1),
        Expanded(
          child: ScheduleTimeline(
            index: index,
            controller: controller,
            now: campusNow(),
            onTapEvent: onTapEvent,
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

class _GridView extends StatefulWidget {
  const _GridView({
    required this.entry,
    required this.mode,
    required this.day,
    required this.index,
    required this.days,
    required this.showStrip,
    required this.onDayTap,
    required this.onShiftPeriod,
    required this.onTapEvent,
    required this.rangeStart,
    required this.rangeEnd,
    required this.minColumnWidth,
  });

  final CachedEntry<List<ScheduleEvent>> entry;
  final ScheduleViewMode mode;
  final DateTime day;
  final ScheduleDayIndex index;
  final List<DateTime> days;
  final bool showStrip;
  final ValueChanged<DateTime> onDayTap;
  final ValueChanged<int> onShiftPeriod;
  final ValueChanged<ScheduleEvent> onTapEvent;
  final DateTime rangeStart;
  final DateTime rangeEnd;
  final double minColumnWidth;

  @override
  State<_GridView> createState() => _GridViewState();
}

class _GridViewState extends State<_GridView> {
  late final ValueNotifier<double> _sharedVerticalOffset;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _sharedVerticalOffset = ValueNotifier<double>(0.0);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      final scale = MediaQuery.textScalerOf(context).scale(1);
      final hourHeight = 64.0 * scale;
      final now = campusNow();
      _sharedVerticalOffset.value = calculateInitialGridScrollOffset(
        day: widget.day,
        now: now,
        index: widget.index,
        days: widget.days,
        hourHeight: hourHeight,
      );
    }
  }

  @override
  void didUpdateWidget(covariant _GridView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final now = campusNow();
    final wasToday = _isToday(oldWidget.day, now);
    final isNowToday = _isToday(widget.day, now);
    if (!wasToday && isNowToday) {
      final scale = MediaQuery.textScalerOf(context).scale(1);
      final hourHeight = 64.0 * scale;
      _sharedVerticalOffset.value = calculateInitialGridScrollOffset(
        day: widget.day,
        now: now,
        index: widget.index,
        days: widget.days,
        hourHeight: hourHeight,
      );
    }
  }

  static bool _isToday(DateTime day, DateTime now) =>
      day.year == now.year && day.month == now.month && day.day == now.day;

  @override
  void dispose() {
    _sharedVerticalOffset.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (widget.showStrip)
          WeekStrip(
            index: widget.index,
            weekOf: widget.day,
            currentDay: widget.day,
            today: campusNow(),
            onDayTap: widget.onDayTap,
          ),
        Expanded(
          child: _PeriodPager(
            key: ValueKey<ScheduleViewMode>(widget.mode),
            mode: widget.mode,
            day: widget.day,
            rangeStart: widget.rangeStart,
            rangeEnd: widget.rangeEnd,
            onPageChanged: widget.onDayTap,
            itemBuilder: (context, pageDay) => ScheduleGrid(
              index: widget.index,
              days: _daysFor(pageDay),
              now: campusNow(),
              onTapEvent: widget.onTapEvent,
              minColumnWidth: widget.minColumnWidth,
              verticalOffsetNotifier: _sharedVerticalOffset,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: CampusSpacing.x2),
          child: Text(
            scheduleFreshnessLabel(widget.entry),
            style: context.text.labelMedium?.copyWith(
              color: context.scheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }

  List<DateTime> _daysFor(DateTime pageDay) {
    final start = widget.mode == ScheduleViewMode.semaine
        ? DateTime(
            pageDay.year,
            pageDay.month,
            pageDay.day - (pageDay.weekday - 1),
          )
        : pageDay;
    return <DateTime>[
      for (var i = 0; i < widget.mode.dayColumns; i++)
        DateTime(start.year, start.month, start.day + i),
    ];
  }
}

class _MonthView extends StatelessWidget {
  const _MonthView({
    required this.day,
    required this.index,
    required this.rangeStart,
    required this.rangeEnd,
    required this.onPageChanged,
    required this.onPickDay,
    required this.showPreview,
  });

  final DateTime day;
  final ScheduleDayIndex index;
  final DateTime rangeStart;
  final DateTime rangeEnd;
  final ValueChanged<DateTime> onPageChanged;
  final ValueChanged<DateTime> onPickDay;
  final bool showPreview;

  @override
  Widget build(BuildContext context) => _PeriodPager(
    key: const ValueKey<ScheduleViewMode>(ScheduleViewMode.mois),
    mode: ScheduleViewMode.mois,
    day: day,
    rangeStart: rangeStart,
    rangeEnd: rangeEnd,
    onPageChanged: onPageChanged,
    itemBuilder: (context, pageDay) => MonthGrid(
      index: index,
      month: pageDay,
      today: campusNow(),
      onPickDay: onPickDay,
      showPreview: showPreview,
    ),
  );
}

/// A real pager lets the next period follow a drag instead of appearing only
/// once a fling ends. The same controller also gives header arrows that motion.
class _PeriodPager extends StatefulWidget {
  const _PeriodPager({
    required this.mode,
    required this.day,
    required this.rangeStart,
    required this.rangeEnd,
    required this.onPageChanged,
    required this.itemBuilder,
    super.key,
  });

  final ScheduleViewMode mode;
  final DateTime day;
  final DateTime rangeStart;
  final DateTime rangeEnd;
  final ValueChanged<DateTime> onPageChanged;
  final Widget Function(BuildContext context, DateTime day) itemBuilder;

  @override
  State<_PeriodPager> createState() => _PeriodPagerState();
}

class _PeriodPagerState extends State<_PeriodPager> {
  late _PeriodPageWindow _window;
  late PageController _controller;

  @override
  void initState() {
    super.initState();
    _window = _PeriodPageWindow(
      mode: widget.mode,
      anchor: widget.day,
      rangeStart: widget.rangeStart,
      rangeEnd: widget.rangeEnd,
    );
    _controller = PageController(initialPage: _window.indexOf(widget.day));
  }

  @override
  void didUpdateWidget(covariant _PeriodPager oldWidget) {
    super.didUpdateWidget(oldWidget);
    final target = _window.indexOf(widget.day);
    final current = _controller.hasClients
        ? _controller.page?.round()
        : _controller.initialPage;
    if (current == target) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.hasClients) return;
      unawaited(
        _controller.animateToPage(
          target,
          duration: CampusMotion.of(context, CampusMotion.enter),
          curve: CampusMotion.standard,
        ),
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PageView.builder(
    controller: _controller,
    itemCount: _window.length,
    onPageChanged: (index) => widget.onPageChanged(_window.dayAt(index)),
    itemBuilder: (context, index) =>
        widget.itemBuilder(context, _window.dayAt(index)),
  );
}

class _PeriodPageWindow {
  _PeriodPageWindow({
    required this.mode,
    required this.anchor,
    required DateTime rangeStart,
    required DateTime rangeEnd,
  }) : _firstOffset = _firstOffsetFor(mode, anchor, rangeStart),
       _lastOffset = _lastOffsetFor(mode, anchor, rangeEnd);

  final ScheduleViewMode mode;
  final DateTime anchor;
  final int _firstOffset;
  final int _lastOffset;

  int get length => _lastOffset - _firstOffset + 1;

  DateTime dayAt(int index) => shiftPeriod(mode, anchor, _firstOffset + index);

  int indexOf(DateTime day) {
    final offset = switch (mode) {
      ScheduleViewMode.mois =>
        (day.year - anchor.year) * 12 + day.month - anchor.month,
      ScheduleViewMode.jour => _daysBetween(anchor, day),
      ScheduleViewMode.troisJours =>
        _daysBetween(anchor, day) ~/ ScheduleViewMode.troisJours.dayColumns,
      ScheduleViewMode.semaine => _daysBetween(anchor, day) ~/ 7,
      ScheduleViewMode.liste => 0,
    };
    return offset.clamp(_firstOffset, _lastOffset) - _firstOffset;
  }

  static int _daysBetween(DateTime from, DateTime to) => DateTime.utc(
    to.year,
    to.month,
    to.day,
  ).difference(DateTime.utc(from.year, from.month, from.day)).inDays;

  static int _firstOffsetFor(
    ScheduleViewMode mode,
    DateTime anchor,
    DateTime rangeStart,
  ) {
    return switch (mode) {
      ScheduleViewMode.mois => -1200,
      ScheduleViewMode.jour => -365,
      ScheduleViewMode.troisJours => -120,
      ScheduleViewMode.semaine => -52,
      ScheduleViewMode.liste => 0,
    };
  }

  static int _lastOffsetFor(
    ScheduleViewMode mode,
    DateTime anchor,
    DateTime rangeEnd,
  ) {
    if (mode == ScheduleViewMode.mois) return 1200;
    var offset = 0;
    while (!shiftPeriod(mode, anchor, offset + 1).isAfter(rangeEnd)) {
      offset++;
    }
    return offset;
  }
}
