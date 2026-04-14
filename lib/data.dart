import 'dart:convert';
import 'package:flutter/foundation.dart';
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
      final Map<String, dynamic> rawData =
          jsonDecode(jsonString) as Map<String, dynamic>;

      // Top-level details must be a list
      if (rawData['details'] is! List) return [];

      final List<dynamic> yearDetails = rawData['details'] as List<dynamic>;

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
      final List<dynamic> ueList = semesterNode['details'] as List<dynamic>;

      for (final ueNode in ueList) {
        if (ueNode is! Map<String, dynamic>) continue;

        // Clean names to ensure consistent key matching with the backend
        final String ueName = (ueNode['name'] ?? 'Unknown UE')
            .toString()
            .cleanName();
        final List<Subject> subjects = [];

        if (ueNode['details'] is List) {
          final List<dynamic> subjectList = ueNode['details'] as List<dynamic>;

          for (final subjectNode in subjectList) {
            if (subjectNode is! Map<String, dynamic>) continue;

            final String subjectName =
                (subjectNode['name'] ?? 'Unknown Subject')
                    .toString()
                    .cleanName();
            // TODO: replace with a dedicated coefficients API call once
            // mobinsapi exposes it — hardcoded to 1.0 in the meantime.
            const double subjectCoeff = 1.0;

            final List<GradeInstance> grades = [];

            // Detailed grades under the subject
            if (subjectNode['details'] is List) {
              final List<dynamic> gradeList =
                  subjectNode['details'] as List<dynamic>;

              for (final gradeNode in gradeList) {
                if (gradeNode is! Map<String, dynamic>) continue;

                final String gradeName = (gradeNode['name'] ?? 'Unknown Grade')
                    .toString()
                    .cleanName();
                final String? gradeScore = _extractScore(gradeNode['score']);

                if (gradeScore != null && !gradeScore.contains('Aucun')) {
                  final double? gradeValue = GradeUtils.parseDouble(gradeScore);
                  if (gradeValue != null) {
                    // coeff omitted — coefficients API not yet available.
                    grades.add(GradeInstance(gradeName, gradeValue));
                  }
                }
              }
            }

            // Fallback: use top-level score only if no detailed grades were found
            if (grades.isEmpty) {
              final String? subjectScore = _extractScore(subjectNode['score']);
              if (subjectScore != null && !subjectScore.contains('Aucun')) {
                final double? gradeValue = GradeUtils.parseDouble(subjectScore);
                if (gradeValue != null) {
                  grades.add(GradeInstance(subjectName, gradeValue));
                }
              }
            }

            final subject = Subject(
              subjectName,
              subjectCoeff,
              {},
              grades: grades,
            );
            subjects.add(subject);
          }
        }

        if (subjects.isNotEmpty) {
          teachingUnits.add(TeachingUnit(ueName, subjects));
        }
      }

      return teachingUnits;
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[Parser] parseSemester($semesterNumber) failed');
        debugPrint('[Parser] Stack: $st');
      }
      return [];
    }
  }

  /// Read the department/title field from the JSON payload.
  /// Tries to extract the department code if it's in parentheses (e.g. "DOE John (INFO)").
  static String getDepartmentName(String jsonString) {
    try {
      final Map<String, dynamic> rawData =
          jsonDecode(jsonString) as Map<String, dynamic>;
      final String rawName = (rawData['name'] ?? 'Etudiant').toString();

      // Try to find content inside parentheses, usually the department code
      final bracketMatch = RegExp(r'\((.*?)\)').firstMatch(rawName);
      if (bracketMatch != null && bracketMatch.group(1) != null) {
        final dept = bracketMatch.group(1)!.trim();
        if (dept.isNotEmpty) return dept.cleanName();
      }

      // Fallback: if there's a dash, take the last part
      if (rawName.contains('-')) {
        final parts = rawName.split('-');
        return parts.last.trim().cleanName();
      }

      return rawName.cleanName();
    } catch (e) {
      if (kDebugMode) debugPrint('[Parser] getDepartmentName failed: $e');
      return 'Etudiant';
    }
  }

  /// Return available semester numbers found in the JSON payload.
  static List<int> getAvailableSemesters(String jsonString) {
    try {
      final dynamic decoded = jsonDecode(jsonString);

      if (kDebugMode) {
        debugPrint('[Parser] JSON top-level type: ${decoded.runtimeType}');
        if (decoded is Map) {
          debugPrint('[Parser] Top-level keys: ${decoded.keys.toList()}');
          if (decoded['details'] != null) {
            debugPrint(
              '[Parser] details type: ${decoded['details'].runtimeType}',
            );
            if (decoded['details'] is List &&
                (decoded['details'] as List).isNotEmpty) {
              final first = (decoded['details'] as List).first;
              debugPrint(
                '[Parser] First details item keys: ${first is Map ? first.keys.toList() : first.runtimeType}',
              );
              if (first is Map && first['name'] != null) {
                debugPrint(
                  '[Parser] First details item name: "${first['name']}"',
                );
              }
            }
          }
        } else if (decoded is List && decoded.isNotEmpty) {
          debugPrint(
            '[Parser] Top-level is List, first item keys: ${decoded.first is Map ? (decoded.first as Map).keys.toList() : decoded.first.runtimeType}',
          );
        }
      }

      final Map<String, dynamic> rawData = decoded as Map<String, dynamic>;

      if (rawData['details'] is! List) {
        if (kDebugMode) {
          debugPrint(
            '[Parser] getAvailableSemesters: "details" not found or not a List',
          );
        }
        return [];
      }

      final List<int> semesters = [];
      final List<dynamic> yearDetails = rawData['details'] as List<dynamic>;

      // Match "SEMESTRE3", "Semestre 3", "S3", "semestre_3", etc.
      final RegExp regex = RegExp(r'[Ss][Ee][Mm].*?(\d+)');

      for (final item in yearDetails) {
        if (item is Map<String, dynamic> && item['name'] != null) {
          final String name = item['name'].toString();
          final match = regex.firstMatch(name);
          if (kDebugMode) {
            debugPrint('[Parser] Semester candidate: "$name" → match: $match');
          }
          if (match != null) {
            final int? semNum = int.tryParse(match.group(1) ?? '');
            if (semNum != null) semesters.add(semNum);
          }
        }
      }

      semesters.sort();
      if (kDebugMode) debugPrint('[Parser] Found semesters: $semesters');
      return semesters;
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[Parser] getAvailableSemesters failed: $e');
        debugPrint('[Parser] Stack: $st');
      }
      return [];
    }
  }

  /// Extracts a score string from a field that may be either a bare String
  /// (old inscore format) or a List (new mobinsapi format: ["16/20", "VAL"]).
  /// Returns null if the field is absent or not a recognised type.
  static String? _extractScore(dynamic field) {
    if (field is String) return field;
    if (field is List && field.isNotEmpty && field.first is String) {
      return field.first as String;
    }
    return null;
  }
}
