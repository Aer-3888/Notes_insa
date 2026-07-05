import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/utils/pbkdf2.dart';

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

void main() {
  group('pbkdf2Sha256', () {
    // Published PBKDF2-HMAC-SHA256 test vectors (P="password", S="salt").
    test('c=1 matches known vector', () {
      final dk = pbkdf2Sha256(
        utf8.encode('password'),
        utf8.encode('salt'),
        1,
        32,
      );
      expect(
        _hex(dk),
        '120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b',
      );
    });

    test('c=2 matches known vector', () {
      final dk = pbkdf2Sha256(
        utf8.encode('password'),
        utf8.encode('salt'),
        2,
        32,
      );
      expect(
        _hex(dk),
        'ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43',
      );
    });

    test('c=4096 matches known vector', () {
      final dk = pbkdf2Sha256(
        utf8.encode('password'),
        utf8.encode('salt'),
        4096,
        32,
      );
      expect(
        _hex(dk),
        'c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a',
      );
    });

    test('multi-block output (dkLen 40) matches known vector', () {
      // P="passwordPASSWORDpassword", S="saltSALTsaltSALTsaltSALTsaltSALTsalt".
      final dk = pbkdf2Sha256(
        utf8.encode('passwordPASSWORDpassword'),
        utf8.encode('saltSALTsaltSALTsaltSALTsaltSALTsalt'),
        4096,
        40,
      );
      expect(
        _hex(dk),
        '348c89dbcbd32b2f32d814b8116e84cf2b17347ebc1800181c4e2a1fb8dd53e1'
        'c635518c7dac47e9',
      );
    });

    test('same inputs are deterministic; different salt differs', () {
      final a = pbkdf2Sha256(
        utf8.encode('1234'),
        utf8.encode('saltA'),
        500,
        32,
      );
      final b = pbkdf2Sha256(
        utf8.encode('1234'),
        utf8.encode('saltA'),
        500,
        32,
      );
      final c = pbkdf2Sha256(
        utf8.encode('1234'),
        utf8.encode('saltB'),
        500,
        32,
      );
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });
  });
}
