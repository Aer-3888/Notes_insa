import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../constants.dart';
import '../models.dart';
import '../services/averages_service.dart';

/// Fetches class averages for a given department + semester + academic year.
/// Returns [] immediately when department is not yet known.
/// Throws on network/server errors so the UI can show a retry state.
///
/// Not auto-disposed (mirrors [coefficientsProvider]): once a semester's
/// averages are fetched they stay cached for the session, so leaving and
/// returning to the dashboard or reopening a UE sheet doesn't re-trigger a
/// network fetch and loading flicker.
final averagesProvider =
    FutureProvider.family<List<SubjectAverage>, SemesterParams>((
      ref,
      params,
    ) async {
      if (!isRealDepartment(params.department)) {
        return [];
      }
      return AveragesService.fetchAverages(
        department: params.department,
        semester: params.semester,
        academicYear: params.academicYear,
      );
    });
