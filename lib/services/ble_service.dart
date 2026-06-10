import 'dart:io';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:logger/logger.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'package:tusker_trailer_rrc/utils/constants.dart';

import 'package:tusker_trailer_rrc/models/ble_scan_device.dart';
import 'package:tusker_trailer_rrc/models/ble_connection_state.dart';
import 'package:tusker_trailer_rrc/models/plc_output_command.dart';
import 'package:tusker_trailer_rrc/services/ble_crypto.dart';

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

  bool _sessionAuthenticated = false;

  bool _digitalCharWriteNoResponse = false;

  Timer? _rssiTimer;

  // ── Heartbeat loop
  bool _heartbeatActive = false;
  Timer? _heartbeatTimer;
  bool _heartbeatWritePending = false;

  Future<void> _encryptedWriteLane = Future<void>.value();
  int _cryptoSessionGeneration = 0;

  bool _scanShouldContinue = false;

  bool _scanPaused = false;

  DateTime? _scanSessionDeadline;

  bool _connectCancelled = false;

  final Map<String, BleScanDevice> _deviceCache = {};
  Timer? _pruneTimer;

  static const Duration _deviceExpireTimeout = Duration(seconds: 20);
  static const Duration _pruneInterval = Duration(seconds: 3);

  // ── Scan cycle tuning

  static const Duration _scanBurstDuration = Duration(seconds: 6);
  static const Duration _scanPauseDuration = Duration(milliseconds: 1500);
  static const Duration _maxScanSessionDuration = Duration(minutes: 3);

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
    _scanShouldContinue = false;
    _scanPaused = false;
    _pruneTimer?.cancel();
    _pruneTimer = null;
    if (FlutterBluePlus.isScanningNow) {
      await FlutterBluePlus.stopScan();
    }
    await _scanResultsSub?.cancel();
    _scanResultsSub = null;

    _deviceCache.clear();
    _scanSessionDeadline = DateTime.now().add(_maxScanSessionDuration);
    await _startOrResumeScanSession();
  }

  Future<void> pauseScan() async {
    if (_scanSessionDeadline == null) return;
    if (_scanPaused) return;
    _scanPaused = true;
    _scanShouldContinue = false;
    if (FlutterBluePlus.isScanningNow) {
      await FlutterBluePlus.stopScan();
    }
    await _scanResultsSub?.cancel();
    _scanResultsSub = null;

    _freezeCache();
  }

  Future<void> resumeScan() async {
    if (_scanShouldContinue) return; // loop already running
    final deadline = _scanSessionDeadline;
    if (deadline == null) return; // no session to resume

    if (deadline.difference(DateTime.now()).inSeconds < 1) {
      _scanPaused = false;
      _scanSessionDeadline = null;
      _pruneTimer?.cancel();
      _pruneTimer = null;
      if (_snapshot.status == BleConnectionStatus.scanning) {
        _emit(BleConnectionStatus.disconnected);
      }
      return;
    }

    _scanPaused = false;
    await _scanResultsSub?.cancel();
    _scanResultsSub = null;
    await _startOrResumeScanSession();
  }

  Future<void> _startOrResumeScanSession() async {
    _unfreezeCache();
    _emit(BleConnectionStatus.scanning);
    _scanShouldContinue = true;

    if (_deviceCache.isNotEmpty) {
      _scanController.add(List.unmodifiable(_deviceCache.values.toList()));
    }

    _pruneTimer?.cancel();
    _pruneTimer = Timer.periodic(_pruneInterval, (_) => _pruneStaleDevices());

    _scanResultsSub = FlutterBluePlus.scanResults.listen(
      (results) {
        bool changed = false;

        for (final result in results) {
          final advertisedName = result.advertisementData.advName.trim();
          final platformName = result.device.platformName.trim();
          final resolvedName = advertisedName.isNotEmpty
              ? advertisedName
              : platformName;

          if (resolvedName.isEmpty ||
              !resolvedName.startsWith(BLEConstants.scanNamePrefix)) {
            continue;
          }

          final device = BleScanDevice.fromScanResult(result);
          final existing = _deviceCache[device.id];

          if (existing == null) {
            _deviceCache[device.id] = device;
            changed = true;
          } else if (existing.rssi != device.rssi || existing.isStale) {
            _deviceCache[device.id] = device;
            changed = true;
          } else {
            _deviceCache[device.id] = existing.copyWith(
              lastSeenAt: device.lastSeenAt,
            );
          }
        }

        if (changed) {
          debugPrint(
            'Scan update: ${_deviceCache.length} ${BLEConstants.scanNamePrefix}* device(s) in cache',
          );
          _scanController.add(List.unmodifiable(_deviceCache.values.toList()));
        }
      },
      onError: (e) {
        _emit(
          BleConnectionStatus.error,
          message: 'Scan error: ${e.toString()}',
        );
      },
    );

    while (_scanShouldContinue && !_isDisposing) {
      final remaining = _scanSessionDeadline!.difference(DateTime.now());
      if (remaining.inSeconds < 1) break;

      final burst = remaining < _scanBurstDuration
          ? remaining
          : _scanBurstDuration;

      try {
        await FlutterBluePlus.startScan(
          timeout: burst,
          androidScanMode: AndroidScanMode.balanced,
        );
        await FlutterBluePlus.isScanning.where((s) => !s).first;
      } catch (_) {
        break;
      }
      if (!_scanShouldContinue || _isDisposing) break;
      await Future.delayed(_scanPauseDuration);
    }

    await _scanResultsSub?.cancel();
    _scanResultsSub = null;

    _freezeCache();

    if (!_scanPaused) {
      _scanSessionDeadline = null;
      if (_snapshot.status == BleConnectionStatus.scanning) {
        _emit(BleConnectionStatus.disconnected);
      }
    }
  }

  Future<void> stopScan() async {
    _scanShouldContinue = false;
    _scanPaused = false;
    _scanSessionDeadline = null;
    await FlutterBluePlus.stopScan();
    await _scanResultsSub?.cancel();
    _scanResultsSub = null;
    if (FlutterBluePlus.isScanningNow) {
      await FlutterBluePlus.stopScan();
    }
    _freezeCache();
    if (_snapshot.status == BleConnectionStatus.scanning) {
      _emit(BleConnectionStatus.disconnected);
    }
  }

  // ── Cache freeze / unfreeze ───────────────────────────────────────────────

  void _freezeCache({bool forceEmit = false}) {
    _pruneTimer?.cancel();
    _pruneTimer = null;
    if (_deviceCache.isEmpty) return;
    bool changed = false;
    for (final id in _deviceCache.keys.toList()) {
      final d = _deviceCache[id]!;
      if (d.frozenStatus == null) {
        _deviceCache[id] = d.copyWith(frozenStatus: DeviceStaleStatus.active);
        changed = true;
      }
    }
    if (changed || forceEmit) {
      _scanController.add(List.unmodifiable(_deviceCache.values.toList()));
    }
  }

  void _unfreezeCache() {
    if (_deviceCache.isEmpty) return;
    final now = DateTime.now();
    for (final id in _deviceCache.keys.toList()) {
      _deviceCache[id] = _deviceCache[id]!.copyWith(
        lastSeenAt: now,
        clearFrozen: true,
      );
    }
  }

  void _pruneStaleDevices() {
    final now = DateTime.now();

    final expiredIds = _deviceCache.entries
        .where(
          (e) =>
              e.value.frozenStatus == null &&
              now.difference(e.value.lastSeenAt) > _deviceExpireTimeout,
        )
        .map((e) => e.key)
        .toList();

    for (final id in expiredIds) {
      _deviceCache.remove(id);
    }
    if (expiredIds.isNotEmpty) {
      debugPrint(
        '[BLE] Removed ${expiredIds.length} expired device(s) from cache '
        '(silent > ${_deviceExpireTimeout.inSeconds}s).',
      );
    }

    if (_deviceCache.isNotEmpty || expiredIds.isNotEmpty) {
      _scanController.add(List.unmodifiable(_deviceCache.values.toList()));
    }
  }

  // ── Connection ─────────────────────────────────────────────────────────────

  Future<void> connect(BleScanDevice scanDevice) async {
    await disconnect(emitState: false);

    _connectedDevice = scanDevice;
    _device = scanDevice.device;
    _emit(BleConnectionStatus.connecting);

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
        timeout: const Duration(seconds: 8),
        license: License.commercial,
      );
      await _discoverServices();
    } catch (e) {
      if (_connectCancelled) return;

      _connStateSub?.cancel();
      _connStateSub = null;
      _device = null;
      _connectedDevice = null;

      final String message;
      final errStr = e.toString().toLowerCase();
      if (errStr.contains('timed out') || errStr.contains('timeout')) {
        message = 'Controller unreachable — device is out of range or offline.';

        Future.delayed(const Duration(seconds: 3), () {
          if (!_isDisposing && _snapshot.status == BleConnectionStatus.error) {
            _emit(BleConnectionStatus.disconnected);
          }
        });
      } else {
        message = 'Connection failed: ${e.toString()}';
      }

      _emit(BleConnectionStatus.error, message: message);
      _logger.e('Connection failed: ${e.toString()}');
      return;
    }

    _connStateSub?.cancel();
    _connStateSub = _device!.connectionState.listen((state) {
      if (state == BluetoothConnectionState.disconnected) {
        _handleDisconnect();
      }
    });
  }

  Future<void> _discoverServices() async {
    try {
      _emit(BleConnectionStatus.discoveringServices);

      if (!kIsWeb && Platform.isAndroid) {
        try {
          final negotiatedMtu = await _device!.requestMtu(512);
          debugPrint('[BLE] ATT MTU negotiated: $negotiatedMtu bytes');
        } catch (e) {
          _logger.w('MTU negotiation failed — proceeding with default MTU: $e');
          debugPrint('[BLE] MTU negotiation failed: $e');
        }
      }
      final services = await _device!.discoverServices();

      BluetoothCharacteristic? digital;
      BluetoothCharacteristic? auth;
      BluetoothCharacteristic? status;
      _digitalChar = null;
      _authChar = null;

      _statusChar = null;
      _heartbeatChar = null;
      _digitalCharWriteNoResponse = false;

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
            _digitalCharWriteNoResponse = char.properties.writeWithoutResponse;
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

      _emit(BleConnectionStatus.configuringNotifications);

      if (!_digitalCharWriteNoResponse) {
        _logger.w(
          'Digital characteristic does not support writeWithoutResponse — '
          'control writes will use ATT WRITE REQUEST (with ACK, ~15–40 ms '
          'round-trip per command). Add PROPERTY_WRITE_NO_RESPONSE to the '
          'ESP32 digital characteristic declaration to restore low-latency '
          'fire-and-forget control.',
        );
      }
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

      _emit(BleConnectionStatus.initializingSafeState);

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

  Future<void> cancelConnecting() async {
    if (_snapshot.status != BleConnectionStatus.connecting) return;

    _connectCancelled = true;

    await _connStateSub?.cancel();
    _connStateSub = null;

    final device = _device;
    _device = null;
    _connectedDevice = null;
    _digitalChar = null;
    _authChar = null;
    _statusChar = null;
    _heartbeatChar = null;

    if (device != null) {
      try {
        await device.disconnect();
      } catch (_) {}
    }

    _connectCancelled = false;
    _emit(BleConnectionStatus.disconnected);
  }

  Future<void> disconnect({bool emitState = true}) async {
    _stopRssiPolling();
    _stopHeartbeat();
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
    _cryptoSessionGeneration++;
    _sessionAuthenticated = false;
    _heartbeatWritePending = false;
    _encryptedWriteLane = Future<void>.value();
    BleCrypto.endSession();

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
    _cryptoSessionGeneration++;
    _sessionAuthenticated = false;
    _heartbeatWritePending = false;
    _encryptedWriteLane = Future<void>.value();
    BleCrypto.endSession();
    _pendingAuthCompleter?.complete(BleAuthOutcome.timedOut);
    _pendingAuthCompleter = null;

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

    _freezeCache(forceEmit: true);
  }

  void _handleStatusNotification(List<int> bytes) {
    final command = PlcOutputCommand.fromStatusNotification(bytes);
    if (command.estop || command.isIdle) {
      final pending = _pendingSafeStateCompleter;
      if (pending != null && !pending.isCompleted) {
        pending.complete();
      }
      _pendingSafeStateCompleter = null;
    }
    _statusController.add(command);
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
    if (_sessionAuthenticated) {
      await _writeEncryptedCharacteristic(
        characteristic: _digitalChar!,
        plaintext: plainBytes,
        withoutResponse: _digitalCharWriteNoResponse,
        label: 'safe-state',
      );
      return;
    }
    await _digitalChar!.write(
      plainBytes,
      withoutResponse: _digitalCharWriteNoResponse,
    );
  }

  void _handleAuthNotification(List<int> bytes) {
    unawaited(_handleAuthNotificationAsync(bytes));
  }

  Future<void> _handleAuthNotificationAsync(List<int> bytes) async {
    final plainPayload = _tryDecodeUtf8(bytes)?.trim();
    if (await _handleAuthPayload(plainPayload, source: 'plain')) {
      return;
    }

    if (_pendingAuthCompleter == null || !BleCrypto.sessionActive) {
      if (plainPayload == null) {
        _logger.w(
          'Auth notification: non-UTF8 data (${bytes.length} bytes) ignored.',
        );
      } else {
        _logger.w('Unknown auth notification payload: "$plainPayload"');
      }
      return;
    }

    try {
      final decrypted = await BleCrypto.decrypt(bytes);
      final encryptedPayload = _tryDecodeUtf8(decrypted)?.trim();
      if (await _handleAuthPayload(encryptedPayload, source: 'encrypted')) {
        return;
      }
      _logger.w(
        'Unknown encrypted auth notification payload: "$encryptedPayload"',
      );
    } on BleCryptoException catch (e) {
      _logger.e('Encrypted auth notification rejected: $e');
      await _enterCryptoSafeState('Auth response decrypt failed: $e');
    } on StateError catch (e) {
      _logger.e('Encrypted auth notification session error: $e');
      await _enterCryptoSafeState('Auth response session error: $e');
    } catch (e) {
      _logger.e('Encrypted auth notification error: $e');
      await _enterCryptoSafeState('Auth response error: $e');
    }
  }

  Future<bool> _handleAuthPayload(
    String? payload, {
    required String source,
  }) async {
    if (payload == null || payload.isEmpty) {
      return false;
    }

    if (payload.startsWith('AUTH_REQ:')) {
      _logger.i('Auth notification ($source): AUTH_REQ');
      if (_snapshot.status != BleConnectionStatus.authenticated) {
        _emit(BleConnectionStatus.awaitingAuthentication);
      }
      return true;
    }

    if (payload == BLEConstants.authSuccess) {
      _logger.i('Auth notification ($source): $payload');
      await _finalizeAuthenticatedSession();
      return true;
    }

    if (payload == BLEConstants.authUntrusted) {
      _logger.w('Auth notification ($source): $payload');
      _cryptoSessionGeneration++;
      _sessionAuthenticated = false;
      _heartbeatWritePending = false;
      _encryptedWriteLane = Future<void>.value();
      BleCrypto.endSession();
      _pendingAuthCompleter?.complete(BleAuthOutcome.untrusted);
      _pendingAuthCompleter = null;
      _emit(BleConnectionStatus.error, message: payload);

      unawaited(disconnect(emitState: false));
      return true;
    }

    if (payload == BLEConstants.authFailed ||
        payload == BLEConstants.authTimeout) {
      _logger.w('Auth notification ($source): $payload');
      _cryptoSessionGeneration++;
      _sessionAuthenticated = false;
      _heartbeatWritePending = false;
      _encryptedWriteLane = Future<void>.value();
      BleCrypto.endSession();
      _pendingAuthCompleter?.complete(
        payload == BLEConstants.authTimeout
            ? BleAuthOutcome.timedOut
            : BleAuthOutcome.failed,
      );
      _pendingAuthCompleter = null;
      _emit(BleConnectionStatus.error, message: payload);
      return true;
    }

    return false;
  }

  String? _tryDecodeUtf8(List<int> bytes) {
    try {
      return utf8.decode(bytes);
    } catch (_) {
      return null;
    }
  }

  /// Immediately enters safe state after a cryptographic validation failure.
  /// This is triggered whenever decryption, tag verification, session
  /// validation, counter validation, or replay detection fails on an inbound
  /// BLE packet.

  Future<void> _enterCryptoSafeState(String reason) async {
    if (_isDisposing) return;

    _logger.e('CRYPTO SAFE STATE ENTERED: $reason');
    debugPrint('[SECURITY] Entering crypto safe state — reason: $reason');

    // 1. Stop all active output loops immediately.
    _stopHeartbeat();

    // 2. Clear the authenticated session — no further encrypted writes allowed.
    _cryptoSessionGeneration++;
    _sessionAuthenticated = false;
    _heartbeatWritePending = false;
    _encryptedWriteLane = Future<void>.value();
    BleCrypto.endSession();

    // 3. Fail any pending authentication future.
    _pendingAuthCompleter?.complete(BleAuthOutcome.failed);
    _pendingAuthCompleter = null;

    // 4. Surface the security error to the UI.
    _emit(
      BleConnectionStatus.error,
      message: 'Security error — session terminated. Please reconnect.',
    );

    // 5. Disconnect.  disconnect(emitState: false)
    await disconnect(emitState: false);
  }

  Future<void> _finalizeAuthenticatedSession() async {
    if (!BleCrypto.sessionActive) {
      await BleCrypto.beginSession();
    }

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

    _sessionAuthenticated = true;
    _emit(BleConnectionStatus.authenticated);
    _pendingAuthCompleter?.complete(BleAuthOutcome.success);
    _pendingAuthCompleter = null;
    _startRssiPolling();
    _startHeartbeat();
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

    // Auth payload is AES-128-GCM encrypted (Flutter → PLC).

    _cryptoSessionGeneration++;
    _sessionAuthenticated = false;
    _heartbeatWritePending = false;
    _encryptedWriteLane = Future<void>.value();
    BleCrypto.endSession();
    await BleCrypto.beginSession();

    final plaintext = utf8.encode('$email|$password|$deviceId');
    final encryptedAuth = await BleCrypto.encrypt(plaintext);

    await _authChar!.write(encryptedAuth, withoutResponse: false);

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

  // ── Heartbeat helpers

  void _startHeartbeat() {
    _stopHeartbeat();
    if (_heartbeatChar == null) {
      _logger.w('Heartbeat characteristic not found — heartbeat disabled.');
      return;
    }

    final bool useWithoutResponse =
        _heartbeatChar!.properties.writeWithoutResponse;
    if (!useWithoutResponse) {
      _logger.w(
        'HB: ESP32 heartbeat characteristic does not support '
        'writeWithoutResponse — using ATT WRITE REQUEST (~15 ms round-trip). '
        'Declare PROPERTY_WRITE_NO_RESPONSE on the ESP32 heartbeat '
        'characteristic to enable fire-and-forget writes.',
      );
    }

    _heartbeatActive = true;
    _heartbeatTimer = Timer.periodic(
      SafetyConstants.heartbeatInterval,
      (_) => _sendHeartbeatTick(useWithoutResponse),
    );
  }

  void _sendHeartbeatTick(bool useWithoutResponse) {
    if (!_heartbeatActive || _isDisposing) return;
    if (_heartbeatWritePending) return;
    final char = _heartbeatChar;
    if (char == null) return;
    _heartbeatWritePending = true;
    // AES-128-GCM encrypted heartbeat — fire-and-forget.
    unawaited(
      _encryptAndSendHeartbeat(char, useWithoutResponse)
          .catchError((Object e) {
            _logger.w('Heartbeat write failed: $e');
          })
          .whenComplete(() {
            _heartbeatWritePending = false;
          }),
    );
  }

  Future<void> _encryptAndSendHeartbeat(
    BluetoothCharacteristic char,
    bool useWithoutResponse,
  ) async {
    if (!_heartbeatActive || _isDisposing) return;
    await _writeEncryptedCharacteristic(
      characteristic: char,
      plaintext: utf8.encode(BLEConstants.heartbeatPayload),
      withoutResponse: useWithoutResponse,
      label: 'heartbeat',
    );
  }

  void _stopHeartbeat() {
    _heartbeatActive = false;
    _heartbeatWritePending = false;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  // ── Live RSSI helpers

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

        _connectedDevice = connectedDevice.copyWith(rssi: rssi);

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

  // ── Write helpers
  Future<void> _writeEncryptedCharacteristic({
    required BluetoothCharacteristic characteristic,
    required List<int> plaintext,
    required bool withoutResponse,
    required String label,
  }) {
    final generation = _cryptoSessionGeneration;
    final writeFuture = _encryptedWriteLane.then((_) async {
      if (_isDisposing ||
          !_sessionAuthenticated ||
          generation != _cryptoSessionGeneration ||
          _device?.isConnected != true) {
        return;
      }

      final wireBytes = await BleCrypto.encrypt(plaintext);

      if (_isDisposing ||
          !_sessionAuthenticated ||
          generation != _cryptoSessionGeneration ||
          _device?.isConnected != true) {
        return;
      }

      await characteristic.write(wireBytes, withoutResponse: withoutResponse);
    });

    _encryptedWriteLane = writeFuture.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {
        _logger.w('Encrypted BLE write lane recovered after $label: $error');
      },
    );

    return writeFuture;
  }

  Future<void> writeDigital(List<int> bytes) async {
    if (_digitalChar == null) return;
    if (_sessionAuthenticated) {
      try {
        await _writeEncryptedCharacteristic(
          characteristic: _digitalChar!,
          plaintext: bytes,
          withoutResponse: _digitalCharWriteNoResponse,
          label: 'digital',
        );
        return;
      } on BleCryptoException catch (e) {
        _logger.e('Encryption failure on digital write: $e');
        unawaited(
          _enterCryptoSafeState('BleCryptoException during encrypt: $e'),
        );
        return;
      } on StateError catch (e) {
        _logger.e('Crypto session state error on digital write: $e');
        unawaited(_enterCryptoSafeState('StateError during encrypt: $e'));
        return;
      }
    }
    await _digitalChar!.write(
      bytes,
      withoutResponse: _digitalCharWriteNoResponse,
    );
  }

  Future<void> writeAuth(List<int> bytes) async {
    if (_authChar == null) return;
    await _authChar!.write(bytes);
  }

  // ── Bluetooth adapter
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
    _scanPaused = false;
    _scanSessionDeadline = null;
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
