import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:logger/logger.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'package:tusker_trailer_rrc/models/ble_scan_device.dart';
import 'package:tusker_trailer_rrc/models/plc_output_command.dart';
import 'package:tusker_trailer_rrc/utils/constants.dart';

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

enum BleAuthOutcome { success, failed, timedOut }

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

class BleService {
  final Logger _logger = Logger(printer: PrettyPrinter(methodCount: 0));

  final StreamController<BleConnectionState> _connectionController =
      StreamController<BleConnectionState>.broadcast();
  final StreamController<List<BleScanDevice>> _scanController =
      StreamController<List<BleScanDevice>>.broadcast();
  final StreamController<Map<String, int>> _analogController =
      StreamController<Map<String, int>>.broadcast();
  final StreamController<PlcOutputCommand> _statusController =
      StreamController<PlcOutputCommand>.broadcast();

  Stream<BleConnectionState> get connectionStream =>
      _connectionController.stream;
  Stream<List<BleScanDevice>> get scanStream => _scanController.stream;
  Stream<Map<String, int>> get analogStream => _analogController.stream;
  Stream<PlcOutputCommand> get statusStream => _statusController.stream;

  BleConnectionState _snapshot = BleConnectionState.initial();
  BluetoothDevice? _device;
  BleScanDevice? _connectedDevice;
  BluetoothCharacteristic? _analogChar;
  BluetoothCharacteristic? _digitalChar;
  BluetoothCharacteristic? _authChar;
  BluetoothCharacteristic? _statusChar;
  BluetoothCharacteristic? _heartbeatChar;

  StreamSubscription<BluetoothConnectionState>? _connStateSub;
  StreamSubscription<List<int>>? _analogSubscription;
  StreamSubscription<List<int>>? _authSubscription;
  StreamSubscription<List<int>>? _statusSubscription;
  StreamSubscription<List<ScanResult>>? _scanResultsSub;

  Completer<BleAuthOutcome>?
  _pendingAuthCompleter; // For tracking ongoing authentication attempts.
  Completer<void>? _pendingSafeStateCompleter;
  bool _isDisposing = false;

  // ── Live RSSI polling ───────────────────────────────────────────────────────
  Timer? _rssiTimer;

  // ── Heartbeat loop ──────────────────────────────────────────────────────────
  // Timer.periodic fires at wall-clock intervals regardless of event-loop
  // backlog (BLE callbacks, UI redraws, RSSI polls). Unlike a Future.delayed
  // loop, the next tick is never pushed back by pending async work.
  bool _heartbeatActive = false;
  Timer? _heartbeatTimer;

  // ── Continuous scan control ─────────────────────────────────────────────────
  bool _scanShouldContinue = false;

  static const int _safeStateMaxAttempts = 3;
  static const Duration _safeStateAckTimeout = Duration(milliseconds: 1200);

  void _emit(BleConnectionStatus status, {String? message}) { 
    if (_isDisposing || _connectionController.isClosed) {
      return;
    }
    _snapshot = BleConnectionState(
      status: status,
      message: message,
      connectedDevice: _connectedDevice,
    );
    _connectionController.add(_snapshot);
  }

  // ── Scanning ───────────────────────────────────────────────────────────────

