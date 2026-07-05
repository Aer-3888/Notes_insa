import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/services/auth_service.dart';
import 'package:notes_insa/constants.dart';

/// In-memory fake for the flutter_secure_storage method channel so AuthService's
/// PIN logic can be exercised without a device Keystore.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  late Map<String, String> store;

  setUp(() {
    store = <String, String>{};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
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
              store.clear();
              return null;
            case 'containsKey':
              return store.containsKey(key);
            case 'readAll':
              return Map<String, String>.from(store);
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('AuthService PIN', () {
    test(
      'setPin stores a PBKDF2 verifier and verifies the right PIN',
      () async {
        final auth = AuthService();
        await auth.setPin('123456');

        expect(store[kStoragePin], startsWith('pbkdf2\$'));
        expect(store[kStoragePin], isNot(contains('123456')));
        expect(await auth.verifyPin('123456'), isTrue);
        expect(await auth.verifyPin('000000'), isFalse);
      },
    );

    test(
      'legacy salted SHA-256 PIN migrates to PBKDF2 on correct entry',
      () async {
        final auth = AuthService();
        const salt = 'abcdefghijklmnop';
        // Seed a pre-PBKDF2 verifier in the old format.
        store[kStoragePinSalt] = salt;
        final legacyHash = sha256
            .convert(utf8.encode('$salt:654321'))
            .toString();
        store[kStoragePin] = legacyHash;

        // A wrong PIN is rejected and does NOT migrate the legacy verifier.
        expect(await auth.verifyPin('999999'), isFalse);
        expect(store[kStoragePin], legacyHash);

        expect(await auth.verifyPin('654321'), isTrue);
        // Verifier is upgraded in place to the slow hash.
        expect(store[kStoragePin], startsWith('pbkdf2\$'));
        // And still verifies afterwards.
        expect(await auth.verifyPin('654321'), isTrue);
      },
    );

    test('legacy plaintext PIN (no salt) migrates on correct entry', () async {
      final auth = AuthService();
      store[kStoragePin] = '246810'; // plaintext, no salt stored

      // A wrong PIN is rejected and leaves the plaintext verifier untouched.
      expect(await auth.verifyPin('111111'), isFalse);
      expect(store[kStoragePin], '246810');
      expect(store[kStoragePinSalt], isNull);

      expect(await auth.verifyPin('246810'), isTrue);
      expect(store[kStoragePinSalt], isNotNull);
      expect(store[kStoragePin], startsWith('pbkdf2\$'));
    });

    test('lockout triggers after max attempts and escalates', () async {
      final auth = AuthService();
      await auth.setPin('135790');

      // 4 failures leave attempts remaining, none triggers a lockout.
      for (var i = 0; i < 4; i++) {
        final remaining = await auth.recordPinFailure();
        expect(remaining, greaterThan(0));
        expect(await auth.pinLockoutRemaining(), isNull);
      }
      // The 5th trips the lockout. First ladder step is 1 minute.
      expect(await auth.recordPinFailure(), 0);
      final firstLock = await auth.pinLockoutRemaining();
      expect(firstLock, isNotNull);
      expect(firstLock!.inSeconds, greaterThan(0));
      expect(firstLock.inSeconds, lessThanOrEqualTo(60));

      // A second run of failures escalates to a longer (5 minute) lockout.
      for (var i = 0; i < 5; i++) {
        await auth.recordPinFailure();
      }
      final secondLock = await auth.pinLockoutRemaining();
      expect(secondLock, isNotNull);
      expect(secondLock!.inSeconds, greaterThan(firstLock.inSeconds));
      expect(secondLock.inMinutes, greaterThanOrEqualTo(4));

      // A reset (as happens on a correct entry) clears the lockout.
      await auth.resetPinAttempts();
      expect(await auth.pinLockoutRemaining(), isNull);
    });

    test('pinNeedsUpgrade flags a too-short PIN', () async {
      final auth = AuthService();
      store[kStoragePinSalt] = 'abcdefghijklmnop';
      store[kStoragePin] = 'pbkdf2\$120000\$deadbeef';

      // An explicitly-recorded short length needs upgrading.
      store[kStoragePinLength] = '4';
      expect(await auth.pinNeedsUpgrade(), isTrue);

      // A missing length (configured before lengths were recorded) also does.
      store.remove(kStoragePinLength);
      expect(await auth.pinNeedsUpgrade(), isTrue);

      await auth.setPin('123456');
      expect(await auth.pinNeedsUpgrade(), isFalse);
    });
  });
}
