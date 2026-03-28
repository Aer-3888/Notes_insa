import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:flutter/services.dart';
import 'grades_service.dart';

class AuthService {
  // Safe for background tasks
  static const _storage = FlutterSecureStorage();
  final _auth = LocalAuthentication();

  static const _kToken = 'api_token';
  static const _kUser = 'username';
  static const _kPass = 'password';

  // Provide access to storage for background tasks
  static const FlutterSecureStorage storage = _storage;

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

  Future<void> storeCredentials(
    String username,
    String password, {
    String? token,
  }) async {
    await _storage.write(key: _kUser, value: username);
    await _storage.write(key: _kPass, value: password);
    if (token != null) {
      await _storage.write(key: _kToken, value: token);
    }
  }

  // Get stored credentials (returns Map for compatibility with background tasks)
  Future<Map<String, String?>> getStoredCredentials() async {
    final results = await Future.wait([
      _storage.read(key: _kToken),
      _storage.read(key: _kUser),
      _storage.read(key: _kPass),
    ]);
    return {
      'token': results[0],
      'username': results[1],
      'password': results[2],
    };
  }

  // Legacy method for existing code compatibility
  Future<Map<String, String>?> getCredentials() async {
    final credentials = await getStoredCredentials();

    if (credentials['token'] != null &&
        credentials['username'] != null &&
        credentials['password'] != null) {
      return {
        'token': credentials['token']!,
        'username': credentials['username']!,
        'password': credentials['password']!,
      };
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

  // Clear stored credentials (alias for compatibility)
  Future<void> clearStoredCredentials() async {
    await clear();
  }

  // Returns true if Biometrics passes OR if the device has no Biometrics (Fail-open)
  Future<bool> authenticate() async {
    try {
      // Check both in parallel — they're independent hardware queries
      final bool isDeviceSupported = await _auth.isDeviceSupported();

      if (!isDeviceSupported) {
        // No biometric hardware at all — allow access
        return true;
      }

      // Show the Prompt
      final result = await _auth.authenticate(
        localizedReason: 'Veuillez vous authentifier pour accéder à vos notes',
      );

      return result;
    } catch (e) {
      // Return false instead of throwing to allow retry
      return false;
    }
  }
}
