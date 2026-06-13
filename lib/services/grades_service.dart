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
  /// payload, saves to secure storage, and returns the merged JSON string
  /// along with the group count (so callers needing it, e.g. the
  /// coefficients API tier, don't have to call loadGroups() again).
  ///
  /// loadGroups() returns the number of available groups (cards);
  /// grades() takes a 0-based index. When there are multiple groups we
  /// merge all `details` arrays under the first group's top-level object
  /// so the parser sees every semester regardless of which card it belongs to.
  static Future<({String json, int groupCount})> fetchAndSaveGrades() async {
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
      return (json: json, groupCount: groupCount);
    }

    final firstJson = await grades(0);
    final merged = jsonDecode(firstJson) as Map<String, dynamic>;
    final mergedDetails = <dynamic>[];

    if (merged['details'] is List) {
      _mergeDetails(mergedDetails, merged['details'] as List<dynamic>);
    }

    for (int i = 1; i < groupCount; i++) {
      final extraJson = await grades(i);
      final extra = jsonDecode(extraJson) as Map<String, dynamic>;
      if (extra['details'] is List) {
        _mergeDetails(mergedDetails, extra['details'] as List<dynamic>);
      }
    }

    merged['details'] = mergedDetails;
    final result = jsonEncode(merged);
    await saveGrades(result);
    return (json: result, groupCount: groupCount);
  }

  /// Merge [incoming] nodes into [target], deduplicating by name. When a node
  /// with the same name already exists and both carry child `details` lists
  /// (e.g. two "ANNEE 3" wrappers from different cards holding different
  /// semesters), their children are merged recursively instead of dropping the
  /// second wrapper wholesale — otherwise distinct semesters would be lost.
  static void _mergeDetails(List<dynamic> target, List<dynamic> incoming) {
    for (final item in incoming) {
      if (item is! Map<String, dynamic>) {
        target.add(item);
        continue;
      }
      final name = item['name'] as String?;
      if (name == null) {
        target.add(item);
        continue;
      }

      final existing = target.firstWhere(
        (e) => e is Map<String, dynamic> && e['name'] == name,
        orElse: () => null,
      );

      if (existing == null) {
        target.add(item);
        continue;
      }

      // Same name: if both are containers, merge their children; otherwise the
      // node is a true duplicate (same leaf) and is skipped.
      if (existing is Map<String, dynamic> &&
          existing['details'] is List &&
          item['details'] is List) {
        _mergeDetails(
          existing['details'] as List<dynamic>,
          item['details'] as List<dynamic>,
        );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Storage
  // ---------------------------------------------------------------------------

  static Future<void> saveGrades(String gradesJson) async {
    try {
      final stamp = DateTime.now().millisecondsSinceEpoch.toString();
      // Write the canonical store first, then mirror to the worker store. The
      // mirror is best-effort (already swallowed below); a mirror failure
      // leaves the worker copy stale but the worker re-syncs on its next run.
      await _storage.write(key: _gradesKey, value: gradesJson);
      await _storage.write(key: kStorageGradesUpdatedAt, value: stamp);
      await WorkerSyncService.sync({
        WorkerSyncService.keyGradesJson: gradesJson,
        WorkerSyncService.keyGradesUpdatedAt: stamp,
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

  /// Epoch-ms timestamp of the last local grades write, or null if unknown.
  static Future<int?> getLastSavedUpdatedAt() async {
    try {
      final raw = await _storage.read(key: kStorageGradesUpdatedAt);
      return raw == null ? null : int.tryParse(raw);
    } catch (_) {
      return null;
    }
  }

  /// Adopt a snapshot the background worker produced as the canonical local
  /// copy. Does not mirror back to the worker store — the value already lives
  /// there — and preserves the worker's timestamp so freshness stays accurate.
  static Future<void> adoptGrades(String gradesJson, int updatedAt) async {
    try {
      await _storage.write(key: _gradesKey, value: gradesJson);
      await _storage.write(
        key: kStorageGradesUpdatedAt,
        value: updatedAt.toString(),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[GradesService] adoptGrades failed: $e');
    }
  }
}
