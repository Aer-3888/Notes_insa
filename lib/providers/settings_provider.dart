import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import '../background_tasks.dart';

/// Settings state for background fetch configuration
class SettingsState {
  final int fetchInterval;
  final bool fetchEnabled;
  final bool isLoading;

  const SettingsState({
    this.fetchInterval = 15,
    this.fetchEnabled = true,
    this.isLoading = false,
  });

  SettingsState copyWith({
    int? fetchInterval,
    bool? fetchEnabled,
    bool? isLoading,
  }) {
    return SettingsState(
      fetchInterval: fetchInterval ?? this.fetchInterval,
      fetchEnabled: fetchEnabled ?? this.fetchEnabled,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

/// Notifier for managing app settings
class SettingsNotifier extends StateNotifier<SettingsState> {
  static const String _fetchIntervalKey = 'background_fetch_interval';
  static const String _fetchEnabledKey = 'background_fetch_enabled';

  SettingsNotifier() : super(const SettingsState()) {
    _loadSettings();
  }

  /// Load settings from SharedPreferences
  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedInterval = prefs.getInt(_fetchIntervalKey);
      final savedEnabled = prefs.getBool(_fetchEnabledKey) ?? true;

      final interval = (savedInterval ?? 15).clamp(15, 60);
      state = state.copyWith(
        fetchInterval: interval,
        fetchEnabled: savedEnabled,
        isLoading: false,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SettingsProvider] Failed to load settings: $e');
      }
    }
  }

  /// Update fetch interval and restart background tasks
  Future<void> setFetchInterval(int interval) async {
    final previous = state.fetchInterval;
    state = state.copyWith(fetchInterval: interval);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_fetchIntervalKey, interval);

      // Restart background tasks with new interval
      await stopBackgroundTasks();
      await initBackgroundTasks();

      if (kDebugMode) {
        debugPrint(
          '[SettingsProvider] Fetch interval updated to $interval minutes',
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SettingsProvider] Failed to set fetch interval: $e');
      }
      // Restore previous value — background task was not reconfigured
      state = state.copyWith(fetchInterval: previous);
    }
  }

  /// Toggle background fetch enabled/disabled
  Future<void> setFetchEnabled(bool enabled) async {
    final previous = state.fetchEnabled;
    state = state.copyWith(fetchEnabled: enabled);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_fetchEnabledKey, enabled);

      // Start or stop background tasks based on enabled state
      if (enabled) {
        await initBackgroundTasks();
      } else {
        await stopBackgroundTasks();
      }

      if (kDebugMode) {
        debugPrint('[SettingsProvider] Fetch enabled set to $enabled');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SettingsProvider] Failed to set fetch enabled: $e');
      }
      // Restore previous value — background task was not reconfigured
      state = state.copyWith(fetchEnabled: previous);
    }
  }
}

/// Provider for app settings
final settingsProvider = StateNotifierProvider<SettingsNotifier, SettingsState>(
  (ref) {
    return SettingsNotifier();
  },
);

/// Convenience provider for available fetch intervals
final availableIntervalsProvider = Provider<List<int>>((ref) {
  return [15, 30, 60];
});

/// Convenience provider for formatted interval label
final intervalLabelProvider = Provider.family<String, int>((ref, minutes) {
  if (minutes < 60) return '$minutes minutes';
  final hours = minutes ~/ 60;
  return '$hours heure${hours > 1 ? 's' : ''}';
});
