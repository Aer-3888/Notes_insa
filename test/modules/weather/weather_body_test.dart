import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/core/time.dart';
import 'package:notes_insa/modules/weather/weather_advice.dart';
import 'package:notes_insa/modules/weather/weather_body.dart';
import 'package:notes_insa/modules/weather/weather_format.dart';
import 'package:notes_insa/modules/weather/weather_model.dart';
import 'package:notes_insa/theme/campus_theme.dart';

Future<void> _loadCampusFont() async {
  final bytes = File('assets/fonts/PublicSans-Variable.ttf').readAsBytesSync();
  await (FontLoader(
    kCampusFontFamily,
  )..addFont(Future<ByteData>.value(ByteData.view(bytes.buffer)))).load();
}

void main() {
  setUpAll(initCampusTime);

  DateTime at(int hour) => campusInstant(DateTime(2026, 9, 2, hour));

  WeatherSnapshot snapshot() => WeatherSnapshot(
    temperatureC: 14.2,
    apparentTemperatureC: 12.6,
    weatherCode: 3,
    windSpeedKmh: 18.5,
    high: 18.1,
    low: 4.4,
    precipitationSumMm: 2.4,
    uvIndexMax: 5.2,
    sunrise: campusInstant(DateTime(2026, 9, 2, 7, 21)),
    sunset: campusInstant(DateTime(2026, 9, 2, 20, 48)),
    hourly: <HourlyPoint>[
      for (var h = 0; h < 24; h++)
        HourlyPoint(
          time: campusInstant(DateTime(2026, 9, 2, h)),
          temperatureC: h >= 19 ? 4.4 : 14.2,
          weatherCode: h >= 16 && h < 19 ? 80 : 3,
          precipitationProbability: h >= 16 && h < 19 ? 80 : 5,
          windSpeedKmh: 18.5,
        ),
    ],
  );

  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    Brightness brightness = Brightness.light,
    double textScale = 1.0,
  }) async {
    await _loadCampusFont();
    tester.view.physicalSize = const Size(384, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: campusTheme(brightness),
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: Scaffold(body: child),
        ),
      ),
    );
    await tester.pump();
  }

  /// The page's own scroll view; the hourly strip is a second one.
  final page = find.byType(Scrollable).first;

  Widget body([DateTime? now]) => WeatherBody(
    snapshot: snapshot(),
    now: now ?? at(14),
    freshness: 'À jour',
  );

  group('WeatherBody', () {
    testWidgets('leads with the temperature and the phrase', (tester) async {
      await pump(tester, body());
      expect(
        find.descendant(
          of: find.byType(FittedBox),
          matching: find.text(degreesLabel(14.2)),
        ),
        findsOneWidget,
      );
      expect(find.text(weatherPhrase(snapshot(), at(14))), findsOneWidget);
    });

    testWidgets('gives the day range and what it feels like', (tester) async {
      await pump(tester, body());
      expect(find.textContaining(degreesLabel(18.1)), findsWidgets);
      expect(find.textContaining(degreesLabel(12.6)), findsWidgets);
    });

    testWidgets('lists the practical notes', (tester) async {
      await pump(tester, body());
      for (final note in weatherNotes(snapshot(), at(14))) {
        expect(find.text(note.text), findsOneWidget);
      }
    });

    testWidgets('starts the hourly strip at the hour in progress', (
      tester,
    ) async {
      await pump(tester, body());
      expect(find.text(hourLabel(at(14))), findsOneWidget);
      expect(find.text(hourLabel(at(9))), findsNothing);
    });

    testWidgets('shows the rain chance only when it is worth reading', (
      tester,
    ) async {
      await pump(tester, body());
      expect(find.text(percentLabel(80)), findsWidgets);
      expect(find.text(percentLabel(5)), findsNothing);
    });

    testWidgets('gives sunrise, sunset, wind and UV', (tester) async {
      await pump(tester, body());
      await tester.scrollUntilVisible(
        find.text('Lever'),
        200,
        scrollable: page,
      );
      expect(
        find.text(clockLabel(campusInstant(DateTime(2026, 9, 2, 7, 21)))),
        findsOneWidget,
      );
      expect(
        find.text(clockLabel(campusInstant(DateTime(2026, 9, 2, 20, 48)))),
        findsOneWidget,
      );
      expect(find.text('Vent'), findsOneWidget);
      expect(find.text('Indice UV'), findsOneWidget);
    });

    testWidgets('names its source', (tester) async {
      await pump(tester, body());
      await tester.scrollUntilVisible(
        find.text('Données Open-Meteo'),
        200,
        scrollable: page,
      );
      expect(find.text('Données Open-Meteo'), findsOneWidget);
    });

    testWidgets('shows the freshness of what it is showing', (tester) async {
      await pump(tester, body());
      await tester.scrollUntilVisible(
        find.text('À jour'),
        200,
        scrollable: page,
      );
      expect(find.text('À jour'), findsOneWidget);
    });

    testWidgets('reads its numbers as words', (tester) async {
      final semantics = tester.ensureSemantics();
      await pump(tester, body());
      expect(
        find.bySemanticsLabel('${hourLabel(at(14))}, ${spokenDegrees(14.2)}'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          '${hourLabel(at(16))}, ${spokenDegrees(14.2)}, '
          '${percentLabel(80)} de risque de pluie',
        ),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel(RegExp(spokenDegrees(14.2))), findsWidgets);
      semantics.dispose();
    });

    testWidgets('renders in dark mode', (tester) async {
      await pump(tester, body(), brightness: Brightness.dark);
      expect(tester.takeException(), isNull);
    });

    testWidgets('survives 200 percent text', (tester) async {
      await pump(tester, body(), textScale: 2.0);
      expect(tester.takeException(), isNull);
    });
  });

  group('WeatherStripView', () {
    testWidgets('shows the temperature and the phrase', (tester) async {
      await pump(tester, WeatherStripView(snapshot: snapshot(), now: at(14)));
      expect(find.text(temperatureLabel(14.2)), findsOneWidget);
      expect(find.text(weatherPhrase(snapshot(), at(14))), findsOneWidget);
    });

    testWidgets('opens the weather page when tapped', (tester) async {
      var opened = 0;
      await pump(
        tester,
        WeatherStripView(
          snapshot: snapshot(),
          now: at(14),
          onTap: () => opened++,
        ),
      );
      await tester.tap(find.byType(WeatherStripView));
      expect(opened, 1);
    });

    testWidgets('survives 200 percent text', (tester) async {
      await pump(
        tester,
        WeatherStripView(snapshot: snapshot(), now: at(14)),
        textScale: 2.0,
      );
      expect(tester.takeException(), isNull);
    });
  });
}
