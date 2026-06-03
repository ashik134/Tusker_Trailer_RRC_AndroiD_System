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

  // True if the digital characteristic supports ATT WRITE COMMAND (no ACK needed).
  // Enables fire-and-forget control writes for minimal latency (~1 connection interval
  // vs ~2 round-trips with ATT WRITE REQUEST). Set during service discovery.
  bool _digitalCharWriteNoResponse = false;

  // ── Live RSSI polling ───────────────────────────────────────────────────────
  Timer? _rssiTimer;

  // ── Heartbeat loop ──────────────────────────────────────────────────────────
  bool _heartbeatActive = false;
  Timer? _heartbeatTimer;
  bool _heartbeatWritePending = false;

  // All AES-GCM encrypted app→PLC writes share one monotonic nonce counter in
  // the firmware, so they must be encrypted and written in call order.
  Future<void> _encryptedWriteLane = Future<void>.value();
  int _cryptoSessionGeneration = 0;

  // ── Continuous scan control ─────────────────────────────────────────────────
  bool _scanShouldContinue = false;

  // ── Device cache — prevents list flicker between 8-second scan bursts ────────
  final Map<String, BleScanDevice> _deviceCache = {};
  final Map<String, DateTime> _deviceLastSeen = {};
  Timer? _pruneTimer;
  static const Duration _deviceStaleTimeout = Duration(seconds: 20);
  static const Duration _pruneInterval = Duration(seconds: 5);

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
    // Stop the previous scan loop and subscription WITHOUT clearing the device
    // cache. Cached devices are immediately re-emitted below so they appear
    // on screen the instant SCAN is tapped, before BLE has had a chance to
    // re-discover them (important with balanced scan mode).
    _scanShouldContinue = false;
    _pruneTimer?.cancel();
    _pruneTimer = null;
    if (FlutterBluePlus.isScanningNow) {
      await FlutterBluePlus.stopScan();
    }
    await _scanResultsSub?.cancel();
    _scanResultsSub = null;

    _emit(BleConnectionStatus.scanning);
    _scanShouldContinue = true;

    // Re-emit the cache immediately so the UI shows previously seen devices.
    if (_deviceCache.isNotEmpty) {
      _scanController.add(List.unmodifiable(_deviceCache.values.toList()));
    }

    // Start pruning timer to remove devices that stop advertising.
    _pruneTimer = Timer.periodic(_pruneInterval, (_) => _pruneStaleDevices());

    _scanResultsSub = FlutterBluePlus.scanResults.listen(
      (results) {
        final now = DateTime.now();
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
          _deviceLastSeen[device.id] = now;

          if (existing == null || existing.rssi != device.rssi) {
            _deviceCache[device.id] = device;
            changed = true;
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
    _pruneTimer?.cancel();
    _pruneTimer = null;
    _deviceCache.clear();
    _deviceLastSeen.clear();
    await FlutterBluePlus.stopScan();
    _scanResultsSub?.cancel();
    _scanResultsSub = null;
    if (FlutterBluePlus.isScanningNow) {
      await FlutterBluePlus.stopScan();
    }
  }

  void _pruneStaleDevices() {
    final now = DateTime.now();
    final staleIds = _deviceLastSeen.entries
        .where((e) => now.difference(e.value) > _deviceStaleTimeout)
        .map((e) => e.key)
        .toList();

    if (staleIds.isEmpty) return;

    for (final id in staleIds) {
      _deviceCache.remove(id);
      _deviceLastSeen.remove(id);
    }
    debugPrint('[BLE] Pruned ${staleIds.length} stale device(s) from cache.');
    _scanController.add(List.unmodifiable(_deviceCache.values.toList()));
  }

  // ── Connection ─────────────────────────────────────────────────────────────

  Future<void> connect(BleScanDevice scanDevice) async {
    await stopScan();
    await disconnect(emitState: false);

    // Assign the target device BEFORE emitting 'connecting'.
    // _emit() calls broadcast-stream listeners synchronously, so
    // CraneController.connectionState.connectedDevice must already be
    // populated when isConnecting first becomes true — otherwise the UI
    // null-guard fires and shows an empty-device state for one frame.
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
      // Negotiate a larger ATT MTU before any characteristic writes.
      // AES-GCM encrypted digital-characteristic payloads (nonce + ciphertext +
      // tag, hex-encoded) reach ~78 bytes — well above the default 20-byte ATT
      // payload.  Without explicit negotiation the Android BLE stack falls back
      // to Prepare Write / Execute Write (long-write procedure), which is not
      // guaranteed to be handled correctly by all ESP32 NimBLE configurations.
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
      _heartbeatChar = null; // reset before each discovery pass
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
    _cryptoSessionGeneration++;
    _sessionAuthenticated = false; // clear before tearing down characteristics
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
        withoutResponse: false,
        label: 'safe-state',
      );
      return;
    }
    await _digitalChar!.write(plainBytes, withoutResponse: false);
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
      // An untrusted device cannot authenticate by definition — close the
      // session immediately so the BLE link does not remain open and occupy
      // the PLC's single-operator slot, blocking legitimate reconnection.
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

    // 5. Disconnect.  disconnect(emitState: false) preserves our error state
    //    above and attempts a best-effort plaintext safe-state write before
    //    tearing down the BLE link.
    await disconnect(emitState: false);
  }

  Future<void> _finalizeAuthenticatedSession() async {
    // The AES-128-GCM session was started in authenticate() before the
    // encrypted auth write, so the monotonic packet counter is already live.
    // Only start it here as a fallback if authenticate() was somehow bypassed.
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
    // Mark the session live — AES-GCM encryption is now active for all three
    // characteristics: auth, digital, and heartbeat.
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

    // Auth payload is AES-128-GCM encrypted (Flutter → PLC).
    //
    // The session is started here — before the write — so the nonce counter
    // is consistent across auth, digital, and heartbeat characteristics.
    // _finalizeAuthenticatedSession() reuses the active session instead of
    // restarting it, preserving the monotonic packet counter.
    //
    //   Auth char    → AES-128-GCM encrypted (Flutter → PLC)
    //   Digital char → AES-128-GCM encrypted (Flutter → PLC)
    //   Heartbeat    → AES-128-GCM encrypted (Flutter → PLC)
    _cryptoSessionGeneration++;
    _sessionAuthenticated = false;
    _heartbeatWritePending = false;
    _encryptedWriteLane = Future<void>.value();
    BleCrypto.endSession(); // Clear any stale state from a previous attempt.
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

  // ── Heartbeat helpers ─────────────────────────────────────────────────────

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

  // Hot path — called every 50 ms. Keep this method lean: no allocations,
  // no logging, no DateTime calls. Any overhead here directly adds to the
  // Dart event-loop latency visible as sluggish control response.
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

  /// Encrypts the heartbeat payload with AES-128-GCM and writes it to [char].
  ///
  /// The "HB" payload is encrypted using the active [BleCrypto] session before
  /// transmission. The packet counter is incremented on every call, so each
  /// heartbeat nonce is unique within the session.
  ///
  /// Re-checks [_heartbeatActive] and [_isDisposing] before and after
  /// encryption so a write is never attempted after disconnect or dispose.
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
