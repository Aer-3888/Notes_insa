import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'module_cache.dart';

/// Shared across every module, so it lives in core rather than in whichever
/// module happened to need it first.
final moduleCacheProvider = FutureProvider<ModuleCache>(
  (ref) => ModuleCache.open(),
);
