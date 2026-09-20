import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/campus_context.dart';
import '../../theme/now_line.dart';
import '../../theme/tokens.dart';
import 'event_lanes.dart';
import 'grid_block.dart';
import 'schedule_day_index.dart';
import 'schedule_event.dart';
import 'schedule_period.dart';
import 'schedule_view_mode.dart';

/// Full 24 hour day bounds.
const int kScheduleFirstHour = 0;
const int kScheduleLastHour = 24;

/// Height of one hour. The whole grid scrolls vertically, so this can be
/// generous enough to read rather than squeezed to fit a screen.
const double kDefaultScheduleHourHeight = kScheduleHourHeightDefault;

/// A 30 minute class is 32 dp at the hour height above, under the 48 dp
/// minimum target (CP-10). Short blocks are floored to it and so run slightly
/// past their real end, which is what platform calendars do: a block you
/// cannot reliably tap is worse than one a few minutes too tall.
const double _minBlockHeight = 48;

/// Narrowest a column may be unless the reader asks for narrower. Below this
/// a block cannot hold its module name, so the grid scrolls sideways instead
/// of drawing bare bars.
const double kDefaultColumnWidth = 104;

/// Computes the initial vertical scroll offset for [ScheduleGrid].
///
/// If [day] is today (or [days] contains today):
/// anchors around the current time ([now] minus 45 minutes lead-in),
/// floored at 07:00 (or the earliest class in [days] if earlier).
///
/// For other days:
/// anchors at 07:00 (or the earliest class in [days] if earlier).
double calculateInitialGridScrollOffset({
  required DateTime day,
  required DateTime now,
  required ScheduleDayIndex index,
  required double hourHeight,
  List<DateTime>? days,
  double viewportHeight = 0,
}) {
  const defaultHour = 7.0;
  const leadInMinutes = 45;

  final checkDays = days ?? <DateTime>[day];
  final isToday = checkDays.any(
    (d) => d.year == now.year && d.month == now.month && d.day == now.day,
  );

  // Find earliest event start hour across checkDays
  double? earliestClassHour;
  for (final d in checkDays) {
    for (final e in index.eventsOn(d)) {
      final h = e.start.hour + e.start.minute / 60.0;
      if (earliestClassHour == null || h < earliestClassHour) {
        earliestClassHour = h;
      }
    }
  }

  final floorHour = earliestClassHour != null
      ? math.min(defaultHour, earliestClassHour)
      : defaultHour;

  double targetHour;
  if (isToday) {
    final currentHour = now.hour + (now.minute - leadInMinutes) / 60.0;
    targetHour = math.max(floorHour, currentHour);
  } else {
    targetHour = floorHour;
  }

  final offset = targetHour * hourHeight;
  final maxScroll = (kScheduleLastHour * hourHeight - viewportHeight).clamp(
    0.0,
    double.infinity,
  );
  return offset.clamp(0.0, maxScroll);
}

/// The time grid behind Jour, 3 jours and Semaine. The modes differ only in
/// how many days are passed in.
class ScheduleGrid extends StatefulWidget {
  const ScheduleGrid({
    required this.index,
    required this.days,
    required this.onTapEvent,
    this.now,
    this.minColumnWidth = kDefaultColumnWidth,
    this.hourHeight = kDefaultScheduleHourHeight,
    this.initialVerticalOffset,
    this.verticalOffsetNotifier,
    this.onDayWidthDrag,
    this.onDayWidthCommit,
    this.onHourHeightDrag,
    this.onHourHeightCommit,
    super.key,
  }) : assert(
         (onDayWidthDrag == null) == (onDayWidthCommit == null),
         'Day-width drag and commit callbacks must be supplied together.',
       ),
       assert(
         (onHourHeightDrag == null) == (onHourHeightCommit == null),
         'Hour-height drag and commit callbacks must be supplied together.',
       );

