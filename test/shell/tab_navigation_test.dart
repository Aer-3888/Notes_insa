import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/core/module_cache.dart';
import 'package:notes_insa/core/time.dart';
import 'package:notes_insa/modules/weather/weather_model.dart';
import 'package:notes_insa/modules/weather/weather_provider.dart';
import 'package:notes_insa/shell/campus_shell.dart';
import 'package:notes_insa/shell/module_card.dart';
import 'package:notes_insa/theme/campus_theme.dart';

void main() {
  setUpAll(initCampusTime);

  Future<void> pumpShell(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        // Left unresolved the weather screen spins forever and pumpAndSettle
        // never returns; the failed state is static.
        overrides: [
          weatherProvider.overrideWith(
            (ref) => Stream<CachedEntry<WeatherSnapshot>>.value(
              const CachedEntry<WeatherSnapshot>(
                refreshState: RefreshState.failedUpstream,
              ),
            ),
          ),
        ],
        child: MaterialApp(
          theme: campusTheme(Brightness.light),
          home: const CampusShell(),
        ),
      ),
    );
    await tester.pump();
  }

  /// The navigator of whichever destination is on screen. There is one per
  /// destination, below the shell's own Scaffold.
  NavigatorState tabNavigator(WidgetTester tester) =>
      tester.state<NavigatorState>(
        find
            .descendant(
              of: find.byType(IndexedStack),
              matching: find.byType(Navigator),
            )
            .first,
      );

  /// The bar's own label; module names also appear on the hub cards.
  Finder destination(String label) => find.descendant(
    of: find.byType(NavigationBar),
    matching: find.text(label),
  );

  int selectedIndex(WidgetTester tester) =>
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex;

  Future<void> openDetail(WidgetTester tester) async {
    // The route outlives the helper; the test drives it with pumpAndSettle.
    unawaited(
      tabNavigator(tester).push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('détail')),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a page opened from a tab keeps the bottom bar', (tester) async {
    await pumpShell(tester);
    await openDetail(tester);
    expect(find.text('détail'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('system back closes the page before leaving the tab', (
    tester,
  ) async {
    await pumpShell(tester);
    await openDetail(tester);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('détail'), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(selectedIndex(tester), 2);
  });

  testWidgets('system back from another tab returns to Aujourd’hui', (
    tester,
  ) async {
    await pumpShell(tester);
    await tester.tap(destination('Carte'));
    await tester.pumpAndSettle();
    expect(selectedIndex(tester), 3);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(selectedIndex(tester), 2);
  });

  testWidgets('each destination keeps its own stack', (tester) async {
    await pumpShell(tester);
    await openDetail(tester);

    await tester.tap(destination('Carte'));
    await tester.pumpAndSettle();
    expect(find.text('détail'), findsNothing);

    await tester.tap(destination('Aujourd’hui'));
    await tester.pumpAndSettle();
    expect(find.text('détail'), findsOneWidget);
  });

  testWidgets('a hub module card selects that destination', (tester) async {
    await pumpShell(tester);
    final card = find.widgetWithText(ModuleCard, 'Emploi du temps');
    expect(card, findsOneWidget);

    await tester.tap(card);
    await tester.pumpAndSettle();

    expect(selectedIndex(tester), 0);
  });

  testWidgets('a hub card with no destination opens under the bar', (
    tester,
  ) async {
    await pumpShell(tester);
    final card = find.widgetWithText(ModuleCard, 'Météo');
    expect(card, findsOneWidget);

    await tester.tap(card);
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'Météo'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(selectedIndex(tester), 2);
  });
}
