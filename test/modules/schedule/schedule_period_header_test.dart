import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/modules/schedule/schedule_period.dart';
import 'package:notes_insa/modules/schedule/schedule_period_header.dart';
import 'package:notes_insa/modules/schedule/schedule_view_mode.dart';
import 'package:notes_insa/theme/campus_theme.dart';

void main() {
  final tuesday = DateTime(2026, 9, 8);

  Future<List<int>> pump(
    WidgetTester tester, {
    required ScheduleViewMode mode,
    required DateTime day,
    required DateTime today,
    VoidCallback? onToday,
    double textScale = 1.0,
  }) async {
    final shifts = <int>[];
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: campusTheme(Brightness.light),
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: Scaffold(
            body: SchedulePeriodHeader(
              mode: mode,
              day: day,
              today: today,
              onShift: shifts.add,
              onToday: onToday ?? () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return shifts;
  }

  testWidgets('names the period on screen', (tester) async {
    await pump(
      tester,
      mode: ScheduleViewMode.semaine,
      day: tuesday,
      today: tuesday,
    );
    expect(find.text('du 7 au 13 septembre'), findsOneWidget);
  });

  testWidgets('the arrows step one period each way', (tester) async {
    final shifts = await pump(
      tester,
      mode: ScheduleViewMode.semaine,
      day: tuesday,
      today: tuesday,
    );
    await tester.tap(find.byTooltip('Période suivante'));
    await tester.tap(find.byTooltip('Période précédente'));
    await tester.pump();
    expect(shifts, <int>[1, -1]);
  });

  testWidgets('offers a way back only when today is off screen', (
    tester,
  ) async {
    await pump(
      tester,
      mode: ScheduleViewMode.semaine,
      day: tuesday,
      today: tuesday,
    );
    expect(find.byTooltip('Aujourd’hui'), findsNothing);

    await pump(
      tester,
      mode: ScheduleViewMode.semaine,
      day: DateTime(2026, 9, 22),
      today: tuesday,
    );
    expect(find.byTooltip('Aujourd’hui'), findsOneWidget);
  });

  testWidgets('going back to today is reported', (tester) async {
    var returned = 0;
    await pump(
      tester,
      mode: ScheduleViewMode.semaine,
      day: DateTime(2026, 9, 22),
      today: tuesday,
      onToday: () => returned++,
    );
    await tester.tap(find.byTooltip('Aujourd’hui'));
    await tester.pump();
    expect(returned, 1);
  });

  testWidgets('survives 200 percent text on a 360 dp phone', (tester) async {
    await pump(
      tester,
      mode: ScheduleViewMode.troisJours,
      day: DateTime(2026, 9, 30),
      today: tuesday,
      textScale: 2.0,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('reads the month in Mois', (tester) async {
    await pump(
      tester,
      mode: ScheduleViewMode.mois,
      day: tuesday,
      today: tuesday,
    );
    expect(
      find.text(periodLabel(ScheduleViewMode.mois, tuesday)),
      findsOneWidget,
    );
  });
}
