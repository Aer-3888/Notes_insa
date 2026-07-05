import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:local_auth/local_auth.dart';
import 'secure_storage.dart';
import '../constants.dart';
import '../utils/pbkdf2.dart';
import 'worker_sync_service.dart';

enum AuthResult { success, failure, pinRequired }

class AuthService {
  // Safe for background tasks
  static const _storage = kSecureStorage;
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
  // throttled by an attempt counter + an escalating lockout (see
  // pinLockoutRemaining / recordPinFailure).
  static const int _maxPinAttempts = 5;
  static const int minPinLength = 6;

  // Escalating lockout durations, picked by the cumulative lockout count so the
  // throttle gets harsher the more it's triggered (unlike a fixed window that
  // resets each time). Caps at the last entry.
  static const List<Duration> _lockoutLadder = [
    Duration(minutes: 1),
    Duration(minutes: 5),
    Duration(minutes: 30),
    Duration(hours: 1),
  ];

  // PIN verifier hashing. New PINs use PBKDF2-HMAC-SHA256 with a per-PIN salt,
  // stored as "pbkdf2$<iterations>$<base64url digest>" so the scheme and cost
  // are self-describing and can be raised later with lazy re-hashing. A slow
  // hash keeps a low-entropy PIN from being trivially brute-forced if the
  // encrypted store is ever extracted. Older installs may still hold a bare
  // SHA-256 hex digest or, older still, a plaintext PIN, both upgraded on the
  // next correct entry.
  static const int _pbkdf2Iterations = 120000;
  static const int _pbkdf2DkLen = 32;
  static const String _pbkdf2Prefix = 'pbkdf2';

  String _generateSalt() {
    final rng = Random.secure();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    return base64Url.encode(bytes);
  }

  String _pbkdf2Hash(String pin, String salt) {
    final dk = pbkdf2Sha256(
      utf8.encode(pin),
      utf8.encode(salt),
      _pbkdf2Iterations,
      _pbkdf2DkLen,
    );
    return '$_pbkdf2Prefix\$$_pbkdf2Iterations\$${base64Url.encode(dk)}';
  }

  bool _verifyPbkdf2(String pin, String salt, String stored) {
    final parts = stored.split('\$');
    if (parts.length != 3) return false;
    final iterations = int.tryParse(parts[1]);
    if (iterations == null || iterations <= 0) return false;
    final dk = pbkdf2Sha256(
      utf8.encode(pin),
      utf8.encode(salt),
      iterations,
      _pbkdf2DkLen,
    );
    return base64Url.encode(dk) == parts[2];
  }

  // Legacy salted SHA-256 verifier, kept only to check and then upgrade old
  // PINs to PBKDF2 on the next correct entry.
  String _legacySha256Hash(String pin, String salt) =>
      sha256.convert(utf8.encode('$salt:$pin')).toString();

  Future<void> setPin(String pin) async {
    final salt = _generateSalt();
    await Future.wait([
      _storage.write(key: kStoragePinSalt, value: salt),
      _storage.write(key: kStoragePin, value: _pbkdf2Hash(pin, salt)),
      _storage.write(key: kStoragePinLength, value: '${pin.length}'),
    ]);
    await resetPinAttempts();
  }

  /// True when a PIN is set but is shorter than [minPinLength] (or its length
  /// was never recorded — i.e. configured before the 6-digit requirement), so
  /// the user should be prompted to set a stronger one.
  Future<bool> pinNeedsUpgrade() async {
    if (!await hasPin()) return false;
    final raw = await _storage.read(key: kStoragePinLength);
    final len = int.tryParse(raw ?? '');
    return len == null || len < minPinLength;
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
      // Legacy plaintext PIN (pre-hashing). Upgrade on first correct entry.
      if (stored == pin) {
        await setPin(pin);
        return true;
      }
      return false;
    }
    if (stored.startsWith('$_pbkdf2Prefix\$')) {
      return _verifyPbkdf2(pin, salt, stored);
    }
    // Legacy salted SHA-256 verifier. Verify, then lazily re-hash with PBKDF2.
    if (_legacySha256Hash(pin, salt) == stored) {
      await setPin(pin);
      return true;
    }
    return false;
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
      // Cumulative lockout count grows across lockouts (only a success clears
      // it), so each lockout is longer than the last.
      final countRaw = await _storage.read(key: kStoragePinLockoutCount);
      final lockoutsSoFar = int.tryParse(countRaw ?? '') ?? 0;
      final duration =
          _lockoutLadder[lockoutsSoFar.clamp(0, _lockoutLadder.length - 1)];
      await Future.wait([
        _storage.write(
          key: kStoragePinLockUntil,
          value: DateTime.now().add(duration).toIso8601String(),
        ),
        // Reset the per-window counter so the next window starts fresh, but
        // keep escalating via the cumulative count.
        _storage.write(key: kStoragePinAttempts, value: '0'),
        _storage.write(
          key: kStoragePinLockoutCount,
          value: '${lockoutsSoFar + 1}',
        ),
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
      _storage.delete(key: kStoragePinLockoutCount),
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
  // enrolled or the prompt cannot run (skip straight to PIN), or failure on a
  // failed scan so the UI can offer a retry.
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
    } on LocalAuthException catch (e) {
      // Fall back to PIN when the biometric prompt cannot currently succeed
      // (locked out, unavailable, not enrolled, no UI, or the user asked for a
      // fallback) as opposed to a plain cancel/timeout, which stays a failure so
      // the UI offers a biometric retry. New enum values are not exhaustive, so
      // anything unmapped is treated as a retryable failure.
      const pinFallbackCodes = {
        LocalAuthExceptionCode.uiUnavailable,
        LocalAuthExceptionCode.noCredentialsSet,
        LocalAuthExceptionCode.noBiometricsEnrolled,
        LocalAuthExceptionCode.noBiometricHardware,
        LocalAuthExceptionCode.biometricHardwareTemporarilyUnavailable,
        LocalAuthExceptionCode.temporaryLockout,
        LocalAuthExceptionCode.biometricLockout,
        LocalAuthExceptionCode.userRequestedFallback,
      };
      if (pinFallbackCodes.contains(e.code)) {
        return await hasPin() ? AuthResult.pinRequired : AuthResult.failure;
      }
      return AuthResult.failure;
    } catch (e) {
      // Timeout (from .timeout) or any other unexpected error: offer a retry.
      return AuthResult.failure;
    }
  }
}
