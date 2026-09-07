import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/core/time.dart';
import 'package:notes_insa/modules/weather/weather_body.dart';
import 'package:notes_insa/modules/weather/weather_model.dart';
import 'package:notes_insa/modules/weather/weather_scene.dart';
import 'package:notes_insa/theme/campus_theme.dart';

DateTime at(int hour, [int minute = 0, int day = 8]) =>
    campusInstant(DateTime(2026, 9, day, hour, minute));

WeatherSnapshot forecast(int code, {double temperature = 18}) =>
    WeatherSnapshot(
      temperatureC: temperature,
      apparentTemperatureC: temperature - 2,
      weatherCode: code,
      windSpeedKmh: 16,
      high: temperature + 3,
      low: temperature - 5,
      precipitationSumMm: code >= 51 ? 3 : 0,
      uvIndexMax: 3,
      sunrise: at(7, 30),
      sunset: at(20, 30),
      hourly: <HourlyPoint>[
        for (var h = 0; h < 48; h++)
          HourlyPoint(
            time: at(h),
            temperatureC: temperature + (h % 4),
            weatherCode: code,
            precipitationProbability: code >= 51 ? 75 : 10,
            windSpeedKmh: 16,
          ),
      ],
    );

void main() {
  setUpAll(() async {
    await initCampusTime();
    final bytes = File(
      'assets/fonts/PublicSans-Variable.ttf',
    ).readAsBytesSync();
    await (FontLoader(
      kCampusFontFamily,
    )..addFont(Future<ByteData>.value(ByteData.view(bytes.buffer)))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  test(
    'represents every supported weather family, with a neutral fallback',
    () {
      const groups = <WeatherSky, List<int>>{
        WeatherSky.clear: [0],
        WeatherSky.cloudy: [1, 2],
        WeatherSky.overcast: [3],
        WeatherSky.fog: [45, 48],
        WeatherSky.rain: [51, 53, 55, 56, 57, 61, 63, 65, 66, 67, 80, 81, 82],
        WeatherSky.snow: [71, 73, 75, 77, 85, 86],
        WeatherSky.storm: [95, 96, 99],
        WeatherSky.unknown: [-1, 1000],
      };
      for (final group in groups.entries) {
        for (final code in group.value) {
          expect(
            WeatherSceneData.fromSnapshot(forecast(code), at(14)).sky,
            group.key,
            reason: 'WMO $code',
          );
        }
      }
    },
  );

  test(
    'uses sunrise and sunset for daylight, including twilight boundaries',
    () {
      final snapshot = forecast(0);
      final cases = <DateTime, WeatherDaylight>{
        at(6, 49): WeatherDaylight.night,
        at(6, 50): WeatherDaylight.dawn,
        at(7, 30): WeatherDaylight.dawn,
        at(8, 10): WeatherDaylight.day,
        at(19, 49): WeatherDaylight.day,
        at(19, 50): WeatherDaylight.dusk,
        at(20, 30): WeatherDaylight.dusk,
        at(21, 10): WeatherDaylight.night,
      };
      for (final entry in cases.entries) {
        expect(
          WeatherSceneData.fromSnapshot(snapshot, entry.key).daylight,
          entry.value,
          reason: '${entry.key}',
        );
      }
    },
  );

  test(
    'stale solar dates and device timezone do not turn midday into night',
    () {
      final snapshot = forecast(0);
      expect(
        WeatherSceneData.fromSnapshot(snapshot, at(14, 0, 10)).daylight,
        WeatherDaylight.day,
      );
      expect(
        WeatherSceneData.fromSnapshot(snapshot, at(14).toUtc()).daylight,
        WeatherDaylight.day,
      );
      expect(
        WeatherSceneData.fromSnapshot(snapshot, at(2, 0, 10)).daylight,
        WeatherDaylight.night,
      );
    },
  );

  test('all sky palettes keep text contrast above 4.5 to 1', () {
    for (final sky in WeatherSky.values) {
      for (final daylight in WeatherDaylight.values) {
        final palette = WeatherSceneData(sky: sky, daylight: daylight).palette;
        for (final background in [palette.skyTop, palette.skyBottom]) {
          final ink = palette.ink.computeLuminance();
          final bg = background.computeLuminance();
          final contrast = ink > bg
              ? (ink + .05) / (bg + .05)
              : (bg + .05) / (ink + .05);
          expect(
            contrast,
            greaterThanOrEqualTo(4.5),
            reason: '$sky / $daylight',
          );
        }
      }
    }
  });

  for (final width in [320.0, 384.0, 720.0]) {
    for (final brightness in Brightness.values) {
      testWidgets('scrolls at width $width, $brightness and 200% text', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            theme: campusTheme(brightness),
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: Scaffold(
                body: WeatherBody(
                  snapshot: forecast(95, temperature: -12),
                  now: at(14),
                  freshness: 'Hors ligne · Dernière mise à jour à 13:45',
                ),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        await tester.scrollUntilVisible(
          find.text('Données Open-Meteo'),
          250,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Données Open-Meteo').hitTestable(), findsOneWidget);
      });
    }
  }

  testWidgets('scene updates when weather and time change', (tester) async {
    Future<void> show(int code, int hour) => tester.pumpWidget(
      MaterialApp(
        theme: campusTheme(Brightness.light),
        home: Scaffold(
          body: WeatherBody(
            snapshot: forecast(code),
            now: at(hour),
            freshness: 'À jour',
          ),
        ),
      ),
    );
    await show(0, 14);
    expect(
      tester.widget<WeatherScene>(find.byType(WeatherScene)).data.sky,
      WeatherSky.clear,
    );
    await show(71, 23);
    final scene = tester.widget<WeatherScene>(find.byType(WeatherScene)).data;
    expect(scene.sky, WeatherSky.snow);
    expect(scene.daylight, WeatherDaylight.night);
    expect(tester.takeException(), isNull);
  });

  // Optional local review artifacts, not platform-dependent committed goldens:
  // flutter test test/modules/weather/weather_scene_test.dart
  //   --dart-define=WEATHER_PREVIEWS=true --update-goldens
  const previews = bool.fromEnvironment('WEATHER_PREVIEWS');
  if (previews) {
    const variants = <String, (int, int, Brightness)>{
      'clear': (0, 14, Brightness.light),
      'rain': (63, 14, Brightness.light),
      'sunset': (0, 20, Brightness.light),
      'night': (0, 23, Brightness.dark),
      'snow': (73, 14, Brightness.light),
      'fog': (45, 14, Brightness.light),
      'storm': (95, 14, Brightness.dark),
      'overcast': (3, 14, Brightness.light),
    };
    for (final entry in variants.entries) {
      testWidgets('preview ${entry.key}', (tester) async {
        tester.view.physicalSize = const Size(384, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final (code, hour, brightness) = entry.value;
        await tester.pumpWidget(
          MaterialApp(
            theme: campusTheme(brightness),
            home: RepaintBoundary(
              key: const ValueKey('preview'),
              child: Scaffold(
                appBar: AppBar(
                  leading: const BackButton(),
                  title: const Text('Météo'),
                ),
                body: WeatherBody(
                  snapshot: forecast(code, temperature: code == 73 ? -2 : 18),
                  now: at(hour),
                  freshness: 'À jour',
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await expectLater(
          find.byKey(const ValueKey('preview')),
          matchesGoldenFile('../../../build/weather-design/${entry.key}.png'),
        );
      });
    }
  }
}
