import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models.dart';
import '../data.dart';
import '../services/averages_service.dart';
import 'coefficients_provider.dart';
import 'grades_provider.dart';

/// Single memoized decode of the grades payload. Returns null when there is no
/// usable data — either nothing loaded yet (`{}`/empty) or a decode failure
/// (corrupt/changed schema). A non-null map is structurally valid (possibly
/// empty), so callers can tell "corrupt" apart from "loaded but empty".
///
/// Every downstream parser provider reads this instead of decoding the JSON
/// string itself, so the payload is decoded once per state change rather than
/// once per provider.
final decodedGradesProvider = Provider<Map<String, dynamic>?>((ref) {
  final jsonString = ref.watch(gradesProvider.select((s) => s.jsonData));
  return JsonCurriculumParser.tryDecode(jsonString);
});

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
  final data = ref.watch(decodedGradesProvider);
  final semester = ref.watch(effectiveSemesterProvider);
  if (data == null) return 'Etudiant';

  try {
    if (semester == null) {
      return JsonCurriculumParser.getDepartmentName(data);
    }
    return JsonCurriculumParser.getDepartmentForSemester(data, semester);
  } catch (_) {
    return 'Etudiant';
  }
});

/// Computed provider for curriculum based on selected semester.
/// Watches coefficients and re-parses when they arrive. While coefficients
/// are loading, parses with defaults (1.0) so the UI is never blocked.
final curriculumProvider = Provider<List<TeachingUnit>>((ref) {
  final data = ref.watch(decodedGradesProvider);
  final semester = ref.watch(effectiveSemesterProvider);
  if (data == null || semester == null) return [];

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
      data,
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
  final data = ref.watch(decodedGradesProvider);
  final semester = ref.watch(effectiveSemesterProvider);
  if (data == null || semester == null) return null;
  return JsonCurriculumParser.getSemesterAverage(data, semester);
});

/// Computed provider for semester average.
/// Prefers the official score already in the JSON; falls back to the
/// UE-coefficient-weighted calculation when the data doesn't carry it.
final semesterAverageProvider = Provider<double?>((ref) {
  final fromData = ref.watch(_semesterAverageFromDataProvider);
  if (fromData != null) return fromData;

  final curriculum = ref.watch(curriculumProvider);
  return weightedAverage(curriculum, (u) => u.average, (u) => u.coeff);
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

/// True when the displayed semester average is locally estimated because the
/// grades payload did not provide an official semester score.
final semesterAverageProvisionalProvider = Provider<bool>((ref) {
  if (ref.watch(semesterAverageProvider) == null) return false;
  // The school's own pre-computed value is authoritative, not estimated.
  if (ref.watch(_semesterAverageFromDataProvider) != null) return false;
  return true;
});

/// Computed provider for available semesters from grades data
/// Caches result and only recomputes when jsonData changes
final availableSemestersProvider = Provider<List<int>>((ref) {
  final data = ref.watch(decodedGradesProvider);
  if (data == null) return [];

  try {
    return JsonCurriculumParser.getAvailableSemesters(data);
  } catch (_) {
    return [];
  }
});

/// Prefetches coefficients for every available semester as soon as grades
/// data is available. Coefficients are cached per session (see
/// [coefficientsProvider]), so warming them all up here means switching to a
/// semester later finds its coefficients already loaded instead of briefly
/// falling back to unweighted (1.0) averages.
final coefficientsPrefetchProvider = Provider<void>((ref) {
  final data = ref.watch(decodedGradesProvider);
  final available = ref.watch(availableSemestersProvider);
  if (data == null || available.isEmpty) return;

  final baseline = ref.watch(
    gradesProvider.select((s) => s.academicYearBaseline),
  );
  final maxSemester = available.last;
  for (final semester in available) {
    final department = JsonCurriculumParser.getDepartmentForSemester(
      data,
      semester,
    );
    final academicYear = AveragesService.academicYearForSemester(
      semester,
      maxSemester,
      baseline ?? AveragesService.currentAcademicYear(),
    );
    ref.watch(
      coefficientsProvider((
        department: department,
        semester: semester,
        academicYear: academicYear,
      )),
    );
  }
});

/// Academic year for the currently selected semester.
final academicYearProvider = Provider<String>((ref) {
  final semester = ref.watch(effectiveSemesterProvider);
  final available = ref.watch(availableSemestersProvider);
  final baseline =
      ref.watch(gradesProvider.select((s) => s.academicYearBaseline)) ??
      AveragesService.currentAcademicYear();
  if (semester == null || available.isEmpty) {
    return baseline;
  }
  return AveragesService.academicYearForSemester(
    semester,
    available.last,
    baseline,
  );
});
