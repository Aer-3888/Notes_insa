import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/core/time.dart';
import 'package:notes_insa/modules/schedule/schedule_screen.dart';
import 'package:notes_insa/modules/schedule/schedule_view_mode.dart';
import 'package:notes_insa/theme/campus_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
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
    expect(find.text('Liste'), findsOneWidget);
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
}
