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

/// Backwards-compatible helper
List<TeachingUnit> getCurriculum(int semester) =>
    JsonCurriculumParser.parseSemester(jsonString, semester);

/// Static example JSON used as a fallback before real data is loaded.
String jsonString =
    r'''{"name":"INGENIEUR INFO 3A","score":"Aucun résultat","details":[{"name":"3INFO-SEMESTRE5","score":"Aucun résultat","details":[{"name":"ENSEIGNEMENTS D'HUMANITE S5","score":"Aucun résultat","details":[{"name":"Anglais S5","score":"Aucun résultat","details":[{"name":"DS1 ANGLAIS S5","score":"12.5/20","details":null}]},{"name":"Education physique et sportive S5","score":"14/20","details":[{"name":"Controle continu EPS S5","score":"14/20","details":null}]},{"name":"Projet Sciences Humaines","score":"Aucun résultat","details":null},{"name":"Gestion du Risque","score":"11.4/20","details":[{"name":"Controle continu Gestion du Risque","score":"11.4/20","details":null}]}]},{"name":"RIE : Recherche Innovation Entrepreneuriat","score":"Aucun résultat","details":[{"name":"Innovation Entrepreneuriat","score":"Aucun résultat","details":null}]},{"name":"MATHEMATIQUES POUR L'INFORMATIQUE","score":"13.82/20","details":[{"name":"Analyse de données et Fouille de données","score":"14.1/20","details":[{"name":"ADFD  DS 2h","score":"14.1/20","details":null}]},{"name":"Probabilités","score":"13.5/20","details":[{"name":"PROBA DS 2h","score":"13.5/20","details":null}]}]},{"name":"ARCHITECTURE LOGICIELLE ET MATERIELLE","score":"10.25/20","details":[{"name":"Langage C","score":"9.5/20","details":[{"name":"LANGAGE C DS TP 1h","score":"11.0/20","details":null},{"name":"LANGAGE C DS 1h","score":"8.0/20","details":null}]},{"name":"Concepts de la logique à la programmation","score":"12.5/20","details":[{"name":"CLP DS 2h","score":"12.5/20","details":null}]},{"name":"Hygiène numérique","score":"16/20","details":[{"name":"HI DS 2h","score":"16/20","details":null}]}]},{"name":"PARADIGMES DE PROGRAMMATION","score":"11.14/20","details":[{"name":"Introduction aux techniques de l'ingénieur","score":"13.0/20","details":[{"name":"ITI - DS 2H","score":"13.0/20","details":null}]},{"name":"Programmation fonctionnelle","score":"9.75/20","details":[{"name":"PF Note finale","score":"9.75/20","details":null}]},{"name":"Programmation logique","score":"14.5/20","details":[{"name":"PL DS 1h30","score":"14.5/20","details":null}]}]},{"name":"CONCEPTION LOGICIELLE","score":"15.2/20","details":[{"name":"Conception et programmation orientée objet","score":"16.5/20","details":[{"name":"CPOO1 DS 2H","score":"16.5/20","details":null}]},{"name":"Etude Pratique - S5","score":"11.8/20","details":[{"name":"EP S5 PROJET","score":"11.8/20","details":null}]},{"name":"Structure de données","score":"17.1/20","details":[{"name":"SDD DS 2h","score":"17.1/20","details":null}]}]},{"name":"REMEDIATION GESTION DU TRAVAIL","score":"Aucun résultat","details":[{"name":"Remédiation Gestion du travail ","score":"Aucun résultat","details":null}]}]},{"name":"3INFO-SEMESTRE6","score":"Aucun résultat","details":null}]}''';
