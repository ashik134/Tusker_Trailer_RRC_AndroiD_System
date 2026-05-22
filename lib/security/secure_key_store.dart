import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Secure AES-128 key provisioning and storage for the Tusker Trailer RRC.
///
/// ─────────────────────────────────────────────────────────────────────────────
/// PRODUCTION DEPLOYMENT GUIDE
/// ─────────────────────────────────────────────────────────────────────────────
///
/// STEP 1 — GENERATE A UNIQUE DEPLOYMENT KEY (once per installation / site)
///
///   Generate a cryptographically random 128-bit key:
///     $ openssl rand -hex 16
///
///   Example output:
///     a3f1bc2d4e5f67890a1b2c3d4e5f6789
///
///   Each field unit MUST have its own unique key.  Never reuse keys
///   across installations — a compromised key on one unit cannot affect others.
///
/// STEP 2 — PROVISION THE ESP32 FIRMWARE
///
///   In the ESP32 firmware project, update `crypto_config.h`:
///
///     // AES-128 symmetric key — must match the provisioned Android key
///     static const uint8_t AES_KEY[16] = {
///       0xa3, 0xf1, 0xbc, 0x2d, 0x4e, 0x5f, 0x67, 0x89,
///       0x0a, 0x1b, 0x2c, 0x3d, 0x4e, 0x5f, 0x67, 0x89
///     };
///
///   Flash the firmware.  For additional firmware key protection, enable
///   ESP32 Flash Encryption (AES-256 hardware key in eFuse, one-time burn).
///
/// STEP 3 — COMMISSION THE ANDROID APP  (authorized technician, first deploy)
///
///   Call [SecureKeyStore.instance.provisionKey(keyBytes)] with the same 16
///   bytes.  The key is stored in Android Keystore via EncryptedSharedPreferences
///   (hardware-backed TEE on devices with a secure element, API 23+).
///
///   Example provisioning call (admin / commissioning screen):
///
///     final hexKey  = '...';  // 32 hex chars = 16 bytes
///     final keyBytes = List.generate(16, (i) =>
///       int.parse(hexKey.substring(i * 2, i * 2 + 2), radix: 16));
///     await SecureKeyStore.instance.provisionKey(keyBytes);
///
/// STEP 4 — KEY ROTATION
///
///   1. Generate a new key (Step 1).
///   2. Call [SecureKeyStore.instance.clearKey()].
///   3. Re-provision via [provisionKey] (Step 3).
///   4. Re-flash ESP32 firmware with the new key (Step 2).
///   All old sessions are automatically invalidated.
///
/// ANDROID KEYSTORE SECURITY NOTES
/// ─────────────────────────────────────────────────────────────────────────────
///   • flutter_secure_storage on Android uses AES-256 EncryptedSharedPreferences
///     (Jetpack Security library, API 23+).
///   • On devices with a Trusted Execution Environment (TEE) or StrongBox
///     (e.g., Qualcomm, MediaTek secure elements), the wrapping key lives in
///     hardware and cannot be extracted by software.
///   • The AES key is NEVER logged, printed, or transmitted in plain form.
/// ─────────────────────────────────────────────────────────────────────────────
class SecureKeyStore {
  SecureKeyStore._();
  static final SecureKeyStore instance = SecureKeyStore._();

  static const String _keyAlias = 'tusker_rrc_aes_key_v1';

  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  // ── DEVELOPMENT / FACTORY-DEFAULT KEY ─────────────────────────────────────
  //
  // ⚠  WARNING: This key is FOR DEVELOPMENT AND BENCH TESTING ONLY.
  //             It MUST match the key compiled into the development firmware.
  //             NEVER use this key in any deployed production unit.
  //
  //             ASCII: "TUSKER_RRC_DEV_1"  (16 bytes)
  //
  static const List<int> _devKey = [
    0x54, 0x55, 0x53, 0x4B, 0x45, 0x52, 0x5F, 0x52, //  T  U  S  K  E  R  _  R
    0x52, 0x43, 0x5F, 0x44, 0x45, 0x56, 0x5F, 0x31, //  R  C  _  D  E  V  _  1
  ];

  bool _provisioned = false;

  /// True if a deployment key has been provisioned in secure storage.
  bool get isProvisioned => _provisioned;

  /// Load the AES-128 key from Android Keystore / iOS Keychain.
  ///
  /// - **Release build**: throws [StateError] if no provisioned key exists.
  ///   The RRC application MUST NOT operate without a valid deployment key.
  /// - **Debug build**: falls back to [_devKey] with a console warning.
  Future<List<int>> loadKey() async {
    try {
      final encoded = await _storage.read(key: _keyAlias);
      if (encoded != null && encoded.isNotEmpty) {
        final bytes = base64Decode(encoded);
        if (bytes.length == 16) {
          _provisioned = true;
          return bytes;
        }
        // Stored data is corrupt — remove and require re-provisioning.
        await _storage.delete(key: _keyAlias);
        debugPrint(
          '[SecureKeyStore] ⚠  Corrupt key entry removed. '
          'Re-commissioning by an authorized technician is required.',
        );
      }
    } catch (e) {
      debugPrint('[SecureKeyStore] Failed to read from secure storage: $e');
    }

    if (!kDebugMode) {
      throw StateError(
        'No AES deployment key is provisioned on this device. '
        'An authorized technician must commission this unit before '
        'the RRC application can be used in production.',
      );
    }

    debugPrint(
      '[SecureKeyStore] ⚠  DEVELOPMENT KEY IS ACTIVE. '
      'This MUST be replaced with a unique deployment-specific key '
      'before any unit is shipped or put into production service.',
    );
    return _devKey;
  }

  /// Store [keyBytes] (exactly 16 bytes) in Android Keystore / iOS Keychain.
  ///
  /// Call once during initial device commissioning by an authorized technician.
  /// Replaces any previously stored key.
  Future<void> provisionKey(List<int> keyBytes) async {
    if (keyBytes.length != 16) {
      throw ArgumentError(
        'AES-128 key must be exactly 16 bytes; received ${keyBytes.length}.',
      );
    }
    await _storage.write(key: _keyAlias, value: base64Encode(keyBytes));
    _provisioned = true;
  }

  /// Delete the stored key.
  ///
  /// Use only for key rotation or unit decommissioning.
  Future<void> clearKey() async {
    await _storage.delete(key: _keyAlias);
    _provisioned = false;
  }

  /// Returns true if a valid 16-byte provisioned key exists in secure storage.
  Future<bool> hasProvisionedKey() async {
    try {
      final encoded = await _storage.read(key: _keyAlias);
      if (encoded == null || encoded.isEmpty) return false;
      final bytes = base64Decode(encoded);
      return bytes.length == 16;
    } catch (_) {
      return false;
    }
  }
}
