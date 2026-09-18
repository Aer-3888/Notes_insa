import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/core/module_cache.dart';
import 'package:notes_insa/core/time.dart';
import 'package:notes_insa/modules/schedule/month_grid.dart';
import 'package:notes_insa/modules/schedule/schedule_event.dart';
import 'package:notes_insa/modules/schedule/schedule_grid.dart';
import 'package:notes_insa/modules/schedule/schedule_provider.dart';
import 'package:notes_insa/modules/schedule/schedule_screen.dart';
import 'package:notes_insa/modules/schedule/schedule_view_mode.dart';
import 'package:notes_insa/theme/campus_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _PickedGroups extends SelectedGroups {
  @override
  List<int> build() => const <int>[1214];
}

const _entry = CachedEntry<List<ScheduleEvent>>(data: <ScheduleEvent>[]);

void main() {
  setUpAll(initCampusTime);

  Future<void> pump(WidgetTester tester, ScheduleViewMode mode) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      kScheduleViewModeKey: mode.name,
    });
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          selectedGroupsProvider.overrideWith(_PickedGroups.new),
          scheduleProvider.overrideWith(
            (ref) => Stream<CachedEntry<List<ScheduleEvent>>>.value(_entry),
          ),
        ],
        child: MaterialApp(
          theme: campusTheme(Brightness.light),
          home: const ScheduleScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('can swipe forward to future month and back to current month', (
    tester,
  ) async {
    await pump(tester, ScheduleViewMode.mois);
    final initialMonth = tester.widget<MonthGrid>(find.byType(MonthGrid)).month;

    // Swipe left (forward into next month)
    await tester.fling(find.byType(MonthGrid), const Offset(-400, 0), 1000);
    await tester.pumpAndSettle();
    final nextMonth = tester.widget<MonthGrid>(find.byType(MonthGrid)).month;
    expect(
      (nextMonth.year - initialMonth.year) * 12 +
          nextMonth.month -
          initialMonth.month,
      1,
    );

    // Swipe right (backward into current month)
    await tester.fling(find.byType(MonthGrid), const Offset(400, 0), 1000);
    await tester.pumpAndSettle();
    final backMonth = tester.widget<MonthGrid>(find.byType(MonthGrid)).month;
    expect(backMonth.year, initialMonth.year);
    expect(backMonth.month, initialMonth.month);
  });

  testWidgets('can swipe backward into past months from current month', (
    tester,
  ) async {
    await pump(tester, ScheduleViewMode.mois);
    final initialMonth = tester.widget<MonthGrid>(find.byType(MonthGrid)).month;

    // Swipe right (backward into previous month)
    await tester.fling(find.byType(MonthGrid), const Offset(400, 0), 1000);
    await tester.pumpAndSettle();
    final prevMonth = tester.widget<MonthGrid>(find.byType(MonthGrid)).month;
    expect(
      (initialMonth.year - prevMonth.year) * 12 +
          initialMonth.month -
          prevMonth.month,
      1,
    );

    // Swipe right again (two months in the past)
    await tester.fling(find.byType(MonthGrid), const Offset(400, 0), 1000);
    await tester.pumpAndSettle();
    final twoMonthsAgo = tester.widget<MonthGrid>(find.byType(MonthGrid)).month;
    expect(
      (initialMonth.year - twoMonthsAgo.year) * 12 +
          initialMonth.month -
          twoMonthsAgo.month,
      2,
    );
  });

  testWidgets('header arrows navigate months backward and forward', (
    tester,
  ) async {
    await pump(tester, ScheduleViewMode.mois);
    final initialMonth = tester.widget<MonthGrid>(find.byType(MonthGrid)).month;

    // Tap previous period arrow
    await tester.tap(find.byTooltip('Période précédente'));
    await tester.pumpAndSettle();
    final prevMonth = tester.widget<MonthGrid>(find.byType(MonthGrid)).month;
    expect(
      (initialMonth.year - prevMonth.year) * 12 +
          initialMonth.month -
          prevMonth.month,
      1,
    );

    // Tap next period arrow twice (back to current, then next)
    await tester.tap(find.byTooltip('Période suivante'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Période suivante'));
    await tester.pumpAndSettle();
    final nextMonth = tester.widget<MonthGrid>(find.byType(MonthGrid)).month;
    expect(
      (nextMonth.year - initialMonth.year) * 12 +
          nextMonth.month -
          initialMonth.month,
      1,
    );
  });

  testWidgets('Aujourd’hui button in Month view returns from past month', (
    tester,
  ) async {
    await pump(tester, ScheduleViewMode.mois);
    final initialMonth = tester.widget<MonthGrid>(find.byType(MonthGrid)).month;

    // Today button should initially not be shown on current month
    expect(find.byTooltip('Aujourd’hui'), findsNothing);

    // Move 3 months backward
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byTooltip('Période précédente'));
      await tester.pumpAndSettle();
    }
    expect(find.byTooltip('Aujourd’hui'), findsOneWidget);

    // Tap Aujourd'hui
    await tester.tap(find.byTooltip('Aujourd’hui'));
    await tester.pumpAndSettle();

    final restoredMonth = tester
        .widget<MonthGrid>(find.byType(MonthGrid))
        .month;
    expect(restoredMonth.year, initialMonth.year);
    expect(restoredMonth.month, initialMonth.month);
    expect(find.byTooltip('Aujourd’hui'), findsNothing);
  });

  testWidgets('tapping a day in a past month opens Day view on that day', (
    tester,
  ) async {
    await pump(tester, ScheduleViewMode.mois);

    // Move to previous month
    await tester.tap(find.byTooltip('Période précédente'));
    await tester.pumpAndSettle();

    final prevMonth = tester.widget<MonthGrid>(find.byType(MonthGrid)).month;

    // Tap day 15 in the previous month
    await tester.tap(find.text('15').first);
    await tester.pumpAndSettle();

    // Verify view mode switched to Jour
    expect(find.text('Jour'), findsWidgets);

    // Verify ScheduleGrid displays day 15 of that past month
    final grid = tester.widget<ScheduleGrid>(find.byType(ScheduleGrid));
    expect(grid.days.single.year, prevMonth.year);
    expect(grid.days.single.month, prevMonth.month);
    expect(grid.days.single.day, 15);
  });

  testWidgets('Day view can navigate into the past', (tester) async {
    await pump(tester, ScheduleViewMode.jour);
    final initialGrid = tester.widget<ScheduleGrid>(find.byType(ScheduleGrid));
    final todayDay = initialGrid.days.single;

    // Move 10 days into the past (beyond the former 7-day lookback limit)
    for (var i = 0; i < 10; i++) {
      await tester.tap(find.byTooltip('Période précédente'));
      await tester.pumpAndSettle();
    }

    final pastGrid = tester.widget<ScheduleGrid>(find.byType(ScheduleGrid));
    expect(todayDay.difference(pastGrid.days.single).inDays, 10);
  });
}
