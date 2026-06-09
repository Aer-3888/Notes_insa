import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models.dart';
import '../data.dart';
import '../services/averages_service.dart';
import 'coefficients_provider.dart';
import 'grades_provider.dart';

/// Raw semester selection — -1 is the sentinel for "not explicitly chosen".
final selectedSemesterProvider = StateProvider<int>((ref) => -1);

/// Effective semester: resolves the raw selection against what is actually
/// available in the current grades payload. Falls back to the last (most
/// recent) semester when the raw selection is unset or no longer present.
/// Returns null when no grades have been loaded yet.
final effectiveSemesterProvider = Provider<int?>((ref) {
  final raw = ref.watch(selectedSemesterProvider);
  final available = ref.watch(availableSemestersProvider);
  if (available.isEmpty) return null;
  if (raw != -1 && available.contains(raw)) return raw;
  return available.last;
});

/// Department name for the currently selected semester (e.g. "3INFO", "1STPI").
/// Per-semester because a student may belong to different departments across years.
final departmentNameProvider = Provider<String>((ref) {
  final gradesState = ref.watch(gradesProvider);
  final jsonString = gradesState.jsonData;
  final semester = ref.watch(effectiveSemesterProvider);

  try {
    if (semester == null) {
      return JsonCurriculumParser.getDepartmentName(jsonString);
    }
    return JsonCurriculumParser.getDepartmentForSemester(jsonString, semester);
  } catch (_) {
    return 'Etudiant';
  }
});

/// Computed provider for curriculum based on selected semester.
/// Watches coefficients and re-parses when they arrive. While coefficients
/// are loading, parses with defaults (1.0) so the UI is never blocked.
final curriculumProvider = Provider<List<TeachingUnit>>((ref) {
  final gradesState = ref.watch(gradesProvider);
  final jsonString = gradesState.jsonData;
  final semester = ref.watch(effectiveSemesterProvider);
  if (semester == null) return [];

  final department = ref.watch(departmentNameProvider);
  final academicYear = ref.watch(academicYearProvider);

  final coeffsAsync = ref.watch(
    coefficientsProvider((
      department: department,
      semester: semester,
      academicYear: academicYear,
    )),
  );

  final coefficients = coeffsAsync.when(
    data: (data) => data,
    loading: () => <String, double>{},
    error: (e, _) {
      if (kDebugMode) debugPrint('[Dashboard] Coefficients failed: $e');
      return <String, double>{};
    },
  );

  try {
    return JsonCurriculumParser.parseSemester(
      jsonString,
      semester,
      coefficients: coefficients.isEmpty ? null : coefficients,
    );
  } catch (_) {
    return [];
  }
});

/// The semester average embedded directly in the grades JSON by the school.
/// Returns null when the data does not carry a pre-computed score for this
/// semester (older payloads or semesters still in progress may omit it).
final _semesterAverageFromDataProvider = Provider<double?>((ref) {
  final semester = ref.watch(effectiveSemesterProvider);
  if (semester == null) return null;
  return JsonCurriculumParser.getSemesterAverage(
    ref.watch(gradesProvider).jsonData,
    semester,
  );
});

/// Computed provider for semester average.
/// Prefers the official score already in the JSON; falls back to the
/// UE-coefficient-weighted calculation when the data doesn't carry it.
final semesterAverageProvider = Provider<double?>((ref) {
  final fromData = ref.watch(_semesterAverageFromDataProvider);
  if (fromData != null) return fromData;

  final curriculum = ref.watch(curriculumProvider);

  double totalSemScore = 0;
  double totalSemCoeff = 0;

  for (var unit in curriculum) {
    final ueAvg = unit.average;
    if (ueAvg != null) {
      totalSemScore += ueAvg * unit.coeff;
      totalSemCoeff += unit.coeff;
    }
  }

  return (totalSemCoeff > 0) ? totalSemScore / totalSemCoeff : null;
});

/// True when real coefficients are loaded for the current semester. When false,
/// the curriculum parser falls back to 1.0 for every coefficient, so averages
/// are unweighted (and therefore provisional).
final coefficientsReadyProvider = Provider<bool>((ref) {
  final semester = ref.watch(effectiveSemesterProvider);
  if (semester == null) return false;
  final department = ref.watch(departmentNameProvider);
  final academicYear = ref.watch(academicYearProvider);
  final coeffsAsync = ref.watch(
    coefficientsProvider((
      department: department,
      semester: semester,
      academicYear: academicYear,
    )),
  );
  return coeffsAsync.maybeWhen(data: (d) => d.isNotEmpty, orElse: () => false);
});

/// True when the displayed semester average is unweighted (coefficients missing)
/// so the UI can label it as provisional.
final semesterAverageProvisionalProvider = Provider<bool>((ref) {
  if (ref.watch(semesterAverageProvider) == null) return false;
  // The school's own pre-computed value is authoritative — never provisional.
  if (ref.watch(_semesterAverageFromDataProvider) != null) return false;
  return !ref.watch(coefficientsReadyProvider);
});

/// Computed provider for available semesters from grades data
/// Caches result and only recomputes when jsonData changes
final availableSemestersProvider = Provider<List<int>>((ref) {
  final gradesState = ref.watch(gradesProvider);
  final jsonString = gradesState.jsonData;

  try {
    return JsonCurriculumParser.getAvailableSemesters(jsonString);
  } catch (_) {
    return [];
  }
});

/// Academic year for the currently selected semester.
final academicYearProvider = Provider<String>((ref) {
  final semester = ref.watch(effectiveSemesterProvider);
  final available = ref.watch(availableSemestersProvider);
  if (semester == null || available.isEmpty) {
    return AveragesService.currentAcademicYear();
  }
  return AveragesService.academicYearForSemester(semester, available.last);
});
