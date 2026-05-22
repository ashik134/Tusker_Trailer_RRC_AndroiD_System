import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// AES-128-GCM encryption helper for PLC digital-characteristic writes.
///
/// Matches the firmware's `decryptAESGCM_hex_or_raw` in main.cpp exactly:
///   - Key  : "TUSKER_RRC_DEV_1" (aesKey[16] in firmware)
///   - Wire format sent to PLC: uppercase hex text of IV(12) || CIPHER || TAG(16)
///     The firmware's hex-decode path is used, which is unambiguous regardless
///     of raw byte values.
///
/// SECURITY NOTE: A hardcoded symmetric key ships with the binary.
/// For a production deployment, replace this with a per-session key derived via
/// a secure key-exchange step (e.g. ECDH over the auth characteristic) so the
/// key is never static and cannot be extracted from the APK.
class BleCrypto {
  BleCrypto._();

  // "TUSKER_RRC_DEV_1" — 16-byte AES-128 key, must match firmware aesKey[].
  static const List<int> _keyBytes = [
    0x54, 0x55, 0x53, 0x4B, // T U S K
    0x45, 0x52, 0x5F, 0x52, // E R _ R
    0x52, 0x43, 0x5F, 0x44, // R C _ D
    0x45, 0x56, 0x5F, 0x31, // E V _ 1
  ];

  // AesGcm.with128bits() — 128-bit key, 12-byte nonce, 16-byte GCM tag.
  static final _algorithm = AesGcm.with128bits();

  // SecretKey wraps the raw bytes; safe to cache as a static.
  static final _secretKey = SecretKey(_keyBytes);

  /// Encrypts [plaintext] with AES-128-GCM.
  ///
  /// Returns the BLE wire payload as raw bytes that, when written to the
  /// digital characteristic, the firmware can decrypt via its hex-decode path:
  ///
  ///   UTF-8 encoded uppercase hex string of:
  ///     IV (12 bytes) || CIPHERTEXT || GCM TAG (16 bytes)
  ///
  /// Example: 10-byte plaintext → 38 raw bytes → 76-character hex string
  ///   → 76 UTF-8 bytes on the wire.
  static Future<List<int>> encrypt(List<int> plaintext) async {
    // newNonce() uses the platform's cryptographically secure RNG.
    final nonce = _algorithm.newNonce();
    final secretBox = await _algorithm.encrypt(
      plaintext,
      secretKey: _secretKey,
      nonce: nonce,
    );

    // Build IV || ciphertext || GCM tag as a contiguous byte array.
    final rawLen =
        nonce.length + secretBox.cipherText.length + secretBox.mac.bytes.length;
    final raw = Uint8List(rawLen);
    var offset = 0;
    for (final b in nonce) raw[offset++] = b;
    for (final b in secretBox.cipherText) raw[offset++] = b;
    for (final b in secretBox.mac.bytes) raw[offset++] = b;

    // Hex-encode to uppercase 2-char-per-byte text so the firmware reliably
    // picks the decodeHexText branch in decryptAESGCM_hex_or_raw.
    final sb = StringBuffer();
    for (final b in raw) {
      sb.write(b.toRadixString(16).padLeft(2, '0').toUpperCase());
    }
    return utf8.encode(sb.toString());
  }
}
