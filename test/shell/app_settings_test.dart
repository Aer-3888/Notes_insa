import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/shell/app_settings_screen.dart';

void main() {
  testWidgets('app settings render with no credentials', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: AppSettingsScreen())),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byType(AppSettingsScreen), findsOneWidget);
  });

  testWidgets('app settings expose no grade sharing controls', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: AppSettingsScreen())),
    );
    await tester.pump();
    // Grade-specific controls belong to the grades module, which is gated.
    // Anything here is reachable by a user with no account at all.
    expect(find.textContaining('notes'), findsNothing);
    expect(find.textContaining('partage'), findsNothing);
    expect(find.byType(Switch), findsNothing);
  });

  testWidgets('app settings name the timetable data source contact', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: AppSettingsScreen())),
    );
    await tester.pump();
    expect(find.textContaining('À propos'), findsOneWidget);
  });
}
