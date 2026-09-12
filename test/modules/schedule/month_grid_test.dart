import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/modules/schedule/month_grid.dart';
import 'package:notes_insa/modules/schedule/schedule_day_index.dart';
import 'package:notes_insa/modules/schedule/schedule_event.dart';
import 'package:notes_insa/theme/campus_theme.dart';

void main() {
  final september = DateTime(2026, 9, 1);

  ScheduleDayIndex index({int busyDayClasses = 1}) => ScheduleDayIndex.build(
    events: <ScheduleEvent>[
      ScheduleEvent(
        title: 'Algèbre 3',
        start: DateTime(2026, 9, 7, 8),
        end: DateTime(2026, 9, 7, 10),
        groups: const <String>[],
        teachers: const <String>[],
      ),
      // Stacked on one day, to push the cell past what it can draw.
      for (var i = 1; i < busyDayClasses; i++)
        ScheduleEvent(
          title: 'Cours $i',
          start: DateTime(2026, 9, 7, 10 + i),
          end: DateTime(2026, 9, 7, 11 + i),
          groups: const <String>[],
          teachers: const <String>[],
        ),
    ],
    from: september,
    to: DateTime(2026, 9, 30),
  );

  Future<List<DateTime>> pump(
    WidgetTester tester, {
    bool showPreview = true,
    int busyDayClasses = 1,
  }) async {
    final picked = <DateTime>[];
    tester.view.physicalSize = const Size(384, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: campusTheme(Brightness.light),
        home: Scaffold(
          body: MonthGrid(
            index: index(busyDayClasses: busyDayClasses),
            month: september,
            onPickDay: picked.add,
            showPreview: showPreview,
          ),
        ),
      ),
    );
    await tester.pump();
    return picked;
  }

  testWidgets('every day of the month has a cell', (tester) async {
    await pump(tester);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('30'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the weekday header starts on Monday', (tester) async {
    await pump(tester);
    expect(find.text('L'), findsWidgets);
    expect(find.text('D'), findsWidgets);
  });

  testWidgets('tapping a day reports that date', (tester) async {
    final picked = await pump(tester);
    await tester.tap(find.text('7'));
    await tester.pump();
    expect(picked.single, DateTime(2026, 9, 7));
  });

  testWidgets('a cell names the class it holds', (tester) async {
    await pump(tester);
    expect(find.text('Algèbre 3'), findsOneWidget);
  });

  testWidgets('the preview off leaves a bare picker', (tester) async {
    await pump(tester, showPreview: false);
    expect(find.text('Algèbre 3'), findsNothing);
    expect(find.text('7'), findsOneWidget);
  });

  testWidgets('a cell that cannot hold them all counts the rest', (
    tester,
  ) async {
    await pump(tester, busyDayClasses: 8);
    expect(find.textContaining(RegExp(r'^\+\d+$')), findsOneWidget);
  });
}
