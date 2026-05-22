import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// AES-128-GCM symmetric encryption service for the Tusker Trailer RRC BLE protocol.
///
/// LIFECYCLE
/// ─────────────────────────────────────────────────────────────────────────────
/// 1. Call [initialize] once at app startup, passing the 16-byte AES-128 key
///    retrieved from [SecureKeyStore].
/// 2. Call [encryptPacket] for every outbound BLE packet before writing.
/// 3. Call [decryptPacket] for every inbound notification after receiving.
///
/// ENCRYPTED WIRE FORMAT
/// ─────────────────────────────────────────────────────────────────────────────
///   [12 bytes]  Random IV / Nonce  (generated fresh per packet via CSPRNG)
///   [N  bytes]  AES-128-GCM ciphertext
///   [16 bytes]  GCM authentication tag
///
/// Thread safety: pure Dart, single-threaded isolate; [_secretKey] is set once
/// during initialization and never mutated afterwards.
/// ─────────────────────────────────────────────────────────────────────────────
class CryptoService {
  CryptoService._();
  static final CryptoService instance = CryptoService._();

  static final AesGcm _aesGcm = AesGcm.with128bits();

  SecretKey? _secretKey;
  bool _initialized = false;

  bool get isInitialized => _initialized;

  /// Initialize with [keyBytes] — must be exactly 16 bytes (AES-128).
  /// Throws [ArgumentError] if the key length is wrong.
  Future<void> initialize(List<int> keyBytes) async {
    if (keyBytes.length != 16) {
      throw ArgumentError(
        'AES-128 key must be exactly 16 bytes; received ${keyBytes.length}.',
      );
    }
    _secretKey = await _aesGcm.newSecretKeyFromBytes(keyBytes);
    _initialized = true;
  }

  /// Encrypt [plaintext] and return the BLE wire payload:
  ///   [12 bytes IV] || [ciphertext] || [16 bytes GCM auth tag]
  ///
  /// A new cryptographically random IV is generated for every call.
  Future<Uint8List> encryptPacket(Uint8List plaintext) async {
    _assertInitialized();

    final nonce = _aesGcm.newNonce();
    final box = await _aesGcm.encrypt(
      plaintext,
      secretKey: _secretKey!,
      nonce: nonce,
    );

    final out = Uint8List(
      box.nonce.length + box.cipherText.length + box.mac.bytes.length,
    );
    int off = 0;
    out.setAll(off, box.nonce);       off += box.nonce.length;
    out.setAll(off, box.cipherText);  off += box.cipherText.length;
    out.setAll(off, box.mac.bytes);
    return out;
  }

  /// Decrypt and authenticate [packet] produced by [encryptPacket].
  ///
  /// Throws [SecurePacketException] if:
  ///   • the GCM authentication tag does not match (tampering / key mismatch)
  ///   • the packet is too short to be a valid encrypted frame
  ///   • any other decryption error occurs
  Future<Uint8List> decryptPacket(Uint8List packet) async {
    _assertInitialized();

    const ivLen  = 12;
    const tagLen = 16;

    if (packet.length < ivLen + tagLen) {
      throw SecurePacketException(
        'Packet too short (${packet.length} bytes); '
        'minimum valid length is ${ivLen + tagLen} bytes.',
      );
    }

    final nonce      = packet.sublist(0, ivLen);
    final cipherText = packet.sublist(ivLen, packet.length - tagLen);
    final macBytes   = packet.sublist(packet.length - tagLen);

    try {
      final box = SecretBox(cipherText, nonce: nonce, mac: Mac(macBytes));
      final plaintext = await _aesGcm.decrypt(box, secretKey: _secretKey!);
      return Uint8List.fromList(plaintext);
    } on SecretBoxAuthenticationError {
      throw const SecurePacketException(
        'AES-GCM authentication tag mismatch — '
        'packet may be tampered or the device key does not match.',
      );
    } catch (e) {
      throw SecurePacketException('Decryption error: $e');
    }
  }

  void _assertInitialized() {
    if (!_initialized || _secretKey == null) {
      throw StateError(
        'CryptoService is not initialized. '
        'Call CryptoService.instance.initialize(keyBytes) at app startup '
        'before any BLE write operations.',
      );
    }
  }

  /// Zeroize the key reference and reset the initialized state.
  void dispose() {
    _secretKey    = null;
    _initialized  = false;
  }
}

/// Thrown when encrypted packet processing fails.
/// Any [SecurePacketException] at the BLE layer must trigger a safe-state event —
/// the system must never execute commands from a packet it cannot authenticate.
class SecurePacketException implements Exception {
  const SecurePacketException(this.message);
  final String message;

  @override
  String toString() => 'SecurePacketException: $message';
}
