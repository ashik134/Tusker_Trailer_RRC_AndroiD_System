import 'package:tusker_trailer_rrc/models/ble_scan_device.dart';

// ── Connection lifecycle ──────────────────────────────────────────────────────

/// Represents every state the BLE stack can be in, from idle to authenticated.
enum BleConnectionStatus {
  disconnected,
  scanning,
  connecting,
  connected,
  awaitingAuthentication,
  authenticating,
  authenticated,
  error,
}

/// Outcome of a PLC authentication attempt.
enum BleAuthOutcome { success, failed, timedOut, untrusted }

/// Immutable snapshot of the current BLE connection state.
class BleConnectionState {
  const BleConnectionState({
    required this.status,
    this.message,
    this.connectedDevice,
  });

  final BleConnectionStatus status;

  /// Human-readable status message; present on error states.
  final String? message;

  /// The device currently connected (or in the process of connecting).
  final BleScanDevice? connectedDevice;

  factory BleConnectionState.initial() {
    return const BleConnectionState(status: BleConnectionStatus.disconnected);
  }
}
