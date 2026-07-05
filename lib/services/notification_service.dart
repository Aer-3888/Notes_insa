import 'dart:async';
import 'dart:io';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

// Simple cross-platform notification helper.
class NotificationService {
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  static bool _isInitialized = false;

  // Fixed IDs so each notification type replaces the previous one
  // rather than stacking up across process restarts.
  static const int _idNewGrades = 1;
  static const int _idUpdatedGrades = 2;

  // Broadcast stream for notification taps while the app is running.
  static final _tapController = StreamController<String>.broadcast();
  static Stream<String> get tapStream => _tapController.stream;

  // Payload from a notification that cold-started the app (read once via consumePendingPayload).
  static String? _pendingPayload;
  static String? consumePendingPayload() {
    final p = _pendingPayload;
    _pendingPayload = null;
    return p;
  }

  static void _onTap(NotificationResponse response) {
    final payload = response.payload;
    if (payload != null) _tapController.add(payload);
  }

  // Request notification permission — call this from the foreground UI only.
  static Future<void> requestPermission() async {
    if (Platform.isAndroid) {
      await Permission.notification.request();
    } else if (Platform.isIOS) {
      await _notifications
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    }
  }

  // Initialize notifications and create channel on Android.
  static Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      const androidSettings = AndroidInitializationSettings(
        '@mipmap/launcher_icon',
      );
      // Do not request iOS permission at init (app start). It is requested from
      // an explicit user action instead (onboarding notifications slide and the
      // dashboard), matching the Android POST_NOTIFICATIONS flow.
      const iosSettings = DarwinInitializationSettings(
        requestSoundPermission: false,
        requestBadgePermission: false,
        requestAlertPermission: false,
      );

      const settings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );

      await _notifications.initialize(
        settings: settings,
        onDidReceiveNotificationResponse: _onTap,
      );

      // Cold start: app was launched by tapping a Flutter local notification.
      final launchDetails = await _notifications
          .getNotificationAppLaunchDetails();
      if (launchDetails?.didNotificationLaunchApp == true) {
        _pendingPayload = launchDetails?.notificationResponse?.payload;
      }

      if (Platform.isAndroid) {
        final android = _notifications
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();

        // Grade updates carry academic content, so keep them off a secure lock
        // screen (NotificationVisibility.private on each notification below).
        const AndroidNotificationChannel gradesChannel =
            AndroidNotificationChannel(
              'grades_updates',
              'Nouvelles notes',
              description: 'Notifications lorsqu\'une note est publiée',
              importance: Importance.high,
              playSound: true,
              enableVibration: true,
            );
        // Reconnect/security prompts are a different class of message and get
        // their own channel so the user can tune them independently.
        const AndroidNotificationChannel reconnectChannel =
            AndroidNotificationChannel(
              'reconnect_updates',
              'Reconnexion',
              description:
                  'Invitations à se reconnecter (double authentification)',
              importance: Importance.high,
              playSound: true,
              enableVibration: true,
            );

        await android?.createNotificationChannel(gradesChannel);
        await android?.createNotificationChannel(reconnectChannel);
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
      'Nouvelles notes',
      channelDescription: 'Notifications lorsqu\'une note est publiée',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      // Hide the subject names on a secure lock screen.
      visibility: NotificationVisibility.private,
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
      'Nouvelles notes',
      channelDescription: 'Notifications lorsqu\'une note est publiée',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      // Hide the subject names on a secure lock screen.
      visibility: NotificationVisibility.private,
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

  // Show notification asking the user to re-authenticate (2FA required).
  static Future<void> showReauthRequiredNotification() async {
    if (!_isInitialized) await initialize();

    const androidDetails = AndroidNotificationDetails(
      'reconnect_updates',
      'Reconnexion',
      channelDescription:
          'Invitations à se reconnecter (double authentification)',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(),
    );

    try {
      await _notifications.show(
        id: 3,
        title: 'Reconnexion requise',
        body:
            'Une double authentification est nécessaire. Ouvrez l\'application pour vous reconnecter.',
        notificationDetails: details,
        payload: 'reauth_required',
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