  Future<void> startScan() async {
    await stopScan();
    _scanController.add(const []);
    _emit(BleConnectionStatus.scanning);
    _scanShouldContinue = true;

    // Single persistent subscription for the entire scan session.
    // FlutterBluePlus.scanResults emits the full, de-duplicated list of all
    // seen devices with their LATEST RSSI on every new advertisement —
    // so RSSI is live throughout the session without extra work.
    _scanResultsSub = FlutterBluePlus.scanResults.listen(
      (results) {
        final seen = <String>{};
        final devices = results
            .where((result) {
              final advertisedName = result.advertisementData.advName.trim();
              final platformName = result.device.platformName.trim();
              final resolvedName = advertisedName.isNotEmpty
                  ? advertisedName
                  : platformName;

              // Ignore unnamed devices and only include configurable PLC names.
              return resolvedName.isNotEmpty &&
                  resolvedName.startsWith(BLEConstants.scanNamePrefix);
            })
            .map(BleScanDevice.fromScanResult)
            .where((d) => seen.add(d.id))
            .toList();
        debugPrint(
          'Scan update: ${devices.length} ${BLEConstants.scanNamePrefix}* device(s) found',
        );
        _scanController.add(List.unmodifiable(devices));
      },
      onError: (e) {
        _emit(
          BleConnectionStatus.error,
          message: 'Scan error: ${e.toString()}',
        );
      },
    );

    // Continuous scan loop: run 8-second bursts with a brief gap so that
    // FlutterBluePlus keeps receiving fresh advertisements (and thus fresh
    // RSSI values) for as long as the user is on the scan page.
    while (_scanShouldContinue && !_isDisposing) {
      try {
        await FlutterBluePlus.startScan(
          timeout: const Duration(seconds: 8),
          androidScanMode: AndroidScanMode.balanced,
        );
        await FlutterBluePlus.isScanning.where((s) => !s).first;
      } catch (_) {
        break;
      }
      if (!_scanShouldContinue || _isDisposing) break;
      // Brief gap between bursts to let the radio rest.
      await Future.delayed(const Duration(milliseconds: 400));
    }

    _scanResultsSub?.cancel();
    _scanResultsSub = null;
    if (_snapshot.status == BleConnectionStatus.scanning) {
      _emit(BleConnectionStatus.disconnected);
    }
  }

  Future<void> stopScan() async {
    _scanShouldContinue = false; // Break the continuous scan loop.
    await FlutterBluePlus.stopScan();
    _scanResultsSub?.cancel();
    _scanResultsSub = null;
    if (FlutterBluePlus.isScanningNow) {
      await FlutterBluePlus.stopScan();
    }
  }

  // ── Connection ─────────────────────────────────────────────────────────────

  Future<void> connect(BleScanDevice scanDevice) async {
    await stopScan();
    await disconnect(emitState: false);
    _emit(BleConnectionStatus.connecting);

    _connectedDevice = scanDevice;
    _device = scanDevice.device;
    var hasreachedConnectedState = false;

    _connStateSub = _device!.connectionState.listen((state) {
      if (state == BluetoothConnectionState.connected) {
        hasreachedConnectedState = true;
        _logger.i('Device connected: ${_connectedDevice?.name}');
        return;
      }
      if (state == BluetoothConnectionState.disconnected) {
        if (!hasreachedConnectedState) {
          _logger.d('Ignoring initial disconnected state before connect.');
          return;
        }
        _logger.e('Failed to connect to device: ${_connectedDevice?.name}');
        _handleDisconnect();
      }
    });
    _device!.cancelWhenDisconnected(_connStateSub!, delayed: true, next: true);

    try {
      await _device!.connect(
        autoConnect: false,
        timeout: const Duration(seconds: 15),
        license: License.commercial,
      );
      await _discoverServices();
    } catch (e) {
      _connectedDevice = null;
      _emit(
        BleConnectionStatus.error,
        message: 'Connection failed: ${e.toString()}',
      );
      _logger.e('Connection failed: ${e.toString()}');
      return;
    }

    // Monitor for unexpected disconnection.
    _connStateSub?.cancel();
    _connStateSub = _device!.connectionState.listen((state) {
      if (state == BluetoothConnectionState.disconnected) {
        _handleDisconnect();
      }
    });
  }

