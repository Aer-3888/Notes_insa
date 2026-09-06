import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/core/time.dart';
import 'package:notes_insa/modules/weather/weather_model.dart';

void main() {
  setUpAll(initCampusTime);

  const payload = <String, dynamic>{
    'current': <String, dynamic>{
      'temperature_2m': 14.2,
      'apparent_temperature': 12.6,
      'weather_code': 3,
      'wind_speed_10m': 18.5,
    },
    'daily': <String, dynamic>{
      'temperature_2m_max': <dynamic>[18.1],
      'temperature_2m_min': <dynamic>[9.4],
      'precipitation_sum': <dynamic>[2.4],
      'uv_index_max': <dynamic>[5.2],
      'sunrise': <dynamic>['2026-09-02T07:21'],
      'sunset': <dynamic>['2026-09-02T20:48'],
    },
    'hourly': <String, dynamic>{
      'time': <dynamic>['2026-09-02T14:00', '2026-09-02T15:00'],
      'temperature_2m': <dynamic>[14.2, 15.0],
      'weather_code': <dynamic>[3, 80],
      'precipitation_probability': <dynamic>[10, 70],
      'wind_speed_10m': <dynamic>[18.5, 24.0],
    },
  };

  test('parses the current conditions', () {
    final snapshot = WeatherSnapshot.fromOpenMeteo(payload);
    expect(snapshot.temperatureC, 14.2);
    expect(snapshot.apparentTemperatureC, 12.6);
    expect(snapshot.weatherCode, 3);
    expect(snapshot.windSpeedKmh, 18.5);
    expect(snapshot.high, 18.1);
    expect(snapshot.low, 9.4);
  });

  test('parses the day summary', () {
    final snapshot = WeatherSnapshot.fromOpenMeteo(payload);
    expect(snapshot.precipitationSumMm, 2.4);
    expect(snapshot.uvIndexMax, 5.2);
    expect(snapshot.sunrise.hour, 7);
    expect(snapshot.sunrise.minute, 21);
    expect(snapshot.sunset.hour, 20);
    expect(snapshot.sunset.minute, 48);
  });

  test('parses hourly points as campus wall-clock', () {
    final snapshot = WeatherSnapshot.fromOpenMeteo(payload);
    expect(snapshot.hourly.length, 2);
    expect(snapshot.hourly.first.temperatureC, 14.2);
    expect(snapshot.hourly.first.time.hour, 14);
  });

  test('parses the hourly condition, rain chance and wind', () {
    final snapshot = WeatherSnapshot.fromOpenMeteo(payload);
    expect(snapshot.hourly.last.weatherCode, 80);
    expect(snapshot.hourly.last.precipitationProbability, 70);
    expect(snapshot.hourly.last.windSpeedKmh, 24.0);
  });

  test('reads a missing rain chance as zero', () {
    // Open-Meteo sends null for probabilities it has no model for.
    final snapshot = WeatherSnapshot.fromOpenMeteo(<String, dynamic>{
      ...payload,
      'hourly': <String, dynamic>{
        ...payload['hourly'] as Map<String, dynamic>,
        'precipitation_probability': <dynamic>[null, null],
      },
    });
    expect(snapshot.hourly.first.precipitationProbability, 0);
  });

  test('round-trips through toJson for the cache', () {
    final snapshot = WeatherSnapshot.fromOpenMeteo(payload);
    final restored = WeatherSnapshot.fromJson(snapshot.toJson());
    expect(restored.temperatureC, snapshot.temperatureC);
    expect(restored.apparentTemperatureC, snapshot.apparentTemperatureC);
    expect(restored.uvIndexMax, snapshot.uvIndexMax);
    expect(restored.sunrise, snapshot.sunrise);
    expect(restored.sunset, snapshot.sunset);
    expect(restored.hourly.length, snapshot.hourly.length);
    expect(restored.hourly.first.time, snapshot.hourly.first.time);
    expect(restored.hourly.last.weatherCode, 80);
    expect(restored.hourly.last.precipitationProbability, 70);
  });

  test('a cached hour reads as the campus hour, not the device hour', () {
    // The cache round-trip must not reinterpret the instant in the device's
    // zone, or a student abroad would see their own local hours.
    final restored = WeatherSnapshot.fromJson(
      WeatherSnapshot.fromOpenMeteo(payload).toJson(),
    );
    expect(restored.hourly.first.time.hour, 14);
    expect(restored.hourly.last.time.hour, 15);
    expect(restored.sunrise.hour, 7);
  });

  test('throws FormatException on a malformed payload', () {
    expect(
      () => WeatherSnapshot.fromOpenMeteo(const <String, dynamic>{}),
      throwsA(isA<FormatException>()),
    );
  });

  test('throws FormatException when hourly arrays disagree in length', () {
    expect(
      () => WeatherSnapshot.fromOpenMeteo(<String, dynamic>{
        ...payload,
        'hourly': <String, dynamic>{
          'time': <dynamic>['2026-09-02T14:00', '2026-09-02T15:00'],
          'temperature_2m': <dynamic>[1.0],
          'weather_code': <dynamic>[3],
          'precipitation_probability': <dynamic>[10],
          'wind_speed_10m': <dynamic>[18.5],
        },
      }),
      throwsA(isA<FormatException>()),
    );
  });
}
