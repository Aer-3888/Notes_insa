import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/theme/campus_theme.dart';
import 'package:notes_insa/theme/state_view.dart';

void main() {
  testWidgets('shows title, body and action', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: campusTheme(Brightness.light),
        home: Scaffold(
          body: StateView(
            icon: Icons.cloud_off_outlined,
            title: 'Hors ligne',
            body: 'Les données affichées datent d\u2019hier.',
            action: FilledButton(
              onPressed: () => tapped = true,
              child: const Text('Réessayer'),
            ),
          ),
        ),
      ),
    );
    expect(find.text('Hors ligne'), findsOneWidget);
    expect(
      find.text('Les données affichées datent d\u2019hier.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Réessayer'));
    expect(tapped, isTrue);
  });

  testWidgets('body and action are optional', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: campusTheme(Brightness.dark),
        home: const Scaffold(
          body: StateView(icon: Icons.inbox_outlined, title: 'Rien ici'),
        ),
      ),
    );
    expect(find.text('Rien ici'), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
