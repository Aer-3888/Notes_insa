import 'dart:convert';

import 'package:http/http.dart' as http;

import 'weather_model.dart';

/// Campus de Beaulieu. Hardcoded so the app never requests a location
/// permission: it is a campus app, and the campus does not move.
const double kCampusLat = 48.1197;
const double kCampusLon = -1.6383;

class WeatherService {
  const WeatherService({http.Client? client}) : _client = client;

  final http.Client? _client;

  static final Uri endpoint = Uri.parse(
    'https://api.open-meteo.com/v1/forecast'
    '?latitude=$kCampusLat&longitude=$kCampusLon'
    '&current=temperature_2m,weather_code'
    '&daily=temperature_2m_max,temperature_2m_min'
    '&hourly=temperature_2m&forecast_days=1&timezone=Europe%2FParis',
  );

  Future<WeatherSnapshot> fetch() async {
    final client = _client ?? http.Client();
    try {
      final response = await client
          .get(endpoint)
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        throw http.ClientException('HTTP ${response.statusCode}', endpoint);
      }
      return WeatherSnapshot.fromOpenMeteo(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    } finally {
      if (_client == null) client.close();
    }
  }
}
