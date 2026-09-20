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
    VoidCallback? onPickDate,
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
              onPickDate: onPickDate ?? () {},
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

  testWidgets('the period label opens date selection', (tester) async {
    var opened = 0;
    await pump(
      tester,
      mode: ScheduleViewMode.semaine,
      day: tuesday,
      today: tuesday,
      onPickDate: () => opened++,
    );

    await tester.tap(find.byTooltip('Choisir une date'));
    await tester.pump();
    expect(opened, 1);
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

  group('the today button', () {
    Offset centerOf(WidgetTester tester, String tooltip) =>
        tester.getCenter(find.byTooltip(tooltip));

    testWidgets('appearing leaves both arrows where they were', (tester) async {
      await pump(
        tester,
        mode: ScheduleViewMode.semaine,
        day: tuesday,
        today: tuesday,
      );
      final back = centerOf(tester, 'Période précédente');
      final forward = centerOf(tester, 'Période suivante');

      await pump(
        tester,
        mode: ScheduleViewMode.semaine,
        day: DateTime(2026, 9, 22),
        today: tuesday,
      );

      expect(find.byTooltip('Aujourd’hui'), findsOneWidget);
      expect(centerOf(tester, 'Période précédente'), back);
      expect(centerOf(tester, 'Période suivante'), forward);
    });

    testWidgets('sits left of both arrows', (tester) async {
      await pump(
        tester,
        mode: ScheduleViewMode.semaine,
        day: DateTime(2026, 9, 22),
        today: tuesday,
      );
      final today = centerOf(tester, 'Aujourd’hui').dx;
      expect(today, lessThan(centerOf(tester, 'Période précédente').dx));
      expect(today, lessThan(centerOf(tester, 'Période suivante').dx));
    });

    testWidgets('appearing does not hand its element to an arrow', (
      tester,
    ) async {
      // Unkeyed, the children match by position when this button appears, so
      // each arrow inherits its neighbour's element and the tap ripple plays
      // on the icon next door.
      await pump(
        tester,
        mode: ScheduleViewMode.semaine,
        day: tuesday,
        today: tuesday,
      );
      final back = tester.element(find.byTooltip('Période précédente'));
      final forward = tester.element(find.byTooltip('Période suivante'));

      await pump(
        tester,
        mode: ScheduleViewMode.semaine,
        day: DateTime(2026, 9, 22),
        today: tuesday,
      );

      expect(tester.element(find.byTooltip('Période précédente')), back);
      expect(tester.element(find.byTooltip('Période suivante')), forward);
      expect(
        tester.element(find.byTooltip('Aujourd’hui')),
        isNot(anyOf(back, forward)),
      );
    });

    testWidgets('never lands where an arrow was', (tester) async {
      await pump(
        tester,
        mode: ScheduleViewMode.semaine,
        day: tuesday,
        today: tuesday,
      );
      final arrows = <Offset>[
        centerOf(tester, 'Période précédente'),
        centerOf(tester, 'Période suivante'),
      ];

      await pump(
        tester,
        mode: ScheduleViewMode.semaine,
        day: DateTime(2026, 9, 22),
        today: tuesday,
      );
      expect(arrows, isNot(contains(centerOf(tester, 'Aujourd’hui'))));
    });
  });
}
