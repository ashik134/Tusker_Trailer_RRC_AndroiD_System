class SafetyConstants {
  SafetyConstants._();

  /// Maximum BLE scan burst duration
  static const Duration scanTimeout = Duration(seconds: 8);

  /// Maximum wait for PLC to reply after an encrypted auth write.
  static const Duration authReplyTimeout = Duration(seconds: 6);

  /// Duration of a single E-stop output pulse
  static const Duration estopPulse = Duration(milliseconds: 300);

  /// Encrypted heartbeat write period.
  static const Duration heartbeatInterval = Duration(milliseconds: 50);
}
