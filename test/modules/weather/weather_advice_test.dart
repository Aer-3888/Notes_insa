import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/core/time.dart';
import 'package:notes_insa/modules/weather/weather_advice.dart';
import 'package:notes_insa/modules/weather/weather_model.dart';

/// A day of hours starting at midnight, one entry per hour, all identical
/// unless a test overrides a slice of them.
List<HourlyPoint> _day({
  int hours = 24,
  double temperature = 14,
  int code = 0,
  int rain = 0,
  double wind = 10,
}) => <HourlyPoint>[
  for (var h = 0; h < hours; h++)
    HourlyPoint(
      time: campusInstant(DateTime(2026, 9, 2, h)),
      temperatureC: temperature,
      weatherCode: code,
      precipitationProbability: rain,
      windSpeedKmh: wind,
    ),
];

List<HourlyPoint> _patch(
  List<HourlyPoint> hours,
  int from,
  int to, {
  int? code,
  int? rain,
  double? temperature,
  double? wind,
}) => <HourlyPoint>[
  for (final h in hours)
    if (h.time.hour >= from && h.time.hour < to)
      HourlyPoint(
        time: h.time,
        temperatureC: temperature ?? h.temperatureC,
        weatherCode: code ?? h.weatherCode,
        precipitationProbability: rain ?? h.precipitationProbability,
        windSpeedKmh: wind ?? h.windSpeedKmh,
      )
    else
      h,
];

WeatherSnapshot _snapshot({
  double temperature = 14,
  int code = 0,
  double high = 18,
  double low = 9,
  double uv = 2,
  List<HourlyPoint>? hourly,
}) => WeatherSnapshot(
  temperatureC: temperature,
  apparentTemperatureC: temperature - 1,
  weatherCode: code,
  windSpeedKmh: 10,
  high: high,
  low: low,
  precipitationSumMm: 0,
  uvIndexMax: uv,
  sunrise: campusInstant(DateTime(2026, 9, 2, 7, 21)),
  sunset: campusInstant(DateTime(2026, 9, 2, 20, 48)),
  hourly: hourly ?? _day(),
);

DateTime _at(int hour, [int minute = 0]) =>
    campusInstant(DateTime(2026, 9, 2, hour, minute));

void main() {
  setUpAll(initCampusTime);

  group('upcomingHours', () {
    test('starts at the hour in progress, not the next one', () {
      final hours = upcomingHours(_snapshot(), _at(14, 30));
      expect(hours.first.time.hour, 14);
    });

    test('drops the hours already past', () {
      final hours = upcomingHours(_snapshot(), _at(14));
      expect(hours.every((h) => h.time.hour >= 14), isTrue);
    });

    test('caps the window at the requested count', () {
      expect(upcomingHours(_snapshot(), _at(0), count: 12).length, 12);
    });

    test('is empty when the whole forecast is in the past', () {
      expect(
        upcomingHours(_snapshot(), campusInstant(DateTime(2026, 9, 3))),
        isEmpty,
      );
    });
  });

  group('conditionLabel', () {
    test('names the common codes in French', () {
      expect(conditionLabel(0), 'Ciel dégagé');
      expect(conditionLabel(2), 'Nuageux');
      expect(conditionLabel(3), 'Couvert');
      expect(conditionLabel(45), 'Brouillard');
      expect(conditionLabel(53), 'Bruine');
      expect(conditionLabel(63), 'Pluie');
      expect(conditionLabel(73), 'Neige');
      expect(conditionLabel(81), 'Averses');
      expect(conditionLabel(95), 'Orages');
    });

    test('falls back to a plain label on an unknown code', () {
      expect(conditionLabel(199), 'Météo');
    });
  });

  group('weatherPhrase', () {
    test('says when the rain stops', () {
      final snapshot = _snapshot(
        code: 80,
        hourly: _patch(_day(), 12, 16, code: 80),
      );
      expect(weatherPhrase(snapshot, _at(14)), 'Averses jusqu’à 16 h');
    });

    test('says when the rain starts', () {
      final snapshot = _snapshot(hourly: _patch(_day(), 17, 20, code: 61));
      expect(weatherPhrase(snapshot, _at(14)), 'Pluie à partir de 17 h');
    });

    test('does not promise an end it cannot see', () {
      final snapshot = _snapshot(
        code: 61,
        hourly: _patch(_day(), 0, 24, code: 61),
      );
      expect(
        weatherPhrase(snapshot, _at(14)),
        'Pluie pour les prochaines heures',
      );
    });

    test('falls back to the current condition on a dry day', () {
      expect(weatherPhrase(_snapshot(), _at(14)), 'Ciel dégagé');
    });

    test('falls back to the current condition when the cache is stale', () {
      final snapshot = _snapshot(code: 3);
      expect(
        weatherPhrase(snapshot, campusInstant(DateTime(2026, 9, 3))),
        'Couvert',
      );
    });
  });

  group('weatherNotes', () {
    test('says nothing on a mild, dry, calm day', () {
      expect(weatherNotes(_snapshot(), _at(9)), isEmpty);
    });

    test('advises an umbrella when rain is likely', () {
      final snapshot = _snapshot(hourly: _patch(_day(), 15, 18, rain: 70));
      expect(
        weatherNotes(snapshot, _at(9)).first,
        isA<WeatherNote>()
            .having((n) => n.kind, 'kind', WeatherNoteKind.umbrella)
            .having((n) => n.text, 'text', 'Parapluie conseillé'),
      );
    });

    test('ignores rain that has already fallen', () {
      final snapshot = _snapshot(hourly: _patch(_day(), 6, 9, rain: 90));
      expect(weatherNotes(snapshot, _at(14)), isEmpty);
    });

    test('advises a coat on the coming cold', () {
      final snapshot = _snapshot(
        hourly: _patch(_day(), 18, 24, temperature: 4),
      );
      expect(
        weatherNotes(snapshot, _at(14)).first.text,
        'Prenez une veste, il fera 4 °',
      );
    });

    test('warns about strong wind', () {
      final snapshot = _snapshot(hourly: _patch(_day(), 14, 18, wind: 46));
      expect(
        weatherNotes(snapshot, _at(14)).first.text,
        'Vent fort, jusqu’à 46 km/h',
      );
    });

    test('warns about a high UV index', () {
      expect(
        weatherNotes(_snapshot(uv: 7), _at(12)).first.text,
        'UV élevés, protégez-vous',
      );
    });

    test('keeps at most two notes, most useful first', () {
      final snapshot = _snapshot(
        uv: 8,
        hourly: _patch(
          _patch(_day(), 15, 18, rain: 80),
          18,
          24,
          temperature: 3,
          wind: 50,
        ),
      );
      final notes = weatherNotes(snapshot, _at(14));
      expect(notes.length, 2);
      expect(notes.map((n) => n.kind), <WeatherNoteKind>[
        WeatherNoteKind.umbrella,
        WeatherNoteKind.coat,
      ]);
    });
  });
}
