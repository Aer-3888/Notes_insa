import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/modules/schedule/schedule_day_index.dart';
import 'package:notes_insa/modules/schedule/schedule_event.dart';
import 'package:notes_insa/modules/schedule/grid_block.dart';
import 'package:notes_insa/modules/schedule/schedule_grid.dart';
import 'package:notes_insa/theme/campus_theme.dart';

void main() {
  final monday = DateTime(2026, 9, 7);

  ScheduleDayIndex index() => ScheduleDayIndex.build(
    events: <ScheduleEvent>[
      for (var i = 0; i < 5; i++)
        ScheduleEvent(
          title: 'Algèbre 3',
          start: DateTime(2026, 9, 7 + i, 8),
          end: DateTime(2026, 9, 7 + i, 10),
          groups: const <String>[],
          teachers: const <String>[],
          module: 'Algèbre 3',
          room: 'Amphi C',
        ),
      ScheduleEvent(
        title: 'Physique',
        start: DateTime(2026, 9, 7, 16),
        end: DateTime(2026, 9, 7, 18),
        groups: const <String>[],
        teachers: const <String>[],
        module: 'Physique',
      ),
    ],
    from: monday,
    to: DateTime(2026, 9, 13),
  );

  List<DateTime> span(int count) => <DateTime>[
    for (var i = 0; i < count; i++)
      DateTime(monday.year, monday.month, monday.day + i),
  ];

  Future<void> pump(WidgetTester tester, int columns) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: campusTheme(Brightness.light),
        home: Scaffold(
          body: ScheduleGrid(
            index: index(),
            days: span(columns),
            onTapEvent: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();
  }

  List<ScrollPosition> horizontals(WidgetTester tester) => tester
      .stateList<ScrollableState>(find.byType(Scrollable))
      .map((s) => s.position)
      .where((p) => p.axis == Axis.horizontal)
      .toList();

  testWidgets('a week keeps its labels rather than showing bare bars', (
    tester,
  ) async {
    await pump(tester, 7);
    expect(find.text('Algèbre 3'), findsWidgets);
    expect(find.text('Amphi C'), findsWidgets);
  });

  testWidgets('a week is wider than the screen and scrolls sideways', (
    tester,
  ) async {
    await pump(tester, 7);
    expect(horizontals(tester), isNotEmpty);
    expect(horizontals(tester).first.maxScrollExtent, greaterThan(0));
  });

  testWidgets('three days still fit, so nothing scrolls sideways', (
    tester,
  ) async {
    await pump(tester, 3);
    for (final position in horizontals(tester)) {
      expect(position.maxScrollExtent, 0);
    }
  });

  testWidgets('dragging an empty part of a column still scrolls', (
    tester,
  ) async {
    await pump(tester, 7);
    // 11 h on a column whose only class ended at 10 h: no block to catch it.
    await tester.dragFrom(const Offset(200, 250), const Offset(-120, 0));
    await tester.pumpAndSettle();
    expect(horizontals(tester).last.pixels, greaterThan(0));
  });

  testWidgets('the headings follow the columns', (tester) async {
    await pump(tester, 7);
    await tester.drag(find.byType(GridBlock).first, const Offset(-120, 0));
    await tester.pumpAndSettle();
    final offsets = horizontals(tester).map((p) => p.pixels).toSet();
    expect(offsets.length, 1, reason: 'headings drifted from the columns');
    expect(offsets.single, greaterThan(0));
  });
}
