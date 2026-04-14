import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import '../constants.dart';

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

  Future<void> storeOtpSecret(String secret) =>
      _storage.write(key: kStorageOtpSecret, value: secret);

  Future<void> deleteOtpSecret() => _storage.delete(key: kStorageOtpSecret);

  // CAS session token — saved after auth to allow silent session restore on next launch.
  Future<String?> getCasSession() => _storage.read(key: kStorageCasSession);

  Future<void> storeCasSession(String token) =>
      _storage.write(key: kStorageCasSession, value: token);

  Future<void> deleteCasSession() => _storage.delete(key: kStorageCasSession);

  // PIN methods
  Future<void> setPin(String pin) =>
      _storage.write(key: kStoragePin, value: pin);

  Future<bool> hasPin() async {
    final pin = await _storage.read(key: kStoragePin);
    return pin != null && pin.isNotEmpty;
  }

  Future<bool> verifyPin(String pin) async {
    final storedPin = await _storage.read(key: kStoragePin);
    return storedPin == pin;
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
  }

  // Returns success if biometrics pass, pinRequired if a fallback is needed, or failure if unauthorized.
  Future<AuthResult> authenticate() async {
    try {
      final bool isDeviceSupported = await _auth.isDeviceSupported();
      if (!isDeviceSupported) {
        return await hasPin() ? AuthResult.pinRequired : AuthResult.failure;
      }

      final success = await _auth.authenticate(
        localizedReason: 'Veuillez vous authentifier pour accéder à vos notes',
      );

      if (success) return AuthResult.success;

      // If biometric failed (e.g. user canceled), check if we can fall back to PIN
      if (await hasPin()) return AuthResult.pinRequired;

      return AuthResult.failure;
    } catch (e) {
      if (await hasPin()) return AuthResult.pinRequired;
      return AuthResult.failure;
    }
  }
}
