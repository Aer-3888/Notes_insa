import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/utils/base32_codec.dart';

void main() {
  group('Base32Codec', () {
    test('matches RFC 4648 vector ("Hello" -> JBSWY3DP)', () {
      expect(
        Base32Codec.encode(Uint8List.fromList('Hello'.codeUnits)),
        'JBSWY3DP',
      );
    });

    test('encode/decode round-trips arbitrary bytes', () {
      final data = Uint8List.fromList([0, 1, 2, 250, 128, 64, 255, 9, 17]);
      expect(Base32Codec.decode(Base32Codec.encode(data)), equals(data));
    });

    test('isValid accepts a 16+ char base32 secret', () {
      expect(Base32Codec.isValid('JBSWY3DPEHPK3PXP'), isTrue);
    });

    test('isValid rejects too-short or out-of-alphabet input', () {
      expect(Base32Codec.isValid('short'), isFalse);
      expect(Base32Codec.isValid('JBSWY3DPEHPK3PX1'), isFalse); // '1' invalid
    });
  });
}
