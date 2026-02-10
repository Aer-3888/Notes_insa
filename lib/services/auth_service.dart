import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:flutter/services.dart';
import 'grades_service.dart';

class AuthService {
  final _storage = const FlutterSecureStorage();
  final _auth = LocalAuthentication();

  // Keys for our secure storage
  static const _kToken = 'api_token';
  static const _kUser = 'username';
  static const _kPass = 'password';

  /// Convenience: use stored credentials to fetch grades via native AAR.
  /// If [secret] is not provided, the method expects a secret already stored or passed externally.
  Future<String> fetchAndStoreGrades({String? secret}) async {
    final user = await _storage.read(key: _kUser);
    final pass = await _storage.read(key: _kPass);

    if (user == null || pass == null) {
      throw PlatformException(
        code: 'ERR_NO_CREDS',
        message: 'No stored credentials',
      );
    }

    try {
      final json = await GradesService.fetchGrades(user, pass, secret ?? '');
      return json;
    } on PlatformException {
      rethrow;
    }
  }

  // Save Credentials
  Future<void> saveCredentials({
    required String token,
    required String username,
    required String password,
  }) async {
    await _storage.write(key: _kToken, value: token);
    await _storage.write(key: _kUser, value: username);
    await _storage.write(key: _kPass, value: password);
  }

  // Credentials Getter
  Future<Map<String, String>?> getCredentials() async {
    final token = await _storage.read(key: _kToken);
    final user = await _storage.read(key: _kUser);
    final pass = await _storage.read(key: _kPass);

    if (token != null && user != null && pass != null) {
      return {'token': token, 'username': user, 'password': pass};
    }
    return null;
  }

  // Login checker
  Future<bool> isLoggedIn() async {
    final token = await _storage.read(key: _kToken);
    return token != null;
  }

  // Logout: Clear all stored credentials
  Future<void> clear() async {
    await _storage.deleteAll();
  }

  // Returns true if Biometrics passes OR if the device has no Biometrics (Fail-open)
  Future<bool> authenticate() async {
    try {
      // Check if hardware supports it
      final bool canCheckBiometrics = await _auth.canCheckBiometrics;
      final bool isDeviceSupported = await _auth.isDeviceSupported();

      if (!canCheckBiometrics || !isDeviceSupported) {
        // Fallback: If phone has no biometric hardware, allow access in non-production
        return true;
      }

      // Show the Prompt
      final result = await _auth.authenticate(
        localizedReason: 'Veuillez vous authentifier pour accéder à vos notes',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false, // Allow PIN/pattern as fallback
        ),
      );

      return result;
    } catch (e) {
      // Return false instead of throwing to allow retry
      return false;
    }
  }
}
