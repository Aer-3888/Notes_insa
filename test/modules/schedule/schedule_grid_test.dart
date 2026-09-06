import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/modules/schedule/grid_block.dart';
import 'package:notes_insa/modules/schedule/schedule_day_index.dart';
import 'package:notes_insa/modules/schedule/schedule_event.dart';
import 'package:notes_insa/modules/schedule/schedule_grid.dart';
import 'package:notes_insa/theme/campus_theme.dart';

ScheduleEvent _event(
  String title,
  DateTime start,
  DateTime end, {
  String? room,
}) => ScheduleEvent(
  title: title,
  start: start,
  end: end,
  groups: const <String>[],
  teachers: const <String>[],
  room: room,
);

void main() {
  final monday = DateTime(2026, 9, 7);

  ScheduleDayIndex index() => ScheduleDayIndex.build(
    events: <ScheduleEvent>[
      _event(
        'Algèbre 3',
        DateTime(2026, 9, 7, 8),
        DateTime(2026, 9, 7, 10),
        room: 'Amphi C',
      ),
      _event('Physique', DateTime(2026, 9, 7, 14), DateTime(2026, 9, 7, 16)),
    ],
    from: monday,
    to: DateTime(2026, 9, 13),
  );

  Future<List<ScheduleEvent>> pump(
    WidgetTester tester, {
    required List<DateTime> days,
  }) async {
    final tapped = <ScheduleEvent>[];
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
            onTapEvent: tapped.add,
          ),
        ),
      ),
    );
    await tester.pump();
    return tapped;
  }

  testWidgets('one column renders that day and no other', (tester) async {
    await pump(tester, days: <DateTime>[monday]);
    expect(find.byType(GridBlock), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a day with nothing renders the gutter and no blocks', (
    tester,
  ) async {
    await pump(tester, days: <DateTime>[DateTime(2026, 9, 12)]);
    expect(find.byType(GridBlock), findsNothing);
    expect(find.text('08'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping a block reports its event', (tester) async {
    final tapped = await pump(tester, days: <DateTime>[monday]);
    await tester.tap(find.byType(GridBlock).first);
    await tester.pump();
    expect(tapped.single.title, 'Algèbre 3');
  });

  testWidgets('a longer class is drawn taller than a shorter one', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(384, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: campusTheme(Brightness.light),
        home: Scaffold(
          body: ScheduleGrid(
            index: ScheduleDayIndex.build(
              events: <ScheduleEvent>[
                _event(
                  'court',
                  DateTime(2026, 9, 7, 8),
                  DateTime(2026, 9, 7, 8, 30),
                ),
                _event(
                  'long',
                  DateTime(2026, 9, 7, 10),
                  DateTime(2026, 9, 7, 14),
                ),
              ],
              from: monday,
              to: monday,
            ),
            days: <DateTime>[monday],
            onTapEvent: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();
    final sizes = tester
        .widgetList<GridBlock>(find.byType(GridBlock))
        .map((w) => tester.getSize(find.byWidget(w)).height)
        .toList();
    expect(sizes.first, lessThan(sizes.last));
  });
}
