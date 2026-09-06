import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/modules/weather/weather_service.dart';

void main() {
  // The endpoint and the parser are one contract: a field dropped here becomes
  // a FormatException at runtime, so the query is asserted field by field.
  final query = WeatherService.endpoint.queryParameters;

  test('asks for the campus coordinates and the campus timezone', () {
    expect(query['latitude'], kCampusLat.toString());
    expect(query['longitude'], kCampusLon.toString());
    expect(query['timezone'], 'Europe/Paris');
  });

  test('asks for the current fields the header needs', () {
    expect(
      query['current']!.split(','),
      containsAll(<String>[
        'temperature_2m',
        'apparent_temperature',
        'weather_code',
        'wind_speed_10m',
      ]),
    );
  });

  test('asks for the hourly fields the strip and the notes need', () {
    expect(
      query['hourly']!.split(','),
      containsAll(<String>[
        'temperature_2m',
        'weather_code',
        'precipitation_probability',
        'wind_speed_10m',
      ]),
    );
  });

  test('asks for the daily fields the summary needs', () {
    expect(
      query['daily']!.split(','),
      containsAll(<String>[
        'temperature_2m_max',
        'temperature_2m_min',
        'precipitation_sum',
        'uv_index_max',
        'sunrise',
        'sunset',
      ]),
    );
  });

  test('asks for two days so an evening still has hours ahead', () {
    expect(query['forecast_days'], '2');
  });
}
