import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/providers/theme_mode_provider.dart';
import 'package:notes_insa/shell/app_settings_screen.dart';
import 'package:notes_insa/theme/campus_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<ProviderContainer> pumpSettings(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final container = ProviderContainer.test();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: campusTheme(Brightness.light),
          home: const AppSettingsScreen(),
        ),
      ),
    );
    await tester.pump();
    return container;
  }

  testWidgets('app settings render with no credentials', (tester) async {
    await pumpSettings(tester);
    expect(tester.takeException(), isNull);
    expect(find.byType(AppSettingsScreen), findsOneWidget);
  });

  testWidgets('app settings expose no grade sharing controls', (tester) async {
    await pumpSettings(tester);
    // Grade-specific controls belong to the grades module, which is gated.
    // Anything here is reachable by a user with no account at all.
    expect(find.textContaining('notes'), findsNothing);
    expect(find.textContaining('partage'), findsNothing);
    expect(find.byType(Switch), findsNothing);
  });

  testWidgets('app settings name the timetable data source contact', (
    tester,
  ) async {
    await pumpSettings(tester);
    expect(find.textContaining('À propos'), findsOneWidget);
  });

  testWidgets('Apparence offers the three modes and persists the choice', (
    tester,
  ) async {
    final container = await pumpSettings(tester);
    expect(find.text('Apparence'), findsOneWidget);
    for (final label in ['Système', 'Clair', 'Sombre']) {
      expect(find.text(label), findsOneWidget);
    }
    await tester.ensureVisible(find.text('Sombre'));
    await tester.tap(find.text('Sombre'));
    await tester.pump();
    expect(container.read(themeModeProvider), ThemeMode.dark);
  });

  testWidgets('the developer row appears after seven taps on the version', (
    tester,
  ) async {
    await pumpSettings(tester);
    expect(find.text('JSON brut'), findsNothing);
    // The version sits at the end of a list longer than the test viewport.
    await tester.scrollUntilVisible(find.text('Version'), 200);
    for (var i = 0; i < 7; i++) {
      await tester.tap(find.text('Version'));
      await tester.pump();
    }
    expect(find.text('Outils développeur activés'), findsOneWidget);
    expect(find.text('JSON brut'), findsOneWidget);
  });

  testWidgets('settings are laid out without cards', (tester) async {
    await pumpSettings(tester);
    // The old layout wrapped each group in a hand-built bordered Container,
    // not a Material Card, so asserting on Card alone would pass either way.
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Container &&
            w.decoration is BoxDecoration &&
            (w.decoration! as BoxDecoration).border != null,
      ),
      findsNothing,
    );
    expect(find.byType(Card), findsNothing);
  });
}
