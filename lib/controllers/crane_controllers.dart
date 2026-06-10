import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:tusker_trailer_rrc/models/app_enums.dart';
import 'package:tusker_trailer_rrc/models/ble_connection_state.dart';
import 'package:tusker_trailer_rrc/models/ble_scan_device.dart';
import 'package:tusker_trailer_rrc/models/plc_output_command.dart';
import 'package:tusker_trailer_rrc/services/ble_service.dart';
import 'package:tusker_trailer_rrc/services/biometric_service.dart';
import 'package:tusker_trailer_rrc/services/secure_credential_store.dart';
import 'package:tusker_trailer_rrc/services/permission_service.dart';
import 'package:tusker_trailer_rrc/services/device_identity_service.dart';
import 'package:tusker_trailer_rrc/utils/constants.dart';
import 'package:tusker_trailer_rrc/utils/preferences.dart';

class CraneController extends ChangeNotifier with WidgetsBindingObserver {
  final BleService _bleService = BleService();
  final PermissionService _permissionService = PermissionService();
  final AppPreferences _preferences = AppPreferences();

  StreamSubscription<BleConnectionState>? _connStateSubscription;
  StreamSubscription<List<BleScanDevice>>? _scanSubscription;
  StreamSubscription<PlcOutputCommand>? _statusSubscription;
  StreamSubscription<BluetoothAdapterState>? _adapterSubscription;

  BleConnectionState _transportConnState = BleConnectionState.initial();
  BleConnectionStatus _lastConnectionStatus = BleConnectionStatus.disconnected;
  List<BleScanDevice> _devices = const [];

  PlcOutputCommand _activeCommand = PlcOutputCommand.idle();

  // BLE write serializer
  bool _commandInFlight = false;
  List<int>? _pendingCommandBytes;

  bool _initializing = true;
  Future<void>? _initializeFuture;
  bool _streamsAttached = false;
  PermissionState _permissionState = const PermissionState.initial();
  bool _bluetoothReady = false;
  bool _permissionBannerDismissed = false;
  bool _rememberCredentials = true;
  bool _estopLatched = false;
  bool _startupEmergencyArmedForConnection = false;
  bool _biometricAvailable = false;
  bool _biometricEnrolled = false;

  bool _pendingEnrollmentOffer = false;
  String? _sessionEmail;
  String? _errorMessage;
  String _savedEmail = '';
  String _savedPassword = '';
  String _deviceId = '';

  bool _deviceTrustRejected = false;
  final Set<HoistDirection> _activeDirectionalHolds = <HoistDirection>{};
  HoistDirection? _verticalDirectionLock;
  HoistDirection? _horizontalDirectionLock;
  bool _deadmanHeld = false;

  bool _cancellingConnection = false;
  BleScanDevice? _cancellingDevice;

  bool _pendingAuthTimeoutSnack = false;

  bool get isInitializing => _initializing;
  bool get bluetoothReady => _bluetoothReady;
  bool get permissionsGranted => _permissionState.isGranted;
  bool get showPermissionBanner =>
      !permissionsGranted && !_permissionBannerDismissed;

  void dismissPermissionBanner() {
    _permissionBannerDismissed = true;
    notifyListeners();
  }

  bool get rememberCredentials => _rememberCredentials;
  bool get isBiometricAvailable => _biometricAvailable;
  bool get isBiometricEnrolled => _biometricEnrolled;

  bool get hasPendingEnrollmentOffer => _pendingEnrollmentOffer;
  PlcOutputCommand get activeCommand => _activeCommand;
  bool get estopLatched => _estopLatched;
  bool get upHoldActive => _activeDirectionalHolds.contains(HoistDirection.up);
  bool get downHoldActive =>
      _activeDirectionalHolds.contains(HoistDirection.down);
  bool get leftHoldActive =>
      _activeDirectionalHolds.contains(HoistDirection.left);
  bool get rightHoldActive =>
      _activeDirectionalHolds.contains(HoistDirection.right);
  bool get deadmanActive => _deadmanHeld;
  bool get deadmanHeld => _deadmanHeld;
  String? get sessionEmail => _sessionEmail;
  String? get errorMessage => _errorMessage ?? _transportConnState.message;
  List<BleScanDevice> get devices => _devices;

