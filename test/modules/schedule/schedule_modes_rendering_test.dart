import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/modules/schedule/month_grid.dart';
import 'package:notes_insa/modules/schedule/schedule_day_index.dart';
import 'package:notes_insa/modules/schedule/schedule_event.dart';
import 'package:notes_insa/modules/schedule/schedule_grid.dart';
import 'package:notes_insa/theme/campus_theme.dart';

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
        title: 'Thermoénergétique',
        start: DateTime(2026, 9, 7, 8, 15),
        end: DateTime(2026, 9, 7, 10, 15),
        groups: const <String>[],
        teachers: const <String>['LEY OLIVIER'],
        room: 'Amphi C (V)',
      ),
    ],
    from: monday,
    to: DateTime(2026, 9, 30),
  );

  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    required Brightness brightness,
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

  Widget grid(int columns) => ScheduleGrid(
    index: index(),
    days: <DateTime>[
      for (var i = 0; i < columns; i++)
        DateTime(monday.year, monday.month, monday.day + i),
    ],
    onTapEvent: (_) {},
    now: DateTime(2026, 9, 7, 9),
  );

  for (final columns in <int>[1, 3, 7]) {
    testWidgets('the $columns column grid renders in dark mode', (
      tester,
    ) async {
      await pump(tester, grid(columns), brightness: Brightness.dark);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the $columns column grid survives 200 percent text', (
      tester,
    ) async {
      await pump(
        tester,
        grid(columns),
        brightness: Brightness.light,
        textScale: 2.0,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('the month grid renders in dark mode', (tester) async {
    await pump(
      tester,
      MonthGrid(index: index(), month: monday, onPickDay: (_) {}),
      brightness: Brightness.dark,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the month grid survives 200 percent text', (tester) async {
    await pump(
      tester,
      MonthGrid(index: index(), month: monday, onPickDay: (_) {}),
      brightness: Brightness.light,
      textScale: 2.0,
    );
    expect(tester.takeException(), isNull);
  });
}
