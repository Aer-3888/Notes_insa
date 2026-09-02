import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/core/auth/lock_controller.dart';
import 'package:notes_insa/core/auth/lock_screen.dart';
import 'package:notes_insa/providers/auth_providers.dart';

/// A stand-in for a gated module that opens a bottom sheet, as the grades
/// dashboard does at modules/grades/dashboard_screen.dart:219.
class _FakeGatedModule extends StatelessWidget {
  const _FakeGatedModule();

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: ElevatedButton(
        onPressed: () => showModalBottomSheet<void>(
          context: context,
          builder: (_) => const Text('NOTE SECRETE'),
        ),
        child: const Text('ouvrir'),
      ),
    ),
  );
}

void main() {
  testWidgets('the lock covers a bottom sheet opened inside a gated module', (
    tester,
  ) async {
    final navKey = GlobalKey<NavigatorState>();
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(gradesUnlockedProvider.notifier).state = true;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          navigatorKey: navKey,
          home: const _FakeGatedModule(),
        ),
      ),
    );

    await tester.tap(find.text('ouvrir'));
    await tester.pumpAndSettle();
    expect(find.text('NOTE SECRETE'), findsOneWidget);

    // Background, then resume.
    final controller = LockController(container, navKey);
    controller.onPause();
    await tester.pumpAndSettle();
    expect(container.read(gradesUnlockedProvider), isFalse);

    unawaited(controller.onResume());
    await tester.pumpAndSettle();

    // The lock is an opaque root route, so Flutter stops building everything
    // beneath it. The sheet is not merely covered, it is unmounted. Asserted
    // together with the line above proving it was on screen a moment earlier.
    expect(find.byType(LockBarrier), findsOneWidget);
    expect(
      find.text('NOTE SECRETE'),
      findsNothing,
      reason: 'grade content must not survive under the lock',
    );

    // And the lock genuinely fills the viewport rather than being a stub.
    expect(
      tester.getRect(find.byType(LockBarrier)),
      tester.getRect(find.byType(MaterialApp)),
    );
  });

  testWidgets('onResume does not push a second lock when one is showing', (
    tester,
  ) async {
    final navKey = GlobalKey<NavigatorState>();
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          navigatorKey: navKey,
          home: const _FakeGatedModule(),
        ),
      ),
    );

    final controller = LockController(container, navKey);
    unawaited(controller.onResume());
    await tester.pumpAndSettle();
    unawaited(controller.onResume());
    await tester.pumpAndSettle();

    expect(find.byType(LockBarrier), findsOneWidget);
  });

  testWidgets('onResume does not show the lock while already unlocked', (
    tester,
  ) async {
    final navKey = GlobalKey<NavigatorState>();
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(gradesUnlockedProvider.notifier).state = true;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          navigatorKey: navKey,
          home: const _FakeGatedModule(),
        ),
      ),
    );

    final controller = LockController(container, navKey);
    unawaited(controller.onResume());
    await tester.pumpAndSettle();

    expect(find.byType(LockBarrier), findsNothing);
  });
}
