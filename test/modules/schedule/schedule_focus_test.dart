import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/core/module_cache.dart';
import 'package:notes_insa/core/time.dart';
import 'package:notes_insa/modules/schedule/schedule_event.dart';
import 'package:notes_insa/modules/schedule/schedule_focus.dart';
import 'package:notes_insa/modules/schedule/schedule_period.dart';
import 'package:notes_insa/modules/schedule/schedule_provider.dart';
import 'package:notes_insa/modules/schedule/schedule_screen.dart';
import 'package:notes_insa/theme/campus_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _loadCampusFont() async {
  final bytes = File('assets/fonts/PublicSans-Variable.ttf').readAsBytesSync();
  await (FontLoader(
    kCampusFontFamily,
  )..addFont(Future<ByteData>.value(ByteData.view(bytes.buffer)))).load();
}

class _PickedGroups extends SelectedGroups {
  @override
  List<int> build() => const <int>[1214];
}

ScheduleEvent _at(Duration fromNow, {required String title}) {
  final start = campusNow().add(fromNow);
  return ScheduleEvent(
    title: title,
    start: start,
    end: start.add(const Duration(hours: 2)),
    groups: const <String>[],
    teachers: const <String>[],
    room: 'Amphi C',
  );
}

void main() {
  setUpAll(initCampusTime);
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  late ScheduleEvent today;
  late ScheduleEvent later;

  setUp(() {
    today = _at(const Duration(hours: 1), title: 'Algèbre');
    later = _at(const Duration(days: 10), title: 'Thermo');
  });

  Future<ProviderContainer> pump(WidgetTester tester) async {
    await _loadCampusFont();
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(
      overrides: [
        selectedGroupsProvider.overrideWith(_PickedGroups.new),
        scheduleProvider.overrideWith(
          (ref) => Stream<CachedEntry<List<ScheduleEvent>>>.value(
            CachedEntry<List<ScheduleEvent>>(
              data: <ScheduleEvent>[today, later],
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: campusTheme(Brightness.light),
          home: const ScheduleScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('a session filed before the timetable is built opens its sheet', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        selectedGroupsProvider.overrideWith(_PickedGroups.new),
        scheduleProvider.overrideWith(
          (ref) => Stream<CachedEntry<List<ScheduleEvent>>>.value(
            CachedEntry<List<ScheduleEvent>>(
              data: <ScheduleEvent>[today, later],
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.read(scheduleFocusProvider.notifier).request(today);

    await _loadCampusFont();
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: campusTheme(Brightness.light),
          home: const ScheduleScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Copier la salle'), findsOneWidget);
  });

  testWidgets('a session filed while the timetable is on screen opens its '
      'sheet', (tester) async {
    final container = await pump(tester);
    expect(find.text('Copier la salle'), findsNothing);

    container.read(scheduleFocusProvider.notifier).request(today);
    await tester.pumpAndSettle();

    expect(find.text('Copier la salle'), findsOneWidget);
  });

  testWidgets('the request is consumed, so dismissing the sheet ends it', (
    tester,
  ) async {
    final container = await pump(tester);
    container.read(scheduleFocusProvider.notifier).request(today);
    await tester.pumpAndSettle();

    expect(container.read(scheduleFocusProvider), isNull);
  });

  testWidgets('the timetable scrolls to the day the session falls on', (
    tester,
  ) async {
    final container = await pump(tester);
    final day = frenchDayLabel(later.start);
    expect(find.text(day), findsNothing);

    container.read(scheduleFocusProvider.notifier).request(later);
    await tester.pumpAndSettle();

    expect(find.text(day), findsOneWidget);
  });
}
