import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/foundation.dart';
import '../constants.dart';
import 'worker_sync_service.dart';

class GradesService {
  static const MethodChannel _channel = MethodChannel(
    'com.aer.notes_insa/grades',
  );
  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  static const String _gradesKey = kStorageGradesJson;

  /// Native calls go through the CAS server; cap them so a hung native call
  /// can't strand the UI on a control-less splash (see AuthGate).
  static const Duration _nativeTimeout = Duration(seconds: 30);

  /// Wraps [MethodChannel.invokeMethod] with a timeout. Throws
  /// [TimeoutException] if the native side does not respond in time.
  static Future<T?> _invoke<T>(String method, [dynamic arguments]) {
    return _channel.invokeMethod<T>(method, arguments).timeout(_nativeTimeout);
  }

  // ---------------------------------------------------------------------------
  // Auth step primitives
  // ---------------------------------------------------------------------------

  static Future<void> auth(String username, String password) async {
    await _invoke<void>('Auth', {'username': username, 'password': password});
  }

  static Future<bool> isTokenNeeded() async {
    final result = await _invoke<bool>('IsTokenNeeded');
    return result ?? false;
  }

  static Future<void> triggerEmail() async {
    await _invoke<void>('TriggerEmail');
  }

  static Future<void> validate(String code) async {
    await _invoke<void>('Validate', {'code': code});
  }

  static Future<void> autoValidate(String secret) async {
    await _invoke<void>('AutoValidate', {'secret': secret});
  }

  static Future<bool> isAuthenticated() async {
    final result = await _invoke<bool>('IsAuthenticated');
    return result ?? false;
  }

  static Future<int> loadGroups() async {
    final result = await _invoke<int>('LoadGroups');
    if (result == null) {
      throw PlatformException(
        code: 'ERR_LOADGROUPS',
        message: 'Null response from LoadGroups',
      );
    }
    return result;
  }

  static Future<String> grades(int id) async {
    final result = await _invoke<String>('Grades', {'id': id});
    if (result == null) {
      throw PlatformException(
        code: 'ERR_GRADES',
        message: 'Null response from Grades',
      );
    }
    return result;
  }

  static Future<String> coefficients(int id) async {
    final result = await _invoke<String>('Coefficients', {'id': id});
    if (result == null) {
      throw PlatformException(
        code: 'ERR_COEFFICIENTS',
        message: 'Null response from Coefficients',
      );
    }
    return result;
  }

  static Future<void> newCAS() async {
    await _invoke<void>('NewCAS');
  }

  static Future<String> exportCAS() async {
    final result = await _invoke<String>('ExportCAS');
    if (result == null) {
      throw PlatformException(
        code: 'ERR_EXPORTCAS',
        message: 'Null response from ExportCAS',
      );
    }
    return result;
  }

  static Future<void> importCAS(String token) async {
    await _invoke<void>('ImportCAS', {'token': token});
  }

  // ---------------------------------------------------------------------------
  // High-level helper — call only after auth + 2FA are complete
  // ---------------------------------------------------------------------------

  /// Fetches grades for all groups, merges their details into a single JSON
  /// payload, saves to secure storage, and returns the merged JSON string.
  ///
  /// loadGroups() returns the number of available groups (cards);
  /// grades() takes a 0-based index. When there are multiple groups we
  /// merge all `details` arrays under the first group's top-level object
  /// so the parser sees every semester regardless of which card it belongs to.
  static Future<String> fetchAndSaveGrades() async {
    final groupCount = await loadGroups();
    if (groupCount <= 0) {
      throw PlatformException(
        code: 'ERR_NO_GROUPS',
        message: 'No groups available',
      );
    }

    if (groupCount == 1) {
      final json = await grades(0);
      await saveGrades(json);
      return json;
    }

    final firstJson = await grades(0);
    final merged = jsonDecode(firstJson) as Map<String, dynamic>;
    final seenNames = <String>{};
    final mergedDetails = <dynamic>[];

    void addDetails(List<dynamic> items) {
      for (final item in items) {
        if (item is Map<String, dynamic>) {
          final name = item['name'] as String?;
          if (name != null && !seenNames.add(name)) continue;
        }
        mergedDetails.add(item);
      }
    }

    if (merged['details'] is List) {
      addDetails(merged['details'] as List<dynamic>);
    }

    for (int i = 1; i < groupCount; i++) {
      final extraJson = await grades(i);
      final extra = jsonDecode(extraJson) as Map<String, dynamic>;
      if (extra['details'] is List) {
        addDetails(extra['details'] as List<dynamic>);
      }
    }

    merged['details'] = mergedDetails;
    final result = jsonEncode(merged);
    await saveGrades(result);
    return result;
  }

  // ---------------------------------------------------------------------------
  // Storage
  // ---------------------------------------------------------------------------

  static Future<void> saveGrades(String gradesJson) async {
    try {
      await _storage.write(key: _gradesKey, value: gradesJson);
      // Keep the worker's snapshot in sync so background diffs use fresh data.
      await WorkerSyncService.sync({
        WorkerSyncService.keyGradesJson: gradesJson,
      });
    } catch (e) {
      if (kDebugMode) debugPrint('[GradesService] saveGrades failed: $e');
    }
  }

  static Future<String?> getLastSavedGrades() async {
    try {
      final stored = await _storage.read(key: _gradesKey);
      if (stored != null && stored.isNotEmpty) return stored;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[GradesService] getLastSavedGrades failed: $e');
      }
    }
    return null;
  }
}
