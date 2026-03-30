import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../constants.dart';
import '../models.dart';
import '../data.dart';
import 'auth_service.dart';

class AveragesService {
  /// Submit grades for all available semesters.
  static Future<void> submitAllSemesters(String gradesJson) async {
    final department = JsonCurriculumParser.getDepartmentName(gradesJson);
    final availableSems = JsonCurriculumParser.getAvailableSemesters(
      gradesJson,
    );

    if (department.isEmpty || department == 'Etudiant') return;
    if (availableSems.isEmpty) return;

    final credentials = await AuthService().getCredentials();
    if (credentials == null) return;
    final username = credentials[kStorageUser];
    if (username == null || username.isEmpty) return;

    final List<Future<void>> futures = [];
    for (final sem in availableSems) {
      final units = JsonCurriculumParser.parseSemester(gradesJson, sem);
      if (units.isEmpty) continue;
      futures.add(
        submitGrades(
          department: department,
          semester: sem,
          units: units,
          username: username,
        ),
      );
    }
    await Future.wait(futures);
  }

  /// Submit grades for one semester anonymously. Throws on failure.
  static Future<void> submitGrades({
    required String department,
    required int semester,
    required List<TeachingUnit> units,
    required String username,
  }) async {
    final subjects = [
      for (final unit in units)
        for (final sub in unit.subjects)
          if (sub.average != null)
            {'ue': unit.name, 'name': sub.name, 'grade': sub.average!},
    ];

    if (subjects.isEmpty) return;

    final body = jsonEncode({
      'department': department,
      'semester': semester,
      'subjects': subjects,
      'username': username,
    });

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
      throw Exception(
        'Server returned ${response.statusCode}: ${response.body}',
      );
    }
  }

  /// Fetch class averages for a department + semester.
  /// Returns an empty list when the server has no data yet.
  /// Throws on network errors or non-200 responses so the caller
  /// can show an error state with a retry option.
  static Future<List<SubjectAverage>> fetchAverages({
    required String department,
    required int semester,
  }) async {
    final uri = Uri.parse('$kWorkerBaseUrl/averages').replace(
      queryParameters: {
        'department': department,
        'semester': semester.toString(),
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
