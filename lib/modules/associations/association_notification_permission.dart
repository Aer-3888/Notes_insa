import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../services/notification_service.dart';

abstract interface class NotificationPermissionGateway {
  Future<NotificationPermissionState> status();
  Future<NotificationPermissionState> request();
  Future<void> openSettings();
}

class DeviceNotificationPermissionGateway
    implements NotificationPermissionGateway {
  const DeviceNotificationPermissionGateway();

  @override
  Future<NotificationPermissionState> status() =>
      NotificationService.permissionState();

  @override
  Future<NotificationPermissionState> request() =>
      NotificationService.requestPermission();

  @override
  Future<void> openSettings() => openAppSettings();
}

final notificationPermissionGatewayProvider =
    Provider<NotificationPermissionGateway>(
      (ref) => const DeviceNotificationPermissionGateway(),
    );

final associationNotificationPermissionProvider =
    FutureProvider<NotificationPermissionState>(
      (ref) => ref.watch(notificationPermissionGatewayProvider).status(),
    );

Future<NotificationPermissionState> refreshAssociationNotificationPermission(
  WidgetRef ref,
) {
  ref.invalidate(associationNotificationPermissionProvider);
  return ref.read(associationNotificationPermissionProvider.future);
}
