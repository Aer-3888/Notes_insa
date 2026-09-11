import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/services/cas/totp.dart';

void main() {
  // RFC 6238 appendix B, SHA-1 rows, truncated to the last six digits.
  const secret = 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ'; // "12345678901234567890"

  const vectors = <int, String>{
    59: '287082',
    1111111109: '081804',
    1111111111: '050471',
    1234567890: '005924',
    2000000000: '279037',
  };

  group('Totp.generate', () {
    vectors.forEach((int unixSeconds, String expected) {
      test('matches RFC 6238 at T=$unixSeconds', () {
        final at = DateTime.fromMillisecondsSinceEpoch(
          unixSeconds * 1000,
          isUtc: true,
        );
        expect(Totp.generate(secret, at: at), expected);
      });
    });

    test('tolerates the spacing authenticator apps print', () {
      final at = DateTime.fromMillisecondsSinceEpoch(59000, isUtc: true);
      expect(
        Totp.generate('gezd gnbv gy3t qojq gezd gnbv gy3t qojq', at: at),
        '287082',
      );
    });

    test('always returns six digits', () {
      for (var t = 0; t < 2000; t += 37) {
        final at = DateTime.fromMillisecondsSinceEpoch(t * 1000, isUtc: true);
        expect(Totp.generate(secret, at: at), matches(RegExp(r'^\d{6}$')));
      }
    });

    test('rejects a non-base32 secret', () {
      expect(() => Totp.generate('not-a-secret!'), throwsFormatException);
    });

    test('rejects an empty secret', () {
      expect(() => Totp.generate(''), throwsFormatException);
    });
  });

  group('Totp.stepAt', () {
    test('advances once per 30 seconds', () {
      DateTime at(int s) =>
          DateTime.fromMillisecondsSinceEpoch(s * 1000, isUtc: true);

      expect(Totp.stepAt(at(0)), 0);
      expect(Totp.stepAt(at(29)), 0);
      expect(Totp.stepAt(at(30)), 1);
      expect(Totp.stepAt(at(59)), 1);
      expect(Totp.stepAt(at(60)), 2);
    });

    test('agrees with the code boundary', () {
      DateTime at(int s) =>
          DateTime.fromMillisecondsSinceEpoch(s * 1000, isUtc: true);

      expect(
        Totp.generate(secret, at: at(29)),
        Totp.generate(secret, at: at(0)),
      );
      expect(
        Totp.generate(secret, at: at(30)),
        isNot(Totp.generate(secret, at: at(29))),
      );
    });
  });
}
