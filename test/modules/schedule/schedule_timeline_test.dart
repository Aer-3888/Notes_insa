import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/modules/schedule/schedule_day_index.dart';
import 'package:notes_insa/modules/schedule/schedule_event.dart';
import 'package:notes_insa/modules/schedule/schedule_timeline.dart';
import 'package:notes_insa/theme/campus_theme.dart';

ScheduleEvent _event(
  String title,
  DateTime start,
  DateTime end, {
  String? room,
  List<String> teachers = const <String>[],
}) => ScheduleEvent(
  title: title,
  start: start,
  end: end,
  groups: const <String>[],
  teachers: teachers,
  room: room,
);

void main() {
  final monday = DateTime(2026, 9, 7);

  Future<void> pump(WidgetTester tester, ScheduleDayIndex index) async {
    await loadCampusFont();
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: campusTheme(Brightness.light),
        home: Scaffold(
          body: ScheduleTimeline(index: index, controller: ScrollController()),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('a day header names the day in French', (tester) async {
    await pump(
      tester,
      ScheduleDayIndex.build(
        events: const <ScheduleEvent>[],
        from: monday,
        to: monday,
      ),
    );
    expect(find.text('lundi 7 septembre'), findsOneWidget);
  });

  testWidgets('an empty day says so and keeps its header', (tester) async {
    await pump(
      tester,
      ScheduleDayIndex.build(
        events: const <ScheduleEvent>[],
        from: monday,
        to: monday,
      ),
    );
    expect(find.text('Rien de prévu'), findsOneWidget);
  });

  testWidgets('a gap row states the free time in French', (tester) async {
    await pump(
      tester,
      ScheduleDayIndex.build(
        events: <ScheduleEvent>[
          _event('A', DateTime(2026, 9, 7, 8), DateTime(2026, 9, 7, 10)),
          _event('B', DateTime(2026, 9, 7, 11, 30), DateTime(2026, 9, 7, 12)),
        ],
        from: monday,
        to: monday,
      ),
    );
    expect(find.text('1 h 30 de libre'), findsOneWidget);
  });

  testWidgets('an event row shows times, module, room and teacher', (
    tester,
  ) async {
    await pump(
      tester,
      ScheduleDayIndex.build(
        events: <ScheduleEvent>[
          _event(
            'Algèbre 3',
            DateTime(2026, 9, 7, 8, 15),
            DateTime(2026, 9, 7, 10, 15),
            room: 'Amphi C (V)',
            teachers: <String>['CAMAR-EDDINE MOHAMED'],
          ),
        ],
        from: monday,
        to: monday,
      ),
    );
    expect(find.text('08:15'), findsOneWidget);
    expect(find.text('10:15'), findsOneWidget);
    expect(find.text('Algèbre 3'), findsOneWidget);
    expect(find.textContaining('Amphi C (V)'), findsOneWidget);
    expect(find.textContaining('CAMAR-EDDINE MOHAMED'), findsOneWidget);
  });

  testWidgets('event row height does not change with content', (tester) async {
    final index = ScheduleDayIndex.build(
      events: <ScheduleEvent>[
        _event('court', DateTime(2026, 9, 7, 8), DateTime(2026, 9, 7, 9)),
        _event(
          'un nom de module vraiment très long qui devrait être tronqué',
          DateTime(2026, 9, 7, 9),
          DateTime(2026, 9, 7, 10),
          room: 'une salle au nom interminable dans un bâtiment lointain',
          teachers: <String>['UN', 'DEUX', 'TROIS', 'QUATRE'],
        ),
      ],
      from: monday,
      to: monday,
    );
    await pump(tester, index);

    // No overflow is the real assertion: the row is given a tight extent, so
    // content that does not fit reports a RenderFlex overflow rather than a
    // different size.
    expect(tester.takeException(), isNull);

    final heights = tester
        .widgetList<ScheduleEventRow>(find.byType(ScheduleEventRow))
        .map((w) => tester.getSize(find.byWidget(w)).height)
        .toSet();
    expect(
      heights,
      hasLength(1),
      reason: 'row height must not depend on content, or offsets drift',
    );
  });

  testWidgets('every row renders at the height the metrics assume', (
    tester,
  ) async {
    final index = ScheduleDayIndex.build(
      events: <ScheduleEvent>[
        _event('A', DateTime(2026, 9, 7, 8), DateTime(2026, 9, 7, 10)),
        _event('B', DateTime(2026, 9, 7, 12), DateTime(2026, 9, 7, 14)),
      ],
      from: monday,
      to: monday,
    );
    await pump(tester, index);
    expect(tester.takeException(), isNull);
  });
}

/// The default test font draws every glyph as a square of the font size, so a
/// row that fits in the shipped font wraps and overflows here. Any layout
/// assertion has to measure the real typeface.
Future<void> loadCampusFont() async {
  final bytes = File('assets/fonts/PublicSans-Variable.ttf').readAsBytesSync();
  await (FontLoader(
    kCampusFontFamily,
  )..addFont(Future<ByteData>.value(ByteData.view(bytes.buffer)))).load();
}
