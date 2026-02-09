import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

class AuthService {
  final _storage = const FlutterSecureStorage();
  final _auth = LocalAuthentication();

  // Keys for our secure storage
  static const _kToken = 'api_token';
  static const _kUser = 'username';
  static const _kPass = 'password';

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
        // Fallback: If phone has no FaceID hardware, we let them in
        return true;
      }

      // Show the Prompt
      return await _auth.authenticate(
        localizedReason: 'Veuillez vous authentifier pour accéder à vos notes',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );
    } catch (e) {
      throw ("Biometric Error: $e");
    }
  }
}
