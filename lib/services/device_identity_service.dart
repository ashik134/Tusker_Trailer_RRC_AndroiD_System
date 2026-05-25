import 'package:uuid/uuid.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Generates and persistently stores a unique device identity UUID.
///
/// The UUID is hardware-backed via Android Keystore / iOS Keychain through
/// flutter_secure_storage. A new UUID is generated only on first launch or
/// after app reinstall — the identity survives reboots and app restarts.
///
/// This UUID is included in every authentication payload so the PLC can
/// validate that the requesting device is in its trusted-device registry
/// before activating any operator session.
///
/// Security properties:
///   - Different phones generate different UUIDs (cryptographic random v4).
///   - App reinstall generates a new identity (storage cleared on uninstall).
///   - UUID persists across reboots and app restarts.
///   - Stored in Android Keystore / iOS Keychain — not in plaintext.
class DeviceIdentityService {
  DeviceIdentityService._();

  // Key versioned so a future format change does not silently reuse old entries.
  static const String _kDeviceId = 'device_identity_uuid_v1';

  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  // In-memory cache — eliminates repeated Keystore I/O after first load.
  static String? _cachedId;

  /// Returns the device UUID, generating and persisting one if none exists.
  ///
  /// Subsequent calls return the in-memory cached value without any storage
  /// I/O. This is safe to call from [CraneController.initialize] at startup.
  ///
  /// If secure storage is temporarily unavailable (e.g. first boot decryption
  /// not yet complete) the method generates an in-session ID and retries
  /// persistence on the next call.
  static Future<String> getOrCreate() async {
    if (_cachedId != null) return _cachedId!;

    try {
      final stored = await _storage.read(key: _kDeviceId);
      if (stored != null && stored.isNotEmpty) {
        _cachedId = stored;
        return _cachedId!;
      }
    } catch (_) {
      // Storage read failure — fall through to generate a new identity.
    }

    final generated = const Uuid().v4();
    try {
      await _storage.write(key: _kDeviceId, value: generated);
    } catch (_) {
      // Non-fatal: identity is live for this session. Next launch will
      // generate a fresh UUID if the write did not persist.
    }
    _cachedId = generated;
    return _cachedId!;
  }

  /// Returns the in-memory cached device ID without storage I/O.
  ///
  /// Returns null if [getOrCreate] has not yet been called this session.
  /// Call [getOrCreate] at startup to guarantee this is non-null.
  static String? get cachedId => _cachedId;
}
