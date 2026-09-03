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

  testWidgets('the bar has five destinations in the agreed order', (
    tester,
  ) async {
    await pumpShell(tester);
    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(bar.destinations.length, 5);
    final labels = bar.destinations
        .cast<NavigationDestination>()
        .map((d) => d.label)
        .toList();
    expect(labels, <String>[
      'Carte du campus',
      'Emploi du temps',
      'Accueil',
      'Notes',
      'Paramètres',
    ]);
  });

  testWidgets('Accueil is selected on launch, in the middle', (tester) async {
    await pumpShell(tester);
    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(bar.selectedIndex, 2);
  });
}
