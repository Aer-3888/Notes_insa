import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/utils/base32_codec.dart';
import 'package:notes_insa/utils/google_auth_migration_decoder.dart';

/// Builds a length-delimited (wire type 2) protobuf field. Payloads here are
/// small (< 128 bytes) so the length fits in a single varint byte.
List<int> _field(int fieldNumber, List<int> payload) {
  final tag = (fieldNumber << 3) | 2;
  return [tag, payload.length, ...payload];
}

/// Builds a varint (wire type 0) protobuf field. Values here are < 128 so they
/// fit in a single byte.
List<int> _varintField(int fieldNumber, int value) {
  final tag = (fieldNumber << 3) | 0;
  return [tag, value];
}

String _migrationUri(List<int> otpParams) {
  final b64 = base64.encode(_field(1, otpParams));
  return 'otpauth-migration://offline?data=${Uri.encodeQueryComponent(b64)}';
}

void main() {
  test('decodes a single-account otpauth-migration payload', () {
    final secret = [72, 101, 108, 108, 111]; // "Hello"
    final otp = <int>[
      ..._field(1, secret), // secret (bytes)
      ..._field(2, utf8.encode('alice@google.com')), // name
      ..._field(3, utf8.encode('Example')), // issuer
    ];
    final payload = _field(1, otp); // repeated otp_parameters
    final b64 = base64.encode(payload);
    final uri =
        'otpauth-migration://offline?data=${Uri.encodeQueryComponent(b64)}';

    final accounts = GoogleAuthMigrationDecoder.decode(uri);

    expect(accounts.length, 1);
    expect(
      accounts.first.secret,
      Base32Codec.encode(Uint8List.fromList(secret)),
    );
    expect(accounts.first.name, 'alice@google.com');
    expect(accounts.first.issuer, 'Example');
  });

  test('throws on a non-migration URI', () {
    expect(
      () => GoogleAuthMigrationDecoder.decode('otpauth://totp/x?secret=ABC'),
      throwsFormatException,
    );
  });

  test('a plain account with no type/algorithm/digits is a supported TOTP', () {
    final acc = GoogleAuthMigrationDecoder.decode(
      _migrationUri(_field(1, [1, 2, 3, 4, 5])),
    ).single;
    expect(acc.type, OtpType.totp);
    expect(acc.algorithm, OtpAlgorithm.sha1);
    expect(acc.digits, 6);
    expect(acc.isSupportedTotp, isTrue);
  });

  test('HOTP account is parsed but not a supported TOTP', () {
    final acc = GoogleAuthMigrationDecoder.decode(
      _migrationUri([
        ..._field(1, [1, 2, 3, 4, 5]),
        ..._varintField(6, 1), // type = HOTP
      ]),
    ).single;
    expect(acc.type, OtpType.hotp);
    expect(acc.isSupportedTotp, isFalse);
  });

  test('SHA-256 / 8-digit TOTP is parsed but not supported', () {
    final acc = GoogleAuthMigrationDecoder.decode(
      _migrationUri([
        ..._field(1, [1, 2, 3, 4, 5]),
        ..._varintField(4, 2), // algorithm = SHA256
        ..._varintField(5, 2), // digits = EIGHT
        ..._varintField(6, 2), // type = TOTP
      ]),
    ).single;
    expect(acc.algorithm, OtpAlgorithm.sha256);
    expect(acc.digits, 8);
    expect(acc.isSupportedTotp, isFalse);
  });

  test('out-of-range algorithm value is unknown and unsupported', () {
    final acc = GoogleAuthMigrationDecoder.decode(
      _migrationUri([
        ..._field(1, [1, 2, 3, 4, 5]),
        ..._varintField(4, 9), // algorithm: out of range
        ..._varintField(6, 2), // type = TOTP
      ]),
    ).single;
    expect(acc.algorithm, OtpAlgorithm.unknown);
    expect(acc.isSupportedTotp, isFalse);
  });

  test('explicit standard TOTP (SHA1, 6 digits) is supported', () {
    final acc = GoogleAuthMigrationDecoder.decode(
      _migrationUri([
        ..._field(1, [1, 2, 3, 4, 5]),
        ..._varintField(4, 1), // algorithm = SHA1
        ..._varintField(5, 1), // digits = SIX
        ..._varintField(6, 2), // type = TOTP
      ]),
    ).single;
    expect(acc.isSupportedTotp, isTrue);
  });
}
