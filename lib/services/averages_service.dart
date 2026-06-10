import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../constants.dart';
import '../models.dart';
import '../data.dart';
import 'auth_service.dart';

class AveragesService {
  static String currentAcademicYear() {
    final now = DateTime.now();
    final year = now.year;
    return now.month >= 8 ? '$year-${year + 1}' : '${year - 1}-$year';
  }

  static String academicYearForSemester(int semester, int maxSemester) {
    final currentYear = currentAcademicYear();
    final maxPair = (maxSemester - 1) ~/ 2;
    final thisPair = (semester - 1) ~/ 2;
    final offset = maxPair - thisPair;
    if (offset <= 0) return currentYear;
    final parts = currentYear.split('-');
    final startYear = int.parse(parts[0]) - offset;
    return '$startYear-${startYear + 1}';
  }

  /// Submit grades for all available semesters.
  static Future<void> submitAllSemesters(String gradesJson) async {
    final availableSems = JsonCurriculumParser.getAvailableSemesters(
      gradesJson,
    );

    if (kDebugMode) {
      debugPrint('[AveragesService] Available semesters: $availableSems');
    }

    if (availableSems.isEmpty) {
      if (kDebugMode) {
        debugPrint('[AveragesService] Aborting: no semesters found in JSON');
      }
      return;
    }

    final credentials = await AuthService().getCredentials();
    if (credentials == null) {
      if (kDebugMode) {
        debugPrint('[AveragesService] Aborting: no credentials found');
      }
      return;
    }
    final username = credentials[kStorageUser];
    if (username == null || username.isEmpty) {
      if (kDebugMode) {
        debugPrint('[AveragesService] Aborting: username is empty');
      }
      return;
    }

    final maxSemester = availableSems.last;

    final List<Future<void>> futures = [];
    for (final sem in availableSems) {
      final department = JsonCurriculumParser.getDepartmentForSemester(
        gradesJson,
        sem,
      );
      if (department.isEmpty || department == 'Etudiant') {
        if (kDebugMode) {
          debugPrint(
            '[AveragesService] Skipping semester $sem: department is "$department"',
          );
        }
        continue;
      }
      final units = JsonCurriculumParser.parseSemester(gradesJson, sem);
      if (units.isEmpty) {
        if (kDebugMode) {
          debugPrint(
            '[AveragesService] Skipping semester $sem: no units parsed',
          );
        }
        continue;
      }
      final academicYear = academicYearForSemester(sem, maxSemester);
      if (kDebugMode) {
        debugPrint(
          '[AveragesService] Semester $sem → $department / $academicYear',
        );
      }
      futures.add(
        submitGrades(
          department: department,
          semester: sem,
          units: units,
          username: username,
          academicYear: academicYear,
        ),
      );
    }

    if (futures.isEmpty) {
      if (kDebugMode) {
        debugPrint('[AveragesService] No valid semesters with data to submit');
      }
      return;
    }

    await Future.wait(futures);
    if (kDebugMode) debugPrint('[AveragesService] All submissions completed');
  }

