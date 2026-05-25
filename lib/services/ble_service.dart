import 'dart:io';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:logger/logger.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'package:tusker_trailer_rrc/utils/constants.dart';

import 'package:tusker_trailer_rrc/models/ble_scan_device.dart';
import 'package:tusker_trailer_rrc/models/plc_output_command.dart';
import 'package:tusker_trailer_rrc/services/ble_crypto.dart';

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

class BleService {
  final Logger _logger = Logger(printer: SimplePrinter(colors: true));

  final StreamController<BleConnectionState> _connectionController =
      StreamController<BleConnectionState>.broadcast();
  final StreamController<List<BleScanDevice>> _scanController =
      StreamController<List<BleScanDevice>>.broadcast();
  final StreamController<PlcOutputCommand> _statusController =
      StreamController<PlcOutputCommand>.broadcast();

  Stream<BleConnectionState> get connectionStream =>
      _connectionController.stream;
  Stream<List<BleScanDevice>> get scanStream => _scanController.stream;
  Stream<PlcOutputCommand> get statusStream => _statusController.stream;

  BleConnectionState _snapshot = BleConnectionState.initial();
  BluetoothDevice? _device;
  BleScanDevice? _connectedDevice; 

  BluetoothCharacteristic? _digitalChar;
  BluetoothCharacteristic? _authChar;
  BluetoothCharacteristic? _statusChar;
  BluetoothCharacteristic? _heartbeatChar;

  StreamSubscription<BluetoothConnectionState>? _connStateSub;
  StreamSubscription<List<int>>? _authSubscription;
  StreamSubscription<List<int>>? _statusSubscription;
  StreamSubscription<List<ScanResult>>? _scanResultsSub;

  Completer<BleAuthOutcome>? _pendingAuthCompleter;
  Completer<void>? _pendingSafeStateCompleter;
  bool _isDisposing = false;

  // True once the PLC has confirmed AUTH_OK and the session is live.
  // Digital-characteristic writes are AES-128-GCM encrypted while this is true.
  bool _sessionAuthenticated = false;

  // ── Live RSSI polling ───────────────────────────────────────────────────────
  Timer? _rssiTimer;

  // ── Heartbeat loop ──────────────────────────────────────────────────────────
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

      BluetoothCharacteristic? digital;
      BluetoothCharacteristic? auth;
      BluetoothCharacteristic? status;
      _digitalChar = null;
      _authChar = null;

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

      await _authChar!.setNotifyValue(true);
      await _statusChar!.setNotifyValue(true);

      _authSubscription = _authChar!.onValueReceived.listen(
        _handleAuthNotification,
      );
      _statusSubscription = _statusChar!.onValueReceived.listen(
        _handleStatusNotification,
      );

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
    _sessionAuthenticated = false; // clear before tearing down characteristics

    await _authSubscription?.cancel();
    await _statusSubscription?.cancel();
    await _connStateSub?.cancel();

    _authSubscription = null;
    _statusSubscription = null;
    _connStateSub = null;

    _device = null;

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
    _sessionAuthenticated = false;
    BleCrypto.endSession(); // clear in-memory IV state; persisted counter stays as watermark
    _device = null;
    _connectedDevice = null;
    _connStateSub?.cancel();
    _connStateSub = null;

    _authChar = null;
    _digitalChar = null;
    _statusChar = null;
    _heartbeatChar = null;

    _authSubscription?.cancel();
    _statusSubscription?.cancel();

    _authSubscription = null;
    _statusSubscription = null;

