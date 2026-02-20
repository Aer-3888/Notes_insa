import 'dart:convert';
import 'models.dart';

/// JSON curriculum parser.
///
/// Parses the structure exported by the source into a list of
/// [TeachingUnit] objects. The expected JSON contains a top-level
/// `details` array with semester entries (names contain "SEMESTRE").
class JsonCurriculumParser {
  /// Parse a semester JSON payload and return its teaching units.
  ///
  /// Returns an empty list on parse errors or when the expected nodes
  /// are missing.
  static List<TeachingUnit> parseSemester(
    String jsonString,
    int semesterNumber,
  ) {
    try {
      final Map<String, dynamic> rawData = jsonDecode(jsonString);

      // Top-level details must be a list
      if (rawData['details'] is! List) return [];

      final List<dynamic> yearDetails = rawData['details'];

      final String semesterKey = 'SEMESTRE$semesterNumber';
      Map<String, dynamic>? semesterNode;

      // Find the matching semester node
      for (final yearItem in yearDetails) {
        if (yearItem is Map<String, dynamic> &&
            yearItem['name'] != null &&
            yearItem['name'].toString().toUpperCase().contains(semesterKey)) {
          semesterNode = yearItem;
          break;
        }
      }

      if (semesterNode == null || semesterNode['details'] is! List) return [];

      final List<TeachingUnit> teachingUnits = [];
      final List<dynamic> ueList = semesterNode['details'];

      for (final ueNode in ueList) {
        if (ueNode is! Map<String, dynamic>) continue;

        final String ueName = ueNode['name'] ?? 'Unknown UE';
        final List<Subject> subjects = [];

        if (ueNode['details'] is List) {
          final List<dynamic> subjectList = ueNode['details'];

          for (final subjectNode in subjectList) {
            if (subjectNode is! Map<String, dynamic>) continue;

            final String subjectName = subjectNode['name'] ?? 'Unknown Subject';
            final double subjectCoeff = 1.0; // default

            final List<GradeInstance> grades = [];

            // Aggregate subject score (if present)
            final String? subjectScore = subjectNode['score'];
            if (subjectScore != null && !subjectScore.contains('Aucun')) {
              final double? gradeValue = GradeUtils.parseDouble(subjectScore);
              if (gradeValue != null) {
                grades.add(GradeInstance(subjectName, gradeValue));
              }
            }

            // Detailed grades under the subject
            if (subjectNode['details'] is List) {
              final List<dynamic> gradeList = subjectNode['details'];

              for (final gradeNode in gradeList) {
                if (gradeNode is! Map<String, dynamic>) continue;

                final String gradeName = gradeNode['name'] ?? 'Unknown Grade';
                final String? gradeScore = gradeNode['score'];

                if (gradeScore != null && !gradeScore.contains('Aucun')) {
                  final double? gradeValue = GradeUtils.parseDouble(gradeScore);
                  if (gradeValue != null) {
                    grades.add(GradeInstance(gradeName, gradeValue));
                  }
                }
              }
            }

            final Subject subject = Subject(subjectName, subjectCoeff, {});
            subject.grades = grades;
            subjects.add(subject);
          }
        }

        if (subjects.isNotEmpty) {
          teachingUnits.add(TeachingUnit(ueName, subjects));
        }
      }

      return teachingUnits;
    } catch (_) {
      // Return empty on any parsing error
      return [];
    }
  }

  /// Read the department/title field from the JSON payload.
  static String getDepartmentName(String jsonString) {
    try {
      final Map<String, dynamic> rawData = jsonDecode(jsonString);
      return rawData['name'] ?? 'Etudiant';
    } catch (_) {
      return 'Etudiant';
    }
  }

  /// Return available semester numbers found in the JSON payload.
  static List<int> getAvailableSemesters(String jsonString) {
    try {
      final Map<String, dynamic> rawData = jsonDecode(jsonString);

      if (rawData['details'] is! List) return [];

      final List<int> semesters = [];
      final List<dynamic> yearDetails = rawData['details'];

      for (final item in yearDetails) {
        if (item is Map<String, dynamic> && item['name'] != null) {
          final String name = item['name'].toString();
          final RegExp regex = RegExp(r'SEMESTRE(\d+)', caseSensitive: false);
          final match = regex.firstMatch(name);
          if (match != null) {
            final int? semNum = int.tryParse(match.group(1) ?? '');
            if (semNum != null) semesters.add(semNum);
          }
        }
      }

      semesters.sort();
      return semesters;
    } catch (_) {
      return [];
    }
  }
}
