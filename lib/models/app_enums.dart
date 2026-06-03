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
