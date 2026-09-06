import '../../core/time.dart';

class HourlyPoint {
  const HourlyPoint({
    required this.time,
    required this.temperatureC,
    required this.weatherCode,
    required this.precipitationProbability,
    required this.windSpeedKmh,
  });

  final DateTime time;
  final double temperatureC;
  final int weatherCode;

  /// Percent, 0 when upstream has no model for this hour.
  final int precipitationProbability;
  final double windSpeedKmh;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'time': time.millisecondsSinceEpoch,
    'temperatureC': temperatureC,
    'weatherCode': weatherCode,
    'precipitationProbability': precipitationProbability,
    'windSpeedKmh': windSpeedKmh,
  };

  factory HourlyPoint.fromJson(Map<String, dynamic> json) => HourlyPoint(
    time: campusFromEpochMs(json['time'] as int),
    temperatureC: (json['temperatureC'] as num).toDouble(),
    weatherCode: (json['weatherCode'] as num).toInt(),
    precipitationProbability: (json['precipitationProbability'] as num).toInt(),
    windSpeedKmh: (json['windSpeedKmh'] as num).toDouble(),
  );
}

class WeatherSnapshot {
  const WeatherSnapshot({
    required this.temperatureC,
    required this.apparentTemperatureC,
    required this.weatherCode,
    required this.windSpeedKmh,
    required this.high,
    required this.low,
    required this.precipitationSumMm,
    required this.uvIndexMax,
    required this.sunrise,
    required this.sunset,
    required this.hourly,
  });

  final double temperatureC;
  final double apparentTemperatureC;
  final int weatherCode;
  final double windSpeedKmh;
  final double high;
  final double low;
  final double precipitationSumMm;
  final double uvIndexMax;
  final DateTime sunrise;
  final DateTime sunset;

  /// Two days of hours, so an evening still has hours ahead of it.
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
      final codes = hourly['weather_code'] as List<dynamic>;
      final rain = hourly['precipitation_probability'] as List<dynamic>;
      final wind = hourly['wind_speed_10m'] as List<dynamic>;
      final lengths = <int>{
        times.length,
        temps.length,
        codes.length,
        rain.length,
        wind.length,
      };
      if (lengths.length != 1) {
        throw const FormatException('hourly arrays disagree in length');
      }
      return WeatherSnapshot(
        temperatureC: (current['temperature_2m'] as num).toDouble(),
        apparentTemperatureC: (current['apparent_temperature'] as num)
            .toDouble(),
        weatherCode: (current['weather_code'] as num).toInt(),
        windSpeedKmh: (current['wind_speed_10m'] as num).toDouble(),
        high: _firstDouble(daily, 'temperature_2m_max'),
        low: _firstDouble(daily, 'temperature_2m_min'),
        precipitationSumMm: _firstDouble(daily, 'precipitation_sum'),
        uvIndexMax: _firstDouble(daily, 'uv_index_max'),
        sunrise: _firstInstant(daily, 'sunrise'),
        sunset: _firstInstant(daily, 'sunset'),
        hourly: <HourlyPoint>[
          for (var i = 0; i < times.length; i++)
            HourlyPoint(
              // Open-Meteo sends naive local strings; reinterpret as campus time.
              time: campusInstant(DateTime.parse(times[i] as String)),
              temperatureC: (temps[i] as num).toDouble(),
              weatherCode: (codes[i] as num).toInt(),
              precipitationProbability: (rain[i] as num?)?.toInt() ?? 0,
              windSpeedKmh: (wind[i] as num).toDouble(),
            ),
        ],
      );
    } on FormatException {
      rethrow;
    } catch (e) {
      throw FormatException('unexpected Open-Meteo payload: $e');
    }
  }

  static double _firstDouble(Map<String, dynamic> daily, String key) =>
      (((daily[key] as List<dynamic>).first as num?) ?? 0).toDouble();

  static DateTime _firstInstant(Map<String, dynamic> daily, String key) =>
      campusInstant(
        DateTime.parse((daily[key] as List<dynamic>).first as String),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'temperatureC': temperatureC,
    'apparentTemperatureC': apparentTemperatureC,
    'weatherCode': weatherCode,
    'windSpeedKmh': windSpeedKmh,
    'high': high,
    'low': low,
    'precipitationSumMm': precipitationSumMm,
    'uvIndexMax': uvIndexMax,
    'sunrise': sunrise.millisecondsSinceEpoch,
    'sunset': sunset.millisecondsSinceEpoch,
    'hourly': <Map<String, dynamic>>[for (final h in hourly) h.toJson()],
  };

  factory WeatherSnapshot.fromJson(Map<String, dynamic> json) =>
      WeatherSnapshot(
        temperatureC: (json['temperatureC'] as num).toDouble(),
        apparentTemperatureC: (json['apparentTemperatureC'] as num).toDouble(),
        weatherCode: (json['weatherCode'] as num).toInt(),
        windSpeedKmh: (json['windSpeedKmh'] as num).toDouble(),
        high: (json['high'] as num).toDouble(),
        low: (json['low'] as num).toDouble(),
        precipitationSumMm: (json['precipitationSumMm'] as num).toDouble(),
        uvIndexMax: (json['uvIndexMax'] as num).toDouble(),
        sunrise: campusFromEpochMs(json['sunrise'] as int),
        sunset: campusFromEpochMs(json['sunset'] as int),
        hourly: <HourlyPoint>[
          for (final h in json['hourly'] as List<dynamic>)
            HourlyPoint.fromJson(h as Map<String, dynamic>),
        ],
      );
}
