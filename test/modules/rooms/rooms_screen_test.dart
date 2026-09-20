import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/core/module_cache.dart';
import 'package:notes_insa/core/time.dart';
import 'package:notes_insa/modules/rooms/room_filter.dart';
import 'package:notes_insa/modules/rooms/rooms_provider.dart';
import 'package:notes_insa/modules/rooms/rooms_screen.dart';
import 'package:notes_insa/modules/schedule/ade_groups.dart';
import 'package:notes_insa/modules/schedule/ade_groups_provider.dart';
import 'package:notes_insa/modules/schedule/schedule_event.dart';
import 'package:notes_insa/theme/campus_theme.dart';
import 'package:notes_insa/theme/tokens.dart';

const _rooms = <AdeGroup>[
  AdeGroup(id: 1, name: 'Amphi B Bât 12', category: AdeCategory.room),
  AdeGroup(id: 2, name: 'Amphi C Bât 12', category: AdeCategory.room),
  AdeGroup(id: 3, name: 'salle 101 Bât 12', category: AdeCategory.room),
  AdeGroup(id: 4, name: '... MOODLE', category: AdeCategory.room),
  AdeGroup(id: 5, name: 'S7-INFO'),
];

List<ScheduleEvent> _events(DateTime now) => <ScheduleEvent>[
  ScheduleEvent(
    title: 'CPOO2_G1',
    start: now.subtract(const Duration(minutes: 30)),
    end: now.add(const Duration(hours: 1)),
    room: 'Amphi B Bât 12',
    groups: const <String>[],
    teachers: const <String>[],
    uid: 'e1',
  ),
  ScheduleEvent(
    title: 'TD Langage C',
    start: now.add(const Duration(minutes: 45)),
    end: now.add(const Duration(hours: 2)),
    room: 'salle 101 Bât 12',
    groups: const <String>[],
    teachers: const <String>[],
    uid: 'e2',
  ),
];

Future<void> _pump(
  WidgetTester tester, {
  CachedEntry<List<ScheduleEvent>>? entry,
  String? initialBuildingCode,
}) async {
  final container = ProviderContainer(
    overrides: [
      adeGroupsProvider.overrideWith((ref) async => _rooms),
      listableRoomsProvider.overrideWith(
        (ref) async => _rooms.where((r) => r.id <= 3).toList(),
      ),
      roomBuildingsProvider.overrideWith(
        (ref) async => const <int, String>{1: '12', 2: '12', 3: '6'},
      ),
      roomsProvider.overrideWith(
        (ref) => Stream<CachedEntry<List<ScheduleEvent>>>.value(
          entry ??
              CachedEntry<List<ScheduleEvent>>(
                data: _events(campusNow()),
                cachedAt: DateTime.now(),
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
        home: RoomsScreen(initialBuildingCode: initialBuildingCode),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(initCampusTime);

  testWidgets('gathers the free rooms under their building', (tester) async {
    await _pump(tester);
    expect(find.text('Bâtiment 12'), findsOneWidget);
    expect(find.text('Bâtiment 6'), findsOneWidget);
    expect(find.text('Amphi C Bât 12'), findsNothing);

    await tester.tap(find.text('Bâtiment 12'));
    await tester.pumpAndSettle();
    expect(find.text('Amphi C Bât 12'), findsOneWidget);
  });

  testWidgets('opens the requested building', (tester) async {
    await _pump(tester, initialBuildingCode: '12');
    expect(find.text('Amphi C Bât 12'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Bâtiment 12')).dy,
      lessThan(tester.getTopLeft(find.text('Bâtiment 6')).dy),
    );
  });

  testWidgets('insets building groups from the screen edge', (tester) async {
    await _pump(tester);
    final card = find.ancestor(
      of: find.text('Bâtiment 12'),
      matching: find.byType(Card),
    );
    expect(tester.getTopLeft(card).dx, CampusSpacing.gutter);
  });

  testWidgets('buildings run in reading order', (tester) async {
    await _pump(tester);
    expect(
      tester.getTopLeft(find.text('Bâtiment 6')).dy,
      lessThan(tester.getTopLeft(find.text('Bâtiment 12')).dy),
    );
  });

  testWidgets('the rooms in use are counted but folded away', (tester) async {
    await _pump(tester);
    expect(find.text('Occupées'), findsOneWidget);
    expect(find.text('1 salle'), findsOneWidget);
    expect(find.text('Amphi B Bât 12'), findsNothing);

    await tester.tap(find.text('Occupées'));
    await tester.pumpAndSettle();
    expect(find.text('Amphi B Bât 12'), findsOneWidget);
  });

  testWidgets('a room in use names the class and when it frees up', (
    tester,
  ) async {
    await _pump(tester);
    await tester.tap(find.text('Occupées'));
    await tester.pumpAndSettle();
    expect(find.textContaining('CPOO2_G1'), findsOneWidget);
  });

  testWidgets('a room with nothing left today says so', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Bâtiment 12'));
    await tester.pumpAndSettle();
    expect(find.text('Libre le reste de la journée'), findsOneWidget);
  });

  testWidgets('a free room says how long it stays free', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Bâtiment 6'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Libre pendant'), findsOneWidget);
  });

  testWidgets('the duration filter leaves out short free slots', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.byType(SegmentedButton<RoomFreeDuration>), findsOneWidget);
    await tester.tap(find.text('1 h'));
    await tester.pumpAndSettle();
    expect(find.text('Bâtiment 12'), findsOneWidget);
    expect(find.text('Bâtiment 6'), findsNothing);
  });

  testWidgets('search reaches a room the free list leaves out', (tester) async {
    await _pump(tester);
    await tester.enterText(find.byType(TextField), 'MOODLE');
    await tester.pumpAndSettle();
    expect(find.text('... MOODLE'), findsOneWidget);
    expect(find.text('Amphi C Bât 12'), findsNothing);
  });

  testWidgets('search never offers a student group', (tester) async {
    await _pump(tester);
    await tester.enterText(find.byType(TextField), 'INFO');
    await tester.pumpAndSettle();
    expect(find.text('S7-INFO'), findsNothing);
    expect(find.text('Aucune salle'), findsOneWidget);
  });

  testWidgets('tapping a room opens its own planning', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Bâtiment 12'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Amphi C Bât 12'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Amphi C Bât 12'), findsOneWidget);
  });

  testWidgets('an unreachable ADE says so rather than spinning', (
    tester,
  ) async {
    await _pump(
      tester,
      entry: const CachedEntry<List<ScheduleEvent>>(
        refreshState: RefreshState.failedOffline,
      ),
    );
    expect(find.text('Salles indisponibles'), findsOneWidget);
  });
}
