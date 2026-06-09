import 'package:flutter_blue_plus/flutter_blue_plus.dart';

// based on advertisement silence time.
enum DeviceStaleStatus { active, stale, expired }

class BleScanDevice {
  BleScanDevice({
    required this.id,
    required this.name,
    required this.rssi,
    required this.device,
    DateTime? lastSeenAt,
    this.frozenStatus,
  }) : lastSeenAt = lastSeenAt ?? DateTime.now();

  final String id;
  final String name;
  final int rssi;
  final BluetoothDevice device;

  final DateTime lastSeenAt;

  /// When non-null, [staleStatus] returns this fixed value instead of
  /// computing from [lastSeenAt]. Set by [BleService._freezeCache] when the
  /// BLE radio goes idle so device cards never degrade while scan is stopped.
  final DeviceStaleStatus? frozenStatus;

  /// stale detection — thresholds apply ONLY while scanning is active.
  /// Devices frozen by [BleService._freezeCache] bypass these entirely.
  static const Duration staleThreshold = Duration(seconds: 13);
  static const Duration expireThreshold = Duration(seconds: 20);

  Duration get silenceDuration => DateTime.now().difference(lastSeenAt);

  /// Returns [frozenStatus] when set (scan is stopped — no live advertisement
  /// data). Falls back to time-based computation only while scanning is active.
  DeviceStaleStatus get staleStatus {
    if (frozenStatus != null) return frozenStatus!;
    final age = silenceDuration;
    if (age < staleThreshold) return DeviceStaleStatus.active;
    if (age < expireThreshold) return DeviceStaleStatus.stale;
    return DeviceStaleStatus.expired;
  }

  bool get isStale => staleStatus != DeviceStaleStatus.active;

  // ── Factory / copy ────────────────────────────────────────────────────────

  factory BleScanDevice.fromScanResult(ScanResult result) {
    final advertisedName = result.advertisementData.advName.trim();
    final platformName = result.device.platformName.trim();

    return BleScanDevice(
      id: result.device.remoteId.toString(),
      name: advertisedName.isNotEmpty
          ? advertisedName
          : (platformName.isNotEmpty ? platformName : 'Unnamed PLC'),
      rssi: result.rssi,
      device: result.device,
      lastSeenAt: DateTime.now(),
    );
  }

  /// Returns a copy with optionally updated fields.
  /// Pass [clearFrozen] = true to re-enable live stale computation
  /// (used when a scan session resumes after being paused).
  BleScanDevice copyWith({
    int? rssi,
    DateTime? lastSeenAt,
    DeviceStaleStatus? frozenStatus,
    bool clearFrozen = false,
  }) {
    return BleScanDevice(
      id: id,
      name: name,
      rssi: rssi ?? this.rssi,
      device: device,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      frozenStatus: clearFrozen ? null : (frozenStatus ?? this.frozenStatus),
    );
  }

  String get signalLabel {
    if (rssi >= -55) return 'Excellent';
    if (rssi >= -68) return 'Strong';
    if (rssi >= -80) return 'Fair';
    return 'Weak';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is BleScanDevice && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
