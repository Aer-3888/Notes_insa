import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import '../constants.dart';
import '../data.dart';
import '../models.dart';
import 'averages_service.dart';
import 'grades_service.dart';

/// Coefficient for a single subject, keyed by UE + subject name.
typedef CoeffKey = ({String ue, String subject});

/// 3-tier coefficient fetching:
///   1. Local cache (FlutterSecureStorage)
///   2. Cloudflare D1 community database
///   3. Mobinsapi Coefficients() API (last resort)
///
/// Only tier 3 (API) results are pushed to Cloudflare and cached locally.
/// Tier 2 results are cached locally but never re-pushed.
/// A fallback to 1.0 is never stored anywhere.
class CoefficientsService {
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  /// Local coefficient cache lifetime before a re-fetch is forced.
  static const Duration _cacheTtl = Duration(days: 7);

  static String _cacheKey(
    String department,
    int semester,
    String academicYear,
  ) {
    return '$kStorageCoefficientsPrefix${department}_${semester}_$academicYear';
  }

  /// Fetch coefficients for a department+semester+academicYear.
  /// Returns a map of cleaned "ue|subject" → coefficient value.
  /// Only checks local cache and Cloudflare — the API tier is called
  /// separately via [fetchAndCacheFromApi] right after grades are fetched.
  static Future<Map<String, double>> fetch({
    required String department,
    required int semester,
    required String academicYear,
  }) async {
    // Tier 1: local cache
    final local = await _readLocalCache(department, semester, academicYear);
    if (local != null && local.isNotEmpty) {
      if (kDebugMode) {
        debugPrint(
          '[Coefficients] Tier 1 hit (local): ${local.length} entries',
        );
      }
      return local;
    }

    // Tier 2: Cloudflare
    final remote = await _fetchFromCloudflare(
      department,
      semester,
      academicYear,
    );
    if (remote != null && remote.isNotEmpty) {
      if (kDebugMode) {
        debugPrint(
          '[Coefficients] Tier 2 hit (Cloudflare): ${remote.length} entries',
        );
      }
      unawaited(_writeLocalCache(department, semester, academicYear, remote));
      return remote;
    }

    if (kDebugMode) debugPrint('[Coefficients] Tiers 1-2 missed');
    return {};
  }