  // Discover services and map characteristics.
  Future<void> _discoverServices() async {
    try {
      final services = await _device!.discoverServices();
      BluetoothCharacteristic? analog;
      BluetoothCharacteristic? digital;
      BluetoothCharacteristic? auth;
      BluetoothCharacteristic? status;
      _digitalChar = null;
      _authChar = null;
      _analogChar = null;
      _statusChar = null;
      _heartbeatChar = null; // reset before each discovery pass

      for (final service in services) {
        if (service.uuid.toString().toLowerCase() !=
            BLEConstants.serviceUuid.toLowerCase()) {
          continue;
        }

        for (final char in service.characteristics) {
          final uuid = char.uuid.toString().toLowerCase();
          debugPrint(
            '[BLE] Char discovered: $uuid '
            '| write=${char.properties.write} '
            '| writeNoResp=${char.properties.writeWithoutResponse} '
            '| notify=${char.properties.notify}',
          );
          if (uuid == BLEConstants.digitalCharUuid.toLowerCase()) {
            digital = char;
          } else if (uuid == BLEConstants.analogCharUuid.toLowerCase()) {
            analog = char;
          } else if (uuid == BLEConstants.authCharUuid.toLowerCase()) {
            auth = char;
          } else if (uuid == BLEConstants.statusCharUuid.toLowerCase()) {
            status = char;
          } else if (uuid == BLEConstants.heartbeatCharUuid.toLowerCase()) {
            _heartbeatChar = char;
            debugPrint(
              '[BLE] Heartbeat characteristic found '
              '(write=${char.properties.write}, '
              'writeNoResp=${char.properties.writeWithoutResponse})',
            );
          }
        }
      }

      //
      if (digital == null || auth == null || status == null) {
        await _device!.disconnect();
        _connectedDevice = null;
        _emit(
          BleConnectionStatus.error,
          message: 'PLC14 service not found on this device.',
        );
        return;
      }

      _analogChar = analog;
      _digitalChar = digital;
      _authChar = auth;
      _statusChar = status;
      // _heartbeatChar was assigned inline above (optional — no error if absent).
      if (_heartbeatChar == null) {
        debugPrint(
          '[BLE] WARNING: Heartbeat characteristic NOT found '
          '(UUID: ${BLEConstants.heartbeatCharUuid}). '
          'Heartbeat will be disabled.',
        );
      }

      if (_analogChar != null) {
        await _analogChar!.setNotifyValue(true);
      }
      await _authChar!.setNotifyValue(true);
      await _statusChar!.setNotifyValue(true);
      if (_analogChar != null) {
        _analogSubscription = _analogChar!.onValueReceived.listen(
          _handleAnalogNotification,
        );
      }
      _authSubscription = _authChar!.onValueReceived.listen(
        _handleAuthNotification,
      );
      _statusSubscription = _statusChar!.onValueReceived.listen(
        _handleStatusNotification,
      );

      if (_analogSubscription != null) {
        _device!.cancelWhenDisconnected(_analogSubscription!, next: true);
      }
      _device!.cancelWhenDisconnected(_authSubscription!, next: true);
      _device!.cancelWhenDisconnected(_statusSubscription!, next: true);

      // _emit(
      //   BleConnectionStatus.connecting,
      //   message: 'Synchronizing safe state with PLC...',
      // );
      await _sendSafeStatePreAuthBestEffort();
      _emit(BleConnectionStatus.awaitingAuthentication);
    } catch (e) {
      await _device!.disconnect();
      _connectedDevice = null;
      _emit(
        BleConnectionStatus.error,
        message: 'Service discovery failed: ${e.toString()}',
      );
    }
  }

  Future<void> disconnect({bool emitState = true}) async {
    _stopRssiPolling(); // Stop polling before tearing down the BLE link.
    _stopHeartbeat(); // Stop heartbeat before tearing down the BLE link.
    _pendingAuthCompleter?.complete(BleAuthOutcome.failed);
    _pendingAuthCompleter = null;
    final pendingSafeState = _pendingSafeStateCompleter;
    if (pendingSafeState != null && !pendingSafeState.isCompleted) {
      pendingSafeState.complete();
    }
    _pendingSafeStateCompleter = null;

    final device = _device;
    if (device != null && device.isConnected) {
      try {
        await _sendSafeStateCommand().timeout(
          const Duration(milliseconds: 900),
        );
      } catch (_) {
        _logger.w('Safe-state cleanup write failed during disconnect.');
      }
    }

    await _analogSubscription?.cancel();
    await _authSubscription?.cancel();
    await _statusSubscription?.cancel();
    await _connStateSub?.cancel();
    _analogSubscription = null;
    _authSubscription = null;
    _statusSubscription = null;
    _connStateSub = null;

    _device = null;
    _analogChar = null;
    _digitalChar = null;
    _authChar = null;
    _statusChar = null;
    _heartbeatChar = null;

    if (device != null && device.isConnected) {
      await device.disconnect();
    }

    if (emitState) {
      _handleDisconnect();
    } else {
      _connectedDevice = null;
    }
  }

