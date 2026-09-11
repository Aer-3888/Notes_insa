import 'package:flutter/foundation.dart';

import '../../core/time.dart';

/// A library Affluences publishes live attendance for. Two here: the INSA one
/// and the university one next door, which stays open four hours longer.
@immutable
class LibrarySite {
  const LibrarySite({
    required this.slug,
    required this.shortName,
    required this.name,
    required this.bookingUrl,
  });

  /// Affluences site identifier, the only thing the API needs.
  final String slug;
  final String shortName;
  final String name;

  /// Study room booking. Affluences runs it, the libraries only link to it.
  final String bookingUrl;
}

const List<LibrarySite> kLibrarySites = <LibrarySite>[
  LibrarySite(
    slug: 'biblinsa',
    shortName: 'Biblinsa',
    name: 'Bibliothèque de l’INSA',
    bookingUrl: 'https://affluences.com/fr/sites/biblinsa/reservation',
  ),
  LibrarySite(
    slug: 'bu-beaulieu-1',
    shortName: 'BU Beaulieu',
    name: 'BU Beaulieu · Université de Rennes',
    bookingUrl: 'https://affluences.com/fr/sites/bu-beaulieu-1/reservation',
  ),
];

LibrarySite? librarySiteFor(String slug) {
  for (final site in kLibrarySites) {
    if (site.slug == slug) return site;
  }
  return null;
}

/// How full the library is, in the four words a student needs. Derived from a
/// door counter, so it is a band and never a seat count.
enum LibraryCrowd {
  calm,
  busy,
  packed,
  closed,
  unknown;

  String get label => switch (this) {
    LibraryCrowd.calm => 'Calme',
    LibraryCrowd.busy => 'Fréquentée',
    LibraryCrowd.packed => 'Bondée',
    LibraryCrowd.closed => 'Fermée',
    LibraryCrowd.unknown => 'Affluence inconnue',
  };
}

enum LibraryTrend {
  increase,
  decrease,
  stable;

  static LibraryTrend parse(String? raw) => switch (raw) {
    'INCREASE' => LibraryTrend.increase,
    'DECREASE' => LibraryTrend.decrease,
    _ => LibraryTrend.stable,
  };
}

/// The next turn in today's curve, when there is one worth mentioning.
@immutable
class LibraryForecast {
  const LibraryForecast({
    required this.startsAt,
    required this.occupancy,
    required this.trend,
  });

  final DateTime startsAt;
  final int occupancy;
  final LibraryTrend trend;

  String? get hint => switch (trend) {
    LibraryTrend.increase => 'se remplit vers ${_hm(startsAt)}',
    LibraryTrend.decrease => 'plus calme après ${_hm(startsAt)}',
    LibraryTrend.stable => null,
  };

  Map<String, dynamic> toJson() => <String, dynamic>{
    'startsAtMs': startsAt.millisecondsSinceEpoch,
    'occupancy': occupancy,
    'trend': trend.name,
  };

  static LibraryForecast? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final startsAtMs = raw['startsAtMs'];
    final occupancy = raw['occupancy'];
    if (startsAtMs is! int || occupancy is! int) return null;
    return LibraryForecast(
      startsAt: campusFromEpochMs(startsAtMs),
      occupancy: occupancy,
      trend: LibraryTrend.values.firstWhere(
        (value) => value.name == raw['trend'],
        orElse: () => LibraryTrend.stable,
      ),
    );
  }
}

@immutable
class LibraryStatus {
  const LibraryStatus({
    required this.site,
    required this.isOpen,
    this.occupancy,
    this.statusLabel,
    this.openingAt,
    this.closingAt,
    this.notices = const <String>[],
    this.nextForecast,
  });

  final LibrarySite site;
  final bool isOpen;

  /// Percentage, 0-100. Null when the site publishes no counter.
  final int? occupancy;

  /// Already localised upstream: "Ferme à 18:00", "Ouvre à 9:00".
  final String? statusLabel;
  final DateTime? openingAt;
  final DateTime? closingAt;
  final List<String> notices;
  final LibraryForecast? nextForecast;

  LibraryCrowd get crowd {
    if (!isOpen) return LibraryCrowd.closed;
    final value = occupancy;
    if (value == null) return LibraryCrowd.unknown;
    if (value >= 75) return LibraryCrowd.packed;
    if (value >= 40) return LibraryCrowd.busy;
    return LibraryCrowd.calm;
  }

  String get occupancyLabel {
    final value = occupancy;
    if (value == null || !isOpen) return crowd.label;
    return '${crowd.label} · $value %';
  }