  final ScheduleDayIndex index;
  final List<DateTime> days;
  final ValueChanged<ScheduleEvent> onTapEvent;
  final DateTime? now;

  /// Floor for a column before the track scrolls sideways. Columns still
  /// stretch past it when the period has room to spare.
  final double minColumnWidth;

  /// Height of an hour before the user's text-size preference is applied.
  final double hourHeight;

  /// Initial vertical scroll offset if no [verticalOffsetNotifier] is provided.
  final double? initialVerticalOffset;

  /// Shared vertical scroll offset notifier to synchronize scroll across pages.
  final ValueNotifier<double>? verticalOffsetNotifier;

  /// Called while a two-finger pinch changes Week day width.
  final ValueChanged<double>? onDayWidthDrag;

  /// Commits the width chosen by a two-finger pinch when the fingers lift.
  final ValueChanged<double>? onDayWidthCommit;

  /// Called while a vertical pinch changes hour height.
  final ValueChanged<double>? onHourHeightDrag;

  /// Commits the hour height chosen by a vertical pinch when fingers lift.
  final ValueChanged<double>? onHourHeightCommit;

  static const double gutterWidth = 40;

  @override
  State<ScheduleGrid> createState() => _ScheduleGridState();
}

enum _PinchAxis { horizontal, vertical }

class _ScheduleGridState extends State<ScheduleGrid> {
  final ScrollController _headings = ScrollController();
  final ScrollController _columns = ScrollController();
  late final ScrollController _vertical;
  bool _isSyncingVertical = false;
  _PinchAxis? _pinchAxis;
  double? _pinchStartDayWidth;
  double? _pinchedDayWidth;
  double? _pinchColumnUnits;
  double? _pinchFocalX;
  double? _pinchStartHourHeight;
  double? _pinchedHourHeight;
  double? _pinchHourUnits;
  double? _pinchFocalY;
  final Map<int, Offset> _pinchPointers = <int, Offset>{};
  Offset? _pinchInitialSeparation;
  final GlobalKey _gestureAreaKey = GlobalKey();
  final GlobalKey _verticalViewportKey = GlobalKey();
  double _lastColumnWidth = 0;
  double _lastHourHeight = 0;
  double _lastGutter = 0;
  double _lastContentWidth = 0;

  @override
  void initState() {
    super.initState();
    final initialOffset =
        widget.verticalOffsetNotifier?.value ??
        widget.initialVerticalOffset ??
        0.0;
    _vertical = ScrollController(initialScrollOffset: initialOffset);
    _vertical.addListener(_onVerticalScroll);
    widget.verticalOffsetNotifier?.addListener(_onNotifierScroll);
    _columns.addListener(_followColumns);
  }