  void _handleDisconnect() {
    if (_isDisposing) {
      return;
    }
    _stopRssiPolling();
    _stopHeartbeat();
    _device = null;
    _connectedDevice = null;
    _connStateSub?.cancel();
    _connStateSub = null;
    _analogChar = null;
    _authChar = null;
    _digitalChar = null;
    _statusChar = null;
    _heartbeatChar = null;
    _analogSubscription?.cancel();
    _authSubscription?.cancel();
    _statusSubscription?.cancel();
    _analogSubscription = null;
    _authSubscription = null;
    _statusSubscription = null;
    if (!_analogController.isClosed) {
      _analogController.add(const {'A1': 0, 'A2': 0});
    }
    if (!_statusController.isClosed) {
      _statusController.add(PlcOutputCommand.idle());
    }
    _emit(BleConnectionStatus.disconnected);
  }

  // ── Characteristic callbacks ───────────────────────────────────────────────

  // Keeps the last known values so single-channel updates don't zero out the other channel.
  final Map<String, int> _lastAnalog = {'A1': 0, 'A2': 0};

  void _handleAnalogNotification(List<int> bytes) {
    final payload = utf8.decode(bytes).trim();
    final parts = payload.split(',');

    try {
      final updated = Map<String, int>.from(_lastAnalog);
      for (final part in parts) {
        final kv = part.split(':');
        if (kv.length != 2) {
          _logger.w('Unexpected analog token: $part');
          continue;
        }
        final key = kv[0].trim();
        final value = int.parse(kv[1].trim());
        if (updated.containsKey(key)) {
          updated[key] = value;
        } else {
          _logger.w('Unknown analog key: $key');
        }
      }
      _lastAnalog
        ..['A1'] = updated['A1']!
        ..['A2'] = updated['A2']!;
      _analogController.add(Map.unmodifiable(updated));
    } catch (error) {
      _logger.e('Analog parse error', error: error);
    }
  }

  void _handleStatusNotification(List<int> bytes) {
    final command = PlcOutputCommand.fromStatusNotification(bytes);
    _logger.i(
      'PLC status: estop=${command.estop} up=${command.up} down=${command.down} left=${command.left} right=${command.right}',
    );
    if (command.estop || command.isIdle) {
      final pending = _pendingSafeStateCompleter;
      if (pending != null && !pending.isCompleted) {
        pending.complete();
      }
      _pendingSafeStateCompleter = null;
    }
    _statusController.add(command);
  }

  Future<void> _sendSafeStateAndAwaitAck() async {
    if (_digitalChar == null) {
      throw StateError('Digital characteristic is not ready.');
    }

    Object? lastError;
    for (var attempt = 1; attempt <= _safeStateMaxAttempts; attempt++) {
      final ackCompleter = Completer<void>();
      _pendingSafeStateCompleter = ackCompleter;
      try {
        await _sendSafeStateCommand();
        await ackCompleter.future.timeout(_safeStateAckTimeout);
        _logger.i('Safe-state synchronized with PLC on attempt $attempt.');
        return;
      } catch (error) {
        lastError = error;
        _logger.w(
          'Safe-state sync attempt $attempt failed: ${error.toString()}',
        );
      } finally {
        if (identical(_pendingSafeStateCompleter, ackCompleter)) {
          _pendingSafeStateCompleter = null;
        }
      }
    }

    throw StateError(
      'Failed to synchronize safe state with PLC after $_safeStateMaxAttempts attempts. '
      '${lastError ?? ''}',
    );
  }

