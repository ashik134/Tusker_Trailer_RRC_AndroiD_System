class BLEConstants {
  BLEConstants._();

  // GATT Service
  static const String serviceUuid = '6e400001-b5a3-f393-e0a9-e50e24dcca9e';

  // AES-128-GCM encrypted control bytes.
  static const String digitalCharUuid = '6e400003-b5a3-f393-e0a9-e50e24dcca9e';

  static const String authCharUuid = '6e400004-b5a3-f393-e0a9-e50e24dcca9e';

  ///  plain-text CSV status
  static const String statusCharUuid = '6e400005-b5a3-f393-e0a9-e50e24dcca9e';

  static const String heartbeatCharUuid =
      '6e400006-b5a3-f393-e0a9-e50e24dcca9e';

  static const String deviceName = 'RRC_PLC';

  static const String scanNamePrefix = 'RRC_';

  //  Auth protocol strings
  static const String authRequest = 'AUTH_REQ:email|password|device_id';
  static const String authSuccess = 'AUTH_OK';
  static const String authFailed = 'AUTH_FAIL';
  static const String authTimeout = 'AUTH_TIMEOUT';

  static const String authUntrusted = 'AUTH_UNTRUSTED';

  static const String heartbeatPayload = 'HB';
}