  /// Bar fill, or null when there is nothing honest to draw.
  double? get gauge {
    final value = occupancy;
    if (value == null || !isOpen) return null;
    return value / 100;
  }

  String? get forecastHint => isOpen ? nextForecast?.hint : null;

  /// Reads one `/app/v4/sites/{slug}/live-data` payload. [now] decides which
  /// forecast bucket is still ahead.
  static LibraryStatus fromLiveData(
    LibrarySite site,
    Map<String, dynamic> json, {
    required DateTime now,
  }) {
    final data = json['data'];
    final root = data is Map ? data : const <String, Object?>{};
    final rawStatus = root['status'];
    final status = rawStatus is Map ? rawStatus : const <String, Object?>{};

    final isOpen = status['isOpen'] == true;
    final closingText = _nonEmpty(status['closingText']);
    final openingText = _nonEmpty(status['openingText']);

    final attendance = root['liveAttendance'];
    final rawOccupancy = attendance is Map ? attendance['occupancy'] : null;
    final occupancy = rawOccupancy is num
        ? rawOccupancy.round().clamp(0, 100)
        : null;

    return LibraryStatus(
      site: site,
      isOpen: isOpen,
      occupancy: occupancy,
      statusLabel: isOpen
          ? closingText ?? openingText
          : openingText ?? closingText,
      openingAt: _instant(status['openingAt']),
      closingAt: _instant(status['closingAt']),
      notices: _notices(root['notices']),
      nextForecast: _nextForecast(root['todayForecasts'], now),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'slug': site.slug,
    'isOpen': isOpen,
    'occupancy': occupancy,
    'statusLabel': statusLabel,
    'openingAtMs': openingAt?.millisecondsSinceEpoch,
    'closingAtMs': closingAt?.millisecondsSinceEpoch,
    'notices': notices,
    'nextForecast': nextForecast?.toJson(),
  };

  /// Null when the cache holds a site this build no longer knows about.
  static LibraryStatus? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final site = librarySiteFor(raw['slug'] as String? ?? '');
    if (site == null) return null;
    final occupancy = raw['occupancy'];
    final openingAtMs = raw['openingAtMs'];
    final closingAtMs = raw['closingAtMs'];
    final notices = raw['notices'];
    return LibraryStatus(
      site: site,
      isOpen: raw['isOpen'] == true,
      occupancy: occupancy is int ? occupancy : null,
      statusLabel: _nonEmpty(raw['statusLabel']),
      openingAt: openingAtMs is int ? campusFromEpochMs(openingAtMs) : null,
      closingAt: closingAtMs is int ? campusFromEpochMs(closingAtMs) : null,
      notices: notices is List
          ? notices.whereType<String>().toList(growable: false)
          : const <String>[],
      nextForecast: LibraryForecast.fromJson(raw['nextForecast']),
    );
  }
}

/// The API sends wall-clock times with no offset, so they only become instants
/// once reinterpreted on campus.
DateTime? _instant(Object? raw) {
  if (raw is! String || raw.isEmpty) return null;
  final parsed = DateTime.tryParse(raw);
  return parsed == null ? null : campusInstant(parsed);
}

String? _nonEmpty(Object? raw) =>
    raw is String && raw.trim().isNotEmpty ? raw.trim() : null;

/// Always empty in practice. Shape unconfirmed, so both a bare string and the
/// usual title-carrying object are accepted and anything else is dropped.
List<String> _notices(Object? raw) {
  if (raw is! List) return const <String>[];
  final notices = <String>[];
  for (final item in raw) {
    if (item is String) {
      final text = _nonEmpty(item);
      if (text != null) notices.add(text);
      continue;
    }
    if (item is! Map) continue;
    for (final key in const <String>['title', 'message', 'text', 'content']) {
      final text = _nonEmpty(item[key]);
      if (text != null) {
        notices.add(text);
        break;
      }
    }
  }
  return List<String>.unmodifiable(notices);
}

LibraryForecast? _nextForecast(Object? raw, DateTime now) {
  if (raw is! List) return null;
  for (final item in raw) {
    if (item is! Map) continue;
    final range = item['hourRange'];
    if (range is! List || range.isEmpty) continue;
    final startsAt = _instant(range.first);
    if (startsAt == null || !startsAt.isAfter(now)) continue;
    final trend = LibraryTrend.parse(item['occupancyEvolution'] as String?);
    if (trend == LibraryTrend.stable) continue;
    final occupancy = item['occupancy'];
    return LibraryForecast(
      startsAt: startsAt,
      occupancy: occupancy is num ? occupancy.round().clamp(0, 100) : 0,
      trend: trend,
    );
  }
  return null;
}

String _hm(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