  String get savedEmail => _savedEmail;
  String get savedPassword => _savedPassword;
  BleConnectionState get connectionState => _transportConnState;
  bool get isScanning =>
      _transportConnState.status == BleConnectionStatus.scanning;
  bool get isConnecting =>
      _transportConnState.status == BleConnectionStatus.connecting;
  bool get isDiscoveringServices =>
      _transportConnState.status == BleConnectionStatus.discoveringServices;
  bool get isConfiguringNotifications =>
      _transportConnState.status ==
      BleConnectionStatus.configuringNotifications;
  bool get isInitializingSafeState =>
      _transportConnState.status == BleConnectionStatus.initializingSafeState;
  bool get isAuthenticating =>
      _transportConnState.status == BleConnectionStatus.authenticating;
  bool get isConnected =>
      _transportConnState.status == BleConnectionStatus.connected ||
      _transportConnState.status == BleConnectionStatus.authenticated;
  bool get isDisconnected =>
      _transportConnState.status == BleConnectionStatus.disconnected;
  bool get isAuthenticated =>
      _transportConnState.status == BleConnectionStatus.authenticated;
  bool get isAwaitingAuthentication =>
      _transportConnState.status == BleConnectionStatus.awaitingAuthentication;

  bool get isConnectionActive =>
      _transportConnState.status == BleConnectionStatus.connecting ||
      _transportConnState.status == BleConnectionStatus.discoveringServices ||
      _transportConnState.status ==
          BleConnectionStatus.configuringNotifications ||
      _transportConnState.status == BleConnectionStatus.initializingSafeState ||
      _transportConnState.status == BleConnectionStatus.connected ||
      _transportConnState.status ==
          BleConnectionStatus.awaitingAuthentication ||
      _transportConnState.status == BleConnectionStatus.authenticating;

  String get deviceId => _deviceId;

  bool get isDeviceTrustRejected => _deviceTrustRejected;

  bool get isCancellingConnection => _cancellingConnection;

  bool get hasPendingAuthTimeoutNotification => _pendingAuthTimeoutSnack;

  void consumeAuthTimeoutNotification() {
    if (_pendingAuthTimeoutSnack) {
      _pendingAuthTimeoutSnack = false;
    }
  }

  BleScanDevice? get cancellingDevice => _cancellingDevice;

  //  LED indicator states

  bool get ledEstop => _estopLatched;
  bool get ledUp => _activeCommand.up && !_activeCommand.estop;
  bool get ledDown => _activeCommand.down && !_activeCommand.estop;
  bool get ledLeft => _activeCommand.left && !_activeCommand.estop;
  bool get ledRight => _activeCommand.right && !_activeCommand.estop;
  bool get ledFast =>
      _activeCommand.speed == HoistSpeed.fast && !_activeCommand.estop;

  String? get connectedDeviceName => _transportConnState.connectedDevice?.name;
  int? get connectedDeviceRssi => _transportConnState.connectedDevice?.rssi;
  PlcType? get connectedDevicePlcType =>
      _transportConnState.connectedDevice?.plcType;

  /// "RRC_PLC1 • PLC14"
  String get connectedDeviceTitle {
    final name = connectedDeviceName ?? BLEConstants.deviceName;
    final plc = connectedDevicePlcType;
    if (plc != null && plc != PlcType.unknown) {
      return '$name \u2022 ${plc.displayName}';
    }
    return name;
  }

  // ── Hoist state derived from active command ───────────────────────────────
  HoistState get hoistState {
    if (_activeCommand.estop || _activeCommand.hasHorizontalMotion) {
      return HoistState.idle;
    }
    return switch ((
      _activeCommand.up,
      _activeCommand.down,
      _activeCommand.speed,
    )) {
      (true, false, HoistSpeed.fast) => HoistState.upFast,
      (true, false, _) => HoistState.upSlow,
      (false, true, HoistSpeed.fast) => HoistState.downFast,
      (false, true, _) => HoistState.downSlow,
      _ => HoistState.idle,
    };
  }

