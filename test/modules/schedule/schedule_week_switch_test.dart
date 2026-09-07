import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/core/module_cache.dart';
import 'package:notes_insa/core/time.dart';
import 'package:notes_insa/modules/schedule/schedule_event.dart';
import 'package:notes_insa/modules/schedule/schedule_grid.dart';
import 'package:notes_insa/modules/schedule/month_grid.dart';
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

  List<DateTime> shownDays(WidgetTester tester) =>
      tester.widget<ScheduleGrid>(find.byType(ScheduleGrid)).days;

  testWidgets('the next arrow moves a week in Semaine', (tester) async {
    await pump(tester, ScheduleViewMode.semaine);
    final before = shownDays(tester).first;

    await tester.tap(find.byTooltip('Période suivante'));
    await tester.pumpAndSettle();

    expect(shownDays(tester).first.difference(before).inDays, 7);
  });

  testWidgets('swiping moves a week in Semaine', (tester) async {
    await pump(tester, ScheduleViewMode.semaine);
    final before = shownDays(tester).first;

    await tester.fling(find.byType(ScheduleGrid), const Offset(-300, 0), 1000);
    await tester.pumpAndSettle();

    expect(shownDays(tester).first.difference(before).inDays, 7);
  });

  testWidgets('3 jours moves three days at a time', (tester) async {
    await pump(tester, ScheduleViewMode.troisJours);
    final before = shownDays(tester).first;

    await tester.tap(find.byTooltip('Période suivante'));
    await tester.pumpAndSettle();

    expect(shownDays(tester).first.difference(before).inDays, 3);
  });

  testWidgets('swiping moves three days in 3 jours', (tester) async {
    await pump(tester, ScheduleViewMode.troisJours);
    final before = shownDays(tester).first;

    await tester.fling(find.byType(ScheduleGrid), const Offset(-300, 0), 1000);
    await tester.pumpAndSettle();

    expect(shownDays(tester).first.difference(before).inDays, 3);
  });

  testWidgets('swiping changes the month', (tester) async {
    await pump(tester, ScheduleViewMode.mois);
    final before = tester.widget<MonthGrid>(find.byType(MonthGrid)).month;

    await tester.fling(find.byType(MonthGrid), const Offset(-300, 0), 1000);
    await tester.pumpAndSettle();

    final after = tester.widget<MonthGrid>(find.byType(MonthGrid)).month;
    expect((after.year - before.year) * 12 + after.month - before.month, 1);
  });

  testWidgets('the way back to today appears once it is off screen', (
    tester,
  ) async {
    await pump(tester, ScheduleViewMode.semaine);
    expect(find.byTooltip('Aujourd’hui'), findsNothing);

    await tester.tap(find.byTooltip('Période suivante'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Aujourd’hui'), findsOneWidget);

    await tester.tap(find.byTooltip('Aujourd’hui'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Aujourd’hui'), findsNothing);
  });

  testWidgets('the arrows stop at the end of the fetched window', (
    tester,
  ) async {
    await pump(tester, ScheduleViewMode.semaine);
    for (var i = 0; i < 20; i++) {
      await tester.tap(find.byTooltip('Période suivante'));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    final last = shownDays(tester).last;
    expect(last.difference(DateTime.now()).inDays, lessThan(70));
  });
}
