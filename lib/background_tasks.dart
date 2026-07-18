import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/auth_service.dart';

// The custom MethodChannel used for all Mobinsapi calls.
const _channel = MethodChannel('com.aer.notes_insa/grades');

/// Initialize or reschedule the native Android background task.
///
/// Reads the configured fetch interval from SharedPreferences and passes it to
/// the native scheduler via MethodChannel.
///
/// - Android: schedules a WorkManager [GradesBackgroundWorker] that calls
///   Mobinsapi directly, so it runs even after the app process is killed.
/// - iOS: schedules a BGTaskScheduler processing task (GradesBackgroundTask.swift)
///   that runs in-process when the system grants background time. The interval
///   is an earliest-begin hint, not a guaranteed schedule.
const _backgroundStateKeys = <String>[
  'background_failure_started_at_ms',
  'last_background_failure_alert_ms',
  'last_reauth_notif_ms',
  // Legacy keys from the old failure-counter implementation.
  'last_creds_notif_ms',
  'consecutive_auth_failures',
];

Future<void> initBackgroundTasks({bool rethrowOnError = false}) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final fetchEnabled = prefs.getBool('background_fetch_enabled') ?? true;
    // Do not recreate account work after logout. A successful sign-in invokes
    // this helper again, preserving the user's saved background-fetch setting.
    if (!fetchEnabled || !await AuthService().isLoggedIn()) return;
    final fetchInterval = (prefs.getInt('background_fetch_interval') ?? 15)
        .clamp(15, 60);
    await _channel.invokeMethod<void>('InitBackgroundTask', {
      'intervalMinutes': fetchInterval,
    });
    if (kDebugMode) {
      debugPrint(
        '[BackgroundTask] Scheduled native worker with ${fetchInterval}min interval',
      );
    }
  } catch (e) {
    if (kDebugMode) {
      debugPrint('[BackgroundTask] Failed to schedule native worker');
    }
    if (rethrowOnError) rethrow;
  }
}

/// Cancel the native Android background task.
Future<void> stopBackgroundTasks({bool rethrowOnError = false}) async {
  try {
    await _channel.invokeMethod<void>('StopBackgroundTask');
    if (kDebugMode) debugPrint('[BackgroundTask] Native worker cancelled');
  } catch (e) {
    if (kDebugMode) debugPrint('[BackgroundTask] Failed to stop native worker');
    if (rethrowOnError) rethrow;
  }
}

/// Clears account-scoped retry windows and notification cooldowns.
///
/// These values are not sensitive, so normal logout treats this as best-effort;
/// callers that need to surface a preferences failure can opt into rethrowing.
Future<void> resetBackgroundTaskState({bool rethrowOnError = false}) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    for (final key in _backgroundStateKeys) {
      await prefs.remove(key);
    }
  } catch (e) {
    if (kDebugMode) {
      debugPrint('[BackgroundTask] Failed to clear background task state');
    }
    if (rethrowOnError) rethrow;
  }
}
