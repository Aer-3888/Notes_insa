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

  testWidgets('a two-finger pinch drags and commits the Week day width', (
    tester,
  ) async {
    final dragged = <double>[];
    final committed = <double>[];
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
              for (var i = 0; i < 7; i++)
                DateTime(monday.year, monday.month, monday.day + i),
            ],
            minColumnWidth: 104,
            onTapEvent: (_) {},
            onDayWidthDrag: dragged.add,
            onDayWidthCommit: committed.add,
          ),
        ),
      ),
    );
    await tester.pump();

    final first = await tester.startGesture(const Offset(100, 300), pointer: 1);
    final second = await tester.startGesture(
      const Offset(220, 300),
      pointer: 2,
    );
    await tester.pump();
    await first.moveTo(const Offset(70, 300));
    await second.moveTo(const Offset(260, 300));
    await tester.pump();

    expect(dragged, isNotEmpty);
    expect(find.textContaining('Largeur des jours'), findsOneWidget);

    await first.up();
    await second.up();
    await tester.pump();
    expect(committed, hasLength(1));
    expect(committed.single, greaterThan(104));
    expect(committed.single % 4, 0);
  });

  testWidgets('a vertical two-finger pinch drags and commits hour height', (
    tester,
  ) async {
    final dragged = <double>[];
    final committed = <double>[];
    tester.view.physicalSize = const Size(384, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: campusTheme(Brightness.light),
        home: Scaffold(
          body: ScheduleGrid(
            index: index(),
            days: <DateTime>[monday],
            onTapEvent: (_) {},
            onHourHeightDrag: dragged.add,
            onHourHeightCommit: committed.add,
          ),
        ),
      ),
    );
    await tester.pump();

    final first = await tester.startGesture(const Offset(180, 220), pointer: 1);
    final second = await tester.startGesture(
      const Offset(180, 380),
      pointer: 2,
    );
    await tester.pump();
    await first.moveTo(const Offset(180, 180));
    await second.moveTo(const Offset(180, 430));
    await tester.pump();

    expect(dragged, isNotEmpty);
    expect(find.textContaining('Hauteur des heures'), findsOneWidget);

    await first.up();
    await second.up();
    await tester.pump();
    expect(committed, hasLength(1));
    expect(committed.single, greaterThan(kDefaultScheduleHourHeight));
    expect(committed.single % 4, 0);
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

  testWidgets('a 30 minute class is still a 48 dp touch target', (
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
                  'Distribution calculatrice',
                  DateTime(2026, 9, 7, 11, 30),
                  DateTime(2026, 9, 7, 12),
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
    // Proportionally this is 32 dp, which CP-10 would fail.
    expect(
      tester.getSize(find.byType(GridBlock)).height,
      greaterThanOrEqualTo(48),
    );
  });

  testWidgets('renders all 24 hours in the gutter from 00 to 23', (
    tester,
  ) async {
    await pump(tester, days: <DateTime>[DateTime(2026, 9, 12)]);
    expect(find.text('00'), findsOneWidget);
    expect(find.text('08'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('23'), findsOneWidget);
  });

  testWidgets('synchronizes vertical offset from notifier', (tester) async {
    final notifier = ValueNotifier<double>(200.0);
    tester.view.physicalSize = const Size(384, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: campusTheme(Brightness.light),
        home: Scaffold(
          body: ScheduleGrid(
            index: index(),
            days: <DateTime>[monday],
            onTapEvent: (_) {},
            verticalOffsetNotifier: notifier,
          ),
        ),
      ),
    );
    await tester.pump();

    final scrollable = tester.state<ScrollableState>(
      find.byWidgetPredicate(
        (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
      ),
    );
    expect(scrollable.position.pixels, 200.0);

    notifier.value = 400.0;
    await tester.pump();
    expect(scrollable.position.pixels, 400.0);
  });
}
