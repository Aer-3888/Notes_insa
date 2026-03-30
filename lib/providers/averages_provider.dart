import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models.dart';
import '../services/averages_service.dart';

typedef AveragesParams = ({String department, int semester});

/// Fetches class averages for a given department + semester.
/// Returns [] immediately when department is not yet known.
/// Throws on network/server errors so the UI can show a retry state.
final averagesProvider =
    FutureProvider.family<List<SubjectAverage>, AveragesParams>((
      ref,
      params,
    ) async {
      if (params.department.isEmpty || params.department == 'Etudiant') {
        return [];
      }
      return AveragesService.fetchAverages(
        department: params.department,
        semester: params.semester,
      );
    });
