import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const kGradesViewModeKey = 'grades_view_mode';

const kDefaultGradesViewMode = GradesViewMode.synthese;

enum GradesViewMode {
  cartes('Cartes'),
  liste('Liste'),
  synthese('Synthèse');

  const GradesViewMode(this.label);

  final String label;
}

/// Only the display preference is stored here, never grades or credentials.
class GradesViewModeNotifier extends Notifier<GradesViewMode> {
  bool _selected = false;

  @override
  GradesViewMode build() {
    _selected = false;
    unawaited(_restore());
    return kDefaultGradesViewMode;
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    if (!ref.mounted || _selected) return;
    final stored = prefs.getString(kGradesViewModeKey);
    for (final mode in GradesViewMode.values) {
      if (mode.name == stored) {
        state = mode;
        return;
      }
    }
  }

  Future<void> set(GradesViewMode mode) async {
    _selected = true;
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kGradesViewModeKey, mode.name);
  }
}

final gradesViewModeProvider =
    NotifierProvider<GradesViewModeNotifier, GradesViewMode>(
      GradesViewModeNotifier.new,
    );
