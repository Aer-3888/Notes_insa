import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/core/time.dart';
import 'package:notes_insa/core/module_cache.dart';
import 'package:notes_insa/modules/schedule/schedule_event.dart';
import 'package:notes_insa/modules/schedule/schedule_provider.dart';
import 'package:notes_insa/modules/schedule/schedule_screen.dart';
import 'package:notes_insa/modules/schedule/schedule_view_mode.dart';
import 'package:notes_insa/modules/schedule/week_strip.dart';
import 'package:notes_insa/theme/campus_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A group is selected and one day has a class, so the screen renders its
/// real body instead of the "choose a group" state.
class _PickedGroups extends SelectedGroups {
  @override
  List<int> build() => const <int>[1214];
}

final _entry = CachedEntry<List<ScheduleEvent>>(
  data: <ScheduleEvent>[
    ScheduleEvent(
      title: 'Algèbre 3',
      start: DateTime(2026, 9, 7, 8),
      end: DateTime(2026, 9, 7, 10),
      groups: const <String>[],
      teachers: const <String>[],
      room: 'Amphi C',
    ),
  ],
);

Future<void> pump(WidgetTester tester) async {
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
  await tester.pump();
}

void main() {
  // The screen reads campusNow() in initState, which throws until the
  // timezone database is loaded.
  setUpAll(initCampusTime);
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets('the app bar names the current mode', (tester) async {
    await pump(tester);
    expect(find.text('Jour'), findsOneWidget);
  });

  testWidgets('the title opens a menu of all five modes', (tester) async {
    await pump(tester);
    await tester.tap(find.byType(PopupMenuButton<ScheduleViewMode>));
    await tester.pumpAndSettle();
    for (final label in <String>[
      'Liste',
      'Jour',
      '3 jours',
      'Semaine',
      'Mois',
    ]) {
      expect(find.text(label), findsWidgets, reason: '$label missing');
    }
  });

  testWidgets('choosing a mode changes the title', (tester) async {
    await pump(tester);
    await tester.tap(find.byType(PopupMenuButton<ScheduleViewMode>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Semaine').last);
    await tester.pumpAndSettle();
    expect(find.text('Semaine'), findsOneWidget);
  });

  testWidgets('only Jour starts with the week strip', (tester) async {
    for (final entry in <String, bool>{
      'Liste': false,
      'Jour': true,
      '3 jours': false,
      'Semaine': false,
      'Mois': false,
    }.entries) {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await pump(tester);
      await tester.tap(find.byType(PopupMenuButton<ScheduleViewMode>));
      await tester.pumpAndSettle();
      await tester.tap(find.text(entry.key).last);
      await tester.pumpAndSettle();
      expect(
        find.byType(WeekStrip),
        entry.value ? findsOneWidget : findsNothing,
        reason: '${entry.key} strip visibility is wrong',
      );
    }
  });

  testWidgets('Jour can hide and show its week strip', (tester) async {
    await pump(tester);
    final hide = find.byTooltip('Masquer l\'aper\u00e7u de la semaine');
    expect(hide, findsOneWidget);
    await tester.tap(hide);
    await tester.pumpAndSettle();

    expect(find.byType(WeekStrip), findsNothing);
    expect(
      find.byTooltip('Afficher l\'aper\u00e7u de la semaine'),
      findsOneWidget,
    );
  });

  testWidgets('Liste can show the week strip it starts without', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.byType(PopupMenuButton<ScheduleViewMode>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Liste').last);
    await tester.pumpAndSettle();

    expect(find.byType(WeekStrip), findsNothing);

    final show = find.byTooltip('Afficher l\'aperçu de la semaine');
    expect(show, findsOneWidget);
    await tester.tap(show);
    await tester.pumpAndSettle();

    expect(find.byType(WeekStrip), findsOneWidget);
  });

  testWidgets('Liste and Jour remember the strip separately', (tester) async {
    await pump(tester);
    await tester.tap(find.byTooltip('Masquer l\'aperçu de la semaine'));
    await tester.pumpAndSettle();
    expect(find.byType(WeekStrip), findsNothing);

    await tester.tap(find.byType(PopupMenuButton<ScheduleViewMode>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Liste').last);
    await tester.pumpAndSettle();
    expect(find.byType(WeekStrip), findsNothing);

    await tester.tap(find.byTooltip('Afficher l\'aperçu de la semaine'));
    await tester.pumpAndSettle();
    expect(find.byType(WeekStrip), findsOneWidget);

    await tester.tap(find.byType(PopupMenuButton<ScheduleViewMode>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Jour').last);
    await tester.pumpAndSettle();
    expect(find.byType(WeekStrip), findsNothing);
  });

  testWidgets('Mois can hide the classes in its cells', (tester) async {
    await pump(tester);
    await tester.tap(find.byType(PopupMenuButton<ScheduleViewMode>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mois').last);
    await tester.pumpAndSettle();

    final hide = find.byTooltip('Masquer les cours dans les cases');
    expect(hide, findsOneWidget);
    await tester.tap(hide);
    await tester.pumpAndSettle();

    expect(find.byTooltip('Afficher les cours dans les cases'), findsOneWidget);
  });
}
