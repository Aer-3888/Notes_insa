import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/modules/weather/weather_advice.dart';
import 'package:notes_insa/modules/weather/weather_icons.dart';

void main() {
  test('clear hours use a moon at night, precipitation keeps its icon', () {
    expect(weatherIcon(0, isNight: true), Icons.nightlight_outlined);
    expect(weatherIcon(1, isNight: true), Icons.nightlight_outlined);
    expect(weatherIcon(0, isNight: false), Icons.wb_sunny_outlined);
    expect(weatherIcon(63, isNight: true), weatherIcon(63));
  });

  test('a clear sky and a downpour do not share an icon', () {
    expect(weatherIcon(0), isNot(weatherIcon(63)));
    expect(weatherIcon(0), isNot(weatherIcon(73)));
    expect(weatherIcon(45), isNot(weatherIcon(3)));
  });

  test('falls back to a neutral icon on an unknown code', () {
    expect(weatherIcon(199), Icons.thermostat_outlined);
  });

  test('every note kind has its own icon', () {
    final icons = WeatherNoteKind.values.map(noteIcon).toSet();
    expect(icons.length, WeatherNoteKind.values.length);
  });
}
