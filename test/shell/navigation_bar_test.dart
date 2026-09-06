import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/shell/campus_shell.dart';
import 'package:notes_insa/theme/campus_theme.dart';

void main() {
  Future<void> pumpShell(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: CampusShell())),
    );
    await tester.pump();
  }

  testWidgets('the bar centres home and puts settings last', (tester) async {
    await pumpShell(tester);
    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    final labels = bar.destinations
        .cast<NavigationDestination>()
        .map((d) => d.label)
        .toList();
    expect(labels, <String>[
      'Cours',
      'Notes',
      'Aujourd’hui',
      'Carte',
      'Réglages',
    ]);
    expect(bar.selectedIndex, 2);
  });

  testWidgets('five labels fit the bar on a 360 dp phone', (tester) async {
    // The default test font draws every glyph as a full square, which makes
    // any label wrap and hides whether the real one fits. Five destinations
    // leave 72 dp each, so the bar only survives single-line labels.
    await _loadCampusFont();

    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: campusTheme(Brightness.light),
          home: const CampusShell(),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    final labels = find.descendant(
      of: find.byType(NavigationBar),
      matching: find.byType(Text),
    );
    for (final text in tester.widgetList<Text>(labels)) {
      final size = tester.getSize(
        find
            .descendant(
              of: find.byType(NavigationBar),
              matching: find.text(text.data!),
            )
            .first,
      );
      expect(
        size.height,
        lessThanOrEqualTo(20),
        reason: '"${text.data}" wraps to a second line and overflows the bar',
      );
    }
  });

  testWidgets('the app opens on home, not on the first destination', (
    tester,
  ) async {
    await pumpShell(tester);
    expect(find.widgetWithText(AppBar, 'Aujourd’hui'), findsOneWidget);
  });

  testWidgets('settings is a destination, not an app-bar action', (
    tester,
  ) async {
    await pumpShell(tester);
    expect(find.byTooltip('Paramètres'), findsNothing);

    await tester.tap(find.text('Réglages'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Paramètres'), findsOneWidget);
  });
}

/// Loads the shipped typeface so label widths are the real ones. Without it
/// every glyph is a square of the font size and the measurements mean nothing.
Future<void> _loadCampusFont() async {
  final bytes = File('assets/fonts/PublicSans-Variable.ttf').readAsBytesSync();
  await (FontLoader(
    kCampusFontFamily,
  )..addFont(Future<ByteData>.value(ByteData.view(bytes.buffer)))).load();
}
