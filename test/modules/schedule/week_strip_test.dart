import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/modules/schedule/schedule_day_index.dart';
import 'package:notes_insa/modules/schedule/schedule_event.dart';
import 'package:notes_insa/modules/schedule/week_strip.dart';
import 'package:notes_insa/theme/campus_theme.dart';

ScheduleEvent _event(DateTime start, DateTime end) => ScheduleEvent(
  title: 'Cours',
  start: start,
  end: end,
  groups: const <String>[],
  teachers: const <String>[],
);

void main() {
  final monday = DateTime(2026, 9, 7);
  final sunday = DateTime(2026, 9, 13);

  ScheduleDayIndex withEvents() => ScheduleDayIndex.build(
    events: <ScheduleEvent>[
      _event(DateTime(2026, 9, 7, 8), DateTime(2026, 9, 7, 10)),
      _event(DateTime(2026, 9, 9, 14), DateTime(2026, 9, 9, 16)),
    ],
    from: monday,
    to: sunday,
  );

  Future<DateTime?> pump(
    WidgetTester tester, {
    required ScheduleDayIndex index,
    DateTime? today,
  }) async {
    DateTime? tapped;
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: campusTheme(Brightness.light),
        home: Scaffold(
          body: WeekStrip(
            index: index,
            weekOf: monday,
            currentDay: monday,
            today: today,
            onDayTap: (d) => tapped = d,
          ),
        ),
      ),
    );
    await tester.pump();
    return tapped;
  }

  testWidgets('the strip has seven day columns', (tester) async {
    await pump(tester, index: withEvents());
    for (final label in <String>[
      'lun',
      'mar',
      'mer',
      'jeu',
      'ven',
      'sam',
      'dim',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets('a day with events renders a bar, an empty day does not', (
    tester,
  ) async {
    await pump(tester, index: withEvents());
    expect(find.byType(WeekStripBar), findsNWidgets(2));
  });

  testWidgets('tapping a day reports it', (tester) async {
    DateTime? tapped;
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: campusTheme(Brightness.light),
        home: Scaffold(
          body: WeekStrip(
            index: ScheduleDayIndex.build(
              events: const <ScheduleEvent>[],
              from: monday,
              to: sunday,
            ),
            weekOf: monday,
            currentDay: monday,
            onDayTap: (d) => tapped = d,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('mer'));
    await tester.pump();
    expect(tapped, DateTime(2026, 9, 9));
  });

  testWidgets('a day column carries a semantics label', (tester) async {
    await pump(tester, index: withEvents());
    expect(
      find.bySemanticsLabel('lundi 7, 1 cours, de 8 h à 10 h'),
      findsOneWidget,
    );
  });

  testWidgets('an empty day says so in semantics', (tester) async {
    await pump(tester, index: withEvents());
    expect(find.bySemanticsLabel('mardi 8, rien de prévu'), findsOneWidget);
  });
}
