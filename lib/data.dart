import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'models.dart';

// Parses the provided JSON structure into TeachingUnit/Subject/Grade models.
// Expected structure: top-level -> details (semesters) -> teaching units -> subjects -> grades
class JsonCurriculumParser {
  static List<TeachingUnit> parseSemester(
    String jsonString,
    int semesterNumber,
  ) {
    try {
      Map<String, dynamic> rawData = jsonDecode(jsonString);

      // Navigate to the year level (top level details)
      if (rawData['details'] is! List) return [];

      List<dynamic> yearDetails = rawData['details'];

      // Find the semester in the year details
      String semesterKey = 'SEMESTRE$semesterNumber';
      Map<String, dynamic>? semesterNode;

      for (var yearItem in yearDetails) {
        if (yearItem is Map<String, dynamic> &&
            yearItem['name'] != null &&
            yearItem['name'].toString().toUpperCase().contains(semesterKey)) {
          semesterNode = yearItem;
          break;
        }
      }

      if (semesterNode == null || semesterNode['details'] is! List) return [];

      // Parse teaching units (UE) from semester details
      List<TeachingUnit> teachingUnits = [];
      List<dynamic> ueList = semesterNode['details'];

      for (var ueNode in ueList) {
        if (ueNode is! Map<String, dynamic>) continue;

        String ueName = ueNode['name'] ?? 'Unknown UE';
        List<Subject> subjects = [];

        if (ueNode['details'] is List) {
          List<dynamic> subjectList = ueNode['details'];

          for (var subjectNode in subjectList) {
            if (subjectNode is! Map<String, dynamic>) continue;

            String subjectName = subjectNode['name'] ?? 'Unknown Subject';
            double subjectCoeff = 1.0; // Default coefficient when not provided

            // Parse grades for this subject
            List<GradeInstance> grades = [];

            // If the subject has an aggregate score, include it as a grade entry
            String? subjectScore = subjectNode['score'];
            if (subjectScore != null && !subjectScore.contains('Aucun')) {
              double? gradeValue = GradeUtils.parseDouble(subjectScore);
              if (gradeValue != null) {
                grades.add(GradeInstance(subjectName, gradeValue));
              }
            }

            // Parse detailed grades under the subject
            if (subjectNode['details'] is List) {
              List<dynamic> gradeList = subjectNode['details'];

              for (var gradeNode in gradeList) {
                if (gradeNode is! Map<String, dynamic>) continue;

                String gradeName = gradeNode['name'] ?? 'Unknown Grade';
                String? gradeScore = gradeNode['score'];

                if (gradeScore != null && !gradeScore.contains('Aucun')) {
                  double? gradeValue = GradeUtils.parseDouble(gradeScore);
                  if (gradeValue != null) {
                    grades.add(GradeInstance(gradeName, gradeValue));
                  }
                }
              }
            }

            // Build Subject instance; jsonKeys maintained for compatibility with other parsers
            Subject subject = Subject(subjectName, subjectCoeff, {});
            subject.grades = grades;
            subjects.add(subject);
          }
        }

        if (subjects.isNotEmpty) {
          teachingUnits.add(TeachingUnit(ueName, subjects));
        }
      }

      return teachingUnits;
    } catch (e) {
      // Only print parsing errors in debug mode to avoid leaking info in release builds
      if (kDebugMode) {
        debugPrint('Error parsing curriculum: $e');
      }
      return [];
    }
  }

  // Extract department/year name from JSON
  static String getDepartmentName(String jsonString) {
    try {
      Map<String, dynamic> rawData = jsonDecode(jsonString);
      return rawData['name'] ?? 'Etudiant';
    } catch (e) {
      return 'Etudiant';
    }
  }

