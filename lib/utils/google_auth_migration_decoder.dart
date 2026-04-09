import 'dart:convert';
import 'dart:typed_data';
import 'base32_codec.dart';

/// Decoder for Google Authenticator migration URIs.
///
/// The `decode` method accepts an `otpauth-migration` URI (as produced by
/// Google Authenticator export) and returns a list of OTP accounts with
/// base32-encoded secrets.
class GoogleAuthMigrationDecoder {
  /// Decode an `otpauth-migration` URI and return decoded OTP accounts.
  ///
  /// Throws [FormatException] when the URI is invalid or the payload is
  /// malformed.
  static List<OtpAccount> decode(String uri) {
    final parsedUri = Uri.parse(uri);

    if (parsedUri.scheme != 'otpauth-migration') {
      throw const FormatException('Not a valid otpauth-migration URI');
    }

    final dataParam = parsedUri.queryParameters['data'];
    if (dataParam == null) {
      throw const FormatException('Missing data parameter in migration URI');
    }

    final decodedBytes = base64.decode(Uri.decodeComponent(dataParam));
    return _parseProtobuf(decodedBytes);
  }

  /// Parse the top-level protobuf payload and return OTP accounts.
  static List<OtpAccount> _parseProtobuf(Uint8List data) {
    final accounts = <OtpAccount>[];
    int offset = 0;

    while (offset < data.length) {
      final result = _readField(data, offset);
      final fieldNumber = result['fieldNumber'] as int;
      final wireType = result['wireType'] as int;
      offset = result['offset'] as int;

      // Field 1 = repeated OtpParameters (length-delimited)
      if (fieldNumber == 1 && wireType == 2) {
        final lengthResult = _readVarint(data, offset);
        final length = lengthResult['value'] as int;
        offset = lengthResult['offset'] as int;

        // Guard against malformed payloads where the length would overrun
        if (offset + length > data.length) {
          throw const FormatException(
            'Invalid length for OtpParameters in migration payload',
          );
        }

        final otpParamsData = data.sublist(offset, offset + length);
        final account = _parseOtpParameters(otpParamsData);
        if (account != null) accounts.add(account);
        offset += length;
      } else {
        // Skip unknown fields
        offset = _skipField(data, offset, wireType);
      }
    }

    return accounts;
  }

  /// Parse a single OtpParameters message and return an [OtpAccount].
  static OtpAccount? _parseOtpParameters(Uint8List data) {
    String? name;
    String? issuer;
    Uint8List? secret;

    int offset = 0;
    while (offset < data.length) {
      final result = _readField(data, offset);
      final fieldNumber = result['fieldNumber'] as int;
      final wireType = result['wireType'] as int;
      offset = result['offset'] as int;

      if (wireType == 2) {
        // Length-delimited (string or bytes)
        final lengthResult = _readVarint(data, offset);
        final length = lengthResult['value'] as int;
        offset = lengthResult['offset'] as int;

        // Protect against invalid lengths
        if (offset + length > data.length) {
          throw const FormatException(
            'Invalid length for field in OtpParameters',
          );
        }

        final value = data.sublist(offset, offset + length);

        switch (fieldNumber) {
          case 1: // secret (bytes)
            secret = value;
            break;
          case 2: // name (string)
            name = utf8.decode(value);
            break;
          case 3: // issuer (string)
            issuer = utf8.decode(value);
            break;
        }

        offset += length;
      } else {
        offset = _skipField(data, offset, wireType);
      }
    }

    if (secret != null) {
      final secretBase32 = Base32Codec.encode(secret);
      return OtpAccount(
        name: name ?? 'Unknown',
        issuer: issuer ?? 'Unknown',
        secret: secretBase32,
      );
    }

    return null;
  }

  /// Read a protobuf field tag and return its field number and wire type.
  static Map<String, int> _readField(Uint8List data, int offset) {
    final varintResult = _readVarint(data, offset);
    final tag = varintResult['value'] as int;
    final fieldNumber = tag >> 3;
    final wireType = tag & 0x7;
    return {
      'fieldNumber': fieldNumber,
      'wireType': wireType,
      'offset': varintResult['offset'] as int,
    };
  }

  /// Read a varint value starting at [offset]. Returns the parsed value and
  /// the offset immediately after the varint.
  static Map<String, int> _readVarint(Uint8List data, int offset) {
    int value = 0;
    int shift = 0;

    while (offset < data.length) {
      if (shift >= 63) throw const FormatException('Varint too large');
      final byte = data[offset];
      value |= (byte & 0x7F) << shift;
      offset++;

      if ((byte & 0x80) == 0) break;
      shift += 7;
    }

    return {'value': value, 'offset': offset};
  }

  /// Skip an encoded field by its wire type and return the new offset.
  static int _skipField(Uint8List data, int offset, int wireType) {
    switch (wireType) {
      case 0: // Varint
        final result = _readVarint(data, offset);
        return result['offset'] as int;
      case 1: // 64-bit
        return offset + 8;
      case 2: // Length-delimited
        final lengthResult = _readVarint(data, offset);
        final length = lengthResult['value'] as int;
        // Guard against invalid lengths when skipping
        if ((lengthResult['offset'] as int) + length > data.length) {
          throw const FormatException('Invalid length while skipping field');
        }
        return (lengthResult['offset'] as int) + length;
      case 5: // 32-bit
        return offset + 4;
      default:
        throw FormatException('Unknown wire type: $wireType');
    }
  }
}

/// OTP account container with base32 secret.
class OtpAccount {
  final String name;
  final String issuer;
  final String secret; // Base32 encoded

  OtpAccount({required this.name, required this.issuer, required this.secret});

  @override
  String toString() {
    return 'OtpAccount(name: $name, issuer: $issuer, secret: [REDACTED])';
  }
}
