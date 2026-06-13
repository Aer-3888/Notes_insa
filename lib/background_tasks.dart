import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
Future<void> initBackgroundTasks() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final fetchInterval = prefs.getInt('background_fetch_interval') ?? 15;
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
  }
}

/// Cancel the native Android background task.
Future<void> stopBackgroundTasks() async {
  try {
    await _channel.invokeMethod<void>('StopBackgroundTask');
    if (kDebugMode) debugPrint('[BackgroundTask] Native worker cancelled');
  } catch (e) {
    if (kDebugMode) debugPrint('[BackgroundTask] Failed to stop native worker');
  }
}
