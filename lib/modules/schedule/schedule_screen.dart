import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/freshness.dart' as freshness;
import '../../core/module_cache.dart';
import '../../core/time.dart';
import '../../theme/campus_context.dart';
import '../../theme/state_view.dart';
import '../../theme/tokens.dart';
import 'group_wizard/group_wizard_screen.dart';
import 'hidden_courses_provider.dart';
import 'hidden_courses_scope.dart';
import 'hide_course_sheet.dart';
import 'my_selection_screen.dart';
import 'hide_rule.dart';
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
import 'schedule_width_screen.dart';
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
    final target = DateTime(day.year, day.month, day.day);
    if (mode != ScheduleViewMode.liste) {
      setState(() => _day = target);
      return;
    }
    final offset = _metrics?.offsetOfDay(target);
    if (offset == null || !_controller.hasClients) {
      setState(() => _day = target);
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

  ScheduleRange get _initialRange => ScheduleRange(
    _today().subtract(kScheduleLookback),
    _today().add(kScheduleLookahead),
  );

  ScheduleRange _rangeFor(ScheduleViewMode mode, DateTime day) {
    final period = periodRange(mode, day);
    return ScheduleRange(
      period.from.subtract(kScheduleLookback),
      period.to.add(kScheduleLookahead),
    );
  }

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
    final hourHeight = ref.watch(scheduleHourHeightProvider);
    final rules = ref.watch(hiddenRulesProvider);
    final reveal = ref.watch(scheduleRevealHiddenProvider);

    ref.listen<ScheduleFocus?>(scheduleFocusProvider, (_, next) {
      if (next == null) return;
      WidgetsBinding.instance.addPostFrameCallback((_) => _consumeFocus());
    });
    ref.listen<int>(scheduleTodayRequestProvider, (_, _) => _goTo(_today()));
    final requestedRange = _rangeFor(mode, _day);
    final needsRange = !_initialRange.contains(requestedRange);
    ScheduleRangeData? rangeData;
    var rangeLoading = false;
    if (needsRange) {
      final range = ref.watch(
        scheduleRangeProvider((resourceIds: ids, range: requestedRange)),
      );
      rangeData = range.asData?.value;
      rangeLoading = range.isLoading;
    }

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
          // Leftmost. The row is anchored right, so an eye that comes and
          // goes here leaves every other button where it was. Every action is
          // keyed, or they inherit one another's element as this one and the
          // mode toggles come and go, and the ripple plays on the wrong icon.
          if (rules.isNotEmpty)
            IconButton(
              key: const ValueKey<String>('schedule-reveal-hidden'),
              icon: Icon(
                reveal
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
              ),
              tooltip: reveal
                  ? 'Masquer les cours filtrés'
                  : 'Afficher les cours masqués',
              onPressed: () => unawaited(
                ref.read(scheduleRevealHiddenProvider.notifier).toggle(),
              ),
            ),
          if (mode.showsStrip)
            IconButton(
              key: const ValueKey<String>('schedule-week-strip'),
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
              key: const ValueKey<String>('schedule-month-preview'),
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
          if (mode.dayColumns > 0)
            IconButton(
              key: const ValueKey<String>('schedule-day-width'),
              icon: const Icon(Icons.view_column_outlined),
              tooltip: 'Réglages de la grille, pincez pour ajuster',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const ScheduleWidthScreen(),
                ),
              ),
            ),
          IconButton(
            key: const ValueKey<String>('schedule-groups'),
            icon: const Icon(Icons.group_outlined),
            tooltip: 'Ma sélection',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const MySelectionScreen(),
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
                    builder: (_) => const GroupWizardScreen(),
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
                final activeRange = rangeData?.range ?? requestedRange;
                final all = _mergeScheduleEvents(
                  entry.data ?? const <ScheduleEvent>[],
                  rangeData?.events ?? const <ScheduleEvent>[],
                );
                // Revealing keeps the hidden sessions in the index so they can
                // be drawn dimmed; otherwise they leave before it is built and
                // the free time they held is recomputed.
                final shown = reveal ? all : visibleEvents(all, rules);
                final index = ScheduleDayIndex.build(
                  events: shown,
                  from: activeRange.from,
                  to: activeRange.to,
                  hidden: reveal
                      ? const <ScheduleEvent>[]
                      : hiddenEvents(all, rules),
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
                    // Day width applies only in Semaine.
                    minColumnWidth: mode == ScheduleViewMode.semaine
                        ? dayWidth
                        : kDefaultColumnWidth,
                    hourHeight: hourHeight,
                    onDayWidthDrag: mode == ScheduleViewMode.semaine
                        ? ref.read(scheduleDayWidthProvider.notifier).drag
                        : null,
                    onHourHeightDrag: ref
                        .read(scheduleHourHeightProvider.notifier)
                        .drag,
                    onHourHeightCommit: (height) => unawaited(
                      ref.read(scheduleHourHeightProvider.notifier).set(height),
                    ),
                    onDayWidthCommit: mode == ScheduleViewMode.semaine
                        ? (width) => unawaited(
                            ref
                                .read(scheduleDayWidthProvider.notifier)
                                .set(width),
                          )
                        : null,
                    onDayTap: _goTo,
                    onShiftPeriod: _shiftPeriod,
                    onTapEvent: (e) => showEventSheet(context, e),
                    rangeStart: activeRange.from,
                    rangeEnd: activeRange.to,
                  ),
                  ScheduleViewMode.mois => _MonthView(
                    day: _day,
                    index: index,
                    showPreview: showMonthPreview,
                    rangeStart: activeRange.from,
                    rangeEnd: activeRange.to,
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
                return HiddenCoursesScope(
                  rules: rules,
                  onHide: (ctx, event) =>
                      unawaited(showHideCourseSheet(ctx, event)),
                  child: Column(
                    children: <Widget>[
                      SchedulePeriodHeader(
                        mode: mode,
                        day: _day,
                        today: campusNow(),
                        onShift: _shiftPeriod,
                        onToday: () => _goTo(_today()),
                      ),
                      if (needsRange &&
                          (rangeLoading ||
                              rangeData?.state != RefreshState.fresh))
                        _ScheduleRangeStatus(
                          loading: rangeLoading,
                          state: rangeData?.state,
                        ),
                      Expanded(child: body),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

List<ScheduleEvent> _mergeScheduleEvents(
  List<ScheduleEvent> first,
  List<ScheduleEvent> second,
) {
  final byKey = <String, ScheduleEvent>{};
  for (final event in <ScheduleEvent>[...first, ...second]) {
    byKey[event.uid ??
            '${event.start.millisecondsSinceEpoch}:${event.end.millisecondsSinceEpoch}:${event.title}'] =
        event;
  }
  return byKey.values.toList()..sort((a, b) => a.start.compareTo(b.start));
}

class _ScheduleRangeStatus extends StatelessWidget {
  const _ScheduleRangeStatus({required this.loading, required this.state});

  final bool loading;
  final RefreshState? state;

  @override
  Widget build(BuildContext context) {
    final text = loading
        ? 'Cette période n’est pas encore chargée'
        : state == RefreshState.failedOffline
        ? 'Cette période n’est pas disponible hors connexion'
        : 'Impossible d’actualiser cette période';
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        CampusSpacing.gutter,
        0,
        CampusSpacing.gutter,
        CampusSpacing.x1,
      ),
      child: Row(
        children: <Widget>[
          Icon(
            loading ? Icons.sync_outlined : Icons.info_outline,
            size: 16,
            color: context.scheme.onSurfaceVariant,
          ),
          const SizedBox(width: CampusSpacing.x2),
          Expanded(child: Text(text, style: context.text.labelMedium)),
        ],
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
    required this.hourHeight,
    this.onDayWidthDrag,
    this.onDayWidthCommit,
    required this.onHourHeightDrag,
    required this.onHourHeightCommit,
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
  final double hourHeight;
  final ValueChanged<double>? onDayWidthDrag;
  final ValueChanged<double>? onDayWidthCommit;
  final ValueChanged<double> onHourHeightDrag;
  final ValueChanged<double> onHourHeightCommit;

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
      final hourHeight = widget.hourHeight * scale;
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
      final hourHeight = widget.hourHeight * scale;
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
              hourHeight: widget.hourHeight,
              onDayWidthDrag: widget.onDayWidthDrag,
              onDayWidthCommit: widget.onDayWidthCommit,
              onHourHeightDrag: widget.onHourHeightDrag,
              onHourHeightCommit: widget.onHourHeightCommit,
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
    // One million periods in either direction.
    itemCount: 2000001,
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
  });

  final ScheduleViewMode mode;
  final DateTime anchor;
  static const int _anchorPage = 1000000;

  DateTime dayAt(int index) => shiftPeriod(mode, anchor, index - _anchorPage);

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
    return _anchorPage + offset;
  }

  static int _daysBetween(DateTime from, DateTime to) => DateTime.utc(
    to.year,
    to.month,
    to.day,
  ).difference(DateTime.utc(from.year, from.month, from.day)).inDays;
}
