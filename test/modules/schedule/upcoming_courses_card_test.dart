import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/core/time.dart';
import 'package:notes_insa/modules/schedule/schedule_event.dart';
import 'package:notes_insa/modules/schedule/schedule_period.dart';
import 'package:notes_insa/modules/schedule/schedule_provider.dart';
import 'package:notes_insa/modules/schedule/schedule_timeline.dart';
import 'package:notes_insa/modules/schedule/upcoming_courses_card.dart';
import 'package:notes_insa/theme/campus_theme.dart';

/// The default test font draws every glyph as a square of the font size, so a
/// layout that fits in the shipped font overflows here.
Future<void> _loadCampusFont() async {
  final bytes = File('assets/fonts/PublicSans-Variable.ttf').readAsBytesSync();
  await (FontLoader(
    kCampusFontFamily,
  )..addFont(Future<ByteData>.value(ByteData.view(bytes.buffer)))).load();
}

/// Sessions are placed relative to now, so the fixtures read as upcoming
/// whatever day the suite runs on.
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

  final tapped = <ScheduleEvent>[];
  setUp(tapped.clear);

  Future<void> pump(
    WidgetTester tester,
    List<ScheduleEvent> events, {
    Brightness brightness = Brightness.light,
    double textScale = 1.0,
  }) async {
    await _loadCampusFont();
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [upcomingCoursesProvider.overrideWithValue(events)],
        child: MaterialApp(
          theme: campusTheme(brightness),
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
            child: Scaffold(body: UpcomingCoursesCard(onOpenEvent: tapped.add)),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('renders one row per upcoming session', (tester) async {
    await pump(tester, <ScheduleEvent>[
      _at(const Duration(hours: 1), title: 'Algèbre'),
      _at(const Duration(hours: 4), title: 'Thermo'),
    ]);

    expect(find.byType(ScheduleEventRow), findsNWidgets(2));
    expect(find.text('Algèbre'), findsOneWidget);
    expect(find.text('Thermo'), findsOneWidget);
  });

  testWidgets('renders nothing when nothing is coming', (tester) async {
    await pump(tester, const <ScheduleEvent>[]);

    expect(find.byType(ScheduleEventRow), findsNothing);
    expect(find.byType(Card), findsNothing);
  });

  testWidgets('dates a session that is not today and leaves today undated', (
    tester,
  ) async {
    final tomorrow = campusNow().add(const Duration(days: 1));
    await pump(tester, <ScheduleEvent>[
      _at(const Duration(hours: 1), title: 'Aujourd’hui'),
      _at(const Duration(days: 1), title: 'Demain'),
    ]);

    expect(find.text(frenchDayLabel(tomorrow)), findsOneWidget);
    expect(find.text(frenchDayLabel(campusNow())), findsNothing);
  });

  testWidgets('scrolls to the sessions past the two on show', (tester) async {
    await pump(tester, <ScheduleEvent>[
      for (var i = 1; i <= 5; i++)
        _at(Duration(hours: i * 3), title: 'Cours $i'),
    ]);
    final before = tester.getTopLeft(find.byType(ScheduleEventRow).first);

    await tester.drag(find.byType(UpcomingCoursesCard), const Offset(0, -150));
    await tester.pumpAndSettle();

    final after = tester.getTopLeft(find.byType(ScheduleEventRow).first);
    expect(after.dy, lessThan(before.dy));
  });

  testWidgets('reports the session that was tapped', (tester) async {
    final second = _at(const Duration(hours: 4), title: 'Thermo');
    await pump(tester, <ScheduleEvent>[
      _at(const Duration(hours: 1), title: 'Algèbre'),
      second,
    ]);

    await tester.tap(find.text('Thermo'));
    await tester.pump();

    expect(tapped, <ScheduleEvent>[second]);
  });

  for (final brightness in Brightness.values) {
    for (final scale in <double>[1.0, 2.0]) {
      testWidgets('renders in ${brightness.name} at ${scale}x text', (
        tester,
      ) async {
        await pump(
          tester,
          <ScheduleEvent>[
            _at(const Duration(hours: 1), title: 'Algèbre'),
            _at(const Duration(days: 1), title: 'Thermoénergétique'),
          ],
          brightness: brightness,
          textScale: scale,
        );

        expect(tester.takeException(), isNull);
        expect(find.byType(ScheduleEventRow), findsWidgets);
      });
    }
  }

  testWidgets('the preview grows with the text, so rows never clip', (
    tester,
  ) async {
    final events = <ScheduleEvent>[
      for (var i = 1; i <= 4; i++)
        _at(Duration(hours: i * 3), title: 'Cours $i'),
    ];
    await pump(tester, events);
    final normal = tester.getSize(find.byType(Card)).height;

    await pump(tester, events, textScale: 2.0);

    expect(tester.getSize(find.byType(Card)).height, greaterThan(normal));
  });
}
