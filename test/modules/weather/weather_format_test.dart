import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/core/time.dart';
import 'package:notes_insa/modules/weather/weather_format.dart';

void main() {
  setUpAll(initCampusTime);

  test('keeps the gap before a unit non-breaking', () {
    expect(temperatureLabel(14), '14 °C');
    expect(degreesLabel(14), '14 °');
    expect(hourLabel(campusInstant(DateTime(2026, 9, 2, 7))), '7 h');
  });

  test('keeps the gap before a percent sign non-breaking', () {
    expect(percentLabel(80), '80$nbsp%');
  });

  test('writes millimetres with a French decimal comma', () {
    expect(millimetresLabel(2.4), '2,4${nbsp}mm');
  });

  test('speaks numbers as words for the screen reader', () {
    expect(spokenDegrees(15), '15 degrés');
    expect(spokenDegrees(1), '1 degré');
    expect(spokenDegrees(0), '0 degré');
    expect(spokenClock(campusInstant(DateTime(2026, 9, 2, 7, 5))), '7 h 05');
  });

  test('rounds to the whole degree', () {
    expect(degreesLabel(14.6), '15 °');
    expect(degreesLabel(14.4), '14 °');
  });

  test('never prints a negative zero', () {
    expect(degreesLabel(-0.4), '0 °');
  });

  test('prints a clock time with two digits for the minutes', () {
    expect(clockLabel(campusInstant(DateTime(2026, 9, 2, 7, 5))), '07:05');
  });
}
