import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/shell/campus_shell.dart';

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

  testWidgets('the bar has four destinations, home first', (tester) async {
    await pumpShell(tester);
    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    final labels = bar.destinations
        .cast<NavigationDestination>()
        .map((d) => d.label)
        .toList();
    expect(labels, <String>[
      'Aujourd’hui',
      'Emploi du temps',
      'Notes',
      'Carte',
    ]);
    expect(bar.selectedIndex, 0);
  });

  testWidgets('settings is not a destination but is reachable from home', (
    tester,
  ) async {
    await pumpShell(tester);
    expect(find.text('Paramètres'), findsNothing);
    expect(find.byTooltip('Paramètres'), findsOneWidget);
  });
}
