import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/modules/registry.dart';
import 'package:notes_insa/shell/home_hub_screen.dart';
import 'package:notes_insa/shell/module_card.dart';

void main() {
  Future<void> pumpHub(WidgetTester tester) async {
    // The hub grid is lazy, so the viewport must be tall enough to build every
    // card. Anything shorter tests the grid's laziness, not the hub's contents.
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: HomeHubScreen())),
    );
    await tester.pump();
  }

  testWidgets('the hub lists every registered module', (tester) async {
    await pumpHub(tester);
    for (final module in kCampusModules) {
      expect(
        find.text(module.label),
        findsWidgets,
        reason: '${module.id} missing from the hub',
      );
    }
  });

  testWidgets('coming-soon modules render their teaser and are not tappable', (
    tester,
  ) async {
    await pumpHub(tester);
    final placeholders = kCampusModules.whereType<ComingSoonModule>();
    expect(placeholders, isNotEmpty);
    for (final module in placeholders) {
      expect(find.text(module.teaser), findsOneWidget);
    }
    final cards = tester.widgetList<ModuleCard>(find.byType(ModuleCard));
    for (final card in cards) {
      if (card.module is ComingSoonModule) {
        expect(card.onTap, isNull);
      }
    }
  });

  testWidgets('the hub renders without any credentials', (tester) async {
    await pumpHub(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('Emploi du temps'), findsWidgets);
  });
}
