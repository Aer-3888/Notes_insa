import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/coefficients_service.dart';

typedef CoeffParams = ({String department, int semester, String academicYear});

/// Fetches coefficients for a given department + semester + academic year
/// using the 3-tier fallback (local → Cloudflare → API).
/// Returns an empty map while loading or on failure (parser uses 1.0 fallback).
final coefficientsProvider =
    FutureProvider.family<Map<String, double>, CoeffParams>((
      ref,
      params,
    ) async {
      if (params.department.isEmpty || params.department == 'Etudiant') {
        return {};
      }
      return CoefficientsService.fetch(
        department: params.department,
        semester: params.semester,
        academicYear: params.academicYear,
      );
    });
