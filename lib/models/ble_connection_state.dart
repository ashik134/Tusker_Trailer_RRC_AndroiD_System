import 'package:tusker_trailer_rrc/models/ble_scan_device.dart';

// ── Connection

enum BleConnectionStatus {
  disconnected,
  scanning,
  connecting,

  discoveringServices,
  configuringNotifications,
  initializingSafeState,

  connected,
  awaitingAuthentication,
  authenticating,
  authenticated,
  error,
}

/// Outcome of a PLC authentication attempt.
enum BleAuthOutcome { success, failed, timedOut, untrusted }

class BleConnectionState {
  const BleConnectionState({
    required this.status,
    this.message,
    this.connectedDevice,
  });

  final BleConnectionStatus status;

  final String? message;

  final BleScanDevice? connectedDevice;

  factory BleConnectionState.initial() {
    return const BleConnectionState(status: BleConnectionStatus.disconnected);
  }
}
