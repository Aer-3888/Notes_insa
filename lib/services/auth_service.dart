import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import '../constants.dart';
import 'worker_sync_service.dart';

enum AuthResult { success, failure, pinRequired }

class AuthService {
  // Safe for background tasks
  static const _storage = FlutterSecureStorage();
  final _auth = LocalAuthentication();

  Future<void> storeCredentials(String username, String password) async {
    await Future.wait([
      _storage.write(key: kStorageUser, value: username),
      _storage.write(key: kStoragePass, value: password),
    ]);
    await WorkerSyncService.sync({
      WorkerSyncService.keyUsername: username,
      WorkerSyncService.keyPassword: password,
    });
  }

  Future<Map<String, String>?> getCredentials() async {
    final results = await Future.wait([
      _storage.read(key: kStorageUser),
      _storage.read(key: kStoragePass),
    ]);
    final username = results[0];
    final password = results[1];
    if (username == null || password == null) return null;
    return {kStorageUser: username, kStoragePass: password};
  }

  // OTP secret — optional, stored only when user opts in.
  Future<String?> getOtpSecret() => _storage.read(key: kStorageOtpSecret);

  Future<void> storeOtpSecret(String secret) async {
    await _storage.write(key: kStorageOtpSecret, value: secret);
    await WorkerSyncService.sync({WorkerSyncService.keyOtpSecret: secret});
  }

  Future<void> deleteOtpSecret() async {
    await _storage.delete(key: kStorageOtpSecret);
    await WorkerSyncService.sync({WorkerSyncService.keyOtpSecret: null});
  }

  // CAS session token — saved after auth to allow silent session restore on next launch.
  Future<String?> getCasSession() => _storage.read(key: kStorageCasSession);

  Future<void> storeCasSession(String token) async {
    await _storage.write(key: kStorageCasSession, value: token);
    await WorkerSyncService.sync({WorkerSyncService.keyCasSession: token});
  }

  Future<void> deleteCasSession() async {
    await _storage.delete(key: kStorageCasSession);
    await WorkerSyncService.sync({WorkerSyncService.keyCasSession: null});
  }

  // PIN methods
  // The PIN is stored as a salted SHA-256 hash. Brute-forcing is further
  // throttled by an attempt counter + lockout (see pinLockoutRemaining).
  static const int _maxPinAttempts = 5;
  static const Duration _pinLockoutDuration = Duration(minutes: 1);

  String _generateSalt() {
    final rng = Random.secure();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    return base64Url.encode(bytes);
  }

  String _hashPin(String pin, String salt) =>
      sha256.convert(utf8.encode('$salt:$pin')).toString();

  Future<void> setPin(String pin) async {
    final salt = _generateSalt();
    await Future.wait([
      _storage.write(key: kStoragePinSalt, value: salt),
      _storage.write(key: kStoragePin, value: _hashPin(pin, salt)),
    ]);
    await resetPinAttempts();
  }

  Future<bool> hasPin() async {
    final pin = await _storage.read(key: kStoragePin);
    return pin != null && pin.isNotEmpty;
  }

  Future<bool> verifyPin(String pin) async {
    final stored = await _storage.read(key: kStoragePin);
    if (stored == null || stored.isEmpty) return false;
    final salt = await _storage.read(key: kStoragePinSalt);
    if (salt == null) {
      // Legacy plaintext PIN — migrate to a salted hash on first correct entry.
      if (stored == pin) {
        await setPin(pin);
        return true;
      }
      return false;
    }
    return _hashPin(pin, salt) == stored;
  }

  /// Remaining lockout duration after too many failed attempts, or null if the
  /// user may attempt a PIN now.
  Future<Duration?> pinLockoutRemaining() async {
    final until = await _storage.read(key: kStoragePinLockUntil);
    if (until == null) return null;
    final ts = DateTime.tryParse(until);
    if (ts == null) return null;
    final remaining = ts.difference(DateTime.now());
    return remaining > Duration.zero ? remaining : null;
  }

  /// Records a failed PIN attempt. Returns the number of attempts remaining
  /// before lockout (0 means a lockout was just triggered).
  Future<int> recordPinFailure() async {
    final raw = await _storage.read(key: kStoragePinAttempts);
    final attempts = (int.tryParse(raw ?? '') ?? 0) + 1;
    if (attempts >= _maxPinAttempts) {
      await Future.wait([
        _storage.write(
          key: kStoragePinLockUntil,
          value: DateTime.now().add(_pinLockoutDuration).toIso8601String(),
        ),
        _storage.write(key: kStoragePinAttempts, value: '0'),
      ]);
      return 0;
    }
    await _storage.write(key: kStoragePinAttempts, value: '$attempts');
    return _maxPinAttempts - attempts;
  }

  Future<void> resetPinAttempts() async {
    await Future.wait([
      _storage.delete(key: kStoragePinAttempts),
      _storage.delete(key: kStoragePinLockUntil),
    ]);
  }

  // Logged in means we have credentials stored (OTP secret is not required).
  Future<bool> isLoggedIn() async {
    final results = await Future.wait([
      _storage.read(key: kStorageUser),
      _storage.read(key: kStoragePass),
    ]);
    return results[0] != null && results[1] != null;
  }

  // Logout: clear all stored data including optional OTP secret.
  Future<void> clear() async {
    await _storage.deleteAll();
    await WorkerSyncService.clear();
  }

  Future<bool> hasBiometrics() async {
    final biometrics = await _auth.getAvailableBiometrics();
    return biometrics.isNotEmpty;
  }

  // Returns success if biometrics pass, pinRequired when no biometrics are
  // enrolled (skip straight to PIN), or failure so the UI can offer retry.
  Future<AuthResult> authenticate() async {
    try {
      final biometrics = await _auth.getAvailableBiometrics();
      if (biometrics.isEmpty) {
        return await hasPin() ? AuthResult.pinRequired : AuthResult.failure;
      }

      // Bounded so a native lifecycle race (BiometricPrompt invoked while the
      // FragmentManager still reports a saved state right after resume, e.g.
      // "Called after onSaveInstanceState") can't strand the future — and the
      // caller — forever; it resolves to failure and the UI offers a retry.
      final success = await _auth
          .authenticate(
            localizedReason:
                'Veuillez vous authentifier pour accéder à vos notes',
            biometricOnly: true,
          )
          .timeout(const Duration(seconds: 30));

      if (success) return AuthResult.success;
      return AuthResult.failure;
    } catch (e) {
      return AuthResult.failure;
    }
  }
}
