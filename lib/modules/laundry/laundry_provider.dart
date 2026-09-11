import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'laundry_model.dart';
import 'laundry_service.dart';

final laundryServiceProvider = Provider<LaundryService>(
  (ref) => const LaundryService(),
);

/// Fetches once per watch. The screen drives adaptive refresh by invalidating
/// this; auto-dispose stops all work when nobody is looking. During a refresh
/// Riverpod keeps the previous value, so the view never flickers to a spinner.
final laundryProvider = FutureProvider.autoDispose<LaundryStatus>(
  (ref) => ref.watch(laundryServiceProvider).fetch(),
);
