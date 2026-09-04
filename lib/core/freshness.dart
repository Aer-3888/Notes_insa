import 'module_cache.dart';

/// One vocabulary for every cached module. Schedule and weather both call
/// this so the same state never gets two different words.
String freshnessLabel(RefreshState state, DateTime? cachedAt) {
  final stamp = cachedAt == null
      ? ''
      : ' (${cachedAt.day}/${cachedAt.month} ${_hm(cachedAt)})';
  return switch (state) {
    RefreshState.fresh => 'À jour',
    RefreshState.refreshing => 'Actualisation…',
    RefreshState.failedOffline => 'Hors ligne$stamp',
    RefreshState.failedUpstream => 'Service indisponible$stamp',
  };
}

String _hm(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
