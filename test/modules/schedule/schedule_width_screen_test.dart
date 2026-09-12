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
    tester.view.physicalSize = const Size(400, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const ProviderScope(child: _Harness()));
    await tester.pumpAndSettle();
  }

  double previewWidth(WidgetTester tester) =>
      tester.widget<ScheduleGrid>(find.byType(ScheduleGrid)).minColumnWidth;

  testWidgets('the preview runs at the chosen width', (tester) async {
    await pump(tester);
    expect(previewWidth(tester), ScheduleDayWidth.normal.minColumnWidth);
  });

  testWidgets('every preset is offered with what it costs', (tester) async {
    await pump(tester);
    for (final preset in ScheduleDayWidth.values) {
      expect(find.text(preset.label), findsOneWidget);
      expect(find.text(preset.description), findsOneWidget);
    }
  });

  testWidgets('a preset sets the width and is written down', (tester) async {
    await pump(tester);
    await tester.tap(find.text(ScheduleDayWidth.compact.label));
    await tester.pumpAndSettle();

    expect(previewWidth(tester), ScheduleDayWidth.compact.minColumnWidth);
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getDouble(kScheduleDayWidthKey),
      ScheduleDayWidth.compact.minColumnWidth,
    );
  });

  testWidgets('the slider sets a width no preset offers', (tester) async {
    await pump(tester);
    expect(find.text('104 dp'), findsWidgets);

    // Drag the thumb left; the exact landing is the slider's business, the
    // point is that it moves and commits something off the preset list.
    await tester.drag(find.byType(Slider), const Offset(-60, 0));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getDouble(kScheduleDayWidthKey);
    expect(stored, isNotNull);
    expect(stored, lessThan(ScheduleDayWidth.normal.minColumnWidth));
    expect(stored, greaterThanOrEqualTo(kScheduleDayWidthMin));
    expect(previewWidth(tester), stored);
  });

  testWidgets('the slider stays inside the bounds it advertises', (
    tester,
  ) async {
    await pump(tester);
    final slider = tester.widget<Slider>(find.byType(Slider));
    expect(slider.min, kScheduleDayWidthMin);
    expect(slider.max, kScheduleDayWidthMax);
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
