import 'dart:math';

import 'weather_format.dart';
import 'weather_model.dart';

/// The forecast from the hour in progress onward, capped at [count].
List<HourlyPoint> upcomingHours(
  WeatherSnapshot snapshot,
  DateTime now, {
  int count = 12,
}) => snapshot.hourly
    .where((h) => h.time.add(const Duration(hours: 1)).isAfter(now))
    .take(count)
    .toList();

/// French label for a WMO weather code.
String conditionLabel(int code) => switch (code) {
  0 => 'Ciel dégagé',
  1 => 'Peu nuageux',
  2 => 'Nuageux',
  3 => 'Couvert',
  45 || 48 => 'Brouillard',
  51 || 53 || 55 || 56 || 57 => 'Bruine',
  61 || 63 || 65 || 66 || 67 => 'Pluie',
  71 || 73 || 75 || 77 => 'Neige',
  80 || 81 || 82 => 'Averses',
  85 || 86 => 'Averses de neige',
  95 || 96 || 99 => 'Orages',
  _ => 'Météo',
};

/// Every WMO code from 51 up is precipitation; fog and cloud stay below it.
bool _isWet(int code) => code >= 51;

/// The one sentence shown on the home row and under the temperature.
///
/// Timing comes from the hourly codes, never from a probability, so the phrase
/// only ever promises what the forecast actually says.
String weatherPhrase(WeatherSnapshot snapshot, DateTime now) {
  final hours = upcomingHours(snapshot, now);
  if (hours.isEmpty) return conditionLabel(snapshot.weatherCode);

  if (_isWet(hours.first.weatherCode)) {
    final word = conditionLabel(hours.first.weatherCode);
    final clearing = hours.indexWhere((h) => !_isWet(h.weatherCode));
    return clearing == -1
        ? '$word pour les prochaines heures'
        : '$word jusqu’à ${hourLabel(hours[clearing].time)}';
  }

  final wet = hours.indexWhere((h) => _isWet(h.weatherCode));
  if (wet == -1) return conditionLabel(snapshot.weatherCode);
  return '${conditionLabel(hours[wet].weatherCode)} '
      'à partir de ${hourLabel(hours[wet].time)}';
}

enum WeatherNoteKind { umbrella, coat, wind, sun }

class WeatherNote {
  const WeatherNote(this.kind, this.text);

  final WeatherNoteKind kind;
  final String text;
}

/// At most two practical notes, most useful first.
List<WeatherNote> weatherNotes(WeatherSnapshot snapshot, DateTime now) {
  final hours = upcomingHours(snapshot, now);
  final notes = <WeatherNote>[];

  if (hours.isNotEmpty) {
    final rain = hours
        .map((h) => h.precipitationProbability)
        .reduce((a, b) => max(a, b));
    if (rain >= 50) {
      notes.add(
        const WeatherNote(WeatherNoteKind.umbrella, 'Parapluie conseillé'),
      );
    }

    final coldest = hours.map((h) => h.temperatureC).reduce(min);
    if (coldest <= 8) {
      notes.add(
        WeatherNote(
          WeatherNoteKind.coat,
          'Prenez une veste, il fera ${degreesLabel(coldest)}',
        ),
      );
    }

    final gust = hours.map((h) => h.windSpeedKmh).reduce(max);
    if (gust >= 40) {
      notes.add(
        WeatherNote(
          WeatherNoteKind.wind,
          'Vent fort, jusqu’à ${gust.round()}${nbsp}km/h',
        ),
      );
    }
  }

  if (snapshot.uvIndexMax >= 6) {
    notes.add(
      const WeatherNote(WeatherNoteKind.sun, 'UV élevés, protégez-vous'),
    );
  } else if (snapshot.high >= 27) {
    notes.add(
      WeatherNote(
        WeatherNoteKind.sun,
        'Prévoyez de l’eau, il fera ${degreesLabel(snapshot.high)}',
      ),
    );
  }

  return notes.take(2).toList();
}
