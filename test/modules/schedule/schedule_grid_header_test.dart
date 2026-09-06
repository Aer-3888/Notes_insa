import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/modules/schedule/schedule_day_index.dart';
import 'package:notes_insa/modules/schedule/schedule_event.dart';
import 'package:notes_insa/modules/schedule/schedule_grid.dart';
import 'package:notes_insa/theme/campus_theme.dart';

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
      ),
    ],
    from: monday,
    to: DateTime(2026, 9, 13),
  );

  List<DateTime> span(int count) => <DateTime>[
    for (var i = 0; i < count; i++)
      DateTime(monday.year, monday.month, monday.day + i),
  ];

  Future<List<DateTime>> pump(
    WidgetTester tester, {
    required List<DateTime> days,
    DateTime? now,
  }) async {
    final picked = <DateTime>[];
    tester.view.physicalSize = const Size(384, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: campusTheme(Brightness.light),
        home: Scaffold(
          body: ScheduleGrid(
            index: index(),
            days: days,
            now: now,
            onTapEvent: (_) {},
            onPickDay: picked.add,
          ),
        ),
      ),
    );
    await tester.pump();
    return picked;
  }

  testWidgets('every column of a multi-day grid is named and dated', (
    tester,
  ) async {
    await pump(tester, days: span(3));
    for (final label in <String>['lun', 'mar', 'mer']) {
      expect(find.text(label), findsOneWidget);
    }
    for (final day in <String>['7', '8', '9']) {
      expect(find.text(day), findsOneWidget);
    }
  });

  testWidgets('a week names all seven columns', (tester) async {
    await pump(tester, days: span(7));
    expect(find.byType(ScheduleDayHeading), findsNWidgets(7));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a single day carries no heading, the page already names it', (
    tester,
  ) async {
    await pump(tester, days: span(1));
    expect(find.byType(ScheduleDayHeading), findsNothing);
  });

  testWidgets('tapping a column heading picks that day', (tester) async {
    final picked = await pump(tester, days: span(3));
    await tester.tap(find.text('mar'));
    await tester.pump();
    expect(picked.single, DateTime(2026, 9, 8));
  });

  testWidgets('the columns are separated so a day cannot bleed into the next', (
    tester,
  ) async {
    await pump(tester, days: span(3));
    expect(find.byType(ScheduleColumnRule), findsNWidgets(2));
  });

  testWidgets('today is marked among the columns', (tester) async {
    await pump(tester, days: span(3), now: DateTime(2026, 9, 8, 10));
    final headings = tester.widgetList<ScheduleDayHeading>(
      find.byType(ScheduleDayHeading),
    );
    expect(headings.where((h) => h.isToday).length, 1);
  });

  testWidgets('survives 200 percent text at seven columns', (tester) async {
    tester.view.physicalSize = const Size(384, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: campusTheme(Brightness.light),
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: ScheduleGrid(
              index: index(),
              days: span(7),
              onTapEvent: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