  @override
  void didUpdateWidget(covariant ScheduleGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.verticalOffsetNotifier != oldWidget.verticalOffsetNotifier) {
      oldWidget.verticalOffsetNotifier?.removeListener(_onNotifierScroll);
      widget.verticalOffsetNotifier?.addListener(_onNotifierScroll);
      _onNotifierScroll();
    }
    if (widget.minColumnWidth != oldWidget.minColumnWidth) {
      _restorePinchAnchorsAfterLayout();
    }
    if (widget.hourHeight != oldWidget.hourHeight) {
      _restorePinchAnchorsAfterLayout();
    }
  }

  @override
  void dispose() {
    widget.verticalOffsetNotifier?.removeListener(_onNotifierScroll);
    _vertical
      ..removeListener(_onVerticalScroll)
      ..dispose();
    _columns
      ..removeListener(_followColumns)
      ..dispose();
    _headings.dispose();
    super.dispose();
  }

  void _followColumns() {
    if (_headings.hasClients) _headings.jumpTo(_columns.offset);
  }

  void _onVerticalScroll() {
    if (_isSyncingVertical) return;
    final notifier = widget.verticalOffsetNotifier;
    if (notifier != null && (notifier.value - _vertical.offset).abs() > 0.5) {
      _isSyncingVertical = true;
      notifier.value = _vertical.offset;
      _isSyncingVertical = false;
    }
  }

  void _onNotifierScroll() {
    if (_isSyncingVertical) return;
    final notifier = widget.verticalOffsetNotifier;
    if (notifier != null &&
        _vertical.hasClients &&
        _vertical.position.haveDimensions) {
      final target = notifier.value.clamp(
        0.0,
        _vertical.position.maxScrollExtent,
      );
      if ((_vertical.offset - target).abs() > 0.5) {
        _isSyncingVertical = true;
        _vertical.jumpTo(target);
        _isSyncingVertical = false;
      }
    }
  }

  void _onPointerDown(PointerDownEvent event) {
    _pinchPointers[event.pointer] = event.position;
    if (_pinchPointers.length != 2) return;
    _pinchStartDayWidth = widget.minColumnWidth;
    _pinchedDayWidth = widget.minColumnWidth;
    _pinchStartHourHeight = widget.hourHeight;
    _pinchedHourHeight = widget.hourHeight;
    _pinchInitialSeparation = _pointerSeparation;
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (!_pinchPointers.containsKey(event.pointer)) return;
    _pinchPointers[event.pointer] = event.position;
    final initial = _pinchInitialSeparation;
    if (_pinchPointers.length != 2 || initial == null) return;
    final separation = _pointerSeparation;
    final horizontalScale = _axisScale(separation.dx, initial.dx);
    final verticalScale = _axisScale(separation.dy, initial.dy);

    // Raw events avoid competing with the grid's scroll views.
    final axis = _pinchAxis ?? _selectPinchAxis(horizontalScale, verticalScale);
    if (axis == null) return;
    _pinchAxis ??= axis;

    if (axis == _PinchAxis.horizontal) {
      _updateDayWidth(horizontalScale);
    } else {
      _updateHourHeight(verticalScale);
    }
  }

  _PinchAxis? _selectPinchAxis(double horizontalScale, double verticalScale) {
    final horizontalChange = (horizontalScale - 1).abs();
    final verticalChange = (verticalScale - 1).abs();
    const threshold = 0.025;
    final canAdjustDays = widget.onDayWidthDrag != null;
    final canAdjustHours = widget.onHourHeightDrag != null;
    if ((!canAdjustDays || horizontalChange < threshold) &&
        (!canAdjustHours || verticalChange < threshold)) {
      return null;
    }
    if (!canAdjustHours ||
        (canAdjustDays && horizontalChange >= verticalChange)) {
      return _PinchAxis.horizontal;
    }
    return _PinchAxis.vertical;
  }

  void _updateDayWidth(double scale) {
    if (_pinchColumnUnits == null) {
      final box =
          _gestureAreaKey.currentContext?.findRenderObject() as RenderBox?;
      if (box == null) return;
      final focalX = (box.globalToLocal(_pointerFocalPoint).dx - _lastGutter)
          .clamp(0.0, _lastContentWidth);
      _pinchFocalX = focalX;
      if (_lastColumnWidth > 0 && _columns.hasClients) {
        _pinchColumnUnits = (_columns.offset + focalX) / _lastColumnWidth;
      }
    }

    final start = _pinchStartDayWidth ?? widget.minColumnWidth;
    final width = (start * scale)
        .clamp(kScheduleDayWidthMin, kScheduleDayWidthMax)
        .toDouble();
    _pinchedDayWidth = width;
    widget.onDayWidthDrag!(width);
    setState(() {});
  }

  void _updateHourHeight(double scale) {
    if (_pinchHourUnits == null) {
      final box =
          _verticalViewportKey.currentContext?.findRenderObject() as RenderBox?;
      if (box == null) return;
      final focalY = box
          .globalToLocal(_pointerFocalPoint)
          .dy
          .clamp(0.0, box.size.height);
      _pinchFocalY = focalY;
      if (_lastHourHeight > 0 && _vertical.hasClients) {
        _pinchHourUnits = (_vertical.offset + focalY) / _lastHourHeight;
      }
    }

    final start = _pinchStartHourHeight ?? widget.hourHeight;
    final height = (start * scale)
        .clamp(kScheduleHourHeightMin, kScheduleHourHeightMax)
        .toDouble();
    _pinchedHourHeight = height;
    widget.onHourHeightDrag!(height);
    setState(() {});
  }

  void _onPointerUpOrCancel(PointerEvent event) {
    if (_pinchAxis != null &&
        _pinchPointers.length == 2 &&
        _pinchPointers.containsKey(event.pointer)) {
      switch (_pinchAxis!) {
        case _PinchAxis.horizontal:
          _commitPinchedDayWidth();
        case _PinchAxis.vertical:
          _commitPinchedHourHeight();
      }
    }
    _pinchPointers.remove(event.pointer);
    if (_pinchPointers.length < 2) _pinchInitialSeparation = null;
  }

  void _commitPinchedDayWidth() {
    if (_pinchAxis != _PinchAxis.horizontal) return;
    _pinchAxis = null;
    final width = _pinchedDayWidth ?? widget.minColumnWidth;
    final snapped = (width / CampusSpacing.x1).round() * CampusSpacing.x1;
    widget.onDayWidthCommit!(
      snapped.clamp(kScheduleDayWidthMin, kScheduleDayWidthMax).toDouble(),
    );
    _pinchStartDayWidth = null;
    _pinchedDayWidth = null;
    setState(() {});
  }

  void _commitPinchedHourHeight() {
    if (_pinchAxis != _PinchAxis.vertical) return;
    _pinchAxis = null;
    final height = _pinchedHourHeight ?? widget.hourHeight;
    final snapped = (height / CampusSpacing.x1).round() * CampusSpacing.x1;
    widget.onHourHeightCommit!(
      snapped.clamp(kScheduleHourHeightMin, kScheduleHourHeightMax).toDouble(),
    );
    _pinchStartHourHeight = null;
    _pinchedHourHeight = null;
    setState(() {});
  }

  Offset get _pointerSeparation {
    final points = _pinchPointers.values.toList(growable: false);
    return points[0] - points[1];
  }

  Offset get _pointerFocalPoint {
    final points = _pinchPointers.values.toList(growable: false);
    return (points[0] + points[1]) / 2;
  }

  double _axisScale(double current, double initial) {
    if (initial.abs() < 24) return 1;
    return current.abs() / initial.abs();
  }

  void _restorePinchAnchorsAfterLayout() {
    final units = _pinchColumnUnits;
    final focalX = _pinchFocalX;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (units != null &&
          focalX != null &&
          _columns.hasClients &&
          _lastColumnWidth > 0) {
        final target = (units * _lastColumnWidth - focalX).clamp(
          0.0,
          _columns.position.maxScrollExtent,
        );
        _columns.jumpTo(target);
      }
      final hourUnits = _pinchHourUnits;
      final focalY = _pinchFocalY;
      if (hourUnits != null &&
          focalY != null &&
          _vertical.hasClients &&
          _lastHourHeight > 0) {
        final target = (hourUnits * _lastHourHeight - focalY).clamp(
          0.0,
          _vertical.position.maxScrollExtent,
        );
        _vertical.jumpTo(target);
      }
      if (_pinchAxis == null) {
        _pinchColumnUnits = null;
        _pinchFocalX = null;
        _pinchHourUnits = null;
        _pinchFocalY = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final index = widget.index;
    final days = widget.days;
    final now = widget.now;
    const first = kScheduleFirstHour;
    const last = kScheduleLastHour;

    final scale = MediaQuery.textScalerOf(context).scale(1);
    final hourHeight = widget.hourHeight * scale;
    final bodyHeight = (last - first) * hourHeight;

    // One column needs no heading: the page header already names that day.
    final headed = days.length > 1;

    final gutter = ScheduleGrid.gutterWidth * scale;

    return LayoutBuilder(
      builder: (context, constraints) {
        final rules = (days.length - 1).toDouble();
        final free = constraints.maxWidth - gutter - rules;
        final columnWidth = math.max(
          widget.minColumnWidth * scale,
          free / days.length,
        );
        final trackWidth = columnWidth * days.length + rules;
        _lastColumnWidth = columnWidth;
        _lastHourHeight = hourHeight;
        _lastGutter = gutter;
        _lastContentWidth = math.max(0, constraints.maxWidth - gutter);
        // A track that fits must not claim horizontal drags: the screen reads
        // those as "next period".
        final physics = trackWidth > constraints.maxWidth - gutter
            ? const ClampingScrollPhysics()
            : const NeverScrollableScrollPhysics();

        final grid = Column(
          children: <Widget>[
            if (headed)
              Row(
                children: <Widget>[
                  SizedBox(width: gutter),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      controller: _headings,
                      physics: const NeverScrollableScrollPhysics(),
                      child: SizedBox(
                        width: trackWidth,
                        child: _HeadingRow(
                          days: days,
                          columnWidth: columnWidth,
                          today: now,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            Expanded(
              child: SingleChildScrollView(
                key: _verticalViewportKey,
                controller: _vertical,
                child: SizedBox(
                  height: bodyHeight,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      _Gutter(
                        firstHour: first,
                        lastHour: last,
                        hourHeight: hourHeight,
                        width: gutter,
                      ),
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          controller: _columns,
                          physics: physics,
                          child: SizedBox(
                            width: trackWidth,
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: <Widget>[
                                for (
                                  var i = 0;
                                  i < days.length;
                                  i++
                                ) ...<Widget>[
                                  if (i > 0) const ScheduleColumnRule(),
                                  SizedBox(
                                    width: columnWidth,
                                    child: _DayColumn(
                                      events: index.eventsOn(days[i]),
                                      firstHour: first,
                                      hourHeight: hourHeight,
                                      minBlockHeight: _minBlockHeight * scale,
                                      now: _nowFor(days[i]),
                                      onTapEvent: widget.onTapEvent,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );

        if (widget.onDayWidthDrag == null && widget.onHourHeightDrag == null) {
          return grid;
        }
        return Listener(
          key: _gestureAreaKey,
          behavior: HitTestBehavior.translucent,
          onPointerDown: _onPointerDown,
          onPointerMove: _onPointerMove,
          onPointerUp: _onPointerUpOrCancel,
          onPointerCancel: _onPointerUpOrCancel,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              grid,
              if (_pinchAxis != null)
                Positioned(
                  top: CampusSpacing.x2,
                  right: CampusSpacing.x2,
                  child: ExcludeSemantics(
                    child: Material(
                      color: context.scheme.inverseSurface,
                      borderRadius: BorderRadius.circular(CampusSpacing.x2),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: CampusSpacing.x2,
                          vertical: CampusSpacing.x1,
                        ),
                        child: Text(
                          _pinchAxis == _PinchAxis.horizontal
                              ? 'Largeur des jours · '
                                    '${(_pinchedDayWidth ?? widget.minColumnWidth).round()} dp'
                              : 'Hauteur des heures · '
                                    '${(_pinchedHourHeight ?? widget.hourHeight).round()} dp',
                          style: context.text.labelLarge?.copyWith(
                            color: context.scheme.onInverseSurface,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  /// Non-null only for today's column, so the line is drawn once.
  DateTime? _nowFor(DateTime day) {
    final n = widget.now;
    if (n == null) return null;
    return n.year == day.year && n.month == day.month && n.day == day.day
        ? n
        : null;
  }
}

/// Hairline between two day columns.
class ScheduleColumnRule extends StatelessWidget {
  const ScheduleColumnRule({super.key});

  @override
  Widget build(BuildContext context) =>
      Container(width: 1, color: context.scheme.outlineVariant);
}

class _HeadingRow extends StatelessWidget {
  const _HeadingRow({
    required this.days,
    required this.columnWidth,
    required this.today,
  });

  final List<DateTime> days;
  final double columnWidth;
  final DateTime? today;

  bool _isToday(DateTime day) {
    final t = today;
    return t != null &&
        t.year == day.year &&
        t.month == day.month &&
        t.day == day.day;
  }

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: context.scheme.outlineVariant)),
    ),
    child: Row(
      children: <Widget>[
        for (var i = 0; i < days.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(width: 1),
          SizedBox(
            width: columnWidth,
            child: ScheduleDayHeading(day: days[i], isToday: _isToday(days[i])),
          ),
        ],
      ],
    ),
  );
}

/// One column's name and date, above the time grid.
class ScheduleDayHeading extends StatelessWidget {
  const ScheduleDayHeading({
    required this.day,
    required this.isToday,
    super.key,
  });

  final DateTime day;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final campus = context.campus;
    return Semantics(
      label: frenchDayLabel(day),
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: CampusSpacing.x2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              frenchWeekdaysShort[day.weekday - 1],
              maxLines: 1,
              style: context.text.labelMedium?.copyWith(
                color: context.scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: CampusSpacing.x1),
            Text('${day.day}', maxLines: 1, style: context.campusType.numeral),
            const SizedBox(height: CampusSpacing.x1),
            // Today keeps the underline the week strip uses, not a fill.
            SizedBox(
              height: 2,
              width: CampusSpacing.x5,
              child: isToday
                  ? DecoratedBox(decoration: BoxDecoration(color: campus.now))
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _Gutter extends StatelessWidget {
  const _Gutter({
    required this.firstHour,
    required this.lastHour,
    required this.hourHeight,
    required this.width,
  });

  final int firstHour;
  final int lastHour;
  final double hourHeight;
  final double width;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: Column(
      children: [
        for (var h = firstHour; h < lastHour; h++)
          SizedBox(
            height: hourHeight,
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.only(right: CampusSpacing.x1),
                child: Text(
                  h.toString().padLeft(2, '0'),
                  style: context.text.labelMedium?.copyWith(
                    color: context.scheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

class _DayColumn extends StatelessWidget {
  const _DayColumn({
    required this.events,
    required this.firstHour,
    required this.hourHeight,
    required this.minBlockHeight,
    required this.now,
    required this.onTapEvent,
  });

  final List<ScheduleEvent> events;
  final int firstHour;
  final double hourHeight;
  final double minBlockHeight;
  final DateTime? now;
  final ValueChanged<ScheduleEvent> onTapEvent;

  double _offsetOf(DateTime t) =>
      ((t.hour - firstHour) * 60 + t.minute) / 60 * hourHeight;

  @override
  Widget build(BuildContext context) {
    final lanes = assignLanes(events);
    return LayoutBuilder(
      builder: (context, constraints) => Stack(
        children: <Widget>[
          for (var h = 1; h < kScheduleLastHour; h++)
            Positioned(
              top: h * hourHeight,
              left: 0,
              right: 0,
              child: Container(
                height: 1,
                color: context.scheme.outlineVariant.withValues(alpha: 0.35),
              ),
            ),
          for (var i = 0; i < events.length; i++)
            Positioned(
              top: _offsetOf(events[i].start),
              height: (_offsetOf(events[i].end) - _offsetOf(events[i].start))
                  .clamp(minBlockHeight, double.infinity),
              left: lanes[i].lane * (constraints.maxWidth / lanes[i].lanes),
              width: lanes[i].span * (constraints.maxWidth / lanes[i].lanes),
              child: GridBlock(
                event: events[i],
                onTap: () => onTapEvent(events[i]),
              ),
            ),
          if (now != null)
            Positioned(
              top: _offsetOf(now!) - NowLine.dot / 2,
              left: 0,
              right: 0,
              child: const NowLine(),
            ),
        ],
      ),
    );
  }
}
