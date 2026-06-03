/// BLE service UUIDs, characteristic UUIDs, and protocol string constants.
///
/// All UUIDs match the ESP32 NimBLE service declaration.
/// Protocol strings are case-sensitive and must match firmware exactly.
class BLEConstants {
  BLEConstants._();

  // ── GATT Service ─────────────────────────────────────────────────────────
  static const String serviceUuid = '6e400001-b5a3-f393-e0a9-e50e24dcca9e';

  // ── Characteristics ───────────────────────────────────────────────────────
  /// Flutter → PLC: AES-128-GCM encrypted control bytes.
  static const String digitalCharUuid = '6e400003-b5a3-f393-e0a9-e50e24dcca9e';

  /// Flutter → PLC: AES-128-GCM encrypted auth payload.
  /// PLC → Flutter: plain-text or AES-128-GCM hex-encoded response.
  static const String authCharUuid = '6e400004-b5a3-f393-e0a9-e50e24dcca9e';

  /// PLC → Flutter: plain-text CSV status (notify, read-only).
  static const String statusCharUuid = '6e400005-b5a3-f393-e0a9-e50e24dcca9e';

  /// Flutter → PLC: AES-128-GCM encrypted heartbeat ('HB').
  static const String heartbeatCharUuid =
      '6e400006-b5a3-f393-e0a9-e50e24dcca9e';

  // ── Device naming ─────────────────────────────────────────────────────────
  static const String deviceName = 'RRC_PLC';

  /// Only devices whose advertised name starts with this prefix are shown.
  static const String scanNamePrefix = 'RRC_';

  // ── Auth protocol strings ─────────────────────────────────────────────────
  static const String authRequest = 'AUTH_REQ:email|password|device_id';
  static const String authSuccess = 'AUTH_OK';
  static const String authFailed = 'AUTH_FAIL';
  static const String authTimeout = 'AUTH_TIMEOUT';

  /// Sent when the device UUID is not in the PLC trusted-device registry.
  static const String authUntrusted = 'AUTH_UNTRUSTED';

  // ── Heartbeat ─────────────────────────────────────────────────────────────
  static const String heartbeatPayload = 'HB';
}
