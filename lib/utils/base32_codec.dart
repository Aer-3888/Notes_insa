import 'dart:typed_data';

/// Simple Base32 encoder for OTP secrets
/// Implements RFC 4648 base32 encoding
class Base32Codec {
  static const String _alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

  /// Encode bytes to base32 string
  static String encode(Uint8List data) {
    if (data.isEmpty) return '';

    final result = StringBuffer();
    int bits = 0;
    int value = 0;

    for (final byte in data) {
      value = (value << 8) | byte;
      bits += 8;

      while (bits >= 5) {
        result.write(_alphabet[(value >> (bits - 5)) & 31]);
        bits -= 5;
      }
    }

    if (bits > 0) {
      result.write(_alphabet[(value << (5 - bits)) & 31]);
    }

    // Add padding
    while (result.length % 8 != 0) {
      result.write('=');
    }

    return result.toString();
  }

  /// Returns true if [data] looks like a valid base32 secret.
  /// Strips padding, checks charset, and requires at least 16 characters
  /// (80 bits — the minimum for a usable TOTP secret).
  static bool isValid(String data) {
    final stripped = data.replaceAll('=', '').toUpperCase().trim();
    if (stripped.length < 16) return false;
    return stripped.split('').every((c) => _alphabet.contains(c));
  }

  /// Decode base32 string to bytes
  static Uint8List decode(String data) {
    // Remove padding
    data = data.replaceAll('=', '').toUpperCase();

    if (data.isEmpty) return Uint8List(0);

    final result = <int>[];
    int bits = 0;
    int value = 0;

    for (int i = 0; i < data.length; i++) {
      final char = data[i];
      final index = _alphabet.indexOf(char);

      if (index < 0) {
        throw FormatException('Invalid base32 character: $char');
      }

      value = (value << 5) | index;
      bits += 5;

      if (bits >= 8) {
        result.add((value >> (bits - 8)) & 255);
        bits -= 8;
      }
    }

    return Uint8List.fromList(result);
  }
}
