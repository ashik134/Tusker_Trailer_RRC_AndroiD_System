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
  }) : lastSeenAt = lastSeenAt ?? DateTime.now();

  final String id;
  final String name;
  final int rssi;
  final BluetoothDevice device;

  final DateTime lastSeenAt;

  /// stale detection
  static const Duration staleThreshold = Duration(seconds: 5);
  static const Duration expireThreshold = Duration(seconds: 15);

  Duration get silenceDuration => DateTime.now().difference(lastSeenAt);

  DeviceStaleStatus get staleStatus {
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

  /// Returns a copy with optionally updated [rssi] and/or [lastSeenAt].
  BleScanDevice copyWith({int? rssi, DateTime? lastSeenAt}) {
    return BleScanDevice(
      id: id,
      name: name,
      rssi: rssi ?? this.rssi,
      device: device,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
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