  // Get list of available semesters from JSON
  static List<int> getAvailableSemesters(String jsonString) {
    try {
      Map<String, dynamic> rawData = jsonDecode(jsonString);

      if (rawData['details'] is! List) return [];

      List<int> semesters = [];
      List<dynamic> yearDetails = rawData['details'];

      for (var item in yearDetails) {
        if (item is Map<String, dynamic> && item['name'] != null) {
          String name = item['name'].toString();
          // Extract semester number from names like "3INFO-SEMESTRE5"
          RegExp regex = RegExp(r'SEMESTRE(\d+)', caseSensitive: false);
          var match = regex.firstMatch(name);
          if (match != null) {
            int? semNum = int.tryParse(match.group(1) ?? '');
            if (semNum != null) {
              semesters.add(semNum);
            }
          }
        }
      }

      return semesters..sort();
    } catch (e) {
      return [];
    }
  }
}

// Helper for backward compatibility
List<TeachingUnit> getCurriculum(int semester) {
  return JsonCurriculumParser.parseSemester(jsonString, semester);
}

// JSON payload used as a static example; replaced at runtime after login
String jsonString =
    r'''{"name":"INGENIEUR INFO 3A","score":"Aucun résultat","details":[{"name":"3INFO-SEMESTRE5","score":"Aucun résultat","details":[{"name":"ENSEIGNEMENTS D'HUMANITE S5","score":"Aucun résultat","details":[{"name":"Anglais S5","score":"Aucun résultat","details":[{"name":"DS1 ANGLAIS S5","score":"15.5/20","details":null}]},{"name":"Education physique et sportive S5","score":"15/20","details":[{"name":"Controle continu EPS S5","score":"15/20","details":null}]},{"name":"Projet Sciences Humaines","score":"Aucun résultat","details":null},{"name":"Gestion du Risque","score":"19.6/20","details":[{"name":"Controle continu Gestion du Risque","score":"19.6/20","details":null}]}]},{"name":"RIE : Recherche Innovation Entrepreneuriat","score":"Aucun résultat","details":[{"name":"Innovation Entrepreneuriat","score":"Aucun résultat","details":null}]},{"name":"MATHEMATIQUES POUR L'INFORMATIQUE","score":"10.157/20","details":[{"name":"Analyse de données et Fouille de données","score":"9.5/20","details":[{"name":"ADFD  DS 2h","score":"9.5/20","details":null}]},{"name":"Probabilités","score":"11.25/20","details":[{"name":"PROBA DS 2h","score":"11.25/20","details":null}]}]},{"name":"ARCHITECTURE LOGICIELLE ET MATERIELLE","score":"12.313/20","details":[{"name":"Langage C","score":"16.25/20","details":[{"name":"LANGAGE C DS TP 1h","score":"15/20","details":null},{"name":"LANGAGE C DS 1h","score":"17.5/20","details":null}]},{"name":"Concepts de la logique à la programmation","score":"10/20","details":[{"name":"CLP DS 2h","score":"10/20","details":null}]},{"name":"Hygiène numérique","score":"13/20","details":[{"name":"HI DS 2h","score":"13/20","details":null}]}]},{"name":"PARADIGMES DE PROGRAMMATION","score":"12.558/20","details":[{"name":"Introduction aux techniques de l'ingénieur","score":"12.25/20","details":[{"name":"ITI - DS 2H","score":"12.25/20","details":null}]},{"name":"Programmation fonctionnelle","score":"15.5/20","details":[{"name":"PF Note finale","score":"15.5/20","details":null}]},{"name":"Programmation logique","score":"10/20","details":[{"name":"PL DS 1h30","score":"10/20","details":null}]}]},{"name":"CONCEPTION LOGICIELLE","score":"13.485/20","details":[{"name":"Conception et programmation orientée objet","score":"15/20","details":[{"name":"CPOO1 DS 2H","score":"15/20","details":null}]},{"name":"Etude Pratique - S5","score":"14.2/20","details":[{"name":"EP S5 PROJET","score":"14.2/20","details":null}]},{"name":"Structure de données","score":"12.25/20","details":[{"name":"SDD DS 2h","score":"12.25/20","details":null}]}]},{"name":"REMEDIATION GESTION DU TRAVAIL","score":"Aucun résultat","details":[{"name":"Remédiation Gestion du travail ","score":"Aucun résultat","details":null}]}]},{"name":"3INFO-SEMESTRE6","score":"Aucun résultat","details":null}]}''';