  /// Call right after fetchAndSaveGrades() while the Vaadin session is alive.
  /// Fetches coefficients from the Mobinsapi API, caches all semesters
  /// locally, and pushes to Cloudflare.
  static Future<void> fetchAndCacheFromApi(String gradesJson) async {
    try {
      final api = await _fetchFromApi();
      if (api == null || api.isEmpty) return;

      final availableSems =
          api.keys.map((k) => int.tryParse(k)).whereType<int>().toList()
            ..sort();
      if (availableSems.isEmpty) return;
      final maxSem = availableSems.last;

      for (final entry in api.entries) {
        final semNum = int.tryParse(entry.key);
        if (semNum == null || entry.value.isEmpty) continue;

        final department = JsonCurriculumParser.getDepartmentForSemester(
          gradesJson,
          semNum,
        );
        final academicYear = AveragesService.academicYearForSemester(
          semNum,
          maxSem,
        );

        if (kDebugMode) {
          debugPrint(
            '[Coefficients] Caching semester $semNum ($department / $academicYear): '
            '${entry.value.length} subjects',
          );
        }

        await _writeLocalCache(department, semNum, academicYear, entry.value);
        unawaited(
          _pushToCloudflare(department, semNum, academicYear, entry.value),
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[Coefficients] fetchAndCacheFromApi failed: $e');
      }
    }
  }

  // ── Tier 1: Local cache ──────────────────────────────────────────────────

  static Future<Map<String, double>?> _readLocalCache(
    String department,
    int semester,
    String academicYear,
  ) async {
    try {
      final raw = await _storage.read(
        key: _cacheKey(department, semester, academicYear),
      );
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;

      // New format: {"ts": epochMillis, "coeffs": {...}} with a TTL.
      if (decoded['coeffs'] is Map) {
        final ts = (decoded['ts'] as num?)?.toInt() ?? 0;
        final age = DateTime.now().difference(
          DateTime.fromMillisecondsSinceEpoch(ts),
        );
        if (age > _cacheTtl) {
          if (kDebugMode) debugPrint('[Coefficients] Local cache expired');
          return null;
        }
        final coeffs = decoded['coeffs'] as Map<String, dynamic>;
        return coeffs.map((k, v) => MapEntry(k, (v as num).toDouble()));
      }

      // Legacy format: a bare {key: value} map (no timestamp) — accept once;
      // it gets upgraded to the timestamped format on the next API cache write.
      return decoded.map((k, v) => MapEntry(k, (v as num).toDouble()));
    } catch (e) {
      if (kDebugMode) debugPrint('[Coefficients] Local cache read failed: $e');
      return null;
    }
  }

  static Future<void> _writeLocalCache(
    String department,
    int semester,
    String academicYear,
    Map<String, double> coefficients,
  ) async {
    try {
      await _storage.write(
        key: _cacheKey(department, semester, academicYear),
        value: jsonEncode({
          'ts': DateTime.now().millisecondsSinceEpoch,
          'coeffs': coefficients,
        }),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[Coefficients] Local cache write failed: $e');
    }
  }

  // ── Tier 2: Cloudflare ───────────────────────────────────────────────────

  static Future<Map<String, double>?> _fetchFromCloudflare(
    String department,
    int semester,
    String academicYear,
  ) async {
    try {
      final uri = Uri.parse('$kWorkerBaseUrl/coefficients').replace(
        queryParameters: {
          'department': department,
          'semester': semester.toString(),
          'academic_year': academicYear,
        },
      );

      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;

      final List<dynamic> data = jsonDecode(response.body) as List<dynamic>;
      if (data.isEmpty) return null;

      final result = <String, double>{};
      for (final row in data) {
        if (row is! Map<String, dynamic>) continue;
        final ue = (row['ue_name'] as String?)?.cleanName();
        final name = (row['subject_name'] as String?)?.cleanName();
        final coeff = (row['coefficient'] as num?)?.toDouble();
        if (ue != null &&
            ue.isNotEmpty &&
            name != null &&
            name.isNotEmpty &&
            coeff != null &&
            coeff > 0) {
          result['$ue|$name'] = coeff;
        }
      }
      return result.isEmpty ? null : result;
    } catch (e) {
      if (kDebugMode) debugPrint('[Coefficients] Cloudflare fetch failed: $e');
      return null;
    }
  }

  static Future<void> _pushToCloudflare(
    String department,
    int semester,
    String academicYear,
    Map<String, double> coefficients,
  ) async {
    try {
      final entries = <Map<String, dynamic>>[];
      for (final entry in coefficients.entries) {
        final parts = entry.key.split('|');
        if (parts.length != 2) continue;
        // Skip UE-level sentinel entries ("ueName|") — the community DB only
        // stores subject coefficients.
        if (parts[1].isEmpty) continue;
        entries.add({
          'ue': parts[0],
          'name': parts[1],
          'coefficient': entry.value,
        });
      }
      if (entries.isEmpty) return;

      final body = jsonEncode({
        'department': department,
        'semester': semester,
        'academic_year': academicYear,
        'coefficients': entries,
      });

      await http
          .post(
            Uri.parse('$kWorkerBaseUrl/coefficients'),
            headers: {
              'Content-Type': 'application/json',
              'X-App-Secret': kAppSecret,
            },
            body: body,
          )
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      if (kDebugMode) debugPrint('[Coefficients] Cloudflare push failed: $e');
    }
  }

  // ── Tier 3: Mobinsapi API ────────────────────────────────────────────────

  static Future<Map<String, Map<String, double>>?> _fetchFromApi() async {
    try {
      final groupCount = await GradesService.loadGroups();
      if (kDebugMode) {
        debugPrint('[Coefficients] loadGroups returned: $groupCount');
      }
      if (groupCount <= 0) return null;

      final allCoeffs = <String, Map<String, double>>{};

      for (int i = 0; i < groupCount; i++) {
        try {
          final raw = await GradesService.coefficients(i);
          if (kDebugMode) {
            debugPrint(
              '[Coefficients] id=$i SUCCESS: '
              '${raw.substring(0, raw.length.clamp(0, 500))}',
            );
          }
          final parsed = _parseApiResponse(raw);
          if (parsed != null) {
            for (final entry in parsed.entries) {
              allCoeffs.putIfAbsent(entry.key, () => entry.value);
            }
          }
        } catch (e) {
          if (kDebugMode) debugPrint('[Coefficients] id=$i FAILED: $e');
        }
      }

      return allCoeffs.isEmpty ? null : allCoeffs;
    } catch (e) {
      if (kDebugMode) debugPrint('[Coefficients] API fetch failed: $e');
      return null;
    }
  }

  static final RegExp _semesterRegex = RegExp(
    r'sem(?:estre)?[^a-zA-Z]*(\d+)',
    caseSensitive: false,
  );

  /// Parse the Coefficients() API response.
  /// Same structure as grades: Root → Semester → UE → Subject (→ Grade details).
  /// Every level has a "coeff" string field. We extract subject-level coefficients.
  /// Returns: semesterNumber → { "ue|subject" → coefficient }.
  static Map<String, Map<String, double>>? _parseApiResponse(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;

      final topDetails = decoded['details'];
      if (topDetails is! List) return null;

      final results = <String, Map<String, double>>{};

      for (final semNode in topDetails) {
        if (semNode is! Map<String, dynamic>) continue;
        final semName = (semNode['name'] ?? '').toString();
        final semMatch = _semesterRegex.firstMatch(semName);
        if (semMatch == null) {
          // Might be a year wrapper — recurse one level
          if (semNode['details'] is List) {
            for (final inner in semNode['details'] as List) {
              if (inner is! Map<String, dynamic>) continue;
              final innerName = (inner['name'] ?? '').toString();
              final innerMatch = _semesterRegex.firstMatch(innerName);
              if (innerMatch != null) {
                final semKey = innerMatch.group(1)!;
                _extractUeCoeffs(inner, semKey, results);
              }
            }
          }
          continue;
        }
        final semKey = semMatch.group(1)!;
        _extractUeCoeffs(semNode, semKey, results);
      }

      if (kDebugMode) {
        for (final entry in results.entries) {
          debugPrint(
            '[Coefficients] Semester ${entry.key}: ${entry.value.length} subjects',
          );
          for (final sub in entry.value.entries) {
            debugPrint('[Coefficients]   ${sub.key} = ${sub.value}');
          }
        }
      }

      return results.isEmpty ? null : results;
    } catch (e) {
      if (kDebugMode) debugPrint('[Coefficients] Parse failed: $e');
      return null;
    }
  }

  /// Extract subject coefficients from a semester node.
  /// Structure: semesterNode → UE nodes → Subject nodes (with "coeff").
  static void _extractUeCoeffs(
    Map<String, dynamic> semNode,
    String semKey,
    Map<String, Map<String, double>> results,
  ) {
    final ueList = semNode['details'];
    if (ueList is! List) return;

    results.putIfAbsent(semKey, () => {});

    for (final ueNode in ueList) {
      if (ueNode is! Map<String, dynamic>) continue;
      final ueName = (ueNode['name'] ?? '').toString().cleanName();

      // UE-level coefficient is stored under a sentinel key "ueName|" (empty
      // subject part) so the semester average can weight UEs correctly.
      final ueCoeff = _parseCoeffString(ueNode['coeff']);
      if (ueName.isNotEmpty && ueCoeff != null && ueCoeff > 0) {
        results[semKey]!['$ueName|'] = ueCoeff;
      }

      final subjectList = ueNode['details'];
      if (subjectList is! List) continue;

      for (final subNode in subjectList) {
        if (subNode is! Map<String, dynamic>) continue;
        final subName = (subNode['name'] ?? '').toString().cleanName();
        final coeff = _parseCoeffString(subNode['coeff']);
        if (subName.isNotEmpty && coeff != null && coeff > 0) {
          results[semKey]!['$ueName|$subName'] = coeff;
        }
      }
    }
  }

  /// Parse a "coeff" field which is a string like "2", "1.5", etc.
  static double? _parseCoeffString(dynamic val) {
    if (val is num && val > 0 && val <= 30) return val.toDouble();
    if (val is String) {
      final parsed = double.tryParse(val.replaceAll(',', '.'));
      if (parsed != null && parsed > 0 && parsed <= 30) return parsed;
    }
    return null;
  }
}
