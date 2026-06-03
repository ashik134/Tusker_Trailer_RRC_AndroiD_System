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

  test('decrypts ESP32 encrypted auth reply hex packet', () async {
    await BleCrypto.beginSession();

    final wireBytes = await _firmwareEncryptHex('AUTH_OK', replyCounter: 1);
    final plaintext = await BleCrypto.decrypt(wireBytes);

    expect(utf8.decode(plaintext), 'AUTH_OK');
  });

  test('encrypts outbound packets as ASCII hex IV cipher tag', () async {
    await BleCrypto.beginSession();

    final wireBytes = await BleCrypto.encrypt(utf8.encode('HB'));
    final wireText = utf8.decode(wireBytes);
    final raw = _hexDecode(wireText);

    expect(RegExp(r'^[0-9A-F]+$').hasMatch(wireText), isTrue);
    expect(raw.length, 12 + 2 + 16);
    expect(raw.sublist(0, 6), [0, 0, 0, 0, 0, 1]);
    expect(raw.sublist(6, 12), [0, 0, 0, 0, 0, 1]);
  });

  test('rejects replayed ESP32 reply counters', () async {
    await BleCrypto.beginSession();

    final first = await _firmwareEncryptHex('AUTH_OK', replyCounter: 1);
    final replay = await _firmwareEncryptHex('AUTH_OK', replyCounter: 1);

    expect(utf8.decode(await BleCrypto.decrypt(first)), 'AUTH_OK');
    expect(() => BleCrypto.decrypt(replay), throwsA(isA<BleCryptoException>()));
  });
}

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

Uint8List _hexDecode(String hex) {
  final result = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < result.length; i++) {
    result[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return result;
}

String _hexEncode(List<int> bytes) {
  final buffer = StringBuffer();
  for (final byte in bytes) {
    buffer.write(byte.toRadixString(16).padLeft(2, '0').toUpperCase());
  }
  return buffer.toString();
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
