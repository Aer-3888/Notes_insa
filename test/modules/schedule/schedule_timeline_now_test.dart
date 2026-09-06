import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/modules/schedule/schedule_day_index.dart';
import 'package:notes_insa/modules/schedule/schedule_event.dart';
import 'package:notes_insa/modules/schedule/schedule_timeline.dart';
import 'package:notes_insa/theme/campus_theme.dart';
import 'package:notes_insa/theme/now_line.dart';

ScheduleEvent _event(String title, DateTime start, DateTime end) =>
    ScheduleEvent(
      title: title,
      start: start,
      end: end,
      groups: const <String>[],
      teachers: const <String>[],
    );

void main() {
  final monday = DateTime(2026, 9, 7);

  Future<void> pump(WidgetTester tester, DateTime now) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: campusTheme(Brightness.light),
        home: Scaffold(
          body: ScheduleTimeline(
            index: ScheduleDayIndex.build(
              events: <ScheduleEvent>[
                _event('A', DateTime(2026, 9, 7, 8), DateTime(2026, 9, 7, 10)),
                _event('B', DateTime(2026, 9, 7, 12), DateTime(2026, 9, 7, 14)),
              ],
              from: monday,
              to: monday,
            ),
            controller: ScrollController(),
            now: now,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('now inside a gap draws the line in the gap row', (tester) async {
    await pump(tester, DateTime(2026, 9, 7, 11));
    expect(find.byType(NowLine), findsOneWidget);
  });

  testWidgets('now inside a class draws no line through the row', (
    tester,
  ) async {
    await pump(tester, DateTime(2026, 9, 7, 9));
    expect(find.byType(NowLine), findsNothing);
    expect(find.text('en cours'), findsOneWidget);
  });

  testWidgets('a day that is not today has no now treatment', (tester) async {
    await pump(tester, DateTime(2026, 9, 9, 11));
    expect(find.byType(NowLine), findsNothing);
    expect(find.text('en cours'), findsNothing);
  });
}
