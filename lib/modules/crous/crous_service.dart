import 'dart:convert';

import 'package:http/http.dart' as http;

import 'crous_restaurant.dart';

class CrousService {
  const CrousService({this._client});

  final http.Client? _client;

  /// Official CNOUS/CROUS Mobile feed. Region 24 is Rennes Bretagne.
  static final Uri endpoint = Uri.parse(
    'https://webservices-v2.crous-mobile.fr/ws/v1/regions/24/restaurants',
  );

  static List<CrousRestaurant> get fallbackNearby =>
      List<CrousRestaurant>.unmodifiable(
        _nearbyRestaurants.map((definition) => definition.fallback()),
      );

  Future<List<CrousRestaurant>> fetch() async {
    final client = _client ?? http.Client();
    try {
      final response = await client
          .get(endpoint)
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        throw http.ClientException('HTTP ${response.statusCode}', endpoint);
      }
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! List) {
        throw const FormatException('CROUS restaurant list missing');
      }

      final restaurants = <CrousRestaurant>[];
      for (final definition in _nearbyRestaurants) {
        Map<String, dynamic>? match;
        for (final item in decoded) {
          if (item is! Map) continue;
          final candidate = Map<String, dynamic>.from(item);
          if (candidate['title'] == definition.apiTitle) {
            match = candidate;
            break;
          }
        }
        if (match == null) {
          throw FormatException(
            '${definition.apiTitle} missing from CROUS feed',
          );
        }
        restaurants.add(_parse(match, definition));
      }
      return List<CrousRestaurant>.unmodifiable(restaurants);
    } finally {
      if (_client == null) client.close();
    }
  }

  CrousRestaurant _parse(
    Map<String, dynamic> json,
    _RestaurantDefinition definition,
  ) {
    final infos = json['infos'] as String? ?? '';
    final opening = json['opening'] as String?;
    final lunchHours = _serviceHours(infos, 'MIDI') ?? definition.fallbackLunch;
    final lunchDays = _serviceDays(opening, 1);
    final dinnerHours =
        _serviceHours(infos, 'SOIR') ?? definition.fallbackDinner;
    final dinnerDays = _serviceDays(opening, 2);
    final id = json['id'];
    if (id is! num) throw const FormatException('CROUS restaurant id missing');

    return CrousRestaurant(
      id: id.toInt(),
      name: definition.displayName,
      shortName: definition.shortName,
      mapCode: definition.mapCode,
      officialUrl: definition.officialUrl,
      declaredClosed: json['closing'].toString() == '1',
      openingPeriods: <CrousOpeningPeriod>[
        CrousOpeningPeriod(
          days: lunchDays.isEmpty ? definition.fallbackLunchDays : lunchDays,
          opensAtMinute: lunchHours.$1,
          closesAtMinute: lunchHours.$2,
        ),
        if (dinnerHours != null)
          CrousOpeningPeriod(
            days: dinnerDays.isEmpty
                ? definition.fallbackDinnerDays
                : dinnerDays,
            opensAtMinute: dinnerHours.$1,
            closesAtMinute: dinnerHours.$2,
          ),
      ],
      syncedAt: DateTime.tryParse(json['lastSyncAt'] as String? ?? ''),
    );
  }

  Set<int> _serviceDays(String? raw, int flagIndex) {
    if (raw == null) return const <int>{};
    final values = raw.split(',');
    if (values.length != 7) return const <int>{};
    return <int>{
      for (var index = 0; index < values.length; index++)
        if (values[index].length > flagIndex && values[index][flagIndex] == '1')
          index + 1,
    };
  }

  (int, int)? _serviceHours(String html, String service) {
    final match = RegExp(
      '$service\\s*:\\s*(\\d{1,2})h\\s*(\\d{0,2})\\s*[-–à]\\s*'
      r'(\d{1,2})h\s*(\d{0,2})',
      caseSensitive: false,
    ).firstMatch(html);
    if (match == null) return null;

    int minute(String hour, String? minutes) {
      final minuteText = minutes == null || minutes.isEmpty ? '0' : minutes;
      return int.parse(hour) * 60 + int.parse(minuteText);
    }

    final opens = minute(match.group(1)!, match.group(2));
    final closes = minute(match.group(3)!, match.group(4));
    if (opens >= closes || closes > 24 * 60) return null;
    return (opens, closes);
  }
}

class _RestaurantDefinition {
  const _RestaurantDefinition({
    required this.id,
    required this.apiTitle,
    required this.displayName,
    required this.shortName,
    required this.mapCode,
    required this.officialUrl,
    required this.fallbackLunchDays,
    required this.fallbackLunch,
    this.fallbackDinnerDays = const <int>{},
    this.fallbackDinner,
  });

  final int id;
  final String apiTitle;
  final String displayName;
  final String shortName;
  final String mapCode;
  final String officialUrl;
  final Set<int> fallbackLunchDays;
  final (int, int) fallbackLunch;
  final Set<int> fallbackDinnerDays;
  final (int, int)? fallbackDinner;

  CrousRestaurant fallback() => CrousRestaurant(
    id: id,
    name: displayName,
    shortName: shortName,
    mapCode: mapCode,
    officialUrl: officialUrl,
    declaredClosed: false,
    openingPeriods: <CrousOpeningPeriod>[
      CrousOpeningPeriod(
        days: fallbackLunchDays,
        opensAtMinute: fallbackLunch.$1,
        closesAtMinute: fallbackLunch.$2,
      ),
      if (fallbackDinner case final dinner?)
        CrousOpeningPeriod(
          days: fallbackDinnerDays,
          opensAtMinute: dinner.$1,
          closesAtMinute: dinner.$2,
        ),
    ],
  );
}

const _weekdays = <int>{
  DateTime.monday,
  DateTime.tuesday,
  DateTime.wednesday,
  DateTime.thursday,
  DateTime.friday,
};

const _mondayToThursday = <int>{
  DateTime.monday,
  DateTime.tuesday,
  DateTime.wednesday,
  DateTime.thursday,
};

const _nearbyRestaurants = <_RestaurantDefinition>[
  _RestaurantDefinition(
    id: 915,
    apiTitle: "Resto U' Etoile",
    displayName: 'Resto U’ Étoile',
    shortName: 'Étoile',
    mapCode: 'RU-E',
    officialUrl: 'https://www.crous-rennes.fr/restaurant/resto-u-letoile-3/',
    fallbackLunchDays: _weekdays,
    fallbackLunch: (11 * 60 + 15, 13 * 60 + 45),
    fallbackDinnerDays: _mondayToThursday,
    fallbackDinner: (18 * 60 + 15, 20 * 60),
  ),
  _RestaurantDefinition(
    id: 916,
    apiTitle: "Resto U' Astrolabe",
    displayName: 'Resto U’ Astrolabe',
    shortName: 'Astrolabe',
    mapCode: 'RU-A',
    officialUrl: 'https://www.crous-rennes.fr/restaurant/resto-u-lastrolabe-3/',
    fallbackLunchDays: _weekdays,
    fallbackLunch: (11 * 60 + 15, 13 * 60 + 45),
  ),
];
