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
}
