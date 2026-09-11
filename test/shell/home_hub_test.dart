import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/modules/library/library_today_card.dart';
import 'package:notes_insa/modules/crous/crous_today_card.dart';
import 'package:notes_insa/modules/registry.dart';
import 'package:notes_insa/shell/home_hub_screen.dart';
import 'package:notes_insa/shell/home_layout_provider.dart';
import 'package:notes_insa/shell/module_card.dart';

void main() {
  Future<void> pumpHub(
    WidgetTester tester, {
    Size viewport = const Size(1200, 2400),
  }) async {
    // The hub grid is lazy, so the viewport must be tall enough to build every
    // card. Anything shorter tests the grid's laziness, not the hub's contents.
    tester.view.physicalSize = viewport;
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

  testWidgets('every module card is tappable and nothing is greyed out', (
    tester,
  ) async {
    await pumpHub(tester);
    final cards = tester.widgetList<ModuleCard>(find.byType(ModuleCard));
    expect(cards, isNotEmpty);
    for (final card in cards) {
      expect(
        card.onTap,
        isNotNull,
        reason: '${card.module.id} is not tappable',
      );
    }
    expect(
      find.byWidgetPredicate((w) => w is Opacity && w.opacity < 1),
      findsNothing,
    );
    expect(find.textContaining('Bientôt'), findsNothing);
  });

  testWidgets('the day essentials sit above the grid', (tester) async {
    await pumpHub(tester);
    expect(find.byType(LibraryTodayCard), findsOneWidget);
    expect(find.text('Bibliothèques'), findsOneWidget);
  });

  testWidgets('the hub renders without any credentials', (tester) async {
    await pumpHub(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('Emploi du temps'), findsWidgets);
    expect(find.text('Aujourd’hui'), findsOneWidget);
  });

  testWidgets('edit mode keeps previews and resizes freely before snapping', (
    tester,
  ) async {
    await pumpHub(tester);

    await tester.tap(find.byTooltip('Modifier l’accueil'));
    await tester.pump();

    expect(find.byType(CrousTodayCard), findsOneWidget);
    expect(find.byType(LibraryTodayCard), findsOneWidget);

    final moduleId = moduleCardId('edt');
    final resize = find.byKey(ValueKey<String>('home-resize-$moduleId'));
    final card = find.byKey(ValueKey<String>('home-edit-$moduleId'));
    await tester.ensureVisible(resize);
    await tester.pumpAndSettle();
    final originalWidth = tester.getSize(card).width;
    final container = ProviderScope.containerOf(
      tester.element(find.byType(HomeHubScreen)),
    );
    final gesture = await tester.startGesture(tester.getCenter(resize));
    // Holding the resize grip must not activate the card's long-press mover.
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveBy(
      const Offset(30, 0),
      timeStamp: const Duration(milliseconds: 40),
    );
    await tester.pump(const Duration(milliseconds: 40));
    await gesture.moveBy(
      const Offset(100, 0),
      timeStamp: const Duration(milliseconds: 80),
    );
    await tester.pump(const Duration(milliseconds: 40));
    await gesture.moveBy(
      const Offset(100, 0),
      timeStamp: const Duration(milliseconds: 120),
    );
    await tester.pump(const Duration(milliseconds: 40));

    expect(tester.getSize(card).width, greaterThan(originalWidth));
    expect(
      container.read(homeLayoutProvider).sizeOf(moduleId),
      HomeCardSize.square,
    );

    await gesture.moveBy(
      const Offset(300, 0),
      timeStamp: const Duration(milliseconds: 160),
    );
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(
      container.read(homeLayoutProvider).sizeOf(moduleId),
      HomeCardSize.full,
    );
  });

  testWidgets('dragging the first card replaces its original position', (
    tester,
  ) async {
    await pumpHub(tester);
    await tester.tap(find.byTooltip('Modifier l’accueil'));
    await tester.pumpAndSettle();

    final courses = find.byKey(const ValueKey<String>('home-edit-courses'));
    final weather = find.byKey(const ValueKey<String>('home-edit-weather'));
    final weatherCenter = tester.getCenter(weather);
    final gesture = await tester.startGesture(tester.getCenter(courses));
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveTo(weatherCenter);
    await tester.pump(const Duration(milliseconds: 250));
    await gesture.up();
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(HomeHubScreen)),
    );
    final order = container.read(homeLayoutProvider).order;
    expect(order.indexOf('weather'), lessThan(order.indexOf('courses')));
  });

  testWidgets('resize and remove hit targets never overlap on a compact card', (
    tester,
  ) async {
    await pumpHub(tester, viewport: const Size(360, 1400));
    final container = ProviderScope.containerOf(
      tester.element(find.byType(HomeHubScreen)),
    );
    final moduleId = moduleCardId('edt');
    container
        .read(homeLayoutProvider.notifier)
        .setSize(moduleId, HomeCardSize.dot);

    await tester.tap(find.byTooltip('Modifier l’accueil'));
    await tester.pumpAndSettle();
    final resize = find.byKey(ValueKey<String>('home-resize-$moduleId'));
    final remove = find.byKey(ValueKey<String>('home-remove-$moduleId'));
    await tester.ensureVisible(resize);
    await tester.pumpAndSettle();

    expect(tester.getRect(remove).overlaps(tester.getRect(resize)), isFalse);
  });

  testWidgets(
    'vertical resize owns the gesture instead of scrolling the page',
    (tester) async {
      await pumpHub(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(HomeHubScreen)),
      );
      final moduleId = moduleCardId('edt');
      container
          .read(homeLayoutProvider.notifier)
          .setSize(moduleId, HomeCardSize.horizontal);
      await tester.tap(find.byTooltip('Modifier l’accueil'));
      await tester.pumpAndSettle();

      final resize = find.byKey(ValueKey<String>('home-resize-$moduleId'));
      final card = find.byKey(ValueKey<String>('home-edit-$moduleId'));
      await tester.ensureVisible(resize);
      await tester.pumpAndSettle();
      final originalSize = tester.getSize(card);
      final scrollable = Scrollable.of(tester.element(resize));
      final originalScrollOffset = scrollable.position.pixels;

      final gesture = await tester.startGesture(tester.getCenter(resize));
      await tester.pump(const Duration(milliseconds: 600));
      await gesture.moveBy(const Offset(0, 30));
      await tester.pump();
      await gesture.moveBy(const Offset(0, 200));
      await tester.pump();

      final resized = tester.getSize(card);
      expect(resized.width, originalSize.width);
      expect(resized.height, greaterThan(originalSize.height));
      expect(scrollable.position.pixels, originalScrollOffset);

      await gesture.up();
      await tester.pumpAndSettle();
      expect(
        container.read(homeLayoutProvider).sizeOf(moduleId),
        HomeCardSize.square,
      );

      await tester.ensureVisible(resize);
      await tester.pumpAndSettle();
      final squareHeight = tester.getSize(card).height;
      final scrollBeforeShrink = scrollable.position.pixels;
      final shrink = await tester.startGesture(tester.getCenter(resize));
      await shrink.moveBy(const Offset(0, -30));
      await tester.pump();
      await shrink.moveBy(const Offset(0, -200));
      await tester.pump();

      expect(tester.getSize(card).height, lessThan(squareHeight));
      expect(scrollable.position.pixels, scrollBeforeShrink);

      await shrink.up();
      await tester.pumpAndSettle();
      expect(
        container.read(homeLayoutProvider).sizeOf(moduleId),
        HomeCardSize.horizontal,
      );
    },
  );
}
