/// Timing and safety threshold constants for the BLE communication stack.
class SafetyConstants {
  SafetyConstants._();

  /// Maximum BLE scan burst duration before a rest interval.
  static const Duration scanTimeout = Duration(seconds: 8);

  /// Maximum wait for PLC to reply after an encrypted auth write.
  static const Duration authReplyTimeout = Duration(seconds: 6);

  /// Duration of a single E-stop output pulse (unused in current flow,
  /// retained for forward-compatibility with pulse-mode firmware).
  static const Duration estopPulse = Duration(milliseconds: 300);

  /// Encrypted heartbeat write period. The PLC expects a packet at least
  /// this often; missing heartbeats trigger a firmware watchdog E-stop.
  static const Duration heartbeatInterval = Duration(milliseconds: 50);
}
