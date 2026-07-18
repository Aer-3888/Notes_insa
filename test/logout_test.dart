import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/constants.dart';
import 'package:notes_insa/providers/auth_providers.dart';
import 'package:notes_insa/providers/grades_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Logout must always reset the auth-gated state so AuthGate drops back to
/// onboarding. Regression guard for the bug where the reset lived behind a
/// widget `context.mounted` guard after an `await`, so a storage failure (or the
/// drawer unmounting) silently skipped it and stranded the user on the now-empty
/// dashboard.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const storageChannel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );
  const nativeChannel = MethodChannel('com.aer.notes_insa/grades');

  late Map<String, String> store;
  late List<String> nativeCalls;
  // When true, the secure-storage `deleteAll` throws, simulating a Keystore
  // hiccup — the exact failure mode that used to abort logout.
  late bool deleteAllThrows;

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'background_failure_started_at_ms': 1000,
      'last_background_failure_alert_ms': 2000,
    });
    store = <String, String>{};
    nativeCalls = <String>[];
    deleteAllThrows = false;

    messenger.setMockMethodCallHandler(storageChannel, (call) async {
      final args =
          (call.arguments as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};
      final key = args['key'] as String?;
      switch (call.method) {
        case 'read':
          return store[key];
        case 'write':
          store[key!] = args['value'] as String;
          return null;
        case 'delete':
          store.remove(key);
          return null;
        case 'deleteAll':
          if (deleteAllThrows) {
            throw PlatformException(code: 'Keystore', message: 'boom');
          }
          store.clear();
          return null;
        case 'readAll':
          return Map<String, String>.from(store);
        case 'containsKey':
          return store.containsKey(key);
      }
      return null;
    });

    messenger.setMockMethodCallHandler(nativeChannel, (call) async {
      nativeCalls.add(call.method);
      return null;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(storageChannel, null);
    messenger.setMockMethodCallHandler(nativeChannel, null);
  });

  test(
    'logout clears credentials and drops the session to onboarding',
    () async {
      store[kStorageUser] = 'jdoe';
      store[kStoragePass] = 'secret';

      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(appUnlockedProvider.notifier).state = true;
      // Sanity check: credentials are seen before logout.
      expect(await container.read(hasCredentialsProvider.future), isTrue);

      await container.read(gradesProvider.notifier).logout();

      expect(store, isEmpty);
      expect(container.read(appUnlockedProvider), isFalse);
      expect(await container.read(hasCredentialsProvider.future), isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.get('background_failure_started_at_ms'), isNull);
      expect(prefs.get('last_background_failure_alert_ms'), isNull);
      expect(
        nativeCalls,
        containsAll(<String>[
          'StopBackgroundTask',
          'ClearWorkerStore',
          'NewCAS',
        ]),
      );
    },
  );

  test(
    'logout stays locked and clears the worker store when secure storage fails',
    () async {
      deleteAllThrows = true;
      store[kStorageUser] = 'jdoe';
      store[kStoragePass] = 'secret';

      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(appUnlockedProvider.notifier).state = true;

      // Must not rethrow, and must still re-arm the lock gate — the reset can no
      // longer be skipped by a failing secure store.
      await container.read(gradesProvider.notifier).logout();

      expect(container.read(appUnlockedProvider), isFalse);
      expect(
        container.read(gradesProvider).authStatus,
        AuthStatus.logoutFailed,
      );
      expect(store, containsPair(kStorageUser, 'jdoe'));
      expect(nativeCalls, contains('ClearWorkerStore'));

      // Cleanup is idempotent: once the store recovers, a retry completes logout.
      deleteAllThrows = false;
      await container.read(gradesProvider.notifier).logout();
      expect(store, isEmpty);
      expect(
        container.read(gradesProvider).authStatus,
        AuthStatus.unauthenticated,
      );
    },
  );

  test(
    'an in-flight refresh cannot restore data after logout starts',
    () async {
      store[kStorageUser] = 'jdoe';
      store[kStoragePass] = 'secret';

      final gradesStarted = Completer<void>();
      final gradesResult = Completer<String>();
      messenger.setMockMethodCallHandler(nativeChannel, (call) async {
        nativeCalls.add(call.method);
        switch (call.method) {
          case 'ExportCAS':
            return 'old-session';
          case 'LoadGroups':
            return 1;
          case 'Grades':
            gradesStarted.complete();
            return gradesResult.future;
          case 'StopBackgroundTask':
          case 'ClearWorkerStore':
          case 'NewCAS':
            return null;
        }
        return null;
      });

      final container = ProviderContainer();
      addTearDown(container.dispose);
      final refresh = container
          .read(gradesProvider.notifier)
          .fetchGradesAfterAuth();
      await gradesStarted.future;

      final logout = container.read(gradesProvider.notifier).logout();
      expect(container.read(gradesProvider).authStatus, AuthStatus.loggingOut);
      gradesResult.complete('{"details": []}');

      await Future.wait([refresh, logout]);
      expect(store, isEmpty);
      expect(container.read(gradesProvider).jsonData, '{}');
      expect(
        container.read(gradesProvider).authStatus,
        AuthStatus.unauthenticated,
      );
    },
  );
}
