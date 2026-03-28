import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/foundation.dart';

class GradesService {
  static const MethodChannel _channel = MethodChannel(
    'com.aer.notes_insa/fetch_grades',
  );
  // FlutterSecureStorage uses custom ciphers by default for better security and background task compatibility
  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  static const String _gradesKey = 'stored_grades_json';

  /// Save grades to local storage
  static Future<void> saveGrades(String gradesJson) async {
    try {
      await _storage.write(key: _gradesKey, value: gradesJson);
    } catch (_) {
      // ignore write errors
    }
  }

  /// Calls the native Android AAR via MethodChannel.
  /// Expects the native side to return a JSON string containing grades with coefficients.
  /// On success this function returns the JSON string containing grades and saves locally.
  static Future<String> fetchGrades(
    String username,
    String password,
    String secret,
  ) async {
    try {
      final result = await _channel.invokeMethod<String>(
        'FetchGradesWithCoeffs',
        {'username': username, 'password': password, 'secret': secret},
      );

      if (result == null) {
        throw PlatformException(
          code: 'ERR_FETCH',
          message: 'Null response from native code',
        );
      }

      // Save to local storage for offline access
      await saveGrades(result);

      return result;
    } on PlatformException catch (_) {
      // Re-throw to let callers handle presentation logic
      rethrow;
    } catch (e) {
      throw PlatformException(code: 'ERR_FETCH', message: e.toString());
    }
  }

  /// Get last saved grades as the raw JSON string (no decode/re-encode waste).
  Future<String?> getLastSavedGrades() async {
    try {
      final storedJson = await _storage.read(key: _gradesKey);
      if (storedJson != null && storedJson.isNotEmpty) return storedJson;
    } catch (e) {
      if (kDebugMode) debugPrint('Error reading stored grades: $e');
    }
    return null;
  }
}
