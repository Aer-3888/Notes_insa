import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
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
    final department = JsonCurriculumParser.getDepartmentName(gradesJson);
    final availableSems = JsonCurriculumParser.getAvailableSemesters(
      gradesJson,
    );

    if (kDebugMode) {
      debugPrint(
        '[AveragesService] Starting submission for department: "$department"',
      );
      debugPrint('[AveragesService] Available semesters: $availableSems');
    }

    if (department.isEmpty || department == 'Etudiant') {
      if (kDebugMode) {
        debugPrint(
          '[AveragesService] Aborting: department is empty or default "Etudiant"',
        );
      }
      return;
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
          '[AveragesService] Semester $sem → academic year $academicYear',
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
      final data = jsonDecode(response.body);
      final status = data['status'] ?? 'unknown';
      if (kDebugMode) {
        debugPrint('[AveragesService] Semester $semester response: $status');
      }
    }
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
    return data
        .cast<Map<String, dynamic>>()
        .map(SubjectAverage.fromJson)
        .toList();
  }
}
