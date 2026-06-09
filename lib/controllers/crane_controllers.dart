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

  // ── BLE write serializer ──────────────────────────────────────────────────
  // Prevents BLE queue flooding when commands arrive faster than writes complete.
  // Only one write is in flight at a time; the latest pending command wins.
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
  // When true, currentScreen returns AppScreen.authentication even though
  // the BLE session has already authenticated. This holds the LoginScreen
  // in view until the biometric-enrollment offer dialog has been resolved.
  bool _pendingEnrollmentOffer = false;
  String? _sessionEmail;
  String? _errorMessage;
  String _savedEmail = '';
  String _savedPassword = '';
  String _deviceId = '';
  // True when the last auth attempt was rejected because this device is not
  // in the PLC trusted-device registry. Used to show a targeted UI message.
  bool _deviceTrustRejected = false;
  final Set<HoistDirection> _activeDirectionalHolds = <HoistDirection>{};
  HoistDirection? _verticalDirectionLock;
  HoistDirection? _horizontalDirectionLock;
  bool _deadmanHeld = false;

  // Tracks a user-initiated cancellation of an in-progress connect attempt.
  // Separate from BLE transport state so the UI can show "Cancelling..."
  // during the async teardown window without flickering back to idle first.
  bool _cancellingConnection = false;
  BleScanDevice? _cancellingDevice;

  // Set to true when authenticate() resolves with BleAuthOutcome.timedOut so
  // ConnectionScreen can show a targeted snackbar when it next appears, even
  // if no further notifyListeners() call is triggered after the screen swap.
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
  /// True while the biometric-enrollment offer dialog is pending in the
  /// authentication screen. Causes [currentScreen] to stay on
  /// [AppScreen.authentication] until [completePendingEnrollmentOffer] is
  /// called.
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

  /// True during any connection phase before navigation completes:
  /// transport connecting, transport connected (handshake pending),
  /// awaiting authentication, or mid-authentication.
  /// Use this — not [isConnecting] — to gate UI and scan updates so the
  /// device list and card never revert to idle state during the handshake.
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

  /// The unique permanent identity of this app installation, loaded at startup.
  /// Included in every authentication payload for PLC trusted-device validation.
  String get deviceId => _deviceId;

  /// True when the last authentication attempt was rejected because this
  /// device is not registered in the PLC trusted-device list.
  bool get isDeviceTrustRejected => _deviceTrustRejected;

  /// True while a user-initiated cancellation of a connecting attempt is
  /// in progress. Guards the UI against flickering back to the idle device
  /// list before the async BLE teardown completes.
  bool get isCancellingConnection => _cancellingConnection;

  /// True when an authentication timeout occurred and ConnectionScreen has not
  /// yet shown the corresponding snackbar. Consumed (reset to false) by
  /// [consumeAuthTimeoutNotification] once the snackbar has been displayed.
  bool get hasPendingAuthTimeoutNotification => _pendingAuthTimeoutSnack;

  /// Acknowledges and clears the pending auth-timeout snackbar notification.
  void consumeAuthTimeoutNotification() {
    if (_pendingAuthTimeoutSnack) {
      _pendingAuthTimeoutSnack = false;
    }
  }

  /// The device that was being connected when the user tapped Cancel.
  /// Preserved so the ConnectedDeviceCard stays visible and stable during
  /// the brief async teardown window after [connectionState.connectedDevice]
  /// is cleared by the BLE service.
  BleScanDevice? get cancellingDevice => _cancellingDevice;


  // ── LED indicator states ─────────────────────────────────────────────────
  // Emergency indicator must represent the active lockout condition only.
  bool get ledEstop => _estopLatched;
  bool get ledUp => _activeCommand.up && !_activeCommand.estop;
  bool get ledDown => _activeCommand.down && !_activeCommand.estop;
  bool get ledLeft => _activeCommand.left && !_activeCommand.estop;
  bool get ledRight => _activeCommand.right && !_activeCommand.estop;
  bool get ledFast =>
      _activeCommand.speed == HoistSpeed.fast && !_activeCommand.estop;

  // ── Connected device info ─────────────────────────────────────────────────
  String? get connectedDeviceName => _transportConnState.connectedDevice?.name;
  int? get connectedDeviceRssi => _transportConnState.connectedDevice?.rssi;
  PlcType? get connectedDevicePlcType =>
      _transportConnState.connectedDevice?.plcType;

  /// Device name with PLC model appended when known (e.g. "RRC_PLC1 • PLC14").
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
    // When the enrollment-offer dialog is pending we stay on the
    // authentication screen so the dialog never bleeds into ControlScreen.
    BleConnectionStatus.authenticated =>
      _pendingEnrollmentOffer ? AppScreen.authentication : AppScreen.control,
    // Transport connected: immediately hand off to auth screen so the user
    // never sees the connection screen flicker back to idle before navigation.
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

  // Initialization and Cleanup //////////////////////////////////////////////////////////////////////////////
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
      // Load device identity and saved credentials concurrently.
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
        _pendingEnrollmentOffer = false; // Clean up any stale offer state.
        _deviceTrustRejected = false;
      } else if (snapshot.status == BleConnectionStatus.authenticated &&
          previousStatus != BleConnectionStatus.authenticated) {
        unawaited(ensureControlEntryEmergencyLock());
        // If biometrics are available but not yet enrolled, gate the screen
        // transition so the UI can present the enrollment dialog first.
        if (_biometricAvailable && !_biometricEnrolled) {
          _pendingEnrollmentOffer = true;
        }
      }
      notifyListeners();
    });

    _scanSubscription = _bleService.scanStream.listen((devices) {
      // Don't clobber the device list while a connection is active — the UI
      // shows the cached list alongside the connecting card so it must stay
      // populated until the user explicitly disconnects.
      // isConnectionActive covers connecting, awaitingAuthentication, and
      // authenticating so the guard holds across the entire handshake.
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

  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////
  /// Device Scanning and Connection //////////////////////////////////////////////////////////////////////////////////
  /// Pauses the active scan session without clearing the device cache.
  /// Called by [ConnectionScreen] when it is removed from the widget tree
  /// (navigation away) so the BLE radio is not left scanning on a dead screen.
  Future<void> pauseScan() async {
    await _bleService.pauseScan();
  }

  /// Resumes a previously paused scan session.
  /// Called by [ConnectionScreen] when it first appears in the widget tree.
  /// No-op if no session is active or if the session expired while paused.
  Future<void> resumeScan() async {
    if (!bluetoothReady || !permissionsGranted) return;
    await _bleService.resumeScan();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      // App moved to background — stop the radio burst to save battery.
      _bleService.pauseScan();
    } else if (state == AppLifecycleState.resumed) {
      // App returned to foreground — resume only if user is on the scan screen.
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

  /// Cancels an in-progress connection attempt (connecting state only).
  /// Does NOT perform the full disconnect teardown — no safe-state write,
  /// no auth/status subscription cleanup (those do not exist yet during
  /// the connecting phase). Returns the app cleanly to the idle scan state.
  ///
  /// Idempotent — repeated calls while cancellation is in progress are ignored.
  Future<void> cancelConnecting() async {
    if (_cancellingConnection) return; // prevent duplicate/rapid-tap calls
    _errorMessage = null;
    // Snapshot before the service clears connectedDevice so the UI card
    // stays stable throughout the async teardown window.
    _cancellingDevice = _transportConnState.connectedDevice;
    _cancellingConnection = true;
    notifyListeners(); // → UI immediately shows "Cancelling..." state
    await _bleService.cancelConnecting();
    _cancellingConnection = false;
    _cancellingDevice = null;
    notifyListeners(); // → clean state; UI returns to device list
  }

  void setRememberCredentials(bool value) {
    _rememberCredentials = value;
    notifyListeners();
  }

  Future<void> disconnect() async {
    _errorMessage = null;

    // Best-effort safe stop before disconnecting transport.
    if (isConnected && !_estopLatched) {
      try {
        await _sendCommand(PlcOutputCommand.idle());
      } catch (_) {
        // Ignore: transport teardown below remains the final safety path.
      }
    }

    await _bleService.disconnect();
    notifyListeners();
  }

  Future<void> stopScan() async {
    _errorMessage = null;
    await _bleService.stopScan();
    // State transitions via _connStateSubscription when startScan() resolves.
  }

  // ── Command helpers ───────────────────────────────────────────────────────

  Future<void> _sendCommand(PlcOutputCommand command) async {
    _activeCommand = command;
    notifyListeners();
    final bytes = command.wireBytes.toList();
    if (_commandInFlight) {
      // Replace whatever was pending — latest command wins.
      _pendingCommandBytes = bytes;
      return;
    }
    await _writeBytes(bytes);
  }

  Future<void> _writeBytes(List<int> bytes) async {
    _commandInFlight = true;
    try {
      await _bleService.writeDigital(bytes);
      // Drain at most one pending command queued while this write was in flight.
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
    // E-stop bypasses the serializer: preempts any pending command and sends
    // immediately after the current in-flight write (or right now if idle).
    _pendingCommandBytes = bytes;
    if (!_commandInFlight) {
      final pending = _pendingCommandBytes!;
      _pendingCommandBytes = null;
      await _writeBytes(pending);
    }
    // If a write is in flight it will drain _pendingCommandBytes next,
    // ensuring the E-stop is the very next thing written.
  }

  /// Immediately latches E-stop and terminates the BLE session.
  /// Called when the device leaves foreground or a hardware safety button fires.
  /// The caller does not need to await — fire-and-forget is safe here.
  Future<void> triggerSafeDisconnect() async {
    if (!isConnected) return;
    // Latch state synchronously so the UI reflects the emergency immediately.
    _estopLatched = true;
    _deadmanHeld = false;
    _clearDirectionalHolds(notify: false);
    _activeCommand = PlcOutputCommand.emergencyStop();
    // Discard any queued motion command so it cannot race the safe-state write.
    _pendingCommandBytes = null;
    notifyListeners();
    // BleService.disconnect() writes emergencyStop wireBytes before tearing
    // down the BLE link, giving the PLC one last chance to enter safe state.
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

    // Ensure device identity is available (getOrCreate is idempotent).
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

  /// Checks and caches device biometric availability and app-level enrollment.
  ///
  /// Called during [initialize] and after any enrollment change. Safe to call
  /// at any time — reads only from the local keystore, no BLE I/O.
  Future<void> checkBiometricStatus() async {
    _biometricAvailable = await BiometricService.isAvailableAndEnrolled();
    _biometricEnrolled =
        _biometricAvailable && await SecureCredentialStore.hasCredentials();
    notifyListeners();
  }

  /// Enrolls biometric credentials for this device after a successful manual
  /// PLC-authenticated login.
  ///
  /// Returns true on success, false if the Keystore write fails.
  /// MUST only be called after [authenticate] has returned true.
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

  /// Authenticates the operator via device biometrics, then runs the full
  /// PLC authentication pipeline with the stored operator credentials.
  ///
  /// The PLC ALWAYS validates the operator — biometric authentication is a
  /// local convenience layer only. It never bypasses PLC-side validation,
  /// single-operator enforcement, or the AES-GCM encrypted auth pipeline.
  ///
  /// Returns a [BiometricAuthResult] describing the outcome.
  Future<BiometricAuthResult> authenticateWithBiometrics() async {
    if (!_biometricAvailable || !_biometricEnrolled) {
      return const BiometricAuthResult(
        status: BiometricAuthStatus.notAvailable,
        message: 'Biometric authentication is not configured on this device.',
      );
    }

    // Step 1 — Local biometric verification (device biometric hardware gate).
    final biometricResult = await BiometricService.authenticate();
    if (!biometricResult.isSuccess) {
      return biometricResult;
    }

    // Step 2 — Retrieve credentials from hardware-backed secure storage.
    //           Only reachable after successful biometric verification above.
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

    // Step 3 — Full PLC authentication via AES-GCM encrypted pipeline.
    //           PLC validates the operator, enforces single-operator policy,
    //           and returns AUTH_OK / AUTH_FAIL as normal.
    _errorMessage = null;
    final plcSuccess = await authenticate(
      email: credentials.email,
      password: credentials.password,
    );

    if (!plcSuccess) {
      // PLC rejected stored credentials — they are stale or revoked.
      // Clear enrollment so the operator must log in manually to re-enroll.
      await SecureCredentialStore.clearCredentials();
      _biometricEnrolled = false;
      notifyListeners();
      return BiometricAuthResult(
        status: BiometricAuthStatus.failure,
        message: _errorMessage ??
            'PLC rejected stored operator credentials. Please log in manually.',
      );
    }

    return const BiometricAuthResult(status: BiometricAuthStatus.success);
  }

  /// Clears stored biometric credentials and resets enrollment state.
  ///
  /// Call when an operator explicitly revokes biometric access.
  Future<void> clearBiometricEnrollment() async {
    await SecureCredentialStore.clearCredentials();
    _biometricEnrolled = false;
    notifyListeners();
  }

  /// Releases the enrollment-offer screen hold, allowing the app to navigate
  /// from the authentication screen to the control screen.
  ///
  /// Must be called by the UI exactly once after the biometric enrollment
  /// dialog has been resolved — whether accepted or dismissed.
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