  String get statusLabel => _activeCommand.statusLabel;

  AppScreen get currentScreen => switch (_transportConnState.status) {
    BleConnectionStatus.authenticated =>
      _pendingEnrollmentOffer ? AppScreen.authentication : AppScreen.control,

    BleConnectionStatus.connected ||
    BleConnectionStatus.awaitingAuthentication ||
    BleConnectionStatus.authenticating => AppScreen.authentication,
    BleConnectionStatus.error
        when _transportConnState.connectedDevice != null =>
      AppScreen.authentication,
    _ => AppScreen.connection,
  };

  Future<void> sendCommand({
    required bool estop,
    required bool up,
    required bool down,
    bool left = false,
    bool right = false,
    required bool fast,
  }) async {
    if (estop) {
      await triggerEStop();
      return;
    }

    if (_estopLatched || !isConnected) {
      return;
    }

    final PlcOutputCommand next;
    if ((up && down) || (left && right)) {
      next = PlcOutputCommand.idle();
    } else if (up || down || left || right) {
      next = PlcOutputCommand.motion(
        up: up,
        down: down,
        left: left,
        right: right,
        speed: fast ? HoistSpeed.fast : HoistSpeed.slow,
      );
    } else {
      next = PlcOutputCommand.idle();
    }

    await _sendCommand(next);
  }

  Future<bool> setDirectionalHold({
    required HoistDirection direction,
    required bool pressed,
    bool fast = false,
  }) async {
    if (direction == HoistDirection.idle) {
      return false;
    }

    final axis = _axisForDirection(direction);

    if (_estopLatched || !isConnected || !deadmanActive) {
      if (!pressed) {
        _activeDirectionalHolds.remove(direction);
        if (_lockForAxis(axis) == direction && !_hasHoldOnAxis(axis)) {
          _setLockForAxis(axis, null);
        }
        notifyListeners();
      }
      return false;
    }

    bool changed = false;

    if (pressed) {
      final lock = _lockForAxis(axis);
      if (lock != null && lock != direction) {
        return false;
      }
      changed = _activeDirectionalHolds.add(direction);
      _setLockForAxis(axis, direction);
    } else {
      changed = _activeDirectionalHolds.remove(direction);
      if (_lockForAxis(axis) == direction && !_hasHoldOnAxis(axis)) {
        _setLockForAxis(axis, null);
      }
    }

    await _recomputeDirectionalCommandAndSend(fast: fast);
    notifyListeners();
    return changed;
  }

  Future<void> releaseAllDirectionalHolds() async {
    _clearDirectionalHolds(notify: true);
    if (!_estopLatched && isConnected) {
      await _sendCommand(PlcOutputCommand.idle());
    }
  }

  // Initialization and Cleanup
  Future<void> initialize() {
    if (_initializeFuture != null) {
      return _initializeFuture!;
    }

    _initializing = true;
    notifyListeners();
    _initializeFuture = _initializeInternal();
    return _initializeFuture!;
  }

  Future<void> _initializeInternal() async {
    _attachStreamsIfNeeded();

    try {
      // Load device identity and saved credentials
      final results = await Future.wait<dynamic>([
        DeviceIdentityService.getOrCreate(),
        _preferences.getEmail(),
        _preferences.getPassword(),
      ]);
      _deviceId = results[0] as String;
      _savedEmail = (results[1] as String?) ?? '';
      _savedPassword = (results[2] as String?) ?? '';
      _rememberCredentials =
          _savedEmail.isNotEmpty && _savedPassword.isNotEmpty;

      await _prepareRunTime();
      await checkBiometricStatus();
      debugPrint(
        'Initialization complete. Bluetooth ready: $bluetoothReady, Permissions granted: $permissionsGranted',
      );
    } catch (error) {
      _errorMessage = 'Startup initialization failed. $error';
    } finally {
      _initializing = false;
      notifyListeners();
    }
  }

