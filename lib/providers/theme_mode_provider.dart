import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);

/// System until the stored choice arrives; a storage failure keeps whatever
/// is in memory, the same policy as SettingsNotifier.
class ThemeModeNotifier extends Notifier<ThemeMode> {
  static const String prefsKey = 'theme_mode';

  Future<void>? _loaded;

  @visibleForTesting
  Future<void> get loaded => _loaded ?? Future<void>.value();

  @override
  ThemeMode build() {
    _loaded = _load();
    return ThemeMode.system;
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(prefsKey);
      state = ThemeMode.values.firstWhere(
        (m) => m.name == stored,
        orElse: () => ThemeMode.system,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[ThemeMode] load failed: $e');
    }
  }

  Future<void> set(ThemeMode mode) async {
    state = mode;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(prefsKey, mode.name);
    } catch (e) {
      if (kDebugMode) debugPrint('[ThemeMode] save failed: $e');
    }
  }
}
