import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/core/time.dart';
import 'package:notes_insa/modules/schedule/schedule_event.dart';
import 'package:notes_insa/modules/schedule/schedule_provider.dart';
import 'package:notes_insa/shell/home_hub_screen.dart';
import 'package:notes_insa/theme/campus_theme.dart';

Future<void> _loadCampusFont() async {
  final bytes = File('assets/fonts/PublicSans-Variable.ttf').readAsBytesSync();
  await (FontLoader(
    kCampusFontFamily,
  )..addFont(Future<ByteData>.value(ByteData.view(bytes.buffer)))).load();
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

  testWidgets('tapping a preview session opens the event sheet in-place', (
    tester,
  ) async {
    await _loadCampusFont();
    tester.view.physicalSize = const Size(400, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final event = _at(const Duration(hours: 1), title: 'Algèbre');
    final opened = <String>[];
    final container = ProviderContainer(
      overrides: [
        upcomingCoursesProvider.overrideWithValue(<ScheduleEvent>[event]),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: campusTheme(Brightness.light),
          home: HomeHubScreen(onOpenModule: opened.add),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Algèbre'));
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text('Amphi C'),
      ),
      findsOneWidget,
    );
  });
}