  void _attachStreamsIfNeeded() {
    if (_streamsAttached) {
      return;
    }
    _streamsAttached = true;
    WidgetsBinding.instance.addObserver(this);

    _connStateSubscription = _bleService.connectionStream.listen((snapshot) {
      final previousStatus = _lastConnectionStatus;
      _lastConnectionStatus = snapshot.status;
      _transportConnState = snapshot;
      if (snapshot.status == BleConnectionStatus.disconnected) {
        _clearDirectionalHolds(notify: false);
        _activeCommand = PlcOutputCommand.idle();
        _estopLatched = false;
        _deadmanHeld = false;
        _startupEmergencyArmedForConnection = false;
        _sessionEmail = null;
        _pendingEnrollmentOffer = false;
        _deviceTrustRejected = false;
      } else if (snapshot.status == BleConnectionStatus.authenticated &&
          previousStatus != BleConnectionStatus.authenticated) {
        unawaited(ensureControlEntryEmergencyLock());

        if (_biometricAvailable && !_biometricEnrolled) {
          _pendingEnrollmentOffer = true;
        }
      }
      notifyListeners();
    });

    _scanSubscription = _bleService.scanStream.listen((devices) {
      if (isConnectionActive || isConnected) return;
      _devices = devices;
      notifyListeners();
    });

    _statusSubscription = _bleService.statusStream.listen((command) {
      _activeCommand = command;
      if (command.estop) _estopLatched = true;
      notifyListeners();
    });

    _adapterSubscription = FlutterBluePlus.adapterState.listen((state) {
      _bluetoothReady = state == BluetoothAdapterState.on;
      notifyListeners();
    });
  }

  Future<void> _prepareRunTime() async {
    _permissionState = await _permissionService.requestPermissions();
    if (permissionsGranted) {
      await enableBluetooth();
    }
  }

  Future<void> refreshPermissions() async {
    _permissionState = await _permissionService.requestPermissions();
    _permissionBannerDismissed = false;
    if (permissionsGranted) {
      await enableBluetooth();
    }
    notifyListeners();
  }

  Future<void> openSettings() async {
    await _permissionService.openSettings();
  }

  Future<void> enableBluetooth() async {
    try {
      await _bleService.ensureBluetoothReady();
      final state = await FlutterBluePlus.adapterState.first;
      _bluetoothReady = state == BluetoothAdapterState.on;
    } catch (e) {
      _errorMessage =
          'Bluetooth must be enabled before scanning for PLC 14. Please enable Bluetooth and try again.';
    }
    notifyListeners();
  }

  Future<void> pauseScan() async {
    await _bleService.pauseScan();
  }