    if (!_statusController.isClosed) {
      _statusController.add(PlcOutputCommand.idle());
    }
    _emit(BleConnectionStatus.disconnected);
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
    final plainBytes = PlcOutputCommand.emergencyStop().wireBytes.toList();
    final wireBytes = _sessionAuthenticated
        ? await BleCrypto.encrypt(plainBytes)
        : plainBytes;
    await _digitalChar!.write(wireBytes, withoutResponse: false);
  }

  void _handleAuthNotification(List<int> bytes) {
    // ALL auth-characteristic notifications from the ESP32 firmware are
    // plain-text UTF-8 strings — no AES-GCM encryption on this channel.
    //
    //   PLC → app:  "AUTH_REQ:email|password|device_id" (on connect)
    //               "AUTH_OK"      (credentials + device ID accepted)
    //               "AUTH_FAIL"    (credentials or device ID rejected)
    //               "AUTH_TIMEOUT" (30-second inactivity window expired)
    //               "AUTH_UNTRUSTED" (future: device not in trusted list)
    //
    // The AES-128-GCM session for digital-characteristic writes is started
    // inside _finalizeAuthenticatedSession() after AUTH_OK is confirmed.
    final payload = _tryDecodeUtf8(bytes)?.trim();
    if (payload == null) {
      _logger.w(
        'Auth notification: non-UTF8 data (${bytes.length} bytes) ignored.',
      );
      return;
    }

    _logger.i('Auth notification: $payload');

    if (payload == BLEConstants.authRequest) {
      if (_snapshot.status != BleConnectionStatus.authenticated) {
        _emit(BleConnectionStatus.awaitingAuthentication);
      }
      return;
    }

    if (payload == BLEConstants.authSuccess) {
      // Fire-and-forget: starts AES-GCM session then emits authenticated state.
      _finalizeAuthenticatedSession();
      return;
    }

    if (payload == BLEConstants.authUntrusted) {
      _pendingAuthCompleter?.complete(BleAuthOutcome.untrusted);
      _pendingAuthCompleter = null;
      _emit(BleConnectionStatus.error, message: payload);
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
      return;
    }

    _logger.w('Unknown auth notification payload: "$payload"');
  }

  /// Attempts to decode [bytes] as UTF-8.  Returns [null] on failure rather
  /// than throwing, so callers can handle malformed payloads safely.
  String? _tryDecodeUtf8(List<int> bytes) {
    try {
      return utf8.decode(bytes);
    } catch (_) {
      return null;
    }
  }

  /// Immediately enters safe state after a cryptographic validation failure.
  ///
  /// This is triggered whenever decryption, tag verification, session
  /// validation, counter validation, or replay detection fails on an inbound
  /// BLE packet.
  ///
  /// Because this system controls safety-critical crane/trailer hardware,
  /// ANY cryptographic failure MUST:
  ///   1. Stop all active output loops (heartbeat).
  ///   2. Terminate the encrypted session.
  ///   3. Fail any pending authentication.
  ///   4. Emit an error state visible to the UI.
  ///   5. Disconnect the BLE session and require re-authentication.
  Future<void> _enterCryptoSafeState(String reason) async {
    if (_isDisposing) return;

    _logger.e('CRYPTO SAFE STATE ENTERED: $reason');
    debugPrint('[SECURITY] Entering crypto safe state — reason: $reason');

    // 1. Stop all active output loops immediately.
    _stopHeartbeat();

    // 2. Clear the authenticated session — no further encrypted writes allowed.
    _sessionAuthenticated = false;
    BleCrypto.endSession();

    // 3. Fail any pending authentication future.
    _pendingAuthCompleter?.complete(BleAuthOutcome.failed);
    _pendingAuthCompleter = null;

    // 4. Surface the security error to the UI.
    _emit(
      BleConnectionStatus.error,
      message: 'Security error — session terminated. Please reconnect.',
    );

    // 5. Disconnect.  disconnect(emitState: false) preserves our error state
    //    above and attempts a best-effort plaintext safe-state write before
    //    tearing down the BLE link.
    await disconnect(emitState: false);
  }

  Future<void> _finalizeAuthenticatedSession() async {
    // Start the AES-128-GCM session NOW — after the PLC has confirmed AUTH_OK.
    //
    // beginSession() increments and persists the monotonic session counter so
    // the 12-byte nonce [session_id || packet_counter] is unique across every
    // reconnect, even after crashes or forced restarts.  This session is used
    // exclusively for digital-characteristic writes (control commands).
    //
    // Auth and heartbeat characteristics use plain text; only digital char
    // uses AES-128-GCM encryption, matching the ESP32 firmware architecture.
    BleCrypto.endSession(); // Clear any stale state from a previous session.
    await BleCrypto.beginSession();

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
    // Mark the session live — AES-GCM encryption is now active for digital writes.
    _sessionAuthenticated = true;
    _emit(BleConnectionStatus.authenticated);
    _pendingAuthCompleter?.complete(BleAuthOutcome.success);
    _pendingAuthCompleter = null;
    _startRssiPolling(); // Begin live RSSI updates now that the session is fully up.
    _startHeartbeat(); // Begin 100 ms heartbeat — Timer.periodic, fire-and-forget writes.
  }

  Future<BleAuthOutcome> authenticate({
    required String email,
    required String password,
    required String deviceId,
  }) async {
    if (_authChar == null) {
      throw StateError('Authentication characteristic is not ready.');
    }

    _pendingAuthCompleter?.complete(BleAuthOutcome.failed);
    _pendingAuthCompleter = Completer<BleAuthOutcome>();

    final authFuture = _pendingAuthCompleter!.future;
    _emit(BleConnectionStatus.authenticating);

    // Auth payload is sent as plain text — the ESP32 firmware's
    // AuthCallbacks::onWrite parses it directly with std::string::find('|').
    //
    // The AES-128-GCM session for digital-characteristic writes is NOT started
    // here; it is started in _finalizeAuthenticatedSession() only after the
    // PLC has confirmed AUTH_OK.  This matches the firmware architecture:
    //
    //   Auth char   → plain text both directions
    //   Digital char → AES-128-GCM encrypted (Flutter → PLC only)
    //   Heartbeat   → plain text "HB"
    final plaintext = utf8.encode('$email|$password|$deviceId');

    await _authChar!.write(plaintext, withoutResponse: false);

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

  int _hbTickCount = 0;
  int _hbDispatchCount = 0;

  DateTime? _hbLastTickTime;

  DateTime? _hbLastDispatchTime;

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
      '[HB] Heartbeat started — interval=50ms '
      'writeWithoutResponse=$useWithoutResponse',
    );

    // ── Firmware capability check ───────────────────────────────────────────
    // The ESP32 characteristic must declare PROPERTY_WRITE_NO_RESPONSE to
    // enable ATT WRITE COMMAND (fire-and-forget, ~0 ms latency).

    if (!useWithoutResponse) {
      _logger.w(
        'HB: ESP32 characteristic declares PROPERTY_WRITE only — '
        'using ATT WRITE REQUEST (with ACK, ~15 ms round-trip). '
        'Add PROPERTY_WRITE_NO_RESPONSE to the firmware characteristic '
        'to enable fire-and-forget writes and eliminate Android '
        'main-thread timing sensitivity.',
      );
      debugPrint(
        '[HB] ⚠ writeWithoutResponse=false — '
        'FIRMWARE ACTION REQUIRED: add '
        'BLECharacteristic::PROPERTY_WRITE_NO_RESPONSE to the '
        'heartbeat characteristic declaration on the ESP32.',
      );
    }

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
        _logger.w(
          'HB timer interval anomaly: ${intervalMs}ms (expected ~100ms)',
        );
      }
    }

    // ── Dispatch throttle (time-based) ─────────────────────────────────────
    final lastDispatch = _hbLastDispatchTime;
    if (lastDispatch != null) {
      final msSince = now.difference(lastDispatch).inMilliseconds;
      if (msSince < 50) {
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

    // Send plain-text "HB" — the ESP32 firmware expects exactly this string.
    // Heartbeats are never AES-GCM encrypted; only the digital characteristic
    // (control commands) uses encryption.
    _encryptAndSendHeartbeat(char, useWithoutResponse).catchError((Object e) {
      _logger.w('Heartbeat write failed: $e');
      debugPrint('[HB] write error: $e');
    });
  }

  /// Encrypts the heartbeat payload and writes it to [char].
  ///
  /// Sends the plain-text heartbeat payload to [char].
  ///
  /// The ESP32 firmware's HeartbeatCallbacks::onWrite expects exactly the
  /// two-byte UTF-8 string "HB". Any other value — including AES-GCM
  /// ciphertext — is explicitly rejected. Heartbeats are never encrypted.
  ///
  /// Re-checks [_heartbeatActive] and [_isDisposing] before writing so a
  /// write is never attempted after disconnect or dispose has begun.
  Future<void> _encryptAndSendHeartbeat(
    BluetoothCharacteristic char,
    bool useWithoutResponse,
  ) async {
    // Plain text "HB" — firmware expects exactly this, no AES-GCM.
    final wireBytes = utf8.encode(BLEConstants.heartbeatPayload);
    if (!_heartbeatActive || _isDisposing) return;
    await char.write(wireBytes, withoutResponse: useWithoutResponse);
  }

  void _stopHeartbeat() {
    _heartbeatActive = false;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _hbLastTickTime = null;
    _hbLastDispatchTime = null;
  }

  // ── Live RSSI helpers ─────────────────────────────────────────────────────

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
    final wireBytes = _sessionAuthenticated
        ? await BleCrypto.encrypt(bytes)
        : bytes;
    await _digitalChar!.write(wireBytes, withoutResponse: false);
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
    _authSubscription?.cancel();
    _statusSubscription?.cancel();
    _connStateSub?.cancel();

    if (FlutterBluePlus.isScanningNow) {
      FlutterBluePlus.stopScan();
    }

    final device = _device;
    _device = null;
    _connectedDevice = null;

    _digitalChar = null;
    _authChar = null;
    _statusChar = null;
    _heartbeatChar = null;
    if (device != null && device.isConnected) {
      device.disconnect();
    }

    _connectionController.close();
    _scanController.close();

    _statusController.close();
  }
}