  /// Submit grades for one semester anonymously. Throws on failure.
  static Future<void> submitGrades({
    required String department,
    required int semester,
    required List<TeachingUnit> units,
    required String username,
    required String academicYear,
  }) async {
    final subjects = [
      for (final unit in units)
        for (final sub in unit.subjects)
          if (sub.average != null)
            {'ue': unit.name, 'name': sub.name, 'grade': sub.average!},
    ];

    if (subjects.isEmpty) {
      if (kDebugMode) {
        debugPrint(
          '[AveragesService] Semester $semester: no subjects with averages to submit',
        );
      }
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final hashKey =
        '$kStorageSubmittedHashPrefix${department}_${semester}_$academicYear';
    final currentHash = sha256
        .convert(utf8.encode('$username:${jsonEncode(subjects)}'))
        .toString();

    if (prefs.getString(hashKey) == currentHash) {
      if (kDebugMode) {
        debugPrint(
          '[AveragesService] Semester $semester: grades unchanged, skipping submission',
        );
      }
      return;
    }

    final body = jsonEncode({
      'department': department,
      'semester': semester,
      'subjects': subjects,
      'username': username,
      'academic_year': academicYear,
    });

    if (kDebugMode) {
      debugPrint(
        '[AveragesService] Submitting $semester (subjects: ${subjects.length}) to $kWorkerBaseUrl',
      );
    }

    final response = await http
        .post(
          Uri.parse('$kWorkerBaseUrl/submit'),
          headers: {
            'Content-Type': 'application/json',
            'X-App-Secret': kAppSecret,
          },
          body: body,
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      if (kDebugMode) {
        debugPrint(
          '[AveragesService] Failed with status ${response.statusCode}',
        );
        debugPrint('[AveragesService] Response: ${response.body}');
      }
      throw Exception(
        'Server returned ${response.statusCode}: ${response.body}',
      );
    } else {
      await prefs.setString(hashKey, currentHash);
      final data = jsonDecode(response.body);
      final status = data['status'] ?? 'unknown';
      if (kDebugMode) {
        debugPrint('[AveragesService] Semester $semester response: $status');
      }
    }
  }

  /// Class averages shift slowly as students submit grades, so a short
  /// local cache avoids re-fetching on every dashboard visit.
  static const Duration _cacheTtl = Duration(hours: 1);

  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  static String _cacheKey(
    String department,
    int semester,
    String academicYear,
  ) {
    return '$kStorageAveragesPrefix${department}_${semester}_$academicYear';
  }

  /// Fetch class averages for a department + semester.
  /// Returns an empty list when the server has no data yet.
  /// Throws on network errors or non-200 responses so the caller
  /// can show an error state with a retry option.
  static Future<List<SubjectAverage>> fetchAverages({
    required String department,
    required int semester,
    required String academicYear,
  }) async {
    final cacheKey = _cacheKey(department, semester, academicYear);

    final cached = await _readLocalCache(cacheKey);
    if (cached != null) return cached;

    final uri = Uri.parse('$kWorkerBaseUrl/averages').replace(
      queryParameters: {
        'department': department,
        'semester': semester.toString(),
        'academic_year': academicYear,
      },
    );

    final response = await http.get(uri).timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw Exception('fetchAverages: server returned ${response.statusCode}');
    }

    final List<dynamic> data = jsonDecode(response.body) as List<dynamic>;
    final result = <SubjectAverage>[];
    for (final row in data) {
      if (row is! Map<String, dynamic>) continue;
      try {
        result.add(SubjectAverage.fromJson(row));
      } catch (e) {
        // Skip a malformed row rather than failing the whole list.
        if (kDebugMode) debugPrint('[Averages] skipped bad row: $e');
      }
    }
    unawaited(_writeLocalCache(cacheKey, data));
    return result;
  }

  static Future<List<SubjectAverage>?> _readLocalCache(String cacheKey) async {
    try {
      final raw = await _storage.read(key: cacheKey);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;

      final ts = (decoded['ts'] as num?)?.toInt() ?? 0;
      final age = DateTime.now().difference(
        DateTime.fromMillisecondsSinceEpoch(ts),
      );
      if (age > _cacheTtl) return null;

      final data = decoded['data'];
      if (data is! List) return null;

      final result = <SubjectAverage>[];
      for (final row in data) {
        if (row is! Map<String, dynamic>) continue;
        try {
          result.add(SubjectAverage.fromJson(row));
        } catch (_) {
          // Skip a malformed cached row rather than failing the whole list.
        }
      }
      return result;
    } catch (e) {
      if (kDebugMode) debugPrint('[Averages] Local cache read failed: $e');
      return null;
    }
  }

  static Future<void> _writeLocalCache(
    String cacheKey,
    List<dynamic> data,
  ) async {
    try {
      await _storage.write(
        key: cacheKey,
        value: jsonEncode({
          'ts': DateTime.now().millisecondsSinceEpoch,
          'data': data,
        }),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[Averages] Local cache write failed: $e');
    }
  }
}
