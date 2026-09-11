import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../core/time.dart';
import 'library_site.dart';

/// How long to stay quiet after a 429 that carries no Retry-After.
const Duration kLibraryDefaultCooldown = Duration(minutes: 30);

/// Affluences answered, but not with data. Distinct from a transport failure,
/// which is what tells the card to say "hors ligne" instead.
class LibraryUnavailable implements Exception {
  const LibraryUnavailable(this.statusCode);

  final int statusCode;

  @override
  String toString() => 'LibraryUnavailable(HTTP $statusCode)';
}

/// Affluences asked us to back off. The provider persists the delay so a
/// restart does not walk straight back into the limit.
class LibraryRateLimited implements Exception {
  const LibraryRateLimited(this.retryAfter);

  final Duration retryAfter;

  @override
  String toString() => 'LibraryRateLimited(${retryAfter.inSeconds}s)';
}

/// Reads live library attendance from the public Affluences endpoint. No key,
/// no account: the same data their website shows.
///
/// Deliberately not [ResilientHttp]: a third party with no published rate limit
/// gets one attempt, and a failed refresh simply keeps the cached card.
class LibraryService {
  const LibraryService({http.Client? client}) : _client = client;

  final http.Client? _client;

  static const Duration _timeout = Duration(seconds: 10);

  static Uri endpointFor(String slug) => Uri.parse(
    'https://api.affluences.com/app/v4/sites/$slug/live-data?lang=fr',
  );

  /// Reads [sites] one after another. A site that fails is left out rather
  /// than failing the others; nothing is read at all once a 429 arrives.
  Future<List<LibraryStatus>> fetch({
    List<LibrarySite> sites = kLibrarySites,
    DateTime? now,
  }) async {
    final client = _client ?? http.Client();
    final at = now ?? campusNow();
    final statuses = <LibraryStatus>[];
    Object? lastError;

    try {
      for (final site in sites) {
        try {
          statuses.add(await _fetchSite(client, site, at));
        } on LibraryRateLimited {
          rethrow;
        } catch (error) {
          lastError = error;
        }
      }
    } finally {
      if (_client == null) client.close();
    }

    if (statuses.isEmpty) {
      throw lastError ?? const LibraryUnavailable(0);
    }
    return List<LibraryStatus>.unmodifiable(statuses);
  }

  Future<LibraryStatus> _fetchSite(
    http.Client client,
    LibrarySite site,
    DateTime now,
  ) async {
    final endpoint = endpointFor(site.slug);
    final response = await client
        .get(
          endpoint,
          headers: const <String, String>{'Accept': 'application/json'},
        )
        .timeout(_timeout);

    if (response.statusCode == 429) {
      throw LibraryRateLimited(
        parseRetryAfter(response.headers['retry-after']),
      );
    }
    if (response.statusCode != 200) {
      throw LibraryUnavailable(response.statusCode);
    }

    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map || decoded['data'] is! Map) {
      throw const FormatException('Affluences live-data payload missing');
    }
    return LibraryStatus.fromLiveData(
      site,
      Map<String, dynamic>.from(decoded),
      now: now,
    );
  }
}

/// Retry-After in either allowed form, delta-seconds or an HTTP-date.
Duration parseRetryAfter(String? header) {
  final raw = header?.trim();
  if (raw == null || raw.isEmpty) return kLibraryDefaultCooldown;

  final seconds = int.tryParse(raw);
  if (seconds != null) {
    return seconds <= 0 ? kLibraryDefaultCooldown : Duration(seconds: seconds);
  }
  try {
    final delay = HttpDate.parse(raw).difference(DateTime.now().toUtc());
    if (delay > Duration.zero) return delay;
  } catch (_) {
    // Neither form; fall back to the long cooldown.
  }
  return kLibraryDefaultCooldown;
}
