import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/module_tints.dart';

/// The timetable's colour choice. Both halves are stored, so turning colour
/// off and back on returns the intensity the student had.
@immutable
class ScheduleTintChoice {
  const ScheduleTintChoice({required this.scheme, required this.intensity});

  final ScheduleTintScheme scheme;
  final ScheduleTintIntensity intensity;

  static const ScheduleTintChoice shipped = ScheduleTintChoice(
    scheme: ScheduleTintScheme.spectre,
    intensity: ScheduleTintIntensity.standard,
  );

  @override
  bool operator ==(Object other) =>
      other is ScheduleTintChoice &&
      other.scheme == scheme &&
      other.intensity == intensity;

  @override
  int get hashCode => Object.hash(scheme, intensity);
}

/// The shipped default until the stored choice arrives; a storage failure
/// keeps whatever is in memory, the same policy as ThemeModeNotifier.
class ScheduleTintNotifier extends Notifier<ScheduleTintChoice> {
  static const String schemeKey = 'schedule_tint_scheme';
  static const String intensityKey = 'schedule_tint_intensity';

  Future<void>? _loaded;

  @visibleForTesting
  Future<void> get loaded => _loaded ?? Future<void>.value();

  @override
  ScheduleTintChoice build() {
    _loaded = _load();
    return ScheduleTintChoice.shipped;
  }

  /// An unrecognised stored name falls back rather than throwing, so removing
  /// a scheme in a later release cannot brick a launch.
  static T _restore<T extends Enum>(List<T> values, String? name, T fallback) =>
      values.firstWhere((v) => v.name == name, orElse: () => fallback);

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = ScheduleTintChoice(
        scheme: _restore(
          ScheduleTintScheme.values,
          prefs.getString(schemeKey),
          ScheduleTintChoice.shipped.scheme,
        ),
        intensity: _restore(
          ScheduleTintIntensity.values,
          prefs.getString(intensityKey),
          ScheduleTintChoice.shipped.intensity,
        ),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[ScheduleTint] load failed: $e');
    }
  }

  Future<void> setScheme(ScheduleTintScheme scheme) async {
    state = ScheduleTintChoice(scheme: scheme, intensity: state.intensity);
    await _write(schemeKey, scheme.name);
  }

  Future<void> setIntensity(ScheduleTintIntensity intensity) async {
    state = ScheduleTintChoice(scheme: state.scheme, intensity: intensity);
    await _write(intensityKey, intensity.name);
  }

  Future<void> _write(String key, String value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, value);
    } catch (e) {
      if (kDebugMode) debugPrint('[ScheduleTint] save failed: $e');
    }
  }
}

final scheduleTintProvider =
    NotifierProvider<ScheduleTintNotifier, ScheduleTintChoice>(
      ScheduleTintNotifier.new,
    );
