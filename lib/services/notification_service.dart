import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';

// Simple cross-platform notification helper.
class NotificationService {
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  static bool _isInitialized = false;

  // Fixed IDs so each notification type replaces the previous one
  // rather than stacking up across process restarts.
  static const int _idNewGrades = 1;
  static const int _idUpdatedGrades = 2;

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
      String body = 'Vous avez de nouvelles notes.';
      if (subjectNames.isNotEmpty) {
        if (subjectNames.length == 1) {
          body = 'Nouvelle note : ${subjectNames[0]}';
        } else if (subjectNames.length <= 3) {
          body = 'Nouvelles notes : ${subjectNames.join(', ')}';
        } else {
          body =
              'Nouvelles notes : ${subjectNames.take(3).join(', ')} et ${subjectNames.length - 3} autre(s)';
        }
      }

      await _notifications.show(
        id: _idNewGrades,
        title: 'Nouvelles notes disponibles',
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
      String body = 'Vos notes ont été mises à jour.';
      if (subjectNames.isNotEmpty) {
        if (subjectNames.length == 1) {
          body = 'Note mise à jour : ${subjectNames[0]}';
        } else if (subjectNames.length <= 3) {
          body = 'Notes mises à jour : ${subjectNames.join(', ')}';
        } else {
          body =
              'Notes mises à jour : ${subjectNames.take(3).join(', ')} et ${subjectNames.length - 3} autre(s)';
        }
      }

      await _notifications.show(
        id: _idUpdatedGrades,
        title: 'Notes mises à jour',
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
