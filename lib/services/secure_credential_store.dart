import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Hardware-backed secure storage for biometric-protected operator credentials.
///
/// Operator credentials are encrypted in the Android Keystore via
/// EncryptedSharedPreferences, or in the iOS Keychain. This class does NOT
/// enforce the biometric gate — that responsibility belongs to
/// [BiometricService.authenticate]. [retrieveCredentials] MUST only be called
/// after a successful biometric verification.
///
/// Stored data is scoped to this app package, encrypted at rest, and
/// automatically cleared on uninstall or device factory reset.
class SecureCredentialStore {
  SecureCredentialStore._();

  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  // Keys are versioned so a future schema change does not silently reuse
  // old encrypted entries from a different format.
  static const String _kEmail = 'bio_op_email_v1';
  static const String _kPassword = 'bio_op_password_v1';
  static const String _kEnrolled = 'bio_enrolled_v1';

  // ── Enrollment state ──────────────────────────────────────────────────────

  /// Returns true when valid biometric credentials are stored on this device.
  ///
  /// Performs a lightweight read without decrypting payload content — safe
  /// to call frequently without performance impact.
  static Future<bool> hasCredentials() async {
    try {
      final enrolled = await _storage.read(key: _kEnrolled);
      if (enrolled != 'true') return false;

      final email = await _storage.read(key: _kEmail);
      final password = await _storage.read(key: _kPassword);

      return email != null &&
          email.isNotEmpty &&
          password != null &&
          password.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  // ── Write ─────────────────────────────────────────────────────────────────

  /// Persists operator credentials for future biometric re-authentication.
  ///
  /// MUST only be called after a PLC-validated manual login so that only
  /// credentials already verified by the PLC are enrolled for biometric reuse.
  ///
  /// Throws on Keystore / storage failure — callers should handle gracefully.
  static Future<void> storeCredentials({
    required String email,
    required String password,
  }) async {
    await _storage.write(key: _kEmail, value: email);
    await _storage.write(key: _kPassword, value: password);
    await _storage.write(key: _kEnrolled, value: 'true');
  }

  // ── Read ──────────────────────────────────────────────────────────────────

  /// Retrieves stored operator credentials.
  ///
  /// Returns null if credentials are absent or the store is unreadable.
  ///
  /// MUST only be called AFTER [BiometricService.authenticate] has returned
  /// [BiometricAuthStatus.success]. The biometric gate is the caller's
  /// responsibility — this method does not re-verify identity.
  static Future<({String email, String password})?> retrieveCredentials() async {
    try {
      final email = await _storage.read(key: _kEmail);
      final password = await _storage.read(key: _kPassword);

      if (email == null ||
          email.isEmpty ||
          password == null ||
          password.isEmpty) {
        return null;
      }

      return (email: email, password: password);
    } catch (_) {
      return null;
    }
  }

  // ── Revocation ────────────────────────────────────────────────────────────

  /// Clears all stored biometric credentials.
  ///
  /// Call when the PLC rejects stored credentials (stale or changed password),
  /// or when the operator explicitly revokes biometric access. Stale entries
  /// are non-fatal — the next successful manual login will overwrite them.
  static Future<void> clearCredentials() async {
    try {
      await Future.wait([
        _storage.delete(key: _kEmail),
        _storage.delete(key: _kPassword),
        _storage.delete(key: _kEnrolled),
      ]);
    } catch (_) {
      // Non-fatal: next successful login will overwrite any stale data.
    }
  }
}
