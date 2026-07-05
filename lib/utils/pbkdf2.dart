import 'dart:typed_data';
import 'package:crypto/crypto.dart';

/// PBKDF2-HMAC-SHA256 key derivation (RFC 2898).
///
/// Implemented on top of the crypto package's [Hmac] so no heavyweight crypto
/// dependency is needed. Returns [dkLen] derived bytes from [password] and
/// [salt] after [iterations] rounds. Used to store PIN verifiers with a slow
/// hash so a low-entropy PIN is not trivially brute-forceable if the encrypted
/// store is ever extracted.
Uint8List pbkdf2Sha256(
  List<int> password,
  List<int> salt,
  int iterations,
  int dkLen,
) {
  assert(iterations > 0);
  assert(dkLen > 0);
  const hLen = 32; // SHA-256 output size in bytes.
  final hmac = Hmac(sha256, password);
  final numBlocks = (dkLen + hLen - 1) ~/ hLen;
  final derived = Uint8List(numBlocks * hLen);

  for (var block = 1; block <= numBlocks; block++) {
    // Big-endian block index appended to the salt for the first iteration.
    final blockIndex = Uint8List(4)
      ..[0] = (block >> 24) & 0xff
      ..[1] = (block >> 16) & 0xff
      ..[2] = (block >> 8) & 0xff
      ..[3] = block & 0xff;

    var u = Uint8List.fromList(hmac.convert([...salt, ...blockIndex]).bytes);
    final t = Uint8List.fromList(u);
    for (var i = 1; i < iterations; i++) {
      u = Uint8List.fromList(hmac.convert(u).bytes);
      for (var j = 0; j < hLen; j++) {
        t[j] ^= u[j];
      }
    }
    derived.setRange((block - 1) * hLen, block * hLen, t);
  }

  return Uint8List.sublistView(derived, 0, dkLen);
}
