import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:tusker_trailer_rrc/models/app_enums.dart';

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
    this.plcType = PlcType.unknown,
  }) : lastSeenAt = lastSeenAt ?? DateTime.now();

  final String id;
  final String name;
  final int rssi;
  final BluetoothDevice device;

  /// PLC hardware model decoded from BLE advertisement manufacturer data.
  final PlcType plcType;

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
      plcType: _parsePlcType(result),
    );
  }

  /// Extracts the PLC type from BLE advertisement manufacturer data.
  ///
  /// The firmware encodes the model as a plain ASCII string
  /// (e.g. "PLC14") in the Manufacturer Specific Data AD type.
  /// flutter_blue_plus parses the first two bytes as the little-endian
  /// company ID and the remainder as the payload. This method reconstructs
  /// the original byte sequence to recover the full model string.
  static PlcType _parsePlcType(ScanResult result) {
    try {
      final mfrData = result.advertisementData.manufacturerData;
      for (final entry in mfrData.entries) {
        final companyId = entry.key;
        final payload = entry.value;
        // Reconstruct original bytes: LE uint16 company ID + payload.
        final bytes = [
          companyId & 0xFF,
          (companyId >> 8) & 0xFF,
          ...payload,
        ];
        // Only accept printable ASCII to guard against binary garbage.
        if (bytes.isEmpty || !bytes.every((b) => b >= 0x20 && b <= 0x7E)) {
          continue;
        }
        final str = String.fromCharCodes(bytes);
        final type = PlcType.fromString(str);
        if (type != PlcType.unknown) return type;
      }
    } catch (_) {
      // Malformed manufacturer data — fall through to unknown.
    }
    return PlcType.unknown;
  }

  /// Returns a copy with optionally updated fields.
  /// Pass [clearFrozen] = true to re-enable live stale computation
  /// (used when a scan session resumes after being paused).
  BleScanDevice copyWith({
    int? rssi,
    DateTime? lastSeenAt,
    DeviceStaleStatus? frozenStatus,
    bool clearFrozen = false,
    PlcType? plcType,
  }) {
    return BleScanDevice(
      id: id,
      name: name,
      rssi: rssi ?? this.rssi,
      device: device,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      frozenStatus: clearFrozen ? null : (frozenStatus ?? this.frozenStatus),
      plcType: plcType ?? this.plcType,
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
