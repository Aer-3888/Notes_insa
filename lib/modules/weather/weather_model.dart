import '../../core/time.dart';

class HourlyPoint {
  const HourlyPoint({required this.time, required this.temperatureC});

  final DateTime time;
  final double temperatureC;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'time': time.millisecondsSinceEpoch,
    'temperatureC': temperatureC,
  };

  factory HourlyPoint.fromJson(Map<String, dynamic> json) => HourlyPoint(
    time: campusFromEpochMs(json['time'] as int),
    temperatureC: (json['temperatureC'] as num).toDouble(),
  );
}

class WeatherSnapshot {
  const WeatherSnapshot({
    required this.temperatureC,
    required this.weatherCode,
    required this.high,
    required this.low,
    required this.hourly,
  });

  final double temperatureC;
  final int weatherCode;
  final double high;
  final double low;
  final List<HourlyPoint> hourly;

  /// Parses an Open-Meteo forecast response.
  ///
  /// Throws [FormatException] on anything unexpected so the provider can tell a
  /// changed upstream shape apart from a network failure.
  factory WeatherSnapshot.fromOpenMeteo(Map<String, dynamic> json) {
    try {
      final current = json['current'] as Map<String, dynamic>;
      final daily = json['daily'] as Map<String, dynamic>;
      final hourly = json['hourly'] as Map<String, dynamic>;
      final times = hourly['time'] as List<dynamic>;
      final temps = hourly['temperature_2m'] as List<dynamic>;
      if (times.length != temps.length) {
        throw const FormatException('hourly time/temperature length mismatch');
      }
      return WeatherSnapshot(
        temperatureC: (current['temperature_2m'] as num).toDouble(),
        weatherCode: (current['weather_code'] as num).toInt(),
        high: ((daily['temperature_2m_max'] as List<dynamic>).first as num)
            .toDouble(),
        low: ((daily['temperature_2m_min'] as List<dynamic>).first as num)
            .toDouble(),
        hourly: <HourlyPoint>[
          for (var i = 0; i < times.length; i++)
            HourlyPoint(
              // Open-Meteo sends naive local strings; reinterpret as campus time.
              time: campusInstant(DateTime.parse(times[i] as String)),
              temperatureC: (temps[i] as num).toDouble(),
            ),
        ],
      );
    } on FormatException {
      rethrow;
    } catch (e) {
      throw FormatException('unexpected Open-Meteo payload: $e');
    }
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'temperatureC': temperatureC,
    'weatherCode': weatherCode,
    'high': high,
    'low': low,
    'hourly': <Map<String, dynamic>>[for (final h in hourly) h.toJson()],
  };

  factory WeatherSnapshot.fromJson(Map<String, dynamic> json) =>
      WeatherSnapshot(
        temperatureC: (json['temperatureC'] as num).toDouble(),
        weatherCode: (json['weatherCode'] as num).toInt(),
        high: (json['high'] as num).toDouble(),
        low: (json['low'] as num).toDouble(),
        hourly: <HourlyPoint>[
          for (final h in json['hourly'] as List<dynamic>)
            HourlyPoint.fromJson(h as Map<String, dynamic>),
        ],
      );
}
