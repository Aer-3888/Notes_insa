import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models.dart';
import '../data.dart';
import 'grades_provider.dart';

/// Provider for selected semester (reactive state)
final selectedSemesterProvider = StateProvider<int>((ref) => 5);

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
  final selectedSemester = ref.watch(selectedSemesterProvider);

  try {
    return JsonCurriculumParser.parseSemester(jsonString, selectedSemester);
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
