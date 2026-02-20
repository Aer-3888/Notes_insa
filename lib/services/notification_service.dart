import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';

// Simple cross-platform notification helper.
class NotificationService {
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  static bool _isInitialized = false;
  static int _notificationIdCounter =
      1000; // Start from 1000 to avoid conflicts.

  // Initialize notifications and create channel on Android.
  static Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      if (Platform.isAndroid) {
        await Permission.notification.request();
      }

      const androidSettings = AndroidInitializationSettings(
        '@mipmap/ic_launcher',
      );
      const iosSettings = DarwinInitializationSettings(
        requestSoundPermission: true,
        requestBadgePermission: true,
        requestAlertPermission: true,
      );

      const settings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );

      await _notifications.initialize(
        settings: settings,
        onDidReceiveNotificationResponse: (_) {},
      );

      if (Platform.isAndroid) {
        const AndroidNotificationChannel gradesChannel =
            AndroidNotificationChannel(
              'grades_updates',
              'Grades Updates',
              description: 'Notifications for new grade updates',
              importance: Importance.high,
              playSound: true,
              enableVibration: true,
            );

        await _notifications
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.createNotificationChannel(gradesChannel);
      }

      _isInitialized = true;
    } catch (_) {
      _isInitialized = false;
    }
  }

  // Show notification for new grades.
  static Future<void> showNewGradesNotification(
    List<String> subjectNames,
  ) async {
    if (!_isInitialized) await initialize();

    const androidDetails = AndroidNotificationDetails(
      'grades_updates',
      'Grades Updates',
      channelDescription: 'Notifications for new grade updates',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
    );

    const iosDetails = DarwinNotificationDetails();
    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    try {
      String body = 'You have new grades.';
      if (subjectNames.isNotEmpty) {
        if (subjectNames.length == 1) {
          body = 'New grade: ${subjectNames[0]}';
        } else if (subjectNames.length <= 3) {
          body = 'New grades: ${subjectNames.join(', ')}';
        } else {
          body =
              'New grades: ${subjectNames.take(3).join(', ')} and ${subjectNames.length - 3} more';
        }
      }

      await _notifications.show(
        id: _notificationIdCounter++,
        title: 'New Grades Available!',
        body: body,
        notificationDetails: details,
        payload: 'new_grades',
      );
    } catch (_) {
      // Fail silently
    }
  }

  // Show notification for updated grades.
  static Future<void> showUpdatedGradesNotification(
    List<String> subjectNames,
  ) async {
    if (!_isInitialized) await initialize();

    const androidDetails = AndroidNotificationDetails(
      'grades_updates',
      'Grades Updates',
      channelDescription: 'Notifications for new grade updates',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
    );

    const iosDetails = DarwinNotificationDetails();
    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    try {
      String body = 'Your grades have been updated.';
      if (subjectNames.isNotEmpty) {
        if (subjectNames.length == 1) {
          body = 'Grade updated: ${subjectNames[0]}';
        } else if (subjectNames.length <= 3) {
          body = 'Grades updated: ${subjectNames.join(', ')}';
        } else {
          body =
              'Grades updated: ${subjectNames.take(3).join(', ')} and ${subjectNames.length - 3} more';
        }
      }

      await _notifications.show(
        id: _notificationIdCounter++,
        title: 'Grades Updated!',
        body: body,
        notificationDetails: details,
        payload: 'updated_grades',
      );
    } catch (_) {
      // Fail silently
    }
  }

  // Cancel all delivered notifications.
  static Future<void> cancelAllNotifications() async {
    try {
      await _notifications.cancelAll();
    } catch (_) {}
  }
}
