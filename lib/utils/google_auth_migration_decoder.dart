import 'dart:convert';
import 'dart:typed_data';
import 'base32_codec.dart';

class GoogleAuthMigrationDecoder {
  // Extract OTP accounts from a migration URI
  static List<OtpAccount> decode(String uri) {
    try {
      final parsedUri = Uri.parse(uri);

      if (parsedUri.scheme != 'otpauth-migration') {
        throw Exception('Not a valid otpauth-migration URI');
      }

      final dataParam = parsedUri.queryParameters['data'];
      if (dataParam == null) {
        throw Exception('Missing data parameter in migration URI');
      }

      final decodedBytes = base64.decode(Uri.decodeComponent(dataParam));
      return _parseProtobuf(decodedBytes);
    } catch (e) {
      rethrow;
    }
  }

  // Parse protobuf payload and return accounts
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

        final otpParamsData = data.sublist(offset, offset + length);
        final account = _parseOtpParameters(otpParamsData);
        if (account != null) {
          accounts.add(account);
        }
        offset += length;
      } else {
        // Skip unknown fields
        offset = _skipField(data, offset, wireType);
      }
    }

    return accounts;
  }

  // Parse one OtpParameters message and return account
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
      // Convert secret bytes to base32 string
      final secretBase32 = Base32Codec.encode(secret);
      return OtpAccount(
        name: name ?? 'Unknown',
        issuer: issuer ?? 'Unknown',
        secret: secretBase32,
      );
    }

    return null;
  }

  // Read protobuf field header
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

  // Read varint value
  static Map<String, int> _readVarint(Uint8List data, int offset) {
    int value = 0;
    int shift = 0;

    while (offset < data.length) {
      final byte = data[offset];
      value |= (byte & 0x7F) << shift;
      offset++;

      if ((byte & 0x80) == 0) {
        break;
      }
      shift += 7;
    }

    return {'value': value, 'offset': offset};
  }

  // Skip field by wire type
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
        return (lengthResult['offset'] as int) + length;
      case 5: // 32-bit
        return offset + 4;
      default:
        throw Exception('Unknown wire type: $wireType');
    }
  }
}

// OTP account container
class OtpAccount {
  final String name;
  final String issuer;
  final String secret; // Base32 encoded

  OtpAccount({required this.name, required this.issuer, required this.secret});

  @override
  String toString() =>
      'OtpAccount(name: $name, issuer: $issuer, secret: ${secret.substring(0, secret.length > 10 ? 10 : secret.length)}...)';
}
