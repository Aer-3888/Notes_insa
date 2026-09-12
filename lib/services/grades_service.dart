import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'cas/cas_client.dart';
import 'cas/http_session.dart';
import 'mdw/grade.dart';
import 'mdw/grade_merge.dart';
import 'mdw/grade_parser.dart';
import 'mdw/mdw_client.dart';
import 'mdw/vaadin_nodes.dart';
import 'mdw/vaadin_types.dart';
import 'secure_storage.dart';
import '../constants.dart';
import 'worker_sync_service.dart';

class GradesService {
  static const _storage = kSecureStorage;
  static const String _gradesKey = kStorageGradesJson;

  // ---------------------------------------------------------------------------
  // CAS: pure Dart. MDW below still runs in the native bridge.
  // ---------------------------------------------------------------------------

  static CasClient? _cas;

  static CasClient get _requireCas {
    final cas = _cas;
    if (cas == null) {
      throw PlatformException(
        code: 'ERR_NoCAS',
        message: 'CAS session is not initialized',
      );
    }
    return cas;
  }

  /// Preserves the PlatformException contract the screens already catch.
  static Future<T> _casCall<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on CasException catch (e) {
      throw PlatformException(code: e.code, message: e.message);
    }
  }

  /// Drops both halves of the session. The native side keeps its own cookies
  /// until told otherwise, so logout has to reach it too.
  static CasClient _newCasClient() => CasClient(
    logger: kDebugMode ? (String m) => debugPrint('[CAS] $m') : null,
  );

  static Future<void> newCAS() async {
    if (kDebugMode) debugPrint('[CAS] newCAS (had session: ${_cas != null})');
    _cas?.close();
    _cas = _newCasClient();
  }

  static Future<void> auth(String username, String password) =>
      _casCall(() => _requireCas.auth(username, password));

  static Future<bool> isTokenNeeded() async => _cas?.isTokenNeeded ?? false;

  static Future<void> triggerEmail() =>
      _casCall(() => _requireCas.triggerEmail());

  static Future<void> validate(String code) =>
      _casCall(() => _requireCas.validate(code));

  static Future<void> autoValidate(String secret) =>
      _casCall(() => _requireCas.autoValidate(secret));

  static Future<bool> isAuthenticated() async {
    if (_cas == null) return false;
    return _casCall(() => _requireCas.isAuthenticated());
  }

  static Future<String> exportCAS() async => _requireCas.exportSession();

  static Future<void> importCAS(String token) async {
    if (kDebugMode) debugPrint('[CAS] importCAS');
    final cas = _newCasClient();
    try {
      cas.importSession(token);
    } on FormatException catch (e) {
      cas.close();
      throw PlatformException(code: 'ERR_ImportCAS', message: e.message);
    }
    _cas?.close();
    _cas = cas;
  }

  // ---------------------------------------------------------------------------
  // MDW: pure Dart over the Vaadin UIDL protocol
  // ---------------------------------------------------------------------------

  static MdwClient? _mdw;

  /// Test seams for the MDW half, which otherwise needs a live Vaadin session.
  @visibleForTesting
  static Future<int> Function()? loadGroupsOverride;
  @visibleForTesting
  static Future<String> Function(int id)? gradesOverride;

  static MdwClient get _requireMdw {
    final mdw = _mdw;
    if (mdw == null) {
      throw PlatformException(
        code: 'ERR_NoMDW',
        message: 'grade groups are not loaded',
      );
    }
    return mdw;
  }

  /// Maps MDW transport failures onto the codes the screens already handle.
  static Future<T> _mdwCall<T>(String code, Future<T> Function() body) async {
    try {
      return await body();
    } on VaadinException catch (e) {
      throw PlatformException(code: code, message: e.message);
    } on HttpSessionException catch (e) {
      throw PlatformException(code: code, message: e.message);
    }
  }

  /// Opens an MDW session on the CAS cookies and counts the grade cards.
  static Future<int> loadGroups() async {
    final override = loadGroupsOverride;
    if (override != null) return override();

    final cas = _requireCas;

    return _mdwCall('ERR_LOADGROUPS', () async {
      await _mdw?.dispose();
      _mdw = null;

      final mdw = MdwClient(cas.session);
      await mdw.init();
      final count = await mdw.loadGroups();
      _mdw = mdw;
      return count;
    });
  }

  static Future<String> grades(int id) async {
    final override = gradesOverride;
    if (override != null) return override(id);

    final mdw = _requireMdw;

    return _mdwCall('ERR_GRADES', () async {
      final merged = await mdw.openAllRows(id);
      final root = GradeParser.parse(merged);
      await mdw.closeGrades();

      if (kDebugMode) {
        var nodes = 0;
        root?.forEach((_, _) => nodes++);
        final rows = GradeParser.rowsOf(merged);
        final size = merged.gridSize;
        final unfetched = GradeParser.missingChildKeys(rows);
        debugPrint(
          '[GradesService] group $id: ${merged.changes.length} changes, '
          '${merged.execute.length} calls, $nodes grades '
          'of ${size ?? '?'} rows'
          '${size != null && rows.length < size ? ' SHORT' : ''}'
          '${unfetched.isEmpty ? '' : ', ${unfetched.length} parent(s) '
                    'still claiming rows'}',
        );
      }

      if (root == null) {
        throw VaadinException(
          'no grade rows in the response (${merged.describe()})',
        );
      }

      return jsonEncode(root.toJson());
    });
  }

  /// Reads every row's coefficient from its details dialog.
  ///
  /// MDW only exposes one coefficient at a time, so this opens and closes a
  /// dialog per row and is much slower than a grade fetch.
  static Future<String> coefficients(int id) async {
    final mdw = _requireMdw;

    return _mdwCall('ERR_COEFFICIENTS', () async {
      final data = await mdw.openAllRows(id);
      final root = GradeParser.parse(data);
      if (root == null) {
        await mdw.closeGrades();
        throw VaadinException('no grade rows to read coefficients from');
      }

      final targets = <Grade>[];
      root.forEach((_, Grade grade) {
        if (grade.key.isNotEmpty) targets.add(grade);
      });

      var filled = 0;
      for (final Grade grade in targets) {
        final opened = await mdw.openCoefficient(grade.key);
        if (opened.coefficient != null) {
          grade.coeff = opened.coefficient;
          filled++;
        }
        await mdw.closeCoefficient(opened.node);
      }

      await mdw.closeGrades();

      if (kDebugMode) {
        debugPrint(
          '[GradesService] group $id: $filled/${targets.length} coefficients',
        );
      }

      return jsonEncode(root.toJson());
    });
  }

  // ---------------------------------------------------------------------------
  // High-level helper , call only after auth + 2FA are complete
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

    // A card can hold no results at all (a second cursus not yet graded), and
    // MDW then answers with the page chrome and no rows. That must not lose the
    // cards that did return grades.
    Map<String, dynamic>? merged;
    final mergedDetails = <dynamic>[];
    final failures = <String>[];

    for (var i = 0; i < groupCount; i++) {
      final Map<String, dynamic> group;
      try {
        group = jsonDecode(await grades(i)) as Map<String, dynamic>;
      } on PlatformException catch (e) {
        if (kDebugMode) debugPrint('[GradesService] group $i skipped: $e');
        failures.add('$i');
        continue;
      }

      merged ??= group;
      if (group['details'] is List) {
        mergeGradeDetails(mergedDetails, group['details'] as List<dynamic>);
      }
    }

    if (merged == null) {
      throw PlatformException(
        code: 'ERR_GRADES',
        message: 'no grades in any of the $groupCount card(s)',
      );
    }

    if (kDebugMode && failures.isNotEmpty) {
      debugPrint('[GradesService] empty card(s): ${failures.join(', ')}');
    }

    merged['details'] = mergedDetails;
    final result = jsonEncode(merged);
    await saveGrades(result);
    return (json: result, groupCount: groupCount);
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
  /// copy. Does not mirror back to the worker store , the value already lives
  /// there , and preserves the worker's timestamp so freshness stays accurate.
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
