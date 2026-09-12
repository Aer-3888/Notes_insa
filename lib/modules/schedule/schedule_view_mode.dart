import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Small scalar, so it lives in shared_preferences beside the group ids
/// rather than in the file cache.
const String kScheduleViewModeKey = 'schedule_view_mode';
const String kScheduleDayWeekStripKey = 'schedule_day_week_strip';
const String kScheduleListWeekStripKey = 'schedule_list_week_strip';
const String kScheduleMonthPreviewKey = 'schedule_month_preview';
const String kScheduleDayWidthKey = 'schedule_day_width';

enum ScheduleViewMode {
  liste('Liste', 0),
  jour('Jour', 1),
  troisJours('3 jours', 3),
  semaine('Semaine', 7),
  mois('Mois', 0);

  const ScheduleViewMode(this.label, this.dayColumns);

  /// French, and shown in the app bar.
  final String label;

  /// Columns the grid draws. Zero for the modes that are not a grid.
  final int dayColumns;

  /// Where a week strip is offered at all. The grids draw their own dated
  /// columns, so it would only repeat them.
  bool get showsStrip => this == liste || this == jour;
}

/// The chosen mode, remembered across launches. Losing a chosen default is
/// the thing users object to, so this is persisted rather than session-only.
class ScheduleViewModeNotifier extends Notifier<ScheduleViewMode> {
  @override
  ScheduleViewMode build() {
    unawaited(_restore());
    return ScheduleViewMode.liste;
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(kScheduleViewModeKey);
    if (stored == null) return;
    for (final mode in ScheduleViewMode.values) {
      if (mode.name == stored) {
        state = mode;
        return;
      }
    }
  }

  Future<void> set(ScheduleViewMode mode) async {
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kScheduleViewModeKey, mode.name);
  }
}

final scheduleViewModeProvider =
    NotifierProvider<ScheduleViewModeNotifier, ScheduleViewMode>(
      ScheduleViewModeNotifier.new,
    );

/// A remembered on/off view preference. Each one is independent of the view
/// mode, so leaving a view and coming back keeps what was chosen.
abstract class ScheduleFlagNotifier extends Notifier<bool> {
  ScheduleFlagNotifier(this._key, this._fallback);

  final String _key;
  final bool _fallback;

  @override
  bool build() {
    unawaited(_restore());
    return _fallback;
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool(_key) ?? _fallback;
  }

  Future<void> toggle() async {
    state = !state;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, state);
  }
}

/// Whether Jour keeps the compact week strip above its day timeline.
class ScheduleDayWeekStripNotifier extends ScheduleFlagNotifier {
  ScheduleDayWeekStripNotifier() : super(kScheduleDayWeekStripKey, true);
}

final scheduleDayWeekStripProvider =
    NotifierProvider<ScheduleFlagNotifier, bool>(
      ScheduleDayWeekStripNotifier.new,
    );

/// Whether Liste keeps the week strip. Off by default: the list already runs
/// across day boundaries, so the strip is navigation the body does not need.
class ScheduleListWeekStripNotifier extends ScheduleFlagNotifier {
  ScheduleListWeekStripNotifier() : super(kScheduleListWeekStripKey, false);
}

final scheduleListWeekStripProvider =
    NotifierProvider<ScheduleFlagNotifier, bool>(
      ScheduleListWeekStripNotifier.new,
    );

/// Whether Mois draws the day's classes inside each cell.
class ScheduleMonthPreviewNotifier extends ScheduleFlagNotifier {
  ScheduleMonthPreviewNotifier() : super(kScheduleMonthPreviewKey, true);
}

final scheduleMonthPreviewProvider =
    NotifierProvider<ScheduleFlagNotifier, bool>(
      ScheduleMonthPreviewNotifier.new,
    );

/// How wide a day column may get before the grid scrolls sideways instead.
///
/// The widths come from the label measurements in the calendar research: a
/// seven-column week leaves about 49 dp per day on a 384 dp phone, a short
/// module name needs about 56 dp, and the longest ones need about 111 dp.
enum ScheduleDayWidth {
  compact('Compact', 'Toute la semaine à l’écran', 48),
  normal('Normal', 'Un nom de cours court tient', 104),
  large('Large', 'Les noms longs tiennent en entier', 160);

  const ScheduleDayWidth(this.label, this.description, this.minColumnWidth);

  /// French, and shown in the settings list.
  final String label;
  final String description;

  /// Floor for a column, before text scaling. Columns still stretch to fill a
  /// period that has room to spare.
  final double minColumnWidth;
}

/// The chosen column width, remembered across launches.
class ScheduleDayWidthNotifier extends Notifier<ScheduleDayWidth> {
  @override
  ScheduleDayWidth build() {
    unawaited(_restore());
    return ScheduleDayWidth.normal;
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(kScheduleDayWidthKey);
    if (stored == null) return;
    for (final width in ScheduleDayWidth.values) {
      if (width.name == stored) {
        state = width;
        return;
      }
    }
  }

  Future<void> set(ScheduleDayWidth width) async {
    state = width;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kScheduleDayWidthKey, width.name);
  }
}

final scheduleDayWidthProvider =
    NotifierProvider<ScheduleDayWidthNotifier, ScheduleDayWidth>(
      ScheduleDayWidthNotifier.new,
    );
