import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// AES-128-GCM encryption helper for PLC digital-characteristic writes.
///
/// ## IV format — deterministic, industrial-safe, 12 bytes total
///
/// ```
/// Bytes  0..5  →  Session ID     (48-bit big-endian monotonic counter)
/// Bytes  6..11 →  Packet counter (48-bit big-endian, reset each session)
/// ```
///
/// ### Session ID
/// A persisted integer in [SharedPreferences] is incremented once per
/// authenticated session and stored back **before** the first packet is
/// encrypted.  This guarantees uniqueness even after app crashes, forced
/// restarts, BLE reconnects, and controller/PLC reboots: every new call to
/// [beginSession] produces a strictly higher session number than any previous
/// session on the same device.
///
/// ### Packet counter
/// Reset to zero by [beginSession] and incremented **synchronously** inside
/// [_buildNonce] — before the `await` in [encrypt] — so concurrent async
/// callers (e.g. heartbeat overlapping a control write) each receive a
/// distinct nonce without any locking primitive.
///
/// ### Overflow
/// 48-bit counter → 2^48 ≈ 281 trillion unique values per axis.
/// At a 10 Hz heartbeat a single session would exhaust the packet counter
/// in ≈ 890 000 years.  The session counter has the same capacity.
///
/// ### AES-GCM nonce-reuse guarantee
/// IV reuse requires **both** the session ID **and** the packet counter to
/// collide simultaneously.  The persisted session counter makes session-ID
/// reuse impossible within the device lifetime; the monotonic packet counter
/// makes same-session reuse impossible.
class BleCrypto {
  BleCrypto._();

  // "TUSKER_RRC_DEV_1"
  static const List<int> _keyBytes = [
    0x54, 0x55, 0x53, 0x4B,
    0x45, 0x52, 0x5F, 0x52,
    0x52, 0x43, 0x5F, 0x44,
    0x45, 0x56, 0x5F, 0x31,
  ];

  static const String _kSessionCounter = 'ble_crypto_session_counter';

  // AesGcm.with128bits() — 128-bit key, 12-byte nonce, 16-byte GCM tag.
  static final _algorithm = AesGcm.with128bits();

  // SecretKey wraps the raw bytes; safe to cache as a static.
  static final _secretKey = SecretKey(_keyBytes);

  // ── Session state ────────────────────────────────────────────────────────

  /// Current 6-byte session ID.  Null until [beginSession] has been called.
  static Uint8List? _sessionId;

  /// Monotonically increasing packet counter for the current session.
  /// Incremented synchronously in [_buildNonce]; never reset mid-session.
  static int _packetCounter = 0;

  // ── Session lifecycle ────────────────────────────────────────────────────

  /// Call once after the PLC confirms AUTH_OK and before any [encrypt] call.
  ///
  /// Reads the persisted session counter, increments it, writes it back to
  /// [SharedPreferences], then sets the in-memory session ID.  Writing before
  /// assigning [_sessionId] means a crash between the two operations causes
  /// the next startup to use a *higher* counter — IV reuse is still prevented.
  static Future<void> beginSession() async {
    // Reset packet counter first so that even if the prefs write is slow,
    // no packets can be encrypted until _sessionId is assigned below.
    _packetCounter = 0;
    _sessionId = null;

    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getInt(_kSessionCounter) ?? 0;
    final next = stored + 1;

    // Persist before activating — crash-safe monotonic watermark.
    await prefs.setInt(_kSessionCounter, next);

    _sessionId = _encodeUint48(next);
  }

  /// Call on BLE disconnect, app logout, PLC/controller reset, or auth reset.
  ///
  /// Clears in-memory session state.  The persisted counter is intentionally
  /// left untouched — it acts as a high-water mark so the next [beginSession]
  /// always increments beyond the current value.
  static void endSession() {
    _sessionId = null;
    _packetCounter = 0;
  }

  // ── Encryption ───────────────────────────────────────────────────────────

  /// Returns UTF-8 encoded uppercase hex of:
  ///   IV (12 bytes) || CIPHERTEXT || GCM TAG (16 bytes)
  ///
  /// Example: 10-byte plaintext → 38 raw bytes → 76-char hex string
  ///   → 76 UTF-8 bytes on the wire.
  ///
  /// Throws [StateError] if called before [beginSession].
  static Future<List<int>> encrypt(List<int> plaintext) async {
    // _buildNonce() is synchronous: the packet counter is incremented before
    // the first await, so concurrent callers always get distinct nonces.
    final nonce = _buildNonce();

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
    for (final b in nonce) {
      raw[offset++] = b;
    }
    for (final b in secretBox.cipherText) {
      raw[offset++] = b;
    }
    for (final b in secretBox.mac.bytes) {
      raw[offset++] = b;
    }

    // Hex-encode to uppercase 2-char-per-byte text so the firmware reliably
    // picks the decodeHexText branch in decryptAESGCM_hex_or_raw.
    final sb = StringBuffer();
    for (final b in raw) {
      sb.write(b.toRadixString(16).padLeft(2, '0').toUpperCase());
    }
    return utf8.encode(sb.toString());
  }

  // ── Internal helpers ─────────────────────────────────────────────────────

  /// Builds the deterministic 12-byte nonce for the next packet.
  ///
  /// Layout:
  ///   [0..5]  → session ID     (big-endian 48-bit persisted counter)
  ///   [6..11] → packet counter (big-endian 48-bit, reset each session)
  ///
  /// MUST remain synchronous so the counter is incremented atomically
  /// (within Dart's cooperative scheduler) before any `await` in [encrypt].
  static Uint8List _buildNonce() {
    final session = _sessionId;
    if (session == null) {
      throw StateError(
        'BleCrypto.encrypt() called outside an active session. '
        'Call BleCrypto.beginSession() after receiving AUTH_OK.',
      );
    }

    // Synchronous pre-await increment — race-safe under Dart's single-isolate
    // cooperative scheduler.
    _packetCounter += 1;
    final counter = _packetCounter;

    final nonce = Uint8List(12);

    // Bytes 0..5 — session ID (big-endian 48-bit)
    nonce[0] = session[0];
    nonce[1] = session[1];
    nonce[2] = session[2];
    nonce[3] = session[3];
    nonce[4] = session[4];
    nonce[5] = session[5];

    // Bytes 6..11 — packet counter (big-endian 48-bit)
    nonce[6]  = (counter >> 40) & 0xFF;
    nonce[7]  = (counter >> 32) & 0xFF;
    nonce[8]  = (counter >> 24) & 0xFF;
    nonce[9]  = (counter >> 16) & 0xFF;
    nonce[10] = (counter >> 8)  & 0xFF;
    nonce[11] =  counter        & 0xFF;

    return nonce;
  }

  /// Encodes [value] as a 6-byte (48-bit) big-endian [Uint8List].
  static Uint8List _encodeUint48(int value) {
    assert(value >= 0, 'Session counter must be non-negative');
    final bytes = Uint8List(6);
    bytes[0] = (value >> 40) & 0xFF;
    bytes[1] = (value >> 32) & 0xFF;
    bytes[2] = (value >> 24) & 0xFF;
    bytes[3] = (value >> 16) & 0xFF;
    bytes[4] = (value >> 8)  & 0xFF;
    bytes[5] =  value        & 0xFF;
    return bytes;
  }
}
