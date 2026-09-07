import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Small scalar, so it lives in shared_preferences beside the group ids
/// rather than in the file cache.
const String kScheduleViewModeKey = 'schedule_view_mode';
const String kScheduleDayWeekStripKey = 'schedule_day_week_strip';

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

  /// Redundant wherever the grid draws its own dated columns.
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

/// Whether Jour keeps the compact week strip above its day timeline. This is
/// independent from the view mode, so returning to Jour keeps the preference.
class ScheduleDayWeekStripNotifier extends Notifier<bool> {
  @override
  bool build() {
    unawaited(_restore());
    return true;
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool(kScheduleDayWeekStripKey) ?? true;
  }

  Future<void> toggle() async {
    state = !state;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kScheduleDayWeekStripKey, state);
  }
}

final scheduleDayWeekStripProvider =
    NotifierProvider<ScheduleDayWeekStripNotifier, bool>(
      ScheduleDayWeekStripNotifier.new,
    );
