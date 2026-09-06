import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/modules/schedule/grid_block.dart';
import 'package:notes_insa/modules/schedule/schedule_day_index.dart';
import 'package:notes_insa/modules/schedule/schedule_event.dart';
import 'package:notes_insa/modules/schedule/schedule_grid.dart';
import 'package:notes_insa/theme/campus_theme.dart';

/// Without the shipped font every glyph is a square and these width
/// assertions measure the harness instead of the app.
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
        start: DateTime(2026, 9, 7, 8),
        end: DateTime(2026, 9, 7, 10),
        groups: const <String>[],
        teachers: const <String>[],
        room: 'Amphi C',
      ),
    ],
    from: monday,
    to: DateTime(2026, 9, 13),
  );

  Future<void> pump(WidgetTester tester, int columns) async {
    await _loadCampusFont();
    tester.view.physicalSize = const Size(384, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: campusTheme(Brightness.light),
        home: Scaffold(
          body: ScheduleGrid(
            index: index(),
            days: <DateTime>[
              for (var i = 0; i < columns; i++)
                DateTime(monday.year, monday.month, monday.day + i),
            ],
            onTapEvent: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('three columns carry the module name', (tester) async {
    await pump(tester, 3);
    expect(find.text('Algèbre 3'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('seven columns on a 384 dp phone carry no label', (tester) async {
    // 344 dp of body over seven columns is 49.1 dp, and the shortest real
    // module name needs 55.7 dp.
    await pump(tester, 7);
    expect(find.byType(GridBlock), findsOneWidget);
    expect(find.text('Algèbre 3'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('one column carries the module and the room', (tester) async {
    await pump(tester, 1);
    expect(find.text('Algèbre 3'), findsOneWidget);
    expect(find.text('Amphi C'), findsOneWidget);
  });
}
