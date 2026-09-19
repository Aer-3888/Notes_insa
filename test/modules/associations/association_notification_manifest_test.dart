import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android declares scheduled notification reboot support', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    expect(manifest, contains('android.permission.RECEIVE_BOOT_COMPLETED'));
    expect(
      manifest,
      contains('flutterlocalnotifications.ScheduledNotificationReceiver'),
    );
    expect(
      manifest,
      contains('flutterlocalnotifications.ScheduledNotificationBootReceiver'),
    );
    expect(manifest, contains('android.intent.action.BOOT_COMPLETED'));
    expect(manifest, contains('android.intent.action.MY_PACKAGE_REPLACED'));
  });
}
