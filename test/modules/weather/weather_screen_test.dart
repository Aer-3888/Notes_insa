import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/core/module_cache.dart';
import 'package:notes_insa/core/time.dart';
import 'package:notes_insa/modules/weather/weather_body.dart';
import 'package:notes_insa/modules/weather/weather_model.dart';
import 'package:notes_insa/modules/weather/weather_provider.dart';
import 'package:notes_insa/modules/weather/weather_screen.dart';
import 'package:notes_insa/theme/campus_theme.dart';

Future<void> _loadCampusFont() async {
  final bytes = File('assets/fonts/PublicSans-Variable.ttf').readAsBytesSync();
  await (FontLoader(
    kCampusFontFamily,
  )..addFont(Future<ByteData>.value(ByteData.view(bytes.buffer)))).load();
}

void main() {
  setUpAll(initCampusTime);

  WeatherSnapshot snapshot() => WeatherSnapshot(
    temperatureC: 14.2,
    apparentTemperatureC: 12.6,
    weatherCode: 3,
    windSpeedKmh: 18.5,
    high: 18.1,
    low: 9.4,
    precipitationSumMm: 0,
    uvIndexMax: 2.1,
    sunrise: campusInstant(DateTime(2026, 9, 2, 7, 21)),
    sunset: campusInstant(DateTime(2026, 9, 2, 20, 48)),
    hourly: <HourlyPoint>[
      for (var h = 0; h < 24; h++)
        HourlyPoint(
          time: campusInstant(DateTime(2026, 9, 2, h)),
          temperatureC: 14.2,
          weatherCode: 3,
          precipitationProbability: 5,
          windSpeedKmh: 18.5,
        ),
    ],
  );

  Future<void> pump(
    WidgetTester tester,
    Widget home,
    CachedEntry<WeatherSnapshot> entry, {
    VoidCallback? onLoad,
  }) async {
    await _loadCampusFont();
    tester.view.physicalSize = const Size(384, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          weatherProvider.overrideWith((ref) {
            onLoad?.call();
            return Stream<CachedEntry<WeatherSnapshot>>.value(entry);
          }),
        ],
        child: MaterialApp(theme: campusTheme(Brightness.light), home: home),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows the forecast once it has one', (tester) async {
    await pump(
      tester,
      const WeatherScreen(),
      CachedEntry<WeatherSnapshot>(
        data: snapshot(),
        cachedAt: DateTime(2026, 9, 2, 14),
      ),
    );
    expect(find.byType(WeatherBody), findsOneWidget);
  });

  testWidgets('can be pulled down to refresh', (tester) async {
    var loads = 0;
    await pump(
      tester,
      const WeatherScreen(),
      CachedEntry<WeatherSnapshot>(
        data: snapshot(),
        cachedAt: DateTime(2026, 9, 2, 14),
      ),
      onLoad: () => loads++,
    );
    expect(loads, 1);
    await tester.drag(find.byType(ListView), const Offset(0, 350));
    await tester.pumpAndSettle();
    expect(loads, 2);
  });

  testWidgets('keeps a stale forecast when the refresh fails', (tester) async {
    await pump(
      tester,
      const WeatherScreen(),
      CachedEntry<WeatherSnapshot>(
        data: snapshot(),
        cachedAt: DateTime(2026, 9, 2, 14),
        refreshState: RefreshState.failedOffline,
      ),
    );
    expect(find.byType(WeatherBody), findsOneWidget);
    expect(find.textContaining('Hors ligne'), findsOneWidget);
  });

  testWidgets('offers a retry when it has nothing to show', (tester) async {
    await pump(
      tester,
      const WeatherScreen(),
      const CachedEntry<WeatherSnapshot>(
        refreshState: RefreshState.failedUpstream,
      ),
    );
    expect(find.text('Réessayer'), findsOneWidget);
  });

  testWidgets('the home row opens the weather page', (tester) async {
    await pump(
      tester,
      const Scaffold(body: WeatherStrip()),
      CachedEntry<WeatherSnapshot>(
        data: snapshot(),
        cachedAt: DateTime(2026, 9, 2, 14),
      ),
    );
    await tester.tap(find.byType(WeatherStripView));
    await tester.pumpAndSettle();
    expect(find.byType(WeatherBody), findsOneWidget);
  });
}
