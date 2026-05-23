import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Thrown by [BleCrypto.decrypt] on any cryptographic validation failure.
///
/// Callers MUST treat every instance as a security event and enter safe state
/// immediately.  Do NOT resume operation after catching this exception.
class BleCryptoException implements Exception {
  final String reason;
  const BleCryptoException(this.reason);

  @override
  String toString() => 'BleCryptoException: $reason';
}

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

  /// Last accepted inbound packet counter received from the PLC.
  ///
  /// Every new inbound packet must carry a counter strictly greater than this
  /// value.  Reset to zero by [endSession] and [beginSession] so a fresh
  /// authentication always starts from a known baseline.
  static int _inboundCounter = 0;

  /// Session ID prefix observed in the first inbound packet from the PLC.
  ///
  /// The PLC may use an independent nonce counter scheme (e.g. its own
  /// monotonic counter across all 12 nonce bytes) rather than echoing
  /// Flutter's outbound [_sessionId].  We therefore bind to whichever 6-byte
  /// prefix the PLC sends in its FIRST response and enforce that all
  /// subsequent packets carry the same prefix — preventing mid-session nonce
  /// prefix switching attacks while remaining compatible with firmware that
  /// does not echo Flutter's session counter.
  ///
  /// Reset by [endSession] and [beginSession].
  static Uint8List? _plcSessionId;

  /// [true] while a cryptographic session is active (after [beginSession]
  /// and before [endSession]).  Use this to gate decryption calls.
  static bool get sessionActive => _sessionId != null;

  // ── Session lifecycle ────────────────────────────────────────────────────

  /// Call once after the PLC confirms AUTH_OK and before any [encrypt] call.
  ///
  /// Reads the persisted session counter, increments it, writes it back to
  /// [SharedPreferences], then sets the in-memory session ID.  Writing before
  /// assigning [_sessionId] means a crash between the two operations causes
  /// the next startup to use a *higher* counter — IV reuse is still prevented.
  static Future<void> beginSession() async {
    // Reset all counters first so that even if the prefs write is slow,
    // no packets can be encrypted or decrypted until _sessionId is assigned.
    _packetCounter = 0;
    _inboundCounter = 0;
    _plcSessionId = null;
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
    _inboundCounter = 0; // reset replay-protection window
    _plcSessionId = null; // unbind PLC session prefix
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

  // ── Decryption ───────────────────────────────────────────────────────────

  /// Decrypts an AES-128-GCM packet received from the PLC.
  ///
  /// Accepts both:
  /// - Hex-encoded UTF-8 text (mirrors the ESP32 `encodeHexText` output path).
  /// - Raw binary bytes (BLE MTU-efficient binary format).
  ///
  /// ## Packet layout (raw bytes after optional hex decode)
  /// ```
  /// Bytes  0..5   →  PLC nonce prefix  (big-endian 48-bit, PLC-defined)
  /// Bytes  6..11  →  Packet counter    (big-endian 48-bit)
  /// Bytes 12..N-17 → Ciphertext
  /// Bytes N-16..N  → GCM Auth Tag     (16 bytes)
  /// ```
  ///
  /// ## Validation chain (all must pass)
  /// 1. Minimum length ≥ 28 bytes (12-byte nonce + 16-byte tag).
  /// 2. Nonce prefix (bytes 0–5) matches [_plcSessionId] if already bound,
  ///    otherwise binds to it on the first inbound packet.
  /// 3. Packet counter strictly exceeds [_inboundCounter] (replay protection).
  /// 4. AES-GCM authentication tag verifies (tamper / corruption detection).
  ///
  /// ### Session-ID design note
  /// Flutter's outbound [_sessionId] is NOT required to appear in the PLC
  /// response nonce because the PLC firmware may use an independent counter
  /// (e.g. all-12-byte monotonic counter) rather than echoing Flutter's
  /// persisted session counter.  The AES-GCM authentication tag is the
  /// primary cryptographic proof of authenticity; the bind-on-first-packet
  /// scheme provides within-session continuity.  Firmware can be updated to
  /// echo Flutter's session ID for stronger cross-session replay hardening.
  ///
  /// Throws [BleCryptoException] on ANY validation or decryption failure.
  /// The caller MUST call [endSession] and enter safe state immediately.
  ///
  /// Throws [StateError] if called outside an active session.
  static Future<List<int>> decrypt(List<int> wireBytes) async {
    final session = _sessionId;
    if (session == null) {
      throw StateError(
        'BleCrypto.decrypt() called outside an active session. '
        'A session must be established via beginSession() before decrypting.',
      );
    }

    // Decode: accept uppercase/lowercase hex-encoded text or raw binary.
    final Uint8List raw;
    if (_looksLikeHex(wireBytes)) {
      raw = _hexDecode(wireBytes);
    } else {
      raw = Uint8List.fromList(wireBytes);
    }

    // 1. Length check: 12-byte nonce + ≥0-byte ciphertext + 16-byte tag.
    if (raw.length < 28) {
      throw const BleCryptoException(
        'Packet too short — minimum 28 bytes (12-byte nonce + 16-byte GCM tag).',
      );
    }

    final nonce = raw.sublist(0, 12);

    // 2. Bind to or verify the PLC's nonce prefix (nonce bytes 0..5).
    //
    // The PLC may not echo Flutter's outbound session ID, so we bind to
    // whatever 6-byte prefix the PLC uses in its FIRST response this session,
    // then enforce consistency for all subsequent packets.  This prevents a
    // mid-session nonce-prefix switch without requiring firmware changes.
    final currentPlcSession = _plcSessionId;
    if (currentPlcSession == null) {
      // First inbound packet — bind to the PLC's chosen prefix.
      _plcSessionId = Uint8List.fromList(nonce.sublist(0, 6));
    } else {
      for (var i = 0; i < 6; i++) {
        if (nonce[i] != currentPlcSession[i]) {
          throw const BleCryptoException(
            'PLC nonce prefix changed mid-session — possible session hijack '
            'or nonce desynchronisation.',
          );
        }
      }
    }

    // 3. Decode inbound packet counter (nonce bytes 6..11).
    final inboundCount = _decodeUint48(nonce, 6);

    // 4. Replay protection: counter must be strictly increasing.
    if (inboundCount <= _inboundCounter) {
      throw BleCryptoException(
        'Replay detected — inbound counter $inboundCount '
        'is not greater than last accepted $_inboundCounter.',
      );
    }

    // 5. Separate ciphertext and GCM authentication tag.
    final cipherText = raw.sublist(12, raw.length - 16);
    final tagBytes   = raw.sublist(raw.length - 16);
    final mac        = Mac(tagBytes);

    // 6. AES-GCM decrypt — throws SecretBoxAuthenticationError on tag failure.
    final List<int> plaintext;
    try {
      final secretBox = SecretBox(cipherText, nonce: nonce, mac: mac);
      plaintext = await _algorithm.decrypt(secretBox, secretKey: _secretKey);
    } on SecretBoxAuthenticationError {
      throw const BleCryptoException(
        'GCM authentication tag verification failed — '
        'packet is corrupted, tampered, or uses an incorrect key.',
      );
    } catch (e) {
      throw BleCryptoException('AES-GCM decryption error: $e');
    }

    // Advance inbound counter ONLY after successful full validation.
    _inboundCounter = inboundCount;

    return plaintext;
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

  /// Returns [true] if [bytes] looks like ASCII hex (0-9, A-F, a-f) with even
  /// length.  Used to auto-detect the ESP32 hex-encoded output format.
  static bool _looksLikeHex(List<int> bytes) {
    if (bytes.isEmpty || bytes.length.isOdd) return false;
    return bytes.every((b) =>
      (b >= 0x30 && b <= 0x39) || // 0-9
      (b >= 0x41 && b <= 0x46) || // A-F
      (b >= 0x61 && b <= 0x66),   // a-f
    );
  }

  /// Hex-decodes ASCII hex bytes (e.g. `[0x36, 0x35]` → `[0x65]`).
  static Uint8List _hexDecode(List<int> hexBytes) {
    final text   = String.fromCharCodes(hexBytes);
    final result = Uint8List(text.length ~/ 2);
    for (var i = 0; i < result.length; i++) {
      result[i] = int.parse(text.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return result;
  }

  /// Decodes a big-endian 48-bit unsigned integer from [bytes] at [offset].
  ///
  /// Uses multiplication rather than bit-shifts to avoid 32-bit truncation on
  /// platforms where `<<` silently wraps at 32 bits.
  static int _decodeUint48(Uint8List bytes, int offset) {
    return (bytes[offset]     & 0xFF) * 0x10000000000 +
           (bytes[offset + 1] & 0xFF) * 0x100000000 +
           (bytes[offset + 2] & 0xFF) * 0x1000000 +
           (bytes[offset + 3] & 0xFF) * 0x10000 +
           (bytes[offset + 4] & 0xFF) * 0x100 +
           (bytes[offset + 5] & 0xFF);
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
