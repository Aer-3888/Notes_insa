import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/foundation.dart';
import '../constants.dart';

class GradesService {
  static const MethodChannel _channel = MethodChannel(
    'com.aer.notes_insa/grades',
  );
  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  static const String _gradesKey = kStorageGradesJson;

  // ---------------------------------------------------------------------------
  // Auth step primitives
  // ---------------------------------------------------------------------------

  static Future<void> auth(String username, String password) async {
    await _channel.invokeMethod<void>('Auth', {
      'username': username,
      'password': password,
    });
  }

  static Future<bool> isTokenNeeded() async {
    final result = await _channel.invokeMethod<bool>('IsTokenNeeded');
    return result ?? false;
  }

  static Future<void> triggerEmail() async {
    await _channel.invokeMethod<void>('TriggerEmail');
  }

  static Future<void> validate(String code) async {
    await _channel.invokeMethod<void>('Validate', {'code': code});
  }

  static Future<void> autoValidate(String secret) async {
    await _channel.invokeMethod<void>('AutoValidate', {'secret': secret});
  }

  static Future<bool> isAuthenticated() async {
    final result = await _channel.invokeMethod<bool>('IsAuthenticated');
    return result ?? false;
  }

  static Future<int> loadGroups() async {
    final result = await _channel.invokeMethod<int>('LoadGroups');
    if (result == null) {
      throw PlatformException(
        code: 'ERR_LOADGROUPS',
        message: 'Null response from LoadGroups',
      );
    }
    return result;
  }

  static Future<String> grades(int id) async {
    final result = await _channel.invokeMethod<String>('Grades', {'id': id});
    if (result == null) {
      throw PlatformException(
        code: 'ERR_GRADES',
        message: 'Null response from Grades',
      );
    }
    return result;
  }

  static Future<void> newCAS() async {
    await _channel.invokeMethod<void>('NewCAS');
  }

  static Future<String> exportCAS() async {
    final result = await _channel.invokeMethod<String>('ExportCAS');
    if (result == null) {
      throw PlatformException(
        code: 'ERR_EXPORTCAS',
        message: 'Null response from ExportCAS',
      );
    }
    return result;
  }

  static Future<void> importCAS(String token) async {
    await _channel.invokeMethod<void>('ImportCAS', {'token': token});
  }

  // ---------------------------------------------------------------------------
  // High-level helper — call only after auth + 2FA are complete
  // ---------------------------------------------------------------------------

  /// Fetches grades for the user's primary group, saves to secure storage, and returns the JSON.
  static Future<String> fetchAndSaveGrades() async {
    final groupId = await loadGroups();
    final json = await grades(groupId);
    await saveGrades(json);
    return json;
  }

  // ---------------------------------------------------------------------------
  // Storage
  // ---------------------------------------------------------------------------

  static Future<void> saveGrades(String gradesJson) async {
    try {
      await _storage.write(key: _gradesKey, value: gradesJson);
    } catch (e) {
      if (kDebugMode) debugPrint('[GradesService] saveGrades failed: $e');
    }
  }

  static Future<String?> getLastSavedGrades() async {
    try {
      final stored = await _storage.read(key: _gradesKey);
      if (stored != null && stored.isNotEmpty) return stored;
    } catch (e) {
      if (kDebugMode)
        debugPrint('[GradesService] getLastSavedGrades failed: $e');
    }
    return null;
  }
}
