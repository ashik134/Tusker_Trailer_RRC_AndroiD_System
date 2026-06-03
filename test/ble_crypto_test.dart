import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tusker_trailer_rrc/services/ble_crypto.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'ble_crypto_session_counter': 0});
    BleCrypto.endSession();
  });

  // Current PLC firmware sends encrypted notifications as uppercase hex ASCII
  // strings.  decrypt() auto-detects this format and decodes before decrypting.
  test('decrypts PLC hex-encoded encrypted auth reply', () async {
    await BleCrypto.beginSession();

    final wireBytes = await _firmwareEncryptHex('AUTH_OK', replyCounter: 1);
    final plaintext = await BleCrypto.decrypt(wireBytes);

    expect(utf8.decode(plaintext), 'AUTH_OK');
  });

  // Verifies that decrypt() also accepts raw binary when PLC firmware is
  // updated to send binary packets directly.
  test('decrypts PLC raw binary encrypted auth reply', () async {
    await BleCrypto.beginSession();

    final wireBytes = await _firmwareEncryptRaw('AUTH_OK', replyCounter: 1);
    final plaintext = await BleCrypto.decrypt(wireBytes);

    expect(utf8.decode(plaintext), 'AUTH_OK');
  });

  test('encrypts outbound packets as raw binary nonce + ciphertext + tag', () async {
    await BleCrypto.beginSession();

    final wireBytes = await BleCrypto.encrypt(utf8.encode('HB'));

    // 'HB' = 2 plaintext bytes → nonce(12) + ciphertext(2) + tag(16) = 30 bytes
    expect(wireBytes.length, 12 + 2 + 16);
    // Session counter = 1 (first session after reset)
    expect(wireBytes.sublist(0, 6), [0, 0, 0, 0, 0, 1]);
    // Packet counter = 1 (first packet in session)
    expect(wireBytes.sublist(6, 12), [0, 0, 0, 0, 0, 1]);
  });

  test('rejects replayed ESP32 reply counters', () async {
    await BleCrypto.beginSession();

    final first = await _firmwareEncryptRaw('AUTH_OK', replyCounter: 1);
    final replay = await _firmwareEncryptRaw('AUTH_OK', replyCounter: 1);

    expect(utf8.decode(await BleCrypto.decrypt(first)), 'AUTH_OK');
    expect(() => BleCrypto.decrypt(replay), throwsA(isA<BleCryptoException>()));
  });
}

/// Simulates current PLC firmware: encrypts and returns the result as an
/// uppercase hex ASCII string (the format the PLC currently sends over BLE).
Future<List<int>> _firmwareEncryptHex(
  String plaintext, {
  required int replyCounter,
}) async {
  final algorithm = AesGcm.with128bits();
  final nonce = Uint8List(12);
  nonce[6] = (replyCounter >> 40) & 0xFF;
  nonce[7] = (replyCounter >> 32) & 0xFF;
  nonce[8] = (replyCounter >> 24) & 0xFF;
  nonce[9] = (replyCounter >> 16) & 0xFF;
  nonce[10] = (replyCounter >> 8) & 0xFF;
  nonce[11] = replyCounter & 0xFF;

  final secretBox = await algorithm.encrypt(
    utf8.encode(plaintext),
    secretKey: SecretKey(_aesKey),
    nonce: nonce,
  );

  final raw = <int>[...nonce, ...secretBox.cipherText, ...secretBox.mac.bytes];
  return utf8.encode(_hexEncode(raw));
}

String _hexEncode(List<int> bytes) {
  final buffer = StringBuffer();
  for (final byte in bytes) {
    buffer.write(byte.toRadixString(16).padLeft(2, '0').toUpperCase());
  }
  return buffer.toString();
}

/// Simulates future PLC firmware: encrypts and returns raw binary bytes.
Future<List<int>> _firmwareEncryptRaw(
  String plaintext, {
  required int replyCounter,
}) async {
  final algorithm = AesGcm.with128bits();
  final nonce = Uint8List(12);
  nonce[6] = (replyCounter >> 40) & 0xFF;
  nonce[7] = (replyCounter >> 32) & 0xFF;
  nonce[8] = (replyCounter >> 24) & 0xFF;
  nonce[9] = (replyCounter >> 16) & 0xFF;
  nonce[10] = (replyCounter >> 8) & 0xFF;
  nonce[11] = replyCounter & 0xFF;

  final secretBox = await algorithm.encrypt(
    utf8.encode(plaintext),
    secretKey: SecretKey(_aesKey),
    nonce: nonce,
  );

  return [...nonce, ...secretBox.cipherText, ...secretBox.mac.bytes];
}

const _aesKey = <int>[
  0x54,
  0x55,
  0x53,
  0x4B,
  0x45,
  0x52,
  0x5F,
  0x52,
  0x52,
  0x43,
  0x5F,
  0x44,
  0x45,
  0x56,
  0x5F,
  0x31,
];