  Future<void> resumeScan() async {
    if (!bluetoothReady || !permissionsGranted) return;
    await _bleService.resumeScan();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      _bleService.pauseScan();
    } else if (state == AppLifecycleState.resumed) {
      if (currentScreen == AppScreen.connection) {
        resumeScan();
      }
    }
  }

  Future<void> scanForDevices() async {
    _errorMessage = null;
    _pendingAuthTimeoutSnack = false;

    if (!permissionsGranted) {
      await refreshPermissions();
      if (!permissionsGranted) {
        _errorMessage =
            'Required permissions not granted. Please grant permissions and try again.';
        notifyListeners();
        return;
      }
    }
    if (!bluetoothReady) {
      await enableBluetooth();
      if (!bluetoothReady) {
        _errorMessage =
            'Bluetooth is not enabled. Please enable Bluetooth and try again.';
        notifyListeners();
        return;
      }
    }
    try {
      await _bleService.startScan();
    } catch (e) {
      _errorMessage = _friendlyScanError(e);
      notifyListeners();
    }
  }

  String _friendlyScanError(Object error) {
    final message = error.toString();

    if (message.contains('ACCESS_FINE_LOCATION')) {
      return 'This Android device is requesting location access for BLE scan. '
          'Please allow location permission once, then scan again.';
    }

    if (message.contains('BLUETOOTH_SCAN')) {
      return 'Bluetooth scan permission was denied.';
    }

    if (message.contains('Location services are required for Bluetooth scan')) {
      return 'Android location services are turned off. Enable them and try again.';
    }

    return 'Failed to start PLC scan. $message';
  }

  //////////////////////////////////////////////////////////////////////////////////////////////

  Future<void> connectToDevice(BleScanDevice device) async {
    _errorMessage = null;

    try {
      await _bleService.connect(device);
    } catch (e) {
      _errorMessage = 'Could not connect to ${device.name}: ${e.toString()}';
      notifyListeners();
    }
  }

  Future<void> cancelConnecting() async {
    if (_cancellingConnection) return;
    _errorMessage = null;

    _cancellingDevice = _transportConnState.connectedDevice;
    _cancellingConnection = true;
    notifyListeners();
    await _bleService.cancelConnecting();
    _cancellingConnection = false;
    _cancellingDevice = null;
    notifyListeners();
  }

  void setRememberCredentials(bool value) {
    _rememberCredentials = value;
    notifyListeners();
  }

  Future<void> disconnect() async {
    _errorMessage = null;

    if (isConnected && !_estopLatched) {
      try {
        await _sendCommand(PlcOutputCommand.idle());
      } catch (_) {}
    }

    await _bleService.disconnect();
    notifyListeners();
  }

  Future<void> stopScan() async {
    _errorMessage = null;
    await _bleService.stopScan();
  }

  // Command helpers

  Future<void> _sendCommand(PlcOutputCommand command) async {
    _activeCommand = command;
    notifyListeners();
    final bytes = command.wireBytes.toList();
    if (_commandInFlight) {
      _pendingCommandBytes = bytes;
      return;
    }
    await _writeBytes(bytes);
  }

  Future<void> _writeBytes(List<int> bytes) async {
    _commandInFlight = true;
    try {
      await _bleService.writeDigital(bytes);

      final next = _pendingCommandBytes;
      _pendingCommandBytes = null;
      if (next != null) {
        _commandInFlight = false;
        await _writeBytes(next);
        return;
      }
    } catch (e) {
      _pendingCommandBytes = null;
      _errorMessage = 'Failed to send command: ${e.toString()}';
      notifyListeners();
    }
    _commandInFlight = false;
  }

  Future<void> triggerEStop() async {
    _estopLatched = true;
    _deadmanHeld = false;
    _clearDirectionalHolds(notify: false);
    final cmd = PlcOutputCommand.emergencyStop();
    _activeCommand = cmd;
    notifyListeners();
    final bytes = cmd.wireBytes.toList();

    _pendingCommandBytes = bytes;
    if (!_commandInFlight) {
      final pending = _pendingCommandBytes!;
      _pendingCommandBytes = null;
      await _writeBytes(pending);
    }
  }

  Future<void> triggerSafeDisconnect() async {
    if (!isConnected) return;

    _estopLatched = true;
    _deadmanHeld = false;
    _clearDirectionalHolds(notify: false);
    _activeCommand = PlcOutputCommand.emergencyStop();

    _pendingCommandBytes = null;
    notifyListeners();

    await _bleService.disconnect();
  }

  Future<void> resetEStop() async {
    _estopLatched = false;
    _clearDirectionalHolds(notify: false);
    await _sendCommand(PlcOutputCommand.idle());
  }

  Future<void> setDeadmanHeld(bool held) async {
    // E-stop always overrides deadman — block while emergency is active.
    if (_estopLatched) return;
    if (_deadmanHeld == held) return;
    _deadmanHeld = held;
    notifyListeners();
    if (!deadmanActive) {
      await releaseAllDirectionalHolds();
    }
  }

  Future<void> ensureControlEntryEmergencyLock() async {
    if (!isConnected || _startupEmergencyArmedForConnection) return;
    _startupEmergencyArmedForConnection = true;
    if (_activeCommand.estop || _estopLatched) return;
    await triggerEStop();
  }

  Future<void> _recomputeDirectionalCommandAndSend({required bool fast}) async {
    final verticalDirection = _resolveAxisDirection(MotionAxis.vertical);
    final horizontalDirection = _resolveAxisDirection(MotionAxis.horizontal);

    if (verticalDirection == HoistDirection.idle &&
        horizontalDirection == HoistDirection.idle) {
      await _sendCommand(PlcOutputCommand.idle());
      return;
    }

    await _sendCommand(
      PlcOutputCommand.motion(
        up: verticalDirection == HoistDirection.up,
        down: verticalDirection == HoistDirection.down,
        left: horizontalDirection == HoistDirection.left,
        right: horizontalDirection == HoistDirection.right,
        speed: fast ? HoistSpeed.fast : HoistSpeed.slow,
      ),
    );
  }

  void _clearDirectionalHolds({required bool notify}) {
    _activeDirectionalHolds.clear();
    _verticalDirectionLock = null;
    _horizontalDirectionLock = null;
    if (notify) {
      notifyListeners();
    }
  }

  Future<void> tapHoistButton({required bool isUp}) async {
    if (_estopLatched || !isConnected) return;
    final PlcOutputCommand next;
    if (isUp) {
      next = switch (hoistState) {
        HoistState.upSlow => PlcOutputCommand.motion(
          up: true,
          speed: HoistSpeed.fast,
        ),
        HoistState.upFast => PlcOutputCommand.idle(),
        _ => PlcOutputCommand.motion(up: true, speed: HoistSpeed.slow),
      };
    } else {
      next = switch (hoistState) {
        HoistState.downSlow => PlcOutputCommand.motion(
          down: true,
          speed: HoistSpeed.fast,
        ),
        HoistState.downFast => PlcOutputCommand.idle(),
        _ => PlcOutputCommand.motion(down: true, speed: HoistSpeed.slow),
      };
    }
    await _sendCommand(next);
  }

  Future<void> setHoistCommand({
    required bool isUp,
    required ControlState state,
  }) async {
    if (_estopLatched || !isConnected) return;
    final PlcOutputCommand cmd = switch (state) {
      ControlState.idle => PlcOutputCommand.idle(),
      ControlState.slow => PlcOutputCommand.motion(
        up: isUp,
        down: !isUp,
        speed: HoistSpeed.slow,
      ),
      ControlState.fast => PlcOutputCommand.motion(
        up: isUp,
        down: !isUp,
        speed: HoistSpeed.fast,
      ),
    };
    await _sendCommand(cmd);
  }

  MotionAxis _axisForDirection(HoistDirection direction) {
    return switch (direction) {
      HoistDirection.up || HoistDirection.down => MotionAxis.vertical,
      HoistDirection.left || HoistDirection.right => MotionAxis.horizontal,
      HoistDirection.idle => MotionAxis.vertical,
    };
  }

  HoistDirection? _lockForAxis(MotionAxis axis) {
    return switch (axis) {
      MotionAxis.vertical => _verticalDirectionLock,
      MotionAxis.horizontal => _horizontalDirectionLock,
    };
  }

  void _setLockForAxis(MotionAxis axis, HoistDirection? direction) {
    switch (axis) {
      case MotionAxis.vertical:
        _verticalDirectionLock = direction;
      case MotionAxis.horizontal:
        _horizontalDirectionLock = direction;
    }
  }

  bool _hasHoldOnAxis(MotionAxis axis) {
    return _activeDirectionalHolds.any(
      (hold) => _axisForDirection(hold) == axis,
    );
  }

  HoistDirection _resolveAxisDirection(MotionAxis axis) {
    final lock = _lockForAxis(axis);
    if (lock != null && _activeDirectionalHolds.contains(lock)) {
      return lock;
    }

    return switch (axis) {
      MotionAxis.vertical
          when _activeDirectionalHolds.contains(HoistDirection.up) =>
        HoistDirection.up,
      MotionAxis.vertical
          when _activeDirectionalHolds.contains(HoistDirection.down) =>
        HoistDirection.down,
      MotionAxis.horizontal
          when _activeDirectionalHolds.contains(HoistDirection.left) =>
        HoistDirection.left,
      MotionAxis.horizontal
          when _activeDirectionalHolds.contains(HoistDirection.right) =>
        HoistDirection.right,
      _ => HoistDirection.idle,
    };
  }

  Future<bool> authenticate({
    required String email,
    required String password,
  }) async {
    _errorMessage = null;
    _deviceTrustRejected = false;

    if (_deviceId.isEmpty) {
      _deviceId = await DeviceIdentityService.getOrCreate();
    }

    try {
      final outcome = await _bleService.authenticate(
        email: email.trim(),
        password: password,
        deviceId: _deviceId,
      );

      if (outcome == BleAuthOutcome.success) {
        _sessionEmail = email.trim();
        if (_rememberCredentials) {
          await _preferences.saveCredentials(email.trim(), password);
          _savedEmail = email.trim();
          _savedPassword = password;
        } else {
          await _preferences.clearCredentials();
          _savedEmail = '';
          _savedPassword = '';
        }
        notifyListeners();
        return true;
      }

      if (outcome == BleAuthOutcome.untrusted) {
        _deviceTrustRejected = true;
        _errorMessage =
            'DEVICE NOT AUTHORIZED\nThis device is not registered with PLC 14. '
            'Provide your Device ID to an administrator for registration.';
        notifyListeners();
        return false;
      }

      _errorMessage = outcome == BleAuthOutcome.timedOut
          ? 'PLC authentication timed out.'
          : 'Credentials were rejected by PLC 14.';
      if (outcome == BleAuthOutcome.timedOut) {
        _pendingAuthTimeoutSnack = true;
      }
      notifyListeners();
      return false;
    } catch (error) {
      _errorMessage = 'Authentication failed. $error';
      notifyListeners();
      return false;
    }
  }

  // ── Biometric authentication ──────────────────────────────────────────────

  Future<void> checkBiometricStatus() async {
    _biometricAvailable = await BiometricService.isAvailableAndEnrolled();
    _biometricEnrolled =
        _biometricAvailable && await SecureCredentialStore.hasCredentials();
    notifyListeners();
  }

  Future<bool> enrollBiometrics({
    required String email,
    required String password,
  }) async {
    if (!_biometricAvailable) return false;
    try {
      await SecureCredentialStore.storeCredentials(
        email: email,
        password: password,
      );
      _biometricEnrolled = true;
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<BiometricAuthResult> authenticateWithBiometrics() async {
    if (!_biometricAvailable || !_biometricEnrolled) {
      return const BiometricAuthResult(
        status: BiometricAuthStatus.notAvailable,
        message: 'Biometric authentication is not configured on this device.',
      );
    }

    //  Local biometric verification (device biometric hardware gate).
    final biometricResult = await BiometricService.authenticate();
    if (!biometricResult.isSuccess) {
      return biometricResult;
    }

    // Retrieve credentials from hardware-backed secure storage.

    final credentials = await SecureCredentialStore.retrieveCredentials();
    if (credentials == null) {
      _biometricEnrolled = false;
      notifyListeners();
      return const BiometricAuthResult(
        status: BiometricAuthStatus.credentialsMissing,
        message:
            'Stored operator credentials not found. Log in manually to re-enable biometric access.',
      );
    }

    // PLC validates the operator, enforces single-operator policy,
    // and returns AUTH_OK / AUTH_FAIL as normal.
    _errorMessage = null;
    final plcSuccess = await authenticate(
      email: credentials.email,
      password: credentials.password,
    );

    if (!plcSuccess) {
      await SecureCredentialStore.clearCredentials();
      _biometricEnrolled = false;
      notifyListeners();
      return BiometricAuthResult(
        status: BiometricAuthStatus.failure,
        message:
            _errorMessage ??
            'PLC rejected stored operator credentials. Please log in manually.',
      );
    }

    return const BiometricAuthResult(status: BiometricAuthStatus.success);
  }

  Future<void> clearBiometricEnrollment() async {
    await SecureCredentialStore.clearCredentials();
    _biometricEnrolled = false;
    notifyListeners();
  }

  void completePendingEnrollmentOffer() {
    if (!_pendingEnrollmentOffer) return;
    _pendingEnrollmentOffer = false;
    notifyListeners();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connStateSubscription?.cancel();
    _scanSubscription?.cancel();
    _statusSubscription?.cancel();
    _adapterSubscription?.cancel();
    _bleService.dispose();
    super.dispose();
  }
}
