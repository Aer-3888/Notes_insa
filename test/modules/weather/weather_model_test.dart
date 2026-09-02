import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/core/time.dart';
import 'package:notes_insa/modules/weather/weather_model.dart';

void main() {
  setUpAll(initCampusTime);

  const payload = <String, dynamic>{
    'current': <String, dynamic>{'temperature_2m': 14.2, 'weather_code': 3},
    'daily': <String, dynamic>{
      'temperature_2m_max': <dynamic>[18.1],
      'temperature_2m_min': <dynamic>[9.4],
    },
    'hourly': <String, dynamic>{
      'time': <dynamic>['2026-09-02T14:00', '2026-09-02T15:00'],
      'temperature_2m': <dynamic>[14.2, 15.0],
    },
  };

  test('parses the current conditions', () {
    final snapshot = WeatherSnapshot.fromOpenMeteo(payload);
    expect(snapshot.temperatureC, 14.2);
    expect(snapshot.weatherCode, 3);
    expect(snapshot.high, 18.1);
    expect(snapshot.low, 9.4);
  });

  test('parses hourly points as campus wall-clock', () {
    final snapshot = WeatherSnapshot.fromOpenMeteo(payload);
    expect(snapshot.hourly.length, 2);
    expect(snapshot.hourly.first.temperatureC, 14.2);
    expect(snapshot.hourly.first.time.hour, 14);
  });

  test('round-trips through toJson for the cache', () {
    final snapshot = WeatherSnapshot.fromOpenMeteo(payload);
    final restored = WeatherSnapshot.fromJson(snapshot.toJson());
    expect(restored.temperatureC, snapshot.temperatureC);
    expect(restored.hourly.length, snapshot.hourly.length);
    expect(restored.hourly.first.time, snapshot.hourly.first.time);
  });

  test('a cached hour reads as the campus hour, not the device hour', () {
    // The cache round-trip must not reinterpret the instant in the device's
    // zone, or a student abroad would see their own local hours.
    final restored = WeatherSnapshot.fromJson(
      WeatherSnapshot.fromOpenMeteo(payload).toJson(),
    );
    expect(restored.hourly.first.time.hour, 14);
    expect(restored.hourly.last.time.hour, 15);
  });

  test('throws FormatException on a malformed payload', () {
    expect(
      () => WeatherSnapshot.fromOpenMeteo(const <String, dynamic>{}),
      throwsA(isA<FormatException>()),
    );
  });

  test('throws FormatException when hourly arrays disagree in length', () {
    expect(
      () => WeatherSnapshot.fromOpenMeteo(const <String, dynamic>{
        'current': <String, dynamic>{'temperature_2m': 1.0, 'weather_code': 0},
        'daily': <String, dynamic>{
          'temperature_2m_max': <dynamic>[2.0],
          'temperature_2m_min': <dynamic>[0.0],
        },
        'hourly': <String, dynamic>{
          'time': <dynamic>['2026-09-02T14:00', '2026-09-02T15:00'],
          'temperature_2m': <dynamic>[1.0],
        },
      }),
      throwsA(isA<FormatException>()),
    );
  });
}
