import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

import 'package:tusker_trailer_rrc/utils/constants.dart';
import 'package:tusker_trailer_rrc/models/ble_connection_state.dart';

import 'package:tusker_trailer_rrc/widgets/device_card.dart';
import 'package:tusker_trailer_rrc/screens/settings_screen.dart';

import 'package:tusker_trailer_rrc/controllers/crane_controllers.dart';


class ConnectionScreen extends StatefulWidget {
  const ConnectionScreen({super.key});

  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen> {
  CraneController? _controller;
  String? _lastShownError;
  // Guards the one-time resumeScan() call so it only fires on the first
  // didChangeDependencies() invocation (i.e. when the screen first appears).
  bool _didAttemptResumeOnAppear = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = context.read<CraneController>();
    if (_controller != controller) {
      _controller?.removeListener(_onControllerChanged);
      _controller = controller;
      _controller!.addListener(_onControllerChanged);
    }
    if (!_didAttemptResumeOnAppear) {
      _didAttemptResumeOnAppear = true;
      // Post-frame so we never call resumeScan() inside a build/layout pass.
      // Also check for a pending auth-timeout notification — the flag is set
      // by CraneController when authenticate() times out, and may not have
      // been consumed yet if ConnectionScreen was not in the widget tree when
      // the timeout occurred (i.e. LoginScreen was the active screen).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        controller.resumeScan();
        if (controller.hasPendingAuthTimeoutNotification) {
          controller.consumeAuthTimeoutNotification();
          final authTimeoutError = 'PLC authentication timed out.';
          _lastShownError = authTimeoutError;
          _showAuthTimeoutSnackBar();
        }
      });
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_onControllerChanged);
    // Pause (not stop) the scan so the device cache and session deadline are
    // preserved. resumeScan() will restart the bursts when the screen reappears.
    _controller?.pauseScan();
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) return;

    // Auth-timeout check is INDEPENDENT of errorMessage — disconnect() clears
    // _errorMessage before ConnectionScreen becomes active, so the flag must be
    // detected here regardless of whether there is a current error string.
    // This fires on the very first notifyListeners() that reaches this listener
    // (e.g. the disconnected-state emission or the scan-start emission).
    if (_controller!.hasPendingAuthTimeoutNotification) {
      _controller!.consumeAuthTimeoutNotification();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showAuthTimeoutSnackBar();
      });
      return;
    }

    final error = _controller?.errorMessage;
    if (error != null && error != _lastShownError) {
      _lastShownError = error;

      final errorLower = error.toLowerCase();

      // Distinguish device-unreachable errors (range/power) from generic
      // connection errors so the operator gets an immediately actionable label.
      final bool isUnreachable =
          errorLower.contains('unreachable') ||
          errorLower.contains('timed out') ||
          errorLower.contains('timeout') ||
          errorLower.contains('out of range') ||
          errorLower.contains('offline');
      final String snackTitle =
          isUnreachable ? 'Device Unavailable' : 'Connection Error';

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              behavior: SnackBarBehavior.floating,
              backgroundColor: isUnreachable
                  ? ConnectionColors.warning
                  : ConnectionColors.error,
              margin: const EdgeInsets.all(16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              duration: const Duration(seconds: 4),
              dismissDirection: DismissDirection.horizontal,
              onVisible: () {},
              content: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(51),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isUnreachable
                          ? Icons.wifi_off_rounded
                          : Icons.error_outline_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          snackTitle,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          error,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withAlpha(230),
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.swipe_rounded,
                    color: Colors.white.withAlpha(102),
                    size: 16,
                  ),
                ],
              ),
            ),
          );
      });
    }
  }

  void _showAuthTimeoutSnackBar() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: ConnectionColors.warning,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          duration: const Duration(seconds: 5),
          dismissDirection: DismissDirection.horizontal,
          content: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(51),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.timer_off_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Authentication Timeout',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Device disconnected due to authentication timeout.',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Color(0xFFFFE0B2),
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: 8),
              Icon(
                Icons.swipe_rounded,
                color: Colors.white54,
                size: 16,
              ),
            ],
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<CraneController>();

    return Scaffold(
      // backgroundColor: ConnectionColors.background,
      body: controller.isInitializing
          ? const _InitializingView()
          : Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFFF7F9FC), ConnectionColors.background],
                ),
              ),
              child: SafeArea(
                child: Column(
                  children: [
                    _buildAppBar(controller),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                        child: Column(
                          children: [
                            _StatusBanner(controller: controller),
                            const SizedBox(height: 12),
                            _QuickStatusRow(controller: controller),
                            const SizedBox(height: 12),
                            Expanded(
                              child: _DevicesPanel(controller: controller),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
  // ═══════════════════════════════════════════════════════════
  // App Bar
  // ═══════════════════════════════════════════════════════════

  Widget _buildAppBar(CraneController controller) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 12, 12),
      decoration: BoxDecoration(
        color: ConnectionColors.surface,
        border: const Border(
          bottom: BorderSide(color: ConnectionColors.divider),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha((0.03 * 255).toInt()),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Logo & Title
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [ConnectionColors.primary, Color(0xFF225A95)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: ConnectionColors.primary.withAlpha(
                    (0.3 * 255).toInt(),
                  ),
                  blurRadius: 1,
                  offset: const Offset(1, 1),
                ),
              ],
            ),
            child: const Icon(
              Icons.precision_manufacturing_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Tusker HaulControl',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: ConnectionColors.textPrimary,
                    letterSpacing: -0.2,
                  ),
                ),
                Text(
                  'Trailer RRC · Device Connection',
                  style: TextStyle(
                    fontSize: 10.5,
                    color: ConnectionColors.textSecondary.withAlpha(
                      (0.8 * 255).toInt(),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Scan action button
          _buildScanButton(controller),
          const SizedBox(width: 4),

          // Settings
          Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              onTap: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: ConnectionColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: ConnectionColors.border),
                ),
                child: const Icon(
                  Icons.settings_rounded,
                  color: ConnectionColors.textSecondary,
                  size: 20,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScanButton(CraneController controller) {
    final isScanning = controller.isScanning;
    final isConnected = controller.isConnected;
    final canScan =
        !controller.isConnectionActive &&
        !controller.isCancellingConnection &&
        !isConnected &&
        controller.bluetoothReady &&
        controller.permissionsGranted;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        height: 38,
        child: isScanning
            ? OutlinedButton.icon(
                onPressed: controller.stopScan,
                icon: const Icon(Icons.stop_rounded, size: 14),
                label: const Text(
                  'STOP',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: ConnectionColors.error,
                  side: BorderSide(
                    color: ConnectionColors.error.withAlpha(
                      (0.5 * 255).toInt(),
                    ),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
              )
            : FilledButton.icon(
                onPressed: canScan ? controller.scanForDevices : null,
                icon: Icon(
                  isConnected
                      ? Icons.check_circle_rounded
                      : Icons.bluetooth_searching_rounded,
                  size: 15,
                ),
                label: Text(
                  isConnected ? 'ACTIVE' : 'SCAN',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: isConnected
                      ? ConnectionColors.connected
                      : ConnectionColors.primary,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: ConnectionColors.neutral.withAlpha(
                    (0.3 * 255).toInt(),
                  ),
                  disabledForegroundColor: ConnectionColors.textMuted,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  elevation: isConnected ? 0 : 2,
                  shadowColor: ConnectionColors.primary.withAlpha(
                    (0.4 * 255).toInt(),
                  ),
                ),
              ),
      ),
    );
  }
}

class _BannerData {
  const _BannerData({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.bg,
    required this.border,
    this.loading = false,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final Color bg;
  final Color border;
  final bool loading;
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.controller});
  final CraneController controller;

  @override
  Widget build(BuildContext context) {
    final d = _resolve(controller);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: d.bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: d.border),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            height: 28,
            child: d.loading
                ? Padding(
                    padding: const EdgeInsets.all(5),
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: d.color,
                    ),
                  )
                : Icon(d.icon, color: d.color, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  d.title,
                  style: TextStyle(
                    color: d.color,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.1,
                  ),
                ),
                if (d.subtitle.isNotEmpty) ...[
                  const SizedBox(height: 1),
                  Text(
                    d.subtitle,
                    style: const TextStyle(
                      color: ConnectionColors.textSecondary,
                      fontSize: 11.5,
                      height: 1.3,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          Container(
            width: 7,
            height: 7,
            margin: const EdgeInsets.only(left: 10),
            decoration: BoxDecoration(
              color: d.color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: d.color.withAlpha(60),
                  blurRadius: 4,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  _BannerData _resolve(CraneController c) {
    if (!c.permissionsGranted) {
      return const _BannerData(
        icon: Icons.key_rounded,
        title: 'Permissions Required',
        subtitle: 'Bluetooth & location permissions are needed.',
        color: ConnectionColors.warning,
        bg: ConnectionColors.warningBg,
        border: ConnectionColors.warningBorder,
      );
    }
    if (!c.bluetoothReady) {
      return const _BannerData(
        icon: Icons.bluetooth_disabled_rounded,
        title: 'Bluetooth Off',
        subtitle:
            'Enable Bluetooth to discover ${BLEConstants.scanNamePrefix}* controllers.',
        color: ConnectionColors.scanning,
        bg: ConnectionColors.scanningBg,
        border: ConnectionColors.scanningBorder,
      );
    }
    if (c.connectionState.status == BleConnectionStatus.error) {
      final msg = c.connectionState.message ?? 'An unexpected error occurred.';
      final msgLower = msg.toLowerCase();
      final bool isUnreachable =
          msgLower.contains('unreachable') ||
          msgLower.contains('timed out') ||
          msgLower.contains('timeout') ||
          msgLower.contains('out of range') ||
          msgLower.contains('offline');
      return _BannerData(
        icon: isUnreachable
            ? Icons.wifi_off_rounded
            : Icons.error_outline_rounded,
        title: isUnreachable ? 'Device Unavailable' : 'Connection Error',
        subtitle: msg,
        color: isUnreachable ? ConnectionColors.warning : ConnectionColors.error,
        bg: isUnreachable
            ? ConnectionColors.warningBg
            : ConnectionColors.errorBg,
        border: isUnreachable
            ? ConnectionColors.warningBorder
            : ConnectionColors.errorBorder,
      );
    }
    if (c.isConnected) {
      return _BannerData(
        icon: Icons.bluetooth_connected_rounded,
        title: 'Session Active',
        subtitle:
            'Connected to ${c.connectedDeviceName ?? BLEConstants.deviceName}.',
        color: ConnectionColors.connected,
        bg: ConnectionColors.connectedBg,
        border: ConnectionColors.connectedBorder,
      );
    }
    if (c.isCancellingConnection) {
      return _BannerData(
        icon: Icons.close_rounded,
        title: 'Cancelling Connection',
        subtitle:
            'Aborting connection to ${c.cancellingDevice?.name ?? "device"}...',
        color: ConnectionColors.textSecondary,
        bg: ConnectionColors.neutralBg,
        border: ConnectionColors.neutralBorder,
        loading: true,
      );
    }
    if (c.isConnecting) {
      return const _BannerData(
        icon: Icons.bluetooth_searching_rounded,
        title: 'Connecting',
        subtitle:
            'Establishing BLE link with device…',
        color: ConnectionColors.scanning,
        bg: ConnectionColors.scanningBg,
        border: ConnectionColors.scanningBorder,
        loading: true,
      );
    }
    if (c.isDiscoveringServices) {
      return _BannerData(
        icon: Icons.settings_ethernet_rounded,
        title: 'Discovering Services',
        subtitle:
            'Reading GATT table from ${c.connectedDeviceName ?? "device"}…',
        color: ConnectionColors.scanning,
        bg: ConnectionColors.scanningBg,
        border: ConnectionColors.scanningBorder,
        loading: true,
      );
    }
    if (c.isConfiguringNotifications) {
      return _BannerData(
        icon: Icons.notifications_active_rounded,
        title: 'Configuring Notifications',
        subtitle: 'Initializing communication channels...',
        color: ConnectionColors.scanning,
        bg: ConnectionColors.scanningBg,
        border: ConnectionColors.scanningBorder,
        loading: true,
      );
    }
    if (c.isInitializingSafeState) {
      return _BannerData(
        icon: Icons.shield_rounded,
        title: 'Initializing Safety State',
        subtitle: 'Applying safe PLC state...',
        color: ConnectionColors.scanning,
        bg: ConnectionColors.scanningBg,
        border: ConnectionColors.scanningBorder,
        loading: true,
      );
    }
 
    
    if (c.isAwaitingAuthentication || c.isAuthenticating) {
      return _BannerData(
        icon: Icons.lock_outline_rounded,
        title: 'Preparing Authentication',
        subtitle:
            'Establishing secure session with ${c.connectedDeviceName ?? "device"}...',
        color: ConnectionColors.scanning,
        bg: ConnectionColors.scanningBg,
        border: ConnectionColors.scanningBorder,
        loading: true,
      );
    }
    if (c.isScanning) {
      return const _BannerData(
        icon: Icons.radar_rounded,
        title: 'Scanning',
        subtitle:
            'Searching for ${BLEConstants.scanNamePrefix}* controllers nearby.',
        color: ConnectionColors.scanning,
        bg: ConnectionColors.scanningBg,
        border: ConnectionColors.scanningBorder,
        loading: true,
      );
    }
    return const _BannerData(
      icon: Icons.bluetooth_searching_rounded,
      title: 'Ready to Scan',
      subtitle: 'Tap SCAN to discover available crane controllers.',
      color: ConnectionColors.neutral,
      bg: ConnectionColors.neutralBg,
      border: ConnectionColors.neutralBorder,
    );
  }
}

class _QuickStatusRow extends StatelessWidget {
  const _QuickStatusRow({required this.controller});

  final CraneController controller;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _MiniStatCard(
            label: 'Devices',
            value: controller.isConnected
                ? '1'
                : controller.isConnectionActive
                ? '...'
                : '${controller.devices.length}',
            icon: Icons.memory_rounded,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _MiniStatCard(
            label: 'Bluetooth',
            value: controller.bluetoothReady ? 'ON' : 'OFF',
            icon: controller.bluetoothReady
                ? Icons.bluetooth_connected_rounded
                : Icons.bluetooth_disabled_rounded,
            valueColor: controller.bluetoothReady
                ? ConnectionColors.connected
                : ConnectionColors.error,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _MiniStatCard(
            label: 'Permission',
            value: controller.permissionsGranted ? 'OK' : 'WAIT',
            icon: controller.permissionsGranted
                ? Icons.verified_rounded
                : Icons.key_off_rounded,
            valueColor: controller.permissionsGranted
                ? ConnectionColors.connected
                : ConnectionColors.warning,
          ),
        ),
      ],
    );
  }
}

class _MiniStatCard extends StatelessWidget {
  const _MiniStatCard({
    required this.label,
    required this.value,
    required this.icon,
    this.valueColor = ConnectionColors.primary,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    // Calculate size based on screen width
    final screenWidth = MediaQuery.of(context).size.width;
    final double cardWidth = screenWidth < 600 ? 110 : 140;
    final double cardHeight = screenWidth < 600 ? 65 : 75;

    return Container(
      width: cardWidth,
      height: cardHeight,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: ConnectionColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ConnectionColors.border),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: ConnectionColors.textMuted),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 10,
                    color: ConnectionColors.textMuted,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 12,
                    color: valueColor,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    super.key,
    required this.label,
    required this.color,
    required this.bg,
    required this.border,
  });

  final String label;
  final Color color;
  final Color bg;
  final Color border;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: border),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
          color: color,
        ),
      ),
    );
  }
}

class _DevicesPanel extends StatefulWidget {
  const _DevicesPanel({required this.controller});

  final CraneController controller;

  @override
  State<_DevicesPanel> createState() => _DevicesPanelState();
}

class _DevicesPanelState extends State<_DevicesPanel>
    with TickerProviderStateMixin {
  late final AnimationController _spinCtrl;
  late final AnimationController _scanPulseCtrl;
  late final Animation<double> _scanPulseAnim;

  @override
  void initState() {
    super.initState();
    _spinCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
    _scanPulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
    _scanPulseAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _scanPulseCtrl, curve: Curves.easeInOut),
    );
    if (widget.controller.isScanning) _scanPulseCtrl.repeat();
  }

  @override
  void didUpdateWidget(_DevicesPanel old) {
    super.didUpdateWidget(old);
    final wasScanning = old.controller.isScanning;
    final isScanning = widget.controller.isScanning;
    if (isScanning && !wasScanning) {
      _scanPulseCtrl.repeat();
    } else if (!isScanning && wasScanning) {
      _scanPulseCtrl.stop();
      _scanPulseCtrl.reset();
    }
  }

  @override
  void dispose() {
    _spinCtrl.dispose();
    _scanPulseCtrl.dispose();
    super.dispose();
  }

  Future<void> _onRefresh() async {
    if (widget.controller.isScanning ||
        widget.controller.isConnectionActive ||
        widget.controller.isCancellingConnection ||
        widget.controller.isConnected) {
      return;
    }
    await _spinCtrl.forward(from: 0);
    widget.controller.scanForDevices();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final blocked = c.isScanning || c.isConnectionActive || c.isCancellingConnection || c.isConnected;
    final count = c.isConnected ? 1 : c.devices.length;
    return Container(
      decoration: BoxDecoration(
        color: ConnectionColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ConnectionColors.border),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Text(
                  'NEARBY DEVICES',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                    color: ConnectionColors.textMuted,
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: c.isScanning
                      ? const _Badge(
                          key: ValueKey('scanning'),
                          label: 'SCANNING',
                          color: ConnectionColors.scanning,
                          bg: ConnectionColors.scanningBg,
                          border: ConnectionColors.scanningBorder,
                        )
                      : count > 0
                      ? _Badge(
                          key: ValueKey('count-$count'),
                          label: '$count found',
                          color: ConnectionColors.primary,
                          bg: ConnectionColors.primarySoft,
                          border: ConnectionColors.border,
                        )
                      : const SizedBox.shrink(key: ValueKey('none')),
                ),
                const Spacer(),
                Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  child: InkWell(
                    onTap: blocked ? null : _onRefresh,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: ConnectionColors.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: ConnectionColors.border),
                      ),
                      child: Center(
                        child: RotationTransition(
                          turns: _spinCtrl,
                          child: Icon(
                            Icons.refresh_rounded,
                            size: 15,
                            color: blocked
                                ? ConnectionColors.border
                                : ConnectionColors.textMuted,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: ConnectionColors.divider),
          // Subtle scan-sweep bar — visible only while scanning so users
          // perceive continuous activity even during the radio pause cycle.
          AnimatedBuilder(
            animation: _scanPulseAnim,
            builder: (_, _) {
              final scanning = widget.controller.isScanning;
              if (!scanning) return const SizedBox.shrink();
              return SizedBox(
                height: 2,
                child: CustomPaint(
                  painter: _ScanSweepPainter(progress: _scanPulseAnim.value),
                  size: const Size(double.infinity, 2),
                ),
              );
            },
          ),
          Expanded(
            child: Stack(
              children: [
                ShaderMask(
                  shaderCallback: (Rect bounds) {
                    return LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.white.withAlpha(100),
                        Colors.white.withAlpha(255), // Bottom: fully visible
                      ],
                    ).createShader(bounds);
                  },
                  blendMode: BlendMode.dstOut,
                  child: const Image(
                    image: AssetImage('assets/images/app_icon1.png'),
                    fit: BoxFit.cover,
                  ),
                ),
                // assetImages('assets/images/app_icon1.png',filterQuality: FilterQuality.high, fit: BoxFit.cover,),
                _buildBody(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Returns a short label for the current BLE pipeline stage, shown inside
  /// the inline connecting pill on the target device card.
  String _pipelineStageLabel(CraneController c) {
    if (c.isDiscoveringServices) return 'Services…';
    if (c.isConfiguringNotifications) return 'Channels…';
    if (c.isInitializingSafeState) return 'Safety…';
    if (c.isConnected) return 'Ready…';
    return 'Linking…';
  }

  Widget _buildBody() {
    final c = widget.controller;

    // During cancellation, connectedDevice is cleared by the service before
    // emitting disconnected. Fall back to the cached cancellingDevice so the
    // ConnectedDeviceCard stays stable throughout the async teardown window.
    final targetDevice =
        c.connectionState.connectedDevice ?? c.cancellingDevice;

    if (c.isConnected || c.isConnectionActive || c.isCancellingConnection) {
      if (targetDevice == null) {
        final sorted = [...c.devices]..sort((a, b) => b.rssi.compareTo(a.rssi));
        if (sorted.isEmpty) {
          return const _EmptyDeviceState(
            key: ValueKey('empty-guard'),
            scanning: false,
          );
        }
        return ListView.separated(
          key: const ValueKey('guard-devices-list'),
          padding: const EdgeInsets.all(14),
          itemCount: sorted.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (_, i) => AvailableDeviceCard(
            key: ValueKey(sorted[i].id),
            device: sorted[i],
            connecting: true,
            onConnect: () {},
          ),
        );
      }

      // All scanned devices except the target (already shown at top).
      final others = c.devices.where((d) => d.id != targetDevice.id).toList();

      return ListView.separated(
        key: const ValueKey('connecting-list'),
        padding: const EdgeInsets.all(14),
        itemCount: 1 + others.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, i) {
          if (i == 0) {
            return ConnectedDeviceCard(
              key: ValueKey(targetDevice.id),
              device: targetDevice,
              isCancelling: c.isCancellingConnection,
              onCancel: c.cancelConnecting,
            );
          }
          final d = others[i - 1];
          return AvailableDeviceCard(
            key: ValueKey(d.id),
            device: d,
            connecting: true,
            onConnect: () {},
          );
        },
      );
    }

    // ── Idle / scanning state ──────────────────────────────────────────────
    if (c.devices.isEmpty) {
      return _EmptyDeviceState(
        key: const ValueKey('empty-idle'),
        scanning: c.isScanning,
      );
    }

    final sorted = [...c.devices]..sort((a, b) => b.rssi.compareTo(a.rssi));
    return ListView.separated(
      key: const ValueKey('devices-list'),
      padding: const EdgeInsets.all(14),
      itemCount: sorted.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, i) => AvailableDeviceCard(
        key: ValueKey(sorted[i].id),
        device: sorted[i],
        connecting: false,
        onConnect: () => c.connectToDevice(sorted[i]),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// Empty State View
// ═══════════════════════════════════════════════════════════

class _EmptyDeviceState extends StatefulWidget {
  const _EmptyDeviceState({required this.scanning, super.key});

  final bool scanning;

  @override
  State<_EmptyDeviceState> createState() => _EmptyDeviceStateState();
}

class _EmptyDeviceStateState extends State<_EmptyDeviceState>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;
  late final Animation<double> _scaleAnim;
  late final Animation<double> _opacityAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    _scaleAnim = Tween<double>(begin: 0.75, end: 1.45).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeOut),
    );
    _opacityAnim = Tween<double>(begin: 0.55, end: 0.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeOut),
    );
    if (widget.scanning) _pulseCtrl.repeat();
  }

  @override
  void didUpdateWidget(_EmptyDeviceState old) {
    super.didUpdateWidget(old);
    if (widget.scanning && !old.scanning) {
      _pulseCtrl.repeat();
    } else if (!widget.scanning && old.scanning) {
      _pulseCtrl.stop();
      _pulseCtrl.reset();
    }
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (widget.scanning) ...[
              SizedBox(
                width: 80,
                height: 80,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Outer pulse ring
                    AnimatedBuilder(
                      animation: _pulseCtrl,
                      builder: (_, _) => Opacity(
                        opacity: _opacityAnim.value,
                        child: Transform.scale(
                          scale: _scaleAnim.value,
                          child: Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: ConnectionColors.scanning,
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Center radar icon
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: ConnectionColors.scanningBg,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: ConnectionColors.scanningBorder,
                        ),
                      ),
                      child: const Icon(
                        Icons.radar_rounded,
                        color: ConnectionColors.scanning,
                        size: 30,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ] else
              const SizedBox(height: 14),
            Text(
              widget.scanning ? 'Scanning for Devices...' : 'No Controllers Found',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: ConnectionColors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              widget.scanning
                  ? 'Looking for ${BLEConstants.scanNamePrefix}* nearby.'
                  : 'Power on the PLC14 controller and keep it in BLE range.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: ConnectionColors.textMuted,
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// Scan sweep bar painter
// ═══════════════════════════════════════════════════════════

/// Renders a 2-pixel-high gradient sweep that travels left→right on repeat.
/// Gives a radar-sweep feel that bridges visual gaps between BLE burst cycles.
class _ScanSweepPainter extends CustomPainter {
  const _ScanSweepPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    const sweepWidth = 120.0;
    final center = progress * (size.width + sweepWidth) - sweepWidth / 2;
    final left = center - sweepWidth / 2;
    // final right = center + sweepWidth / 2;

    final rect = Rect.fromLTWH(left, 0, sweepWidth, size.height);
    final paint = Paint()
      ..shader = LinearGradient(
        colors: [
          ConnectionColors.scanning.withAlpha(0),
          ConnectionColors.scanning.withAlpha(200),
          ConnectionColors.scanning.withAlpha(0),
        ],
      ).createShader(rect);

    canvas.drawRect(rect, paint);
  }

  @override
  bool shouldRepaint(_ScanSweepPainter old) => old.progress != progress;
}

// ═══════════════════════════════════════════════════════════
// Initializing View
// ═══════════════════════════════════════════════════════════

class _InitializingView extends StatelessWidget {
  const _InitializingView();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFF7F9FC), ConnectionColors.background],
        ),
      ),
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              color: ConnectionColors.primary,
              strokeWidth: 2.5,
            ),
            SizedBox(height: 18),
            Text(
              'Preparing BLE Runtime',
              style: TextStyle(
                color: ConnectionColors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: 5),
            Text(
              'Checking Bluetooth and permissions...',
              style: TextStyle(
                color: ConnectionColors.textMuted,
                fontSize: 12.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
