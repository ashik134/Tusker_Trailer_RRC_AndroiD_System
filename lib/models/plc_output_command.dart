import 'dart:convert';
import 'dart:typed_data';

enum HoistDirection { idle, up, down, left, right }

enum HoistSpeed { idle, slow, fast }

class PlcOutputCommand {
  const PlcOutputCommand._({
    required this.estop,
    required this.up,
    required this.down,
    required this.left,
    required this.right,
    required this.speed,
  });

  final bool estop;
  final bool up;
  final bool down;
  final bool left;
  final bool right;
  final HoistSpeed speed;

  factory PlcOutputCommand.idle() {
    return const PlcOutputCommand._(
      estop: false,
      up: false,
      down: false,
      left: false,
      right: false,
      speed: HoistSpeed.idle,
    );
  }

  factory PlcOutputCommand.emergencyStop() {
    return const PlcOutputCommand._(
      estop: true,
      up: false,
      down: false,
      left: false,
      right: false,
      speed: HoistSpeed.idle,
    );
  }

  factory PlcOutputCommand.motion({
    bool up = false,
    bool down = false,
    bool left = false,
    bool right = false,
    HoistSpeed speed = HoistSpeed.slow,
  }) {
    if ((up && down) || (left && right)) {
      return PlcOutputCommand.idle();
    }
    if (!up && !down && !left && !right) {
      return PlcOutputCommand.idle();
    }

    return PlcOutputCommand._(
      estop: false,
      up: up,
      down: down,
      left: left,
      right: right,
      speed: speed,
    );
  }

  factory PlcOutputCommand.fromStatusNotification(List<int> bytes) {
    try {
      final raw = utf8.decode(bytes).trim();
      final cleaned = raw.replaceAll('[', '').replaceAll(']', '');
      final parts = cleaned
          .split(',')
          .map((segment) => int.tryParse(segment.trim()) ?? 0)
          .toList();

      if (parts.length < 3) {
        return PlcOutputCommand.idle();
      }

      final estop = parts[0] != 0;
      final up = parts[1] != 0;
      final down = parts[2] != 0;
      final left = parts.length > 3 ? parts[3] != 0 : false;
      final right = parts.length > 4 ? parts[4] != 0 : false;
      final fast = parts.length > 5 ? parts[5] != 0 : false;

      if (estop) {
        return PlcOutputCommand.emergencyStop();
      }

      return PlcOutputCommand.motion(
        up: up,
        down: down,
        left: left,
        right: right,
        speed: fast ? HoistSpeed.fast : HoistSpeed.slow,
      );
    } catch (_) {
      return PlcOutputCommand.idle();
    }
  }

  int get estopBit => estop ? 1 : 0;
  int get upBit => up ? 1 : 0;
  int get downBit => down ? 1 : 0;
  int get leftBit => left ? 1 : 0;
  int get rightBit => right ? 1 : 0;
  int get fastBit => speed == HoistSpeed.fast ? 1 : 0;

  bool get hasVerticalMotion => up || down;
  bool get hasHorizontalMotion => left || right;
  bool get hasMotion => hasVerticalMotion || hasHorizontalMotion;
  bool get isIdle => !estop && !hasMotion;

  bool get isValid {
    if (estop) {
      return !up && !down && !left && !right && speed == HoistSpeed.idle;
    }
    return !(up && down) && !(left && right);
  }

  HoistDirection get direction {
    if (up) return HoistDirection.up;
    if (down) return HoistDirection.down;
    if (left) return HoistDirection.left;
    if (right) return HoistDirection.right;
    return HoistDirection.idle;
  }

  String get wireFormat => '[$estopBit,$upBit,$downBit,$leftBit,$rightBit]';
  Uint8List get wireBytes => Uint8List.fromList(utf8.encode(wireFormat));

  String get statusLabel {
    if (estop) {
      return 'Emergency Active';
    }

    final activeDirections = <String>[
      if (up) 'Up',
      if (down) 'Down',
      if (left) 'Left',
      if (right) 'Right',
    ];

    if (activeDirections.isEmpty) {
      return 'Idle';
    }

    return activeDirections.join(' + ');
  }

  PlcOutputCommand copyWith({
    bool? estop,
    bool? up,
    bool? down,
    bool? left,
    bool? right,
    HoistSpeed? speed,
  }) {
    return PlcOutputCommand._(
      estop: estop ?? this.estop,
      up: up ?? this.up,
      down: down ?? this.down,
      left: left ?? this.left,
      right: right ?? this.right,
      speed: speed ?? this.speed,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is PlcOutputCommand &&
        other.estop == estop &&
        other.up == up &&
        other.down == down &&
        other.left == left &&
        other.right == right &&
        other.speed == speed;
  }

  @override
  int get hashCode => Object.hash(estop, up, down, left, right, speed);
}
