import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models.dart';
import '../data.dart';
import '../services/averages_service.dart';
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

/// Computed provider for department name from grades data
/// Caches result and only recomputes when jsonData changes
final departmentNameProvider = Provider<String>((ref) {
  final gradesState = ref.watch(gradesProvider);
  final jsonString = gradesState.jsonData;

  try {
    return JsonCurriculumParser.getDepartmentName(jsonString);
  } catch (_) {
    return 'Etudiant';
  }
});

/// Computed provider for curriculum based on selected semester
/// Caches parsed curriculum and only recomputes when grades or semester changes
final curriculumProvider = Provider<List<TeachingUnit>>((ref) {
  final gradesState = ref.watch(gradesProvider);
  final jsonString = gradesState.jsonData;
  final semester = ref.watch(effectiveSemesterProvider);
  if (semester == null) return [];

  try {
    return JsonCurriculumParser.parseSemester(jsonString, semester);
  } catch (_) {
    return [];
  }
});

/// Computed provider for semester average
/// Caches calculation and only recomputes when curriculum changes
final semesterAverageProvider = Provider<double?>((ref) {
  final curriculum = ref.watch(curriculumProvider);

  double totalSemScore = 0;
  double totalSemCoeff = 0;

  for (var unit in curriculum) {
    for (var sub in unit.subjects) {
      if (sub.average != null) {
        totalSemScore += sub.average! * sub.coeff;
        totalSemCoeff += sub.coeff;
      }
    }
  }

  return (totalSemCoeff > 0) ? totalSemScore / totalSemCoeff : null;
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
