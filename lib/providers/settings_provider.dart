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
      // Sharing is strictly opt-in: an unset value stays false until the user
      // explicitly consents (re-prompted on the dashboard when never asked).
      final sharingConsent = prefs.getBool(_sharingConsentKey) ?? false;
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
    final safeInterval = interval.clamp(15, 60);
    state = state.copyWith(fetchInterval: safeInterval);
    final prefs = await SharedPreferences.getInstance();
    try {
      await prefs.setInt(_fetchIntervalKey, safeInterval);

      // Restart background tasks with new interval
      await stopBackgroundTasks(rethrowOnError: true);
      await initBackgroundTasks(rethrowOnError: true);

      if (kDebugMode) {
        debugPrint(
          '[SettingsProvider] Fetch interval updated to $interval minutes',
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SettingsProvider] Failed to set fetch interval: $e');
      }
      await prefs.setInt(_fetchIntervalKey, previous);
      // Restore previous value — background task was not reconfigured
      state = state.copyWith(fetchInterval: previous);
      try {
        await stopBackgroundTasks(rethrowOnError: true);
        await initBackgroundTasks(rethrowOnError: true);
      } catch (_) {}
      rethrow;
    }
  }

  /// Enable or disable anonymous grade sharing.
  Future<void> setSharingConsent(bool value) async {
    // Choosing a value is itself answering the question, so record that consent
    // was asked. This keeps the dashboard re-prompt from firing for users who
    // opt in or out from the settings screen.
    state = state.copyWith(sharingConsent: value, sharingConsentAsked: true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_sharingConsentKey, value);
      await prefs.setBool(_consentAskedKey, true);
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
    final prefs = await SharedPreferences.getInstance();
    try {
      await prefs.setBool(_fetchEnabledKey, enabled);

      // Start or stop background tasks based on enabled state
      if (enabled) {
        await initBackgroundTasks(rethrowOnError: true);
      } else {
        await stopBackgroundTasks(rethrowOnError: true);
        await resetBackgroundTaskState();
      }

      if (kDebugMode) {
        debugPrint('[SettingsProvider] Fetch enabled set to $enabled');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SettingsProvider] Failed to set fetch enabled: $e');
      }
      await prefs.setBool(_fetchEnabledKey, previous);
      // Restore previous value — background task was not reconfigured
      state = state.copyWith(fetchEnabled: previous);
      try {
        if (previous) {
          await initBackgroundTasks(rethrowOnError: true);
        } else {
          await stopBackgroundTasks(rethrowOnError: true);
        }
      } catch (_) {}
      rethrow;
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
