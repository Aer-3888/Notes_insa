import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../data.dart';

class GradesService {
  static const MethodChannel _channel = MethodChannel(
    'com.aer.notes_insa/fetch_grades',
  );
  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  static const String _gradesKey = 'stored_grades_json';

  /// Load grades from local storage
  static Future<bool> loadStoredGrades() async {
    try {
      final storedJson = await _storage.read(key: _gradesKey);
      if (storedJson != null && storedJson.isNotEmpty) {
        jsonString = storedJson;
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /// Save grades to local storage
  static Future<void> saveGrades(String gradesJson) async {
    try {
      await _storage.write(key: _gradesKey, value: gradesJson);
    } catch (_) {
      // ignore write errors
    }
  }

  /// Calls the native Android AAR via MethodChannel.
  /// Expects the native side to return a JSON string containing grades.
  /// On success this function updates `lib/data.dart`'s top-level `jsonString` and saves locally.
  static Future<String> fetchGrades(
    String username,
    String password,
    String secret,
  ) async {
    // Log parameters (hide password for security) - intentionally not logging in production

    try {
      final result = await _channel.invokeMethod<String>('FetchGrades', {
        'username': username,
        'password': password,
        'secret': secret,
      });

      if (result == null) {
        throw PlatformException(
          code: 'ERR_FETCH',
          message: 'Null response from native code',
        );
      }

      // Overwrite the in-memory data JSON so UI can read it
      jsonString = result;

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
}
