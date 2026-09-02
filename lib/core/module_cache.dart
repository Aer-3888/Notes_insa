import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// How a cached payload's most recent refresh attempt ended. A timestamp alone
/// cannot tell "you are offline" apart from "the upstream service is broken",
/// and those need different copy.
enum RefreshState { fresh, refreshing, failedOffline, failedUpstream }

class CachedEntry<T> {
  const CachedEntry({
    this.data,
    this.cachedAt,
    this.upstreamSyncedAt,
    this.refreshState = RefreshState.fresh,
  });

  final T? data;
  final DateTime? cachedAt;

  /// Freshness as reported by the upstream service, when it exposes one.
  final String? upstreamSyncedAt;
  final RefreshState refreshState;

  bool get isEmpty => data == null;

  CachedEntry<T> withState(RefreshState state) => CachedEntry<T>(
    data: data,
    cachedAt: cachedAt,
    upstreamSyncedAt: upstreamSyncedAt,
    refreshState: state,
  );
}

/// Non-sensitive per-module payload cache, one JSON file per module.
///
/// Never store grades, credentials or tokens here. Those belong in
/// flutter_secure_storage, and test/architecture_test.dart enforces it.
class ModuleCache {
  const ModuleCache(this._root);

  final Directory _root;

  static Future<ModuleCache> open() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory('${support.path}/cache');
    await dir.create(recursive: true);
    return ModuleCache(dir);
  }

  File _fileFor(String moduleId) => File('${_root.path}/$moduleId.json');

  Future<CachedEntry<Map<String, dynamic>>> read(
    String moduleId, {
    required int schemaVersion,
  }) async {
    final file = _fileFor(moduleId);
    if (!file.existsSync()) return const CachedEntry<Map<String, dynamic>>();
    try {
      final raw = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      if (raw['schemaVersion'] != schemaVersion) {
        return const CachedEntry<Map<String, dynamic>>();
      }
      return CachedEntry<Map<String, dynamic>>(
        data: raw['data'] as Map<String, dynamic>,
        cachedAt: DateTime.fromMillisecondsSinceEpoch(raw['cachedAt'] as int),
        upstreamSyncedAt: raw['upstreamSyncedAt'] as String?,
      );
    } catch (_) {
      // A cache written by an older build, or a truncated write. Treat a
      // damaged cache as no cache; it will be refetched.
      return const CachedEntry<Map<String, dynamic>>();
    }
  }

  Future<void> write(
    String moduleId, {
    required int schemaVersion,
    required Map<String, dynamic> data,
    String? upstreamSyncedAt,
  }) async {
    final payload = jsonEncode(<String, dynamic>{
      'schemaVersion': schemaVersion,
      'cachedAt': DateTime.now().millisecondsSinceEpoch,
      'upstreamSyncedAt': upstreamSyncedAt,
      'data': data,
    });
    // Write to a sibling then rename, so a crash mid-write cannot leave a
    // half-written file where the reader expects valid JSON.
    final tmp = File('${_root.path}/$moduleId.json.tmp');
    await tmp.writeAsString(payload, flush: true);
    await tmp.rename(_fileFor(moduleId).path);
  }

  Future<void> clear(String moduleId) async {
    final file = _fileFor(moduleId);
    if (file.existsSync()) await file.delete();
  }
}
