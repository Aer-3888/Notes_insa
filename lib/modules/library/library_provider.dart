import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../core/module_cache.dart';
import '../../core/module_cache_provider.dart';
import '../../core/time.dart';
import 'library_service.dart';
import 'library_site.dart';

const String kLibraryModuleId = 'bu_affluence';
const int kLibrarySchemaVersion = 1;

/// Affluences publishes no rate limit and no cache headers, so the budget is
/// ours to keep. Below this age the cache is served without any request, which
/// makes reopening the app free.
const Duration kLibraryMinRefreshInterval = Duration(minutes: 10);

final libraryServiceProvider = Provider<LibraryService>(
  (ref) => const LibraryService(),
);

/// Bumped by the card's refresh button. Only a tap gets past
/// [kLibraryMinRefreshInterval]; nothing gets past a 429 cooldown.
class LibraryRefreshTick extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state = state + 1;
}

final libraryRefreshTickProvider = NotifierProvider<LibraryRefreshTick, int>(
  LibraryRefreshTick.new,
);

/// Live attendance for both libraries, cached on disk between launches.
///
/// Not auto-dispose, so the hub scrolling the card in and out does not refetch:
/// one refresh per app launch is the normal cost, two requests in total. There
/// is deliberately no polling timer here, unlike the laundry screen.
final libraryStatusProvider = StreamProvider<CachedEntry<List<LibraryStatus>>>((
  ref,
) async* {
  final forced = ref.watch(libraryRefreshTickProvider) > 0;
  final cache = await ref.watch(moduleCacheProvider.future);
  final stored = await cache.read(
    kLibraryModuleId,
    schemaVersion: kLibrarySchemaVersion,
  );
  final now = campusNow();
  final snapshot = _Snapshot.fromCache(stored.data);

  final previous = snapshot.isEmpty
      ? null
      : CachedEntry<List<LibraryStatus>>(
          data: snapshot.sites,
          cachedAt: snapshot.syncedAt,
          refreshState: RefreshState.refreshing,
        );

  if (previous != null && snapshot.canWait(now, forced: forced)) {
    yield previous.withState(RefreshState.fresh);
    return;
  }
  if (previous != null) yield previous;

  try {
    final fresh = await ref.read(libraryServiceProvider).fetch(now: now);
    await _write(cache, sites: fresh, syncedAt: now);
    yield CachedEntry<List<LibraryStatus>>(data: fresh, cachedAt: now);
  } on LibraryRateLimited catch (limit) {
    // Keep the snapshot and its real age; only the cooldown is new.
    if (!snapshot.isEmpty) {
      await _write(
        cache,
        sites: snapshot.sites,
        syncedAt: snapshot.syncedAt ?? now,
        cooldownUntil: now.add(limit.retryAfter),
      );
    }
    yield previous?.withState(RefreshState.failedUpstream) ??
        const CachedEntry<List<LibraryStatus>>(
          refreshState: RefreshState.failedUpstream,
        );
  } catch (error) {
    final state = error is SocketException || error is http.ClientException
        ? RefreshState.failedOffline
        : RefreshState.failedUpstream;
    yield previous?.withState(state) ??
        CachedEntry<List<LibraryStatus>>(refreshState: state);
  }
});

Future<void> _write(
  ModuleCache cache, {
  required List<LibraryStatus> sites,
  required DateTime syncedAt,
  DateTime? cooldownUntil,
}) => cache.write(
  kLibraryModuleId,
  schemaVersion: kLibrarySchemaVersion,
  data: <String, dynamic>{
    'syncedAtMs': syncedAt.millisecondsSinceEpoch,
    'cooldownUntilMs': cooldownUntil?.millisecondsSinceEpoch,
    'sites': <Map<String, dynamic>>[for (final site in sites) site.toJson()],
  },
);

/// What the cache holds, and whether it is reason enough to stay quiet.
///
/// The snapshot carries its own timestamp rather than leaning on the cache
/// file's, so writing a cooldown does not make stale data look fresh.
class _Snapshot {
  const _Snapshot({required this.sites, this.syncedAt, this.cooldownUntil});

  final List<LibraryStatus> sites;
  final DateTime? syncedAt;
  final DateTime? cooldownUntil;

  bool get isEmpty => sites.isEmpty;

  static _Snapshot fromCache(Map<String, dynamic>? data) {
    if (data == null) return const _Snapshot(sites: <LibraryStatus>[]);
    final rawSites = data['sites'];
    final syncedAtMs = data['syncedAtMs'];
    final cooldownUntilMs = data['cooldownUntilMs'];
    return _Snapshot(
      sites: rawSites is List
          ? rawSites
                .map(LibraryStatus.fromJson)
                .whereType<LibraryStatus>()
                .toList(growable: false)
          : const <LibraryStatus>[],
      syncedAt: syncedAtMs is int ? campusFromEpochMs(syncedAtMs) : null,
      cooldownUntil: cooldownUntilMs is int
          ? campusFromEpochMs(cooldownUntilMs)
          : null,
    );
  }

  bool canWait(DateTime now, {required bool forced}) {
    final cooldown = cooldownUntil;
    if (cooldown != null && now.isBefore(cooldown)) return true;
    if (forced) return false;

    final syncedAt = this.syncedAt;
    if (syncedAt != null &&
        now.difference(syncedAt) < kLibraryMinRefreshInterval) {
      return true;
    }
    // A closed library reads 0 % until it reopens; there is nothing to fetch.
    return sites.every(
      (site) =>
          !site.isOpen &&
          site.openingAt != null &&
          site.openingAt!.isAfter(now),
    );
  }
}
