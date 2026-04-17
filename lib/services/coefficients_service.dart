import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import '../constants.dart';
import '../models.dart';
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

  static String _cacheKey(
    String department,
    int semester,
    String academicYear,
  ) {
    return '${kStorageCoefficientsPrefix}${department}_${semester}_$academicYear';
  }

  /// Fetch coefficients for a department+semester+academicYear.
  /// Returns a map of cleaned "ue|subject" → coefficient value.
  /// Returns an empty map if all tiers fail (caller falls back to 1.0).
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

    // Tier 3: Mobinsapi API (last resort)
    final api = await _fetchFromApi();
    if (api != null && api.isNotEmpty) {
      final filtered = _filterForSemester(
        api,
        department,
        semester,
        academicYear,
      );
      if (filtered.isNotEmpty) {
        if (kDebugMode) {
          debugPrint(
            '[Coefficients] Tier 3 hit (API): ${filtered.length} entries',
          );
        }
        unawaited(
          _writeLocalCache(department, semester, academicYear, filtered),
        );
        unawaited(
          _pushToCloudflare(department, semester, academicYear, filtered),
        );
        return filtered;
      }
    }

    if (kDebugMode) debugPrint('[Coefficients] All tiers missed');
    return {};
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
      final Map<String, dynamic> decoded =
          jsonDecode(raw) as Map<String, dynamic>;
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
        value: jsonEncode(coefficients),
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
        if (ue != null && name != null && coeff != null && coeff > 0) {
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
      if (groupCount <= 0) return null;

      final allCoeffs = <String, Map<String, double>>{};

      for (int i = 0; i < groupCount; i++) {
        final raw = await GradesService.coefficients(i);
        if (kDebugMode) {
          debugPrint(
            '[Coefficients] API raw response (group $i): '
            '${raw.substring(0, raw.length.clamp(0, 500))}',
          );
        }
        final parsed = _parseApiResponse(raw);
        if (parsed != null) {
          for (final entry in parsed.entries) {
            allCoeffs.putIfAbsent(entry.key, () => entry.value);
          }
        }
      }

      return allCoeffs.isEmpty ? null : allCoeffs;
    } catch (e) {
      if (kDebugMode) debugPrint('[Coefficients] API fetch failed: $e');
      return null;
    }
  }

  /// Parse the raw Coefficients() API response.
  /// Returns a nested map: "semesterKey" → { "ue|subject" → coefficient }.
  /// The format is unknown, so we try multiple strategies.
  static Map<String, Map<String, double>>? _parseApiResponse(String raw) {
    try {
      final dynamic decoded = jsonDecode(raw);
      final results = <String, Map<String, double>>{};

      if (decoded is Map<String, dynamic>) {
        _walkTree(decoded, results, '', '');
      } else if (decoded is List<dynamic>) {
        for (final item in decoded) {
          if (item is Map<String, dynamic>) {
            _walkTree(item, results, '', '');
          }
        }
      }

      return results.isEmpty ? null : results;
    } catch (e) {
      if (kDebugMode) debugPrint('[Coefficients] Parse failed: $e');
      return null;
    }
  }

  static final RegExp _semesterRegex = RegExp(
    r'sem(?:estre)?[^a-zA-Z]*(\d+)',
    caseSensitive: false,
  );

  /// Recursively walk a tree that mirrors the grades JSON structure,
  /// extracting coefficient values from nodes.
  static void _walkTree(
    Map<String, dynamic> node,
    Map<String, Map<String, double>> results,
    String currentSemester,
    String currentUe,
  ) {
    final name = (node['name'] ?? '').toString().cleanName();
    final details = node['details'];

    // Detect semester level
    var semKey = currentSemester;
    final semMatch = _semesterRegex.firstMatch(name);
    if (semMatch != null) {
      semKey = semMatch.group(1) ?? currentSemester;
    }

    // Detect UE level (has details children that are subjects)
    var ueKey = currentUe;

    if (details is List && details.isNotEmpty) {
      // Check if children look like subjects (have a coefficient/coeff field)
      final firstChild = details.firstWhere(
        (d) => d is Map<String, dynamic>,
        orElse: () => null,
      );
      final childHasCoeff =
          firstChild is Map<String, dynamic> &&
          (firstChild.containsKey('coefficient') ||
              firstChild.containsKey('coeff') ||
              firstChild.containsKey('coef'));

      if (childHasCoeff && semKey.isNotEmpty) {
        // This node is a UE — its children are subjects with coefficients
        ueKey = name;
        results.putIfAbsent(semKey, () => {});
        for (final child in details) {
          if (child is! Map<String, dynamic>) continue;
          final subName = (child['name'] ?? '').toString().cleanName();
          final coeff = _extractCoeff(child);
          if (subName.isNotEmpty && coeff != null && coeff > 0) {
            results[semKey]!['$ueKey|$subName'] = coeff;
          }
        }
      } else {
        // Intermediate node — recurse
        if (name.isNotEmpty &&
            !name.contains(RegExp(r'sem', caseSensitive: false))) {
          ueKey = name;
        }
        for (final child in details) {
          if (child is Map<String, dynamic>) {
            _walkTree(child, results, semKey, ueKey);
          }
        }
      }
    } else if (semKey.isNotEmpty && currentUe.isNotEmpty) {
      // Leaf node with a coefficient — this is a subject
      final coeff = _extractCoeff(node);
      if (name.isNotEmpty && coeff != null && coeff > 0) {
        results.putIfAbsent(semKey, () => {});
        results[semKey]!['$currentUe|$name'] = coeff;
      }
    }
  }

  static double? _extractCoeff(Map<String, dynamic> node) {
    for (final key in ['coefficient', 'coeff', 'coef', 'ects']) {
      final val = node[key];
      double? candidate;
      if (val is num && val > 0) candidate = val.toDouble();
      if (val is String) {
        candidate = double.tryParse(val.replaceAll(',', '.'));
      }
      if (candidate != null && candidate > 0 && candidate <= 30) {
        return candidate;
      }
    }
    return null;
  }

  /// Filter the full API result to a specific semester.
  static Map<String, double> _filterForSemester(
    Map<String, Map<String, double>> allSemesters,
    String department,
    int semester,
    String academicYear,
  ) {
    final semKey = semester.toString();
    return allSemesters[semKey] ?? {};
  }
}
