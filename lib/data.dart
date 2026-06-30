import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'constants.dart';
import 'models.dart';

/// JSON curriculum parser.
///
/// Parses the structure exported by the source into a list of
/// [TeachingUnit] objects. The expected JSON contains a top-level
/// `details` array with semester entries (names contain "SEMESTRE").
class JsonCurriculumParser {
  /// Decode a raw grades payload once into a map. Returns null when the string
  /// is empty/`{}` or fails to decode — callers treat null as "no usable data"
  /// (distinct from a structurally valid but empty payload).
  ///
  /// All other parser methods take the already-decoded map so a payload is only
  /// decoded once per state change instead of once per method call.
  static Map<String, dynamic>? tryDecode(String jsonString) {
    if (jsonString.isEmpty || jsonString == '{}') return null;
    try {
      final decoded = jsonDecode(jsonString);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  /// Parse a semester from an already-decoded payload and return its units.
  ///
  /// Returns an empty list on parse errors or when the expected nodes
  /// are missing.
  static List<TeachingUnit> parseSemester(
    Map<String, dynamic> data,
    int semesterNumber, {
    Map<String, double>? coefficients,
  }) {
    try {
      // Top-level details must be a list
      if (data['details'] is! List) return [];

      final semesterNode = _findSemesterNode(
        data['details'] as List<dynamic>,
        semesterNumber,
      );

      if (semesterNode == null || semesterNode['details'] is! List) return [];

      final List<TeachingUnit> teachingUnits = [];
      // Some curricula (notably the STPI first cycle) wrap UEs in extra grouping
      // levels, such as a "FILIERE" node and sometimes an additional scientific
      // sub-grouping. Flatten those containers so the real UEs land at semester
      // level instead of collapsing into a single unit.
      final ueNodes = collectUeNodes(semesterNode['details'] as List<dynamic>);

      for (final ueNode in ueNodes) {
        // Clean names to ensure consistent key matching with the backend
        final String ueName = (ueNode['name'] ?? 'Unknown UE')
            .toString()
            .cleanName();
        // UE-level coefficient stored under the "ueName|" sentinel key.
        final double ueCoeff = coefficients?['$ueName|'] ?? 1.0;
        final double? ueAverage = _extractAverage(ueNode['score']);
        final List<Subject> subjects = [];

        if (ueNode['details'] is List) {
          final List<dynamic> subjectList = ueNode['details'] as List<dynamic>;

          for (final subjectNode in subjectList) {
            if (subjectNode is! Map<String, dynamic>) continue;

            final String subjectName =
                (subjectNode['name'] ?? 'Unknown Subject')
                    .toString()
                    .cleanName();
            final double subjectCoeff =
                coefficients?['$ueName|$subjectName'] ?? 1.0;
            final double? subjectAverage = _extractAverage(
              subjectNode['score'],
            );

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

                final double? gradeValue = GradeUtils.parseDouble(gradeScore);
                if (gradeValue != null) {
                  grades.add(
                    GradeInstance(
                      gradeName,
                      gradeValue,
                      coeff: _extractCoeff(gradeNode['coeff']),
                    ),
                  );
                }
              }
            }

            final subject = Subject(
              subjectName,
              subjectCoeff,
              {},
              grades: grades,
              extractedAverage: subjectAverage,
              extractedStatus: _extractStatus(subjectNode['score']),
            );
            subjects.add(subject);
          }
        }

        if (subjects.isNotEmpty || ueAverage != null) {
          teachingUnits.add(
            TeachingUnit(
              ueName,
              subjects,
              coeff: ueCoeff,
              extractedAverage: ueAverage,
              extractedStatus: _extractStatus(ueNode['score']),
            ),
          );
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

  /// A node is a leaf when it has no child details, i.e. an individual grade.
  static bool _nodeIsLeaf(Map<String, dynamic> node) {
    final d = node['details'];
    return d is! List || d.isEmpty;
  }

  /// A subject directly parents individual grades, so all of its children are
  /// leaves. (A gradeless subject, holding only a pass/fail status, is itself a
  /// leaf and is handled by the UE-level detection below.)
  static bool _nodeHasGradeChildren(Map<String, dynamic> node) {
    final d = node['details'];
    if (d is! List || d.isEmpty) return false;
    return d.every((c) => c is Map<String, dynamic> && _nodeIsLeaf(c));
  }

  /// A UE directly parents at least one subject that has grades.
  static bool _nodeIsUe(Map<String, dynamic> node) {
    final d = node['details'];
    if (d is! List) return false;
    return d.any((c) => c is Map<String, dynamic> && _nodeHasGradeChildren(c));
  }

  /// A container groups UEs (or further containers) rather than subjects, for
  /// example the STPI "FILIERE CLASSIQUE" wrapper or an "ENSEIGNEMENTS
  /// SCIENTIFIQUES" sub-grouping. These extra levels must be flattened so their
  /// child UEs land at semester level.
  static bool _nodeIsContainer(Map<String, dynamic> node) {
    final d = node['details'];
    if (d is! List) return false;
    return d.any(
      (c) => c is Map<String, dynamic> && (_nodeIsUe(c) || _nodeIsContainer(c)),
    );
  }

  /// Walk the (possibly nested) groupings beneath a semester and collect the
  /// real UE nodes, flattening any wrapper/container levels in between. This
  /// adapts to both the flat engineering shape (semester → UE → subject → grade)
  /// and the deeper STPI shape (semester → filiere → [group] → UE → subject →
  /// grade) without hard-coding a fixed depth.
  ///
  /// Shared with [CoefficientsService] so coefficient keys ("ue|subject") are
  /// built from the same UE/subject boundary the grade tree uses, instead of
  /// drifting back to a fixed-depth assumption.
  static List<Map<String, dynamic>> collectUeNodes(List<dynamic> nodes) {
    final out = <Map<String, dynamic>>[];
    _collectUeNodes(nodes, out);
    return out;
  }

  static void _collectUeNodes(
    List<dynamic> nodes,
    List<Map<String, dynamic>> out,
  ) {
    for (final node in nodes) {
      if (node is! Map<String, dynamic>) continue;
      if (_nodeIsContainer(node)) {
        final children = node['details'];
        if (children is List) _collectUeNodes(children, out);
      } else {
        out.add(node);
      }
    }
  }

  /// Extracts a short department code from the JSON payload.
  ///
  /// Tries several strategies in order:
  /// 1. Parentheses in top-level name: "DOE John (INFO)" → "INFO"
  /// 2. Semester name prefix: "3INFO-SEMESTRE5" → "INFO", "1STPI-SEMESTRE1" → "STPI"
  /// 3. Top-level name as-is
  static String getDepartmentName(Map<String, dynamic> data) {
    try {
      final String rawName = (data['name'] ?? kUnknownDepartment).toString();

      // 1. Content inside parentheses
      final bracketMatch = RegExp(r'\((.*?)\)').firstMatch(rawName);
      if (bracketMatch != null && bracketMatch.group(1) != null) {
        final dept = bracketMatch.group(1)!.trim();
        if (dept.isNotEmpty) return dept.cleanName();
      }

      // 2. Extract from semester names: "3INFO-SEMESTRE5" → "INFO"
      if (data['details'] is List) {
        final dept = _extractDeptFromSemesters(
          data['details'] as List<dynamic>,
        );
        if (dept != null) return dept;
      }

      return rawName.cleanName();
    } catch (e) {
      if (kDebugMode) debugPrint('[Parser] getDepartmentName failed: $e');
      return kUnknownDepartment;
    }
  }

  // Pattern: {digit(s)}{DEPT}-SEM... e.g. "3INFO-SEMESTRE5", "1STPI-SEMESTRE1"
  // Group 1 = full prefix with year ("3INFO", "1STPI")
  // Group 2 = letters only ("INFO", "STPI")
  static final RegExp _deptFromSemRegex = RegExp(
    r'^(\d+([A-Za-z]+))\s*-\s*sem',
    caseSensitive: false,
  );

  /// Recursively searches for the first semester node and extracts the
  /// year+department prefix from its name (e.g. "3INFO", "1STPI").
  static String? _extractDeptFromSemesters(List<dynamic> items) {
    for (final item in items) {
      if (item is! Map<String, dynamic> || item['name'] == null) continue;
      final name = item['name'].toString();
      if (_isSemesterName(name)) {
        final match = _deptFromSemRegex.firstMatch(name);
        if (match != null) return match.group(1)!.toUpperCase();
      } else if (item['details'] is List) {
        final found = _extractDeptFromSemesters(
          item['details'] as List<dynamic>,
        );
        if (found != null) return found;
      }
    }
    return null;
  }

  /// Returns the year+department prefix for a specific semester number.
  /// e.g. semester 5 in "3INFO-SEMESTRE5" → "3INFO".
  /// Falls back to the global getDepartmentName if the semester isn't found.
  static String getDepartmentForSemester(
    Map<String, dynamic> data,
    int semester,
  ) {
    try {
      if (data['details'] is! List) return getDepartmentName(data);
      final dept = _findDeptForSemester(
        data['details'] as List<dynamic>,
        semester,
      );
      return dept ?? getDepartmentName(data);
    } catch (_) {
      return getDepartmentName(data);
    }
  }

  /// Recursively finds the semester node matching [semesterNumber] and
  /// extracts the year+department prefix from its name.
  static String? _findDeptForSemester(List<dynamic> items, int semesterNumber) {
    for (final item in items) {
      if (item is! Map<String, dynamic> || item['name'] == null) continue;
      final name = item['name'].toString();
      if (_isSemesterName(name)) {
        final semMatch = semesterRegex.firstMatch(name);
        if (semMatch != null &&
            int.tryParse(semMatch.group(1) ?? '') == semesterNumber) {
          final deptMatch = _deptFromSemRegex.firstMatch(name);
          if (deptMatch != null) return deptMatch.group(1)!.toUpperCase();
        }
      } else if (item['details'] is List) {
        final found = _findDeptForSemester(
          item['details'] as List<dynamic>,
          semesterNumber,
        );
        if (found != null) return found;
      }
    }
    return null;
  }

  /// Return available semester numbers found in the JSON payload.
  /// Handles both flat (semesters at top) and nested (year → semesters) structures.
  static List<int> getAvailableSemesters(Map<String, dynamic> data) {
    try {
      if (data['details'] is! List) return [];

      final semesters = <int>{};
      _collectSemesters(data['details'] as List<dynamic>, semesters);

      final sorted = semesters.toList()..sort();
      if (kDebugMode) debugPrint('[Parser] Found semesters: $sorted');
      return sorted;
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[Parser] getAvailableSemesters failed: $e');
        debugPrint('[Parser] Stack: $st');
      }
      return [];
    }
  }

  /// Matches a semester label and captures its number, e.g. "SEMESTRE 5" → "5".
  /// Public so other parsers (e.g. CoefficientsService) reuse the one pattern.
  static final RegExp semesterRegex = RegExp(
    r'sem(?:estre)?[^a-zA-Z]*(\d+)',
    caseSensitive: false,
  );

  static bool _isSemesterName(String name) => semesterRegex.hasMatch(name);

  /// Recursively walks the tree collecting semester numbers.
  /// Stops recursing into a branch once a semester is found (semesters
  /// don't nest inside other semesters).
  static void _collectSemesters(List<dynamic> items, Set<int> out) {
    for (final item in items) {
      if (item is! Map<String, dynamic> || item['name'] == null) continue;
      final match = semesterRegex.firstMatch(item['name'].toString());
      if (match != null) {
        final n = int.tryParse(match.group(1) ?? '');
        if (n != null) out.add(n);
      } else if (item['details'] is List) {
        _collectSemesters(item['details'] as List<dynamic>, out);
      }
    }
  }

  /// Recursively finds the node whose name matches the given semester number.
  static Map<String, dynamic>? _findSemesterNode(
    List<dynamic> items,
    int semesterNumber,
  ) {
    for (final item in items) {
      if (item is! Map<String, dynamic> || item['name'] == null) continue;
      final name = item['name'].toString();
      if (_isSemesterName(name)) {
        final match = semesterRegex.firstMatch(name);
        if (match != null &&
            int.tryParse(match.group(1) ?? '') == semesterNumber) {
          return item;
        }
      } else if (item['details'] is List) {
        final found = _findSemesterNode(
          item['details'] as List<dynamic>,
          semesterNumber,
        );
        if (found != null) return found;
      }
    }
    return null;
  }

  /// Returns the semester-level score embedded in the JSON by the school,
  /// bypassing any manual recalculation. Returns null when the semester node
  /// is missing or carries no score field.
  static double? getSemesterAverage(
    Map<String, dynamic> data,
    int semesterNumber,
  ) {
    try {
      if (data['details'] is! List) return null;
      final semesterNode = _findSemesterNode(
        data['details'] as List<dynamic>,
        semesterNumber,
      );
      if (semesterNode == null) return null;
      return _extractAverage(semesterNode['score']);
    } catch (_) {
      return null;
    }
  }

  /// Extracts a score string from a field that may be either a bare String
  /// (legacy format) or a List (current mobinsapi format: ["16/20", "VAL"]).
  /// Returns null if the field is absent or not a recognised type.
  static String? _extractScore(dynamic field) {
    if (field is String) return field;
    if (field is List && field.isNotEmpty && field.first is String) {
      return field.first as String;
    }
    return null;
  }

  static double? _extractAverage(dynamic field) =>
      GradeUtils.parseDouble(_extractScore(field));

  /// Matches a validation status code such as "VAL", "VALCOMP", "ADM", "AJAC".
  static final RegExp _statusRegex = RegExp(r'^[A-Z]{2,}$');

  /// Extracts the validation status carried alongside the grade in the score
  /// list (e.g. ["13.818/20", "VAL"] → "VAL", ["VAL"] → "VAL"). Scans for the
  /// status code rather than assuming a fixed position, and returns null when
  /// none is present (the unit is still in progress).
  static String? _extractStatus(dynamic field) {
    if (field is! List) return null;
    for (final element in field) {
      if (element is String) {
        final s = element.trim();
        if (_statusRegex.hasMatch(s)) return s;
      }
    }
    return null;
  }

  static String _extractCoeff(dynamic field) {
    if (field is num) return field.toString();
    if (field is String) return field.trim();
    return '';
  }
}

/// Decodes a `{'ts': epochMs, <payloadKey>: ...}` cache envelope and returns the
/// payload under [payloadKey] when it is still within [ttl]. Returns null when
/// the string is unparseable, not an envelope, or expired — callers treat null
/// as a cache miss. The payload's own type is left to the caller to validate.
dynamic readTtlEnvelope(String raw, String payloadKey, Duration ttl) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) return null;
    if (!decoded.containsKey(payloadKey)) return null;
    final ts = (decoded['ts'] as num?)?.toInt() ?? 0;
    final age = DateTime.now().difference(
      DateTime.fromMillisecondsSinceEpoch(ts),
    );
    if (age > ttl) return null;
    return decoded[payloadKey];
  } catch (_) {
    return null;
  }
}

/// Wraps [payload] in a timestamped cache envelope (see [readTtlEnvelope]) and
/// returns the JSON string to persist.
String writeTtlEnvelope(String payloadKey, Object payload) => jsonEncode({
  'ts': DateTime.now().millisecondsSinceEpoch,
  payloadKey: payload,
});