  Future<void> _sendSafeStatePreAuthBestEffort() async {
    if (_digitalChar == null) {
      return;
    }
    try {
      await _sendSafeStateCommand().timeout(const Duration(milliseconds: 900));
      _logger.i('Pre-auth safe-state packet sent (best effort).');
    } catch (error) {
      _logger.w('Pre-auth safe-state write failed: ${error.toString()}');
    }
  }

  Future<void> _sendSafeStateCommand() async {
    if (_digitalChar == null) {
      throw StateError('Digital characteristic is not ready.');
    }
    await _digitalChar!.write(
      PlcOutputCommand.emergencyStop().wireBytes.toList(),
      withoutResponse: false,
    );
  }

  void _handleAuthNotification(List<int> bytes) {
    final payload = utf8.decode(bytes).trim();
    _logger.i('Auth notification: $payload');

    if (payload == BLEConstants.authRequest) {
      if (_snapshot.status != BleConnectionStatus.authenticated) {
        _emit(BleConnectionStatus.awaitingAuthentication);
      }
      return;
    }

    if (payload == BLEConstants.authSuccess) {
      _finalizeAuthenticatedSession();
      return;
    }

    if (payload == BLEConstants.authFailed ||
        payload == BLEConstants.authTimeout) {
      _pendingAuthCompleter?.complete(
        payload == BLEConstants.authTimeout
            ? BleAuthOutcome.timedOut
            : BleAuthOutcome.failed,
      );
      _pendingAuthCompleter = null;
      _emit(BleConnectionStatus.error, message: payload);
    }
  }

  Future<void> _finalizeAuthenticatedSession() async {
    _emit(
      BleConnectionStatus.authenticating,
      message: 'Finalizing safe-state synchronization...',
    );

    try {
      await _sendSafeStateAndAwaitAck();
      // Request a high-priority BLE connection on Android so the controller
      // reduces the connection interval to 7.5–15 ms.  This dramatically cuts
      // GATT write round-trip time and ensures the 100 ms heartbeat can always
      // be delivered without contending with digital-control writes.
      if (!kIsWeb && Platform.isAndroid) {
        try {
          await _device!.requestConnectionPriority(
            connectionPriorityRequest: ConnectionPriority.high,
          );
          debugPrint('[BLE] Connection priority set to HIGH.');
        } catch (e) {
          _logger.w('Could not set connection priority: $e');
        }
      }
      _emit(BleConnectionStatus.authenticated);
      _pendingAuthCompleter?.complete(BleAuthOutcome.success);
      _pendingAuthCompleter = null;
      _startRssiPolling(); // Begin live RSSI updates now that the session is fully up.
      _startHeartbeat(); // Begin 100 ms heartbeat — Timer.periodic, fire-and-forget writes.
    } catch (error) {
      _pendingAuthCompleter?.complete(BleAuthOutcome.failed);
      _pendingAuthCompleter = null;
      _emit(
        BleConnectionStatus.error,
        message: 'Post-auth safe-state sync failed: ${error.toString()}',
      );
      final device = _device;
      if (device != null && device.isConnected) {
        await device.disconnect();
      }
    }
  }

  Future<BleAuthOutcome> authenticate({
    required String email,
    required String password,
  }) async {
    if (_authChar == null) {
      throw StateError('Authentication characteristic is not ready.');
    }

    _pendingAuthCompleter?.complete(BleAuthOutcome.failed);
    _pendingAuthCompleter = Completer<BleAuthOutcome>();
    // Capture the future NOW before the write, so a fast notification that
    // nulls out _pendingAuthCompleter during the await cannot cause a
    // null-check crash on line below.
    final authFuture = _pendingAuthCompleter!.future;
    _emit(BleConnectionStatus.authenticating);

    await _authChar!.write(
      utf8.encode('$email|$password'),
      withoutResponse: false,
    );

    try {
      return await authFuture.timeout(
        SafetyConstants.authReplyTimeout,
        onTimeout: () {
          _pendingAuthCompleter = null;
          _emit(
            BleConnectionStatus.awaitingAuthentication,
            message: 'PLC authentication timed out.',
          );
          return BleAuthOutcome.timedOut;
        },
      );
    } finally {
      if (_snapshot.status != BleConnectionStatus.authenticated &&
          _device != null &&
          _device!.isConnected &&
          _snapshot.status != BleConnectionStatus.error) {
        _emit(BleConnectionStatus.awaitingAuthentication);
      }
    }
  }

