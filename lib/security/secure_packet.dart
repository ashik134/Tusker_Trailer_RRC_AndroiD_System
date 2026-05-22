import 'dart:typed_data';

import 'package:tusker_trailer_rrc/models/plc_output_command.dart';
import 'package:tusker_trailer_rrc/security/crypto_service.dart';
import 'package:tusker_trailer_rrc/security/session_manager.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PACKET TYPE IDENTIFIERS
// ─────────────────────────────────────────────────────────────────────────────
/// First byte of every plaintext payload identifies the packet type.
abstract final class SecurePacketType {
  static const int control   = 0x01;
  static const int heartbeat = 0x02;
  static const int auth      = 0x03;
}

// ─────────────────────────────────────────────────────────────────────────────
// PLAINTEXT HEADER LAYOUT  (17 bytes, common to ALL packet types)
// ─────────────────────────────────────────────────────────────────────────────
//   Offset  0    : packet_type    uint8
//   Offsets 1–8  : timestamp_ms  uint64 big-endian  (UTC epoch milliseconds)
//   Offsets 9–12 : seq_counter   uint32 big-endian  (monotonically increasing)
//   Offsets 13–16: session_id    uint32 big-endian  (random per session)
//   Offset 17+   : type-specific payload (see below)
//
// CONTROL PAYLOAD  (1 byte at offset 17)
// ─────────────────────────────────────────────────────────────────────────────
//   bit 7 : estop
//   bit 6 : up
//   bit 5 : down
//   bit 4 : left
//   bit 3 : right
//   bit 2 : fast
//   bits 0–1 : reserved (always 0)
//
// ENCRYPTED WIRE FORMAT  (what is written to the BLE characteristic)
// ─────────────────────────────────────────────────────────────────────────────
//   [12 bytes]  AES-GCM IV / Nonce  (fresh CSPRNG bytes per packet)
//   [N  bytes]  GCM ciphertext
//   [16 bytes]  GCM authentication tag
//
// Encrypted sizes:
//   Control   packet : 12 + 18 + 16 = 46 bytes
//   Heartbeat packet : 12 + 17 + 16 = 45 bytes
//   Auth      packet : 12 + 17 + len("email|password") + 16 bytes
// ─────────────────────────────────────────────────────────────────────────────

/// Builds and encrypts outbound BLE packets for the Tusker Trailer RRC protocol.
class SecurePacketEncoder {
  SecurePacketEncoder._();
  static final SecurePacketEncoder instance = SecurePacketEncoder._();

  final CryptoService  _crypto  = CryptoService.instance;
  final SessionManager _session = SessionManager.instance;

  // ── Public encoders ────────────────────────────────────────────────────────

  /// Encode and encrypt a motion / E-stop control command.
  Future<Uint8List> encodeControl(PlcOutputCommand cmd) async {
    final int flags =
        (cmd.estop                    ? 0x80 : 0) |
        (cmd.up                       ? 0x40 : 0) |
        (cmd.down                     ? 0x20 : 0) |
        (cmd.left                     ? 0x10 : 0) |
        (cmd.right                    ? 0x08 : 0) |
        (cmd.speed == HoistSpeed.fast ? 0x04 : 0);

    final plaintext = Uint8List(18);
    _writeHeader(plaintext, SecurePacketType.control);
    plaintext[17] = flags;
    return _crypto.encryptPacket(plaintext);
  }

  /// Encode and encrypt a heartbeat packet.
  Future<Uint8List> encodeHeartbeat() async {
    final plaintext = Uint8List(17);
    _writeHeader(plaintext, SecurePacketType.heartbeat);
    return _crypto.encryptPacket(plaintext);
  }

  /// Encode and encrypt an authentication request.
  ///
  /// The session ID is embedded in the header so the PLC can bind it to all
  /// subsequent packets from this operator session.
  Future<Uint8List> encodeAuth({
    required String email,
    required String password,
  }) async {
    final credBytes = Uint8List.fromList('$email|$password'.codeUnits);
    final plaintext = Uint8List(17 + credBytes.length);
    _writeHeader(plaintext, SecurePacketType.auth);
    plaintext.setAll(17, credBytes);
    return _crypto.encryptPacket(plaintext);
  }

  // ── Header builder ─────────────────────────────────────────────────────────

  /// Write the 17-byte common packet header into [buf] starting at offset 0.
  void _writeHeader(Uint8List buf, int packetType) {
    final bd  = ByteData.sublistView(buf);
    final ts  = _session.nowMs();
    final seq = _session.nextOutboundSeq();
    final sid = _session.sessionId;

    bd.setUint8(0, packetType);

    // Timestamp: split 64-bit int into two 32-bit big-endian words.
    bd.setUint32(1, (ts >>> 32) & 0xFFFFFFFF, Endian.big); // high word
    bd.setUint32(5,  ts          & 0xFFFFFFFF, Endian.big); // low  word

    bd.setUint32(9,  seq, Endian.big);
    bd.setUint32(13, sid, Endian.big);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// INBOUND PACKET DECODER
// ─────────────────────────────────────────────────────────────────────────────

/// Decodes and validates an incoming encrypted packet from the PLC.
///
/// Used for processing encrypted status notifications and auth responses once
/// the ESP32 firmware is updated to encrypt outbound packets.
///
/// Any failure (decryption error, authentication tag mismatch, replay detection)
/// MUST be treated as a safe-state event by the caller — never act on a packet
/// that cannot be fully authenticated.
class SecurePacketDecoder {
  SecurePacketDecoder._();
  static final SecurePacketDecoder instance = SecurePacketDecoder._();

  final CryptoService  _crypto  = CryptoService.instance;
  final SessionManager _session = SessionManager.instance;

  /// Decrypt, authenticate, and replay-validate [rawPacket].
  ///
  /// Returns [DecodedPacket] on success.
  /// Throws [SecurePacketException] on any failure.
  Future<DecodedPacket> decode(Uint8List rawPacket) async {
    // Step 1: AES-GCM decrypt + authenticate.
    final plaintext = await _crypto.decryptPacket(rawPacket);

    if (plaintext.length < 17) {
      throw SecurePacketException(
        'Decrypted payload too short '
        '(${plaintext.length} bytes, minimum 17).',
      );
    }

    // Step 2: Parse header.
    final bd         = ByteData.sublistView(plaintext);
    final packetType = bd.getUint8(0);
    final tsHigh     = bd.getUint32(1, Endian.big);
    final tsLow      = bd.getUint32(5, Endian.big);
    final timestampMs = (tsHigh * 0x100000000) + tsLow;
    final seq        = bd.getUint32(9,  Endian.big);
    final sid        = bd.getUint32(13, Endian.big);

    // Step 3: Replay / session validation.
    final result = _session.validateInbound(
      timestampMs:     timestampMs,
      seqCounter:      seq,
      packetSessionId: sid,
    );

    if (result != ReplayValidationResult.valid) {
      throw SecurePacketException(
        'Replay / session validation failed: $result',
      );
    }

    return DecodedPacket(
      type:    packetType,
      payload: plaintext.sublist(17),
    );
  }
}

/// Represents the decrypted and validated payload of an inbound packet.
class DecodedPacket {
  const DecodedPacket({required this.type, required this.payload});

  /// Packet type — see [SecurePacketType] constants.
  final int type;

  /// Type-specific payload bytes (everything after the 17-byte common header).
  final Uint8List payload;
}
