import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/modules/schedule/schedule_colors_screen.dart';
import 'package:notes_insa/providers/schedule_tint_provider.dart';
import 'package:notes_insa/theme/campus_theme.dart';
import 'package:notes_insa/theme/module_tints.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _loadCampusFont() async {
  final bytes = File('assets/fonts/PublicSans-Variable.ttf').readAsBytesSync();
  await (FontLoader(
    kCampusFontFamily,
  )..addFont(Future<ByteData>.value(ByteData.view(bytes.buffer)))).load();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  Future<ProviderContainer> pump(
    WidgetTester tester, {
    Brightness brightness = Brightness.light,
    double textScale = 1.0,
  }) async {
    await _loadCampusFont();
    tester.view.physicalSize = const Size(400, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: campusTheme(brightness),
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
            child: const ScheduleColorsScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('every scheme is offered by name', (tester) async {
    await pump(tester);
    for (final scheme in ScheduleTintScheme.values) {
      expect(find.text(scheme.label), findsOneWidget, reason: scheme.name);
    }
  });

  testWidgets('choosing a scheme records it', (tester) async {
    final container = await pump(tester);

    await tester.tap(find.text(ScheduleTintScheme.froid.label));
    await tester.pumpAndSettle();

    expect(
      container.read(scheduleTintProvider).scheme,
      ScheduleTintScheme.froid,
    );
  });

  testWidgets('choosing an intensity records it', (tester) async {
    final container = await pump(tester);

    await tester.tap(find.text(ScheduleTintIntensity.vif.label));
    await tester.pumpAndSettle();

    expect(
      container.read(scheduleTintProvider).intensity,
      ScheduleTintIntensity.vif,
    );
  });

  testWidgets('intensity is disabled when there is no colour to vary', (
    tester,
  ) async {
    final container = await pump(tester);

    await tester.tap(find.text(ScheduleTintScheme.aucune.label));
    await tester.pumpAndSettle();

    final control = tester.widget<SegmentedButton<ScheduleTintIntensity>>(
      find.byType(SegmentedButton<ScheduleTintIntensity>),
    );
    expect(control.onSelectionChanged, isNull);
    // The choice is kept, so turning colour back on restores it.
    expect(
      container.read(scheduleTintProvider).intensity,
      ScheduleTintIntensity.standard,
    );
  });

  for (final brightness in Brightness.values) {
    for (final scale in <double>[1.0, 2.0]) {
      testWidgets('renders in ${brightness.name} at ${scale}x text', (
        tester,
      ) async {
        await pump(tester, brightness: brightness, textScale: scale);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
