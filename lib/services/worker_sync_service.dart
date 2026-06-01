import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../constants.dart';

/// Mirrors the secrets the native background worker needs into a dedicated
/// AndroidX EncryptedSharedPreferences store (see WorkerStore.kt).
///
/// flutter_secure_storage 10.x stores values in a format the worker cannot read
/// (custom cipher + prefixed keys), so every credential / session / grades write
/// is mirrored here. All calls are best-effort: failures are swallowed so they
/// never block the auth flow.
class WorkerSyncService {
  static const MethodChannel _channel = MethodChannel(
    'com.aer.notes_insa/grades',
  );

  // Keys must match WorkerStore.kt.
  static const String keyUsername = 'username';
  static const String keyPassword = 'password';
  static const String keyOtpSecret = 'otp_secret';
  static const String keyCasSession = 'cas_session';
  static const String keyGradesJson = 'stored_grades_json';

  /// Writes the provided keys to the worker store. A null value removes a key.
  static Future<void> sync(Map<String, String?> values) async {
    try {
      await _channel.invokeMethod<void>('SyncWorkerStore', {'values': values});
    } catch (e) {
      if (kDebugMode) debugPrint('[WorkerSync] sync failed: $e');
    }
  }

  /// Clears all worker-store data (called on logout).
  static Future<void> clear() async {
    try {
      await _channel.invokeMethod<void>('ClearWorkerStore');
    } catch (e) {
      if (kDebugMode) debugPrint('[WorkerSync] clear failed: $e');
    }
  }

  /// One-time mirror of existing secure-storage secrets into the worker store,
  /// so users already logged in before this store existed populate it without
  /// re-authenticating. No-op when not logged in.
  static Future<void> backfill() async {
    try {
      const storage = FlutterSecureStorage();
      final results = await Future.wait([
        storage.read(key: kStorageUser),
        storage.read(key: kStoragePass),
        storage.read(key: kStorageOtpSecret),
        storage.read(key: kStorageCasSession),
        storage.read(key: kStorageGradesJson),
      ]);
      final username = results[0];
      final password = results[1];
      if (username == null || password == null) return;
      await sync({
        keyUsername: username,
        keyPassword: password,
        keyOtpSecret: results[2],
        keyCasSession: results[3],
        keyGradesJson: results[4],
      });
    } catch (e) {
      if (kDebugMode) debugPrint('[WorkerSync] backfill failed: $e');
    }
  }
}
