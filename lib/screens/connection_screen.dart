import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

import 'package:tusker_trailer_rrc/utils/constants.dart';
import 'package:tusker_trailer_rrc/models/ble_scan_device.dart';

import 'package:tusker_trailer_rrc/services/ble_service.dart';
import 'package:tusker_trailer_rrc/controllers/crane_controllers.dart';

import 'package:tusker_trailer_rrc/screens/settings_screen.dart';

class ConnectionScreen extends StatefulWidget {
  const ConnectionScreen({super.key});

  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen> {
  CraneController? _controller;
  String? _lastShownError;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = context.read<CraneController>();
    if (_controller != controller) {
      _controller?.removeListener(_onControllerChanged);
      _controller = controller;
      _controller!.addListener(_onControllerChanged);
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    final error = _controller?.errorMessage;
    if (error != null && error != _lastShownError) {
      _lastShownError = error;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              behavior: SnackBarBehavior.floating,
              backgroundColor: ConnectionColors.error,
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
                    child: const Icon(
                      Icons.error_outline_rounded,
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
                        const Text(
                          'Connection Error',
                          style: TextStyle(
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
      return _BannerData(
        icon: Icons.error_outline_rounded,
        title: 'Connection Error',
        subtitle: c.connectionState.message ?? 'An unexpected error occurred.',
        color: ConnectionColors.error,
        bg: ConnectionColors.errorBg,
        border: ConnectionColors.errorBorder,
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
    if (c.isConnecting) {
      return _BannerData(
        icon: Icons.bluetooth_searching_rounded,
        title: 'Connecting',
        subtitle:
            'Linking to ${c.connectionState.connectedDevice?.name ?? "device"}...',
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
    with SingleTickerProviderStateMixin {
  late final AnimationController _spinCtrl;

  @override
  void initState() {
    super.initState();
    _spinCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
  }

  @override
  void dispose() {
    _spinCtrl.dispose();
    super.dispose();
  }

  Future<void> _onRefresh() async {
    if (widget.controller.isScanning ||
        widget.controller.isConnectionActive ||
        widget.controller.isConnected) {
      return;
    }
    await _spinCtrl.forward(from: 0);
    widget.controller.scanForDevices();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final blocked = c.isScanning || c.isConnectionActive || c.isConnected;
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
          Expanded(
            child: Stack(
              children: [
                ShaderMask(
                  shaderCallback: (Rect bounds) {
                    return LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.white.withAlpha(
                          100,
                        ), 
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

  Widget _buildBody() {
    final c = widget.controller;

    final targetDevice = c.connectionState.connectedDevice;

    if (c.isConnected || c.isConnectionActive) {
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
          itemBuilder: (_, i) => _AvailableDeviceCard(
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
            return _ConnectedDeviceCard(
              key: ValueKey(targetDevice.id),
              device: targetDevice,
              isConnecting: c.isConnectionActive,
              onDisconnect: c.disconnect,
            );
          }
          final d = others[i - 1];
          return _AvailableDeviceCard(
            key: ValueKey(d.id),
            device: d,
            // Disable all other cards while a connection is in progress.
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
      itemBuilder: (_, i) => _AvailableDeviceCard(
        key: ValueKey(sorted[i].id),
        device: sorted[i],
        connecting: false,
        onConnect: () => c.connectToDevice(sorted[i]),
      ),
    );
  }
}

class _AvailableDeviceCard extends StatelessWidget {
  const _AvailableDeviceCard({
    super.key,
    required this.device,
    required this.connecting,
    required this.onConnect,
  });

  final BleScanDevice device;
  final bool connecting;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: connecting ? 0.45 : 1.0,
      duration: const Duration(milliseconds: 250),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: ConnectionColors.surfaceAlt,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: connecting
                ? ConnectionColors.border.withAlpha(120)
                : ConnectionColors.border,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: ConnectionColors.primarySoft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.developer_board_rounded,
                color: ConnectionColors.primary,
                size: 23,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    device.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: ConnectionColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    device.id,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: ConnectionColors.textMuted,
                      fontSize: 11,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(height: 8),
                  _SignalPill(rssi: device.rssi, label: device.signalLabel),
                ],
              ),
            ),
            // Hide the connect button while another device is connecting.
            if (!connecting) ...[
              const SizedBox(width: 8),
              SizedBox(
                width: 92,
                child: FilledButton(
                  onPressed: onConnect,
                  style: FilledButton.styleFrom(
                    backgroundColor: ConnectionColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    textStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                    ),
                  ),
                  child: const Text('CONNECT'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SignalPill extends StatelessWidget {
  const _SignalPill({required this.rssi, required this.label});

  final int rssi;
  final String label;

  @override
  Widget build(BuildContext context) {
    final tone = rssi >= -68
        ? ConnectionColors.connected
        : rssi >= -80
        ? ConnectionColors.warning
        : ConnectionColors.error;

    return Row(
      children: [
        Expanded(
          child: Text(
            '$rssi dBm ',
            style: TextStyle(
              color: tone,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 8),
        // SizedBox(
        //   width: 36,
        //   child: LinearProgressIndicator(
        //     value: barValue,
        //     minHeight: 4,
        //     borderRadius: BorderRadius.circular(4),
        //     backgroundColor: tone.withValues(alpha: 0.22),
        //     valueColor: AlwaysStoppedAnimation<Color>(tone),
        //   ),
        // ),
      ],
    );
  }
}

class _ConnectedDeviceCard extends StatelessWidget {
  // Dedicated card for the actively connected device, showing extra details and a disconnect action.
  const _ConnectedDeviceCard({
    super.key,
    required this.device,
    required this.isConnecting,
    required this.onDisconnect,
  });

  final BleScanDevice device;
  final bool isConnecting;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ConnectionColors.connectedBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ConnectionColors.connectedBorder),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: ConnectionColors.connected.withAlpha(30),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.developer_board_rounded,
                  color: ConnectionColors.connected,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      device.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: ConnectionColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      device.id,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: ConnectionColors.textMuted,
                        fontSize: 11,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
              // Status / Connecting indicator
              if (isConnecting)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: ConnectionColors.scanning,
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: ConnectionColors.connected.withAlpha(25),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _PulsingDot(size: 7, color: ConnectionColors.connected),
                      SizedBox(width: 6),
                      Text(
                        'LIVE',
                        style: TextStyle(
                          color: ConnectionColors.connected,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),

          if (!isConnecting) ...[
            const SizedBox(height: 14),

            // ── RSSI Bar
            _RSSIBar(rssi: device.rssi),

            const SizedBox(height: 14),

            // ── Disconnect Button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onDisconnect,
                icon: const Icon(Icons.bluetooth_disabled_rounded, size: 16),
                label: const Text('DISCONNECT'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: ConnectionColors.error,
                  side: BorderSide(color: ConnectionColors.error.withAlpha(80)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                  backgroundColor: ConnectionColors.error.withAlpha(10),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// RSSI Bar — Clean visual signal indicator
// ═══════════════════════════════════════════════════════════

class _RSSIBar extends StatelessWidget {
  const _RSSIBar({required this.rssi});

  final int rssi;

  double get _signalStrength => ((rssi + 100) / 70).clamp(0.0, 1.0);

  int get _filledBars {
    if (_signalStrength >= 0.85) return 5;
    if (_signalStrength >= 0.65) return 4;
    if (_signalStrength >= 0.45) return 3;
    if (_signalStrength >= 0.25) return 2;
    if (_signalStrength >= 0.1) return 1;
    return 0;
  }

  Color get _signalColor {
    if (_signalStrength >= 0.65) return ConnectionColors.connected;
    if (_signalStrength >= 0.35) return ConnectionColors.warning;
    return ConnectionColors.error;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _signalColor.withAlpha(20),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.signal_cellular_alt_rounded,
              color: _signalColor,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          // Signal bars
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Bars row
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: List.generate(5, (index) {
                    final isFilled = index < _filledBars;
                    final barHeight = 6.0 + (index * 4.0);
                    return Container(
                      width: 8,
                      height: barHeight,
                      margin: const EdgeInsets.only(right: 4),
                      decoration: BoxDecoration(
                        color: isFilled
                            ? _signalColor
                            : ConnectionColors.border.withAlpha(150),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 4),
                Text(
                  '$rssi dBm',
                  style: TextStyle(
                    color: _signalColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'monospace',
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Signal percentage
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _signalColor.withAlpha(20),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${(_signalStrength * 100).toInt()}%',
              style: TextStyle(
                color: _signalColor,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// Pulsing Dot
// ═══════════════════════════════════════════════════════════

class _PulsingDot extends StatefulWidget {
  const _PulsingDot({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _animation = Tween<double>(
      begin: 0.5,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            color: widget.color.withAlpha((255 * _animation.value).toInt()),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: widget.color.withAlpha((77 * _animation.value).toInt()),
                blurRadius: 4 * _animation.value,
                spreadRadius: 1,
              ),
            ],
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════
// Empty State View
// ═══════════════════════════════════════════════════════════

class _EmptyDeviceState extends StatelessWidget {
  const _EmptyDeviceState({required this.scanning, super.key});

  final bool scanning;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Container(
            //   width: 74,
            //   height: 74,
            //   decoration: BoxDecoration(
            //     color: ConnectionColors.primarySoft,
            //     borderRadius: BorderRadius.circular(24),
            //     border: Border.all(color: ConnectionColors.border),
            //   ),
            //   child: Icon(
            //     scanning ? Icons.radar_rounded : Icons.bluetooth_rounded,
            //     color: scanning
            //         ? ConnectionColors.scanning
            //         : ConnectionColors.textMuted,
            //     size: 36,
            //   ),
            // ),
            const SizedBox(height: 14),
            Text(
              scanning ? 'Scanning for Devices...' : 'No Controllers Found',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: ConnectionColors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              scanning
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
