import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../constants.dart';
import '../services/coefficients_service.dart';

/// Fetches coefficients for a given department + semester + academic year
/// using the 3-tier fallback (local → Cloudflare → API).
/// Returns an empty map while loading or on failure (parser uses 1.0 fallback).
///
/// Not auto-disposed: once a semester's coefficients are fetched they stay
/// cached for the app session, so switching back to a previously viewed
/// semester doesn't re-trigger a loading flash with unweighted averages.
final coefficientsProvider =
    FutureProvider.family<Map<String, double>, SemesterParams>((
      ref,
      params,
    ) async {
      if (!isRealDepartment(params.department)) {
        return {};
      }
      return CoefficientsService.fetch(
        department: params.department,
        semester: params.semester,
        academicYear: params.academicYear,
      );
    });
