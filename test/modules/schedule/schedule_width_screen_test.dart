import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/modules/schedule/schedule_grid.dart';
import 'package:notes_insa/modules/schedule/schedule_view_mode.dart';
import 'package:notes_insa/modules/schedule/schedule_width_screen.dart';
import 'package:notes_insa/theme/campus_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  Future<void> pump(WidgetTester tester) async {
    // Tall enough that all three previews build rather than being scrolled off.
    tester.view.physicalSize = const Size(400, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const ProviderScope(child: _Harness()));
    await tester.pumpAndSettle();
  }

  testWidgets('every width is offered with what it costs', (tester) async {
    await pump(tester);
    for (final width in ScheduleDayWidth.values) {
      expect(find.text(width.label), findsOneWidget);
      expect(find.text(width.description), findsOneWidget);
    }
  });

  testWidgets('each row previews the real grid at its own width', (
    tester,
  ) async {
    await pump(tester);
    final grids = tester
        .widgetList<ScheduleGrid>(find.byType(ScheduleGrid))
        .map((g) => g.minColumnWidth)
        .toList();
    expect(grids, ScheduleDayWidth.values.map((w) => w.minColumnWidth));
  });

  testWidgets('Normal is the one ticked until another is chosen', (
    tester,
  ) async {
    await pump(tester);
    expect(find.byIcon(Icons.check), findsOneWidget);

    await tester.tap(find.text(ScheduleDayWidth.compact.label));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(kScheduleDayWidthKey), 'compact');
    expect(find.byIcon(Icons.check), findsOneWidget);
  });
}

class _Harness extends StatelessWidget {
  const _Harness();

  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: campusTheme(Brightness.light),
    home: const ScheduleWidthScreen(),
  );
}