  // ── Heartbeat helpers ─────────────────────────────────────────────────────

  int _hbTickCount = 0;      // total timer ticks fired (including throttled)
  int _hbDispatchCount = 0;  // actual write dispatches sent to flutter_blue_plus
  // Wall-clock time of the most recent timer tick — for interval measurement.
  DateTime? _hbLastTickTime;
  // Wall-clock time of the most recent actual dispatch — for throttle guard.
  // Using elapsed time instead of a Dart callback flag avoids the cascade-skip
  // problem: when Android's main thread is busy rendering, both the platform-
  // channel write call AND its .then() callback are delayed by the same stall.
  // Waiting for the callback causes 3-4 consecutive ticks to skip, creating a
  // 300-400 ms PLC gap.  A 50 ms wall-clock threshold is independent of any
  // Dart/Android callback and is always wider than the ~15 ms BLE round-trip.
  DateTime? _hbLastDispatchTime;

  /// Starts the heartbeat timer. Timer.periodic fires at fixed wall-clock
  /// intervals regardless of event-loop backlog.
  void _startHeartbeat() {
    _stopHeartbeat();
    if (_heartbeatChar == null) {
      _logger.w('Heartbeat characteristic not found — heartbeat disabled.');
      debugPrint('[HB] ERROR: _heartbeatChar is null — heartbeat NOT started.');
      return;
    }

    final bool useWithoutResponse =
        _heartbeatChar!.properties.writeWithoutResponse;
    debugPrint(
      '[HB] Heartbeat started — interval=100ms '
      'writeWithoutResponse=$useWithoutResponse',
    );

    _heartbeatActive = true;
    _hbTickCount = 0;
    _hbDispatchCount = 0;
    _hbLastTickTime = null;
    _hbLastDispatchTime = null;

    _heartbeatTimer = Timer.periodic(
      SafetyConstants.heartbeatInterval,
      (_) => _sendHeartbeatTick(useWithoutResponse),
    );
  }

  /// Called on every timer tick.
  ///
  /// Two concerns are handled independently:
  ///
  /// 1. Interval measurement — recorded at the top of every tick (including
  ///    throttled ones) using wall-clock time so the log reflects true
  ///    Timer.periodic cadence regardless of write completion.
  ///
  /// 2. Dispatch throttle — time-based, NOT callback-based.  When
  ///    Android's main thread is busy rendering, the platform-channel call
  ///    is queued on Android's Looper and may not execute for 100+ ms.  Both
  ///    the write itself AND its .then() callback suffer the same delay.
  ///    Waiting for the callback (the old _hbWriteInFlight approach) causes
  ///    3-4 consecutive ticks to skip, creating a 300-400 ms PLC gap.
  ///    Instead, we allow a new dispatch as soon as 50 ms have elapsed since
  ///    the previous one — well past the ~15 ms BLE round-trip, but without
  ///    coupling to any delayed Dart callback.
  void _sendHeartbeatTick(bool useWithoutResponse) {
    if (!_heartbeatActive || _isDisposing) return;
    final char = _heartbeatChar;
    if (char == null) return;

    final now = DateTime.now();
    _hbTickCount++;

    // ── Interval measurement (every tick) ──────────────────────────────────
    final prev = _hbLastTickTime;
    _hbLastTickTime = now;
    if (prev != null) {
      final intervalMs = now.difference(prev).inMilliseconds;
      final label = (intervalMs > 130 || intervalMs < 70)
          ? '[HB] ⚠ INTERVAL'
          : '[HB] interval';
      debugPrint('$label = ${intervalMs}ms (tick #$_hbTickCount)');
      if (intervalMs > 130 || intervalMs < 70) {
        _logger.w('HB timer interval anomaly: ${intervalMs}ms (expected ~100ms)');
      }
    }

    // ── Dispatch throttle (time-based) ─────────────────────────────────────
    final lastDispatch = _hbLastDispatchTime;
    if (lastDispatch != null) {
      final msSince = now.difference(lastDispatch).inMilliseconds;
      if (msSince < 50) {
        // Catch-up tick fired too soon after the last dispatch — throttle it.
        // This keeps GATT queue depth ≤ 2 without waiting for callbacks.
        debugPrint(
          '[HB] tick #$_hbTickCount throttled (${msSince}ms since last dispatch)',
        );
        return;
      }
    }

    // ── Dispatch ───────────────────────────────────────────────────────────
    _hbLastDispatchTime = now;
    _hbDispatchCount++;
    if (_hbDispatchCount <= 5 || _hbDispatchCount % 10 == 0) {
      debugPrint('[HB] HB dispatched (#$_hbDispatchCount)');
    }

    char
        .write(
          utf8.encode(BLEConstants.heartbeatPayload),
          withoutResponse: useWithoutResponse,
        )
        .catchError((Object e) {
          _logger.w('Heartbeat write failed: $e');
          debugPrint('[HB] write error: $e');
        });
  }

