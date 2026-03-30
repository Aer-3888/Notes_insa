import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import '../background_tasks.dart';

/// Settings state for background fetch configuration
class SettingsState {
  final int fetchInterval;
  final bool fetchEnabled;
  final bool isLoading;
  final bool sharingConsent;
  final bool sharingConsentAsked;

  const SettingsState({
    this.fetchInterval = 15,
    this.fetchEnabled = true,
    this.isLoading = true, // true until _loadSettings() completes
    this.sharingConsent =
        false, // safe default — overwritten by persisted value
    this.sharingConsentAsked = false,
  });

  SettingsState copyWith({
    int? fetchInterval,
    bool? fetchEnabled,
    bool? isLoading,
    bool? sharingConsent,
    bool? sharingConsentAsked,
  }) {
    return SettingsState(
      fetchInterval: fetchInterval ?? this.fetchInterval,
      fetchEnabled: fetchEnabled ?? this.fetchEnabled,
      isLoading: isLoading ?? this.isLoading,
      sharingConsent: sharingConsent ?? this.sharingConsent,
      sharingConsentAsked: sharingConsentAsked ?? this.sharingConsentAsked,
    );
  }
}

/// Notifier for managing app settings
class SettingsNotifier extends StateNotifier<SettingsState> {
  static const String _fetchIntervalKey = 'background_fetch_interval';
  static const String _fetchEnabledKey = 'background_fetch_enabled';
  static const String _sharingConsentKey = 'sharing_consent';
  static const String _consentAskedKey = 'sharing_consent_asked';

  SettingsNotifier() : super(const SettingsState()) {
    _loadSettings();
  }

  /// Load settings from SharedPreferences
  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedInterval = prefs.getInt(_fetchIntervalKey);
      final savedEnabled = prefs.getBool(_fetchEnabledKey) ?? true;
      final sharingConsent = prefs.getBool(_sharingConsentKey) ?? true;
      final consentAsked = prefs.getBool(_consentAskedKey) ?? false;

      final interval = (savedInterval ?? 15).clamp(15, 60);
      state = state.copyWith(
        fetchInterval: interval,
        fetchEnabled: savedEnabled,
        sharingConsent: sharingConsent,
        sharingConsentAsked: consentAsked,
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

  /// Enable or disable anonymous grade sharing.
  Future<void> setSharingConsent(bool value) async {
    state = state.copyWith(sharingConsent: value);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_sharingConsentKey, value);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SettingsProvider] Failed to save sharingConsent: $e');
      }
    }
  }

  /// Mark that the consent dialog has been shown — called exactly once
  /// from the consent dialog, never from the settings screen.
  Future<void> markConsentAsked() async {
    state = state.copyWith(sharingConsentAsked: true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_consentAskedKey, true);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SettingsProvider] Failed to save consentAsked: $e');
      }
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
