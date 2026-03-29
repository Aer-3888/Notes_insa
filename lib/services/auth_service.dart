import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import '../constants.dart';

class AuthService {
  // Safe for background tasks
  static const _storage = FlutterSecureStorage();
  final _auth = LocalAuthentication();

  Future<void> storeCredentials(
    String username,
    String password, {
    String? token,
  }) async {
    await _storage.write(key: kStorageUser, value: username);
    await _storage.write(key: kStoragePass, value: password);
    if (token != null) {
      await _storage.write(key: kStorageToken, value: token);
    }
  }

  Future<Map<String, String>?> getCredentials() async {
    final results = await Future.wait([
      _storage.read(key: kStorageToken),
      _storage.read(key: kStorageUser),
      _storage.read(key: kStoragePass),
    ]);
    final token = results[0];
    final username = results[1];
    final password = results[2];
    if (token == null || username == null || password == null) return null;
    return {
      kStorageToken: token,
      kStorageUser: username,
      kStoragePass: password,
    };
  }

  // Login checker
  Future<bool> isLoggedIn() async {
    final token = await _storage.read(key: kStorageToken);
    return token != null;
  }

  // Logout: Clear all stored credentials
  Future<void> clear() async {
    await _storage.deleteAll();
  }

  // Returns true if Biometrics passes OR if the device has no Biometrics (Fail-open)
  Future<bool> authenticate() async {
    try {
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