  void _stopHeartbeat() {
    _heartbeatActive = false;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _hbLastTickTime = null;
    _hbLastDispatchTime = null;
  }

  // ── Live RSSI helpers ─────────────────────────────────────────────────────

  /// Starts periodic RSSI polling (every 3 s) for the active connection.
  /// On each tick: reads RSSI from the BLE device, reconstructs
  /// [_connectedDevice] with the fresh value, then re-emits the current
  /// connection state so every UI consumer rebuilds with live signal strength.
  void _startRssiPolling() {
    _rssiTimer?.cancel();
    _rssiTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      final device = _device;
      final connectedDevice = _connectedDevice;
      if (device == null ||
          !device.isConnected ||
          connectedDevice == null ||
          _isDisposing) {
        return;
      }
      try {
        final rssi = await device.readRssi();
        // Reconstruct with fresh RSSI (rssi field is final on BleScanDevice).
        _connectedDevice = BleScanDevice(
          id: connectedDevice.id,
          name: connectedDevice.name,
          rssi: rssi,
          device: connectedDevice.device,
        );
        // Re-emit the same connection status — the controller's stream listener
        // will pick up the new connectedDevice and call notifyListeners(),
        // propagating the fresh RSSI to all UI consumers.
        _emit(_snapshot.status);
      } catch (e) {
        _logger.w('RSSI poll failed: $e');
      }
    });
  }

  void _stopRssiPolling() {
    _rssiTimer?.cancel();
    _rssiTimer = null;
  }

  // ── Write helpers ──────────────────────────────────────────────────────────

  Future<void> writeDigital(List<int> bytes) async {
    if (_digitalChar == null) return;
    await _digitalChar!.write(bytes, withoutResponse: false);
  }

  Future<void> writeAuth(List<int> bytes) async {
    if (_authChar == null) return;
    await _authChar!.write(bytes);
  }

  // ── Bluetooth adapter ──────────────────────────────────────────────────────

  Future<void> ensureBluetoothReady() async {
    if (!kIsWeb && Platform.isAndroid) {
      final state = await FlutterBluePlus.adapterState.first;
      if (state != BluetoothAdapterState.on) {
        await FlutterBluePlus.turnOn();
      }
    }
  }

  void dispose() {
    _isDisposing = true;
    _stopRssiPolling();
    _stopHeartbeat();
    _scanResultsSub?.cancel();
    _analogSubscription?.cancel();
    _authSubscription?.cancel();
    _statusSubscription?.cancel();
    _connStateSub?.cancel();

    if (FlutterBluePlus.isScanningNow) {
      FlutterBluePlus.stopScan();
    }

    final device = _device;
    _device = null;
    _connectedDevice = null;
    _analogChar = null;
    _digitalChar = null;
    _authChar = null;
    _statusChar = null;
    _heartbeatChar = null;
    if (device != null && device.isConnected) {
      device.disconnect();
    }

    _connectionController.close();
    _scanController.close();
    _analogController.close();
    _statusController.close();
  }
}
