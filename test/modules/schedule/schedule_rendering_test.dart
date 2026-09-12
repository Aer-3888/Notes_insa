import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/modules/schedule/month_grid.dart';
import 'package:notes_insa/modules/schedule/schedule_day_index.dart';
import 'package:notes_insa/modules/schedule/schedule_event.dart';
import 'package:notes_insa/modules/schedule/schedule_timeline.dart';
import 'package:notes_insa/modules/schedule/week_strip.dart';
import 'package:notes_insa/theme/campus_theme.dart';

/// The default test font draws every glyph as a square of the font size, so a
/// layout that fits in the shipped font wraps and overflows here. Any
/// rendering assertion has to measure the real typeface.
Future<void> _loadCampusFont() async {
  final bytes = File('assets/fonts/PublicSans-Variable.ttf').readAsBytesSync();
  await (FontLoader(
    kCampusFontFamily,
  )..addFont(Future<ByteData>.value(ByteData.view(bytes.buffer)))).load();
}

void main() {
  final monday = DateTime(2026, 9, 7);

  ScheduleDayIndex index() => ScheduleDayIndex.build(
    events: <ScheduleEvent>[
      ScheduleEvent(
        title: 'Algèbre 3',
        start: DateTime(2026, 9, 7, 8, 15),
        end: DateTime(2026, 9, 7, 10, 15),
        groups: const <String>[],
        teachers: const <String>['CAMAR-EDDINE MOHAMED'],
        room: 'Amphi C (V)',
      ),
      ScheduleEvent(
        title: 'Thermoénergétique',
        start: DateTime(2026, 9, 7, 14),
        end: DateTime(2026, 9, 7, 16),
        groups: const <String>[],
        teachers: const <String>['LEY OLIVIER'],
        room: 'B12',
      ),
    ],
    from: monday,
    to: DateTime(2026, 9, 13),
  );

  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    required Brightness brightness,
    double textScale = 1.0,
  }) async {
    await _loadCampusFont();
    tester.view.physicalSize = const Size(360, 800);
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

  Widget strip() => WeekStrip(
    index: index(),
    weekOf: monday,
    currentDay: monday,
    today: monday,
    onDayTap: (_) {},
  );

  Widget month() => MonthGrid(
    index: index(),
    month: monday,
    today: monday,
    onPickDay: (_) {},
  );

  Widget timeline() => ScheduleTimeline(
    index: index(),
    controller: ScrollController(),
    now: DateTime(2026, 9, 7, 11),
  );

  testWidgets('the strip renders in dark mode', (tester) async {
    await pump(tester, strip(), brightness: Brightness.dark);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the timeline renders in dark mode', (tester) async {
    await pump(tester, timeline(), brightness: Brightness.dark);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the strip survives 200 percent text scale', (tester) async {
    await pump(tester, strip(), brightness: Brightness.light, textScale: 2.0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the timeline survives 200 percent text scale', (tester) async {
    await pump(
      tester,
      timeline(),
      brightness: Brightness.light,
      textScale: 2.0,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the month cells render in dark mode', (tester) async {
    await pump(tester, month(), brightness: Brightness.dark);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the month cells survive 200 percent text scale', (tester) async {
    await pump(tester, month(), brightness: Brightness.light, textScale: 2.0);
    expect(tester.takeException(), isNull);
  });
}
