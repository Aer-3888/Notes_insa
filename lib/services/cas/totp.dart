import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../utils/base32_codec.dart';

/// RFC 6238 TOTP with the parameters the CAS accepts: SHA-1, 30 s, 6 digits.
class Totp {
  static const int stepSeconds = 30;
  static const int _digits = 6;

  /// Code for the base32 [secret] at [at], defaulting to now. Throws
  /// [FormatException] when the secret is not valid base32.
  static String generate(String secret, {DateTime? at}) {
    final key = Base32Codec.decode(secret.replaceAll(RegExp(r'[\s-]'), ''));
    if (key.isEmpty) throw const FormatException('empty TOTP secret');

    final seconds =
        (at ?? DateTime.now()).toUtc().millisecondsSinceEpoch ~/ 1000;
    return _hotp(key, seconds ~/ stepSeconds);
  }

  /// The time-step counter [at] falls in, used to avoid replaying a code.
  static int stepAt(DateTime at) =>
      (at.toUtc().millisecondsSinceEpoch ~/ 1000) ~/ stepSeconds;

  static String _hotp(Uint8List key, int counter) {
    final message = Uint8List(8);
    var remaining = counter;
    for (var i = 7; i >= 0; i--) {
      message[i] = remaining & 0xff;
      remaining >>= 8;
    }

    final digest = Hmac(sha1, key).convert(message).bytes;
    final offset = digest[digest.length - 1] & 0x0f;
    final binary =
        ((digest[offset] & 0x7f) << 24) |
        ((digest[offset + 1] & 0xff) << 16) |
        ((digest[offset + 2] & 0xff) << 8) |
        (digest[offset + 3] & 0xff);

    return (binary % 1000000).toString().padLeft(_digits, '0');
  }
}
