// ── App navigation ────────────────────────────────────────────────────────────

/// Top-level screen destinations driven by [CraneController.currentScreen].
enum AppScreen { connection, authentication, control }

// ── Motion state ──────────────────────────────────────────────────────────────

/// Derived hoist state — computed from the active [PlcOutputCommand].
enum HoistState { idle, upSlow, upFast, downSlow, downFast }

/// Motion axes used for mutual-exclusion directional-hold resolution.
enum MotionAxis { vertical, horizontal }

/// Three-stage control input level used by slider and legacy tap-button widgets.
enum ControlState { idle, slow, fast }

// ── PLC hardware model ────────────────────────────────────────────────────────

/// PLC controller model/type detected from BLE advertisement manufacturer data.
enum PlcType {
  plc14('PLC14'),
  plc21('PLC21'),
  plc38('PLC38'),
  unknown('Unknown PLC');

  const PlcType(this.displayName);

  /// Human-readable label (e.g. 'PLC14', 'Unknown PLC').
  final String displayName;

  /// Parses the raw manufacturer-data string recovered from BLE advertisement.
  /// Returns [PlcType.unknown] for any unrecognised or null value.
  static PlcType fromString(String? value) {
    switch (value) {
      case 'PLC14':
        return PlcType.plc14;
      case 'PLC21':
        return PlcType.plc21;
      case 'PLC38':
        return PlcType.plc38;
      default:
        return PlcType.unknown;
    }
  }
}

// ── Permissions ───────────────────────────────────────────────────────────────

/// Result of a Bluetooth/location permission request.
class PermissionState {
  const PermissionState({
    required this.isGranted,
    required this.isPermanentlyDenied,
  });

  const PermissionState.initial()
    : isGranted = false,
      isPermanentlyDenied = false;

  /// True when all permissions required for BLE scanning are granted.
  final bool isGranted;

  /// True when the user has permanently denied at least one required permission.
  final bool isPermanentlyDenied;
}
