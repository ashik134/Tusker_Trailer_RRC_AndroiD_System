enum AppScreen { connection, authentication, control }

enum HoistState { idle, upSlow, upFast, downSlow, downFast }

enum MotionAxis { vertical, horizontal }

enum ControlState { idle, slow, fast }

// PLC hardware model

enum PlcType {
  plc14('PLC14'),
  plc21('PLC21'),
  plc38('PLC38'),
  unknown('Unknown PLC');

  const PlcType(this.displayName);

  final String displayName;

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

class PermissionState {
  const PermissionState({
    required this.isGranted,
    required this.isPermanentlyDenied,
  });

  const PermissionState.initial()
    : isGranted = false,
      isPermanentlyDenied = false;

  final bool isGranted;

  final bool isPermanentlyDenied;
}
