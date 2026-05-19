import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:provider/provider.dart';
import 'package:vibration/vibration.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'package:tusker_trailer_rrc/utils/constants.dart';
import 'package:tusker_trailer_rrc/controllers/crane_controllers.dart';
import 'package:tusker_trailer_rrc/models/plc_output_command.dart';
import 'package:tusker_trailer_rrc/widgets/estop_swipe_button.dart';

// ═══════════════════════════════════════════════════════════════
// ControlScreen — Deadman Hold-to-Run Industrial Controls
//
// Behavior:
//   • UP button pressed  → Output ON [0,1,0]
//   • UP button released → Output OFF [0,0,0]
//   • DOWN button pressed  → Output ON [0,0,1]
//   • DOWN button released → Output OFF [0,0,0]
//
// Safety Rules:
//   • Only ONE direction active at any time
//   • UP active → DOWN disabled
//   • DOWN active → UP disabled
//   • Mutual exclusion enforced in hardware AND software
//   • Both buttons released → IDLE
// ═══════════════════════════════════════════════════════════════

class ControlScreen extends StatefulWidget {
  const ControlScreen({super.key});

  @override
  State<ControlScreen> createState() => _ControlScreenState();
}

class _ControlScreenState extends State<ControlScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _pulseController;
  CraneController? _craneController;
  bool _wasDisconnected = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // ── Operational lock-down ─────────────────────────────────────────────
    // Enter sticky immersive mode: hides the system navigation bar and
    // status bar. Android will show the nav bar temporarily on the first
    // swipe from the bottom edge, but it auto-hides again — meaning one
    // accidental swipe no longer immediately triggers Home/Recents.
    // This is the strongest gesture guard available to non-device-owner apps.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    // Keep the screen alive so the display never times out mid-operation.
    WakelockPlus.enable();
    // ─────────────────────────────────────────────────────────────────────

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final controller = context.read<CraneController>();
      _craneController = controller;
      _wasDisconnected = controller.isDisconnected;
      controller.addListener(_onControllerChange);
      unawaited(controller.ensureControlEntryEmergencyLock());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Restore normal system UI and release the wakelock when leaving.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    WakelockPlus.disable();
    _pulseController.dispose();
    _craneController?.removeListener(_onControllerChange);
    super.dispose();
  }

  /// Re-enter immersive mode whenever the app returns to the foreground.
  /// Handles the case where the operator briefly switched to another app
  /// (e.g., via the Recent Apps panel) and came back.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (!mounted) return;
    if (state == AppLifecycleState.resumed) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      WakelockPlus.enable();
    }
  }

  void _onControllerChange() {
    final controller = _craneController;
    if (!mounted || controller == null) return;

    final isDisconnected = controller.isDisconnected;
    if (isDisconnected && !_wasDisconnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(controller.errorMessage ?? 'Disconnected from PLC14'),
          backgroundColor: AppColors.eStopColor,
          duration: const Duration(seconds: 3),
        ),
      );
    }

    _wasDisconnected = isDisconnected;
  }

  // ═══════════════════════════════════════════════════════════
  // Deadman Hold-to-Run Handlers
  // ═══════════════════════════════════════════════════════════

  /// UP button pressed — request UP hold via centralized state engine
  Future<void> _onUpPressed() async {
    final controller = _craneController;
    if (controller == null) return;
    if (controller.estopLatched || !controller.isConnected) return;

    final accepted = await controller.setDirectionalHold(
      direction: HoistDirection.up,
      pressed: true,
      fast: false,
    );
    if (!accepted) return;

    HapticFeedback.mediumImpact();
    Vibration.vibrate(duration: 30, amplitude: 128);
  }

  /// UP button released — clear UP hold via centralized state engine
  Future<void> _onUpReleased() async {
    final controller = _craneController;
    if (controller == null) return;

    await controller.setDirectionalHold(
      direction: HoistDirection.up,
      pressed: false,
      fast: false,
    );
  }

  /// DOWN button pressed — request DOWN hold via centralized state engine
  Future<void> _onDownPressed() async {
    final controller = _craneController;
    if (controller == null) return;
    if (controller.estopLatched || !controller.isConnected) return;

    final accepted = await controller.setDirectionalHold(
      direction: HoistDirection.down,
      pressed: true,
      fast: false,
    );
    if (!accepted) return;

    HapticFeedback.mediumImpact();
    Vibration.vibrate(duration: 30, amplitude: 128);
  }

  /// DOWN button released — clear DOWN hold via centralized state engine
  Future<void> _onDownReleased() async {
    final controller = _craneController;
    if (controller == null) return;

    await controller.setDirectionalHold(
      direction: HoistDirection.down,
      pressed: false,
      fast: false,
    );
  }

  Future<void> _onLeftPressed() async {
    final controller = _craneController;
    if (controller == null) return;
    if (controller.estopLatched || !controller.isConnected) return;

    final accepted = await controller.setDirectionalHold(
      direction: HoistDirection.left,
      pressed: true,
      fast: false,
    );
    if (!accepted) return;

    HapticFeedback.mediumImpact();
    Vibration.vibrate(duration: 30, amplitude: 128);
  }

  Future<void> _onLeftReleased() async {
    final controller = _craneController;
    if (controller == null) return;

    await controller.setDirectionalHold(
      direction: HoistDirection.left,
      pressed: false,
      fast: false,
    );
  }

  Future<void> _onRightPressed() async {
    final controller = _craneController;
    if (controller == null) return;
    if (controller.estopLatched || !controller.isConnected) return;

    final accepted = await controller.setDirectionalHold(
      direction: HoistDirection.right,
      pressed: true,
      fast: false,
    );
    if (!accepted) return;

    HapticFeedback.mediumImpact();
    Vibration.vibrate(duration: 30, amplitude: 128);
  }

  Future<void> _onRightReleased() async {
    final controller = _craneController;
    if (controller == null) return;

    await controller.setDirectionalHold(
      direction: HoistDirection.right,
      pressed: false,
      fast: false,
    );
  }

  // ═══════════════════════════════════════════════════════════
  // E-Stop Handlers
  // ═══════════════════════════════════════════════════════════

  Future<void> _onEStopTap() async {
    final controller = context.read<CraneController>();

    await controller.releaseAllDirectionalHolds();
    await controller.triggerEStop();
    Vibration.vibrate(duration: 600, amplitude: 255);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.white),
              SizedBox(width: 10),
              Text(
                'EMERGENCY STOP ACTIVATED',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          backgroundColor: AppColors.eStopColor,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _onResetEStopTap() async {
    final controller = _craneController;
    if (controller == null) return;
    if (controller.currentScreen != AppScreen.control ||
        !controller.isConnected) {
      return;
    }
    await controller.resetEStop();
    Vibration.vibrate(duration: 100);
  }

  // ═══════════════════════════════════════════════════════════
  // Deadman Control Handlers
  // ═══════════════════════════════════════════════════════════

  Future<void> _onDeadmanHeld(bool held) async {
    await _craneController?.setDeadmanHeld(held);
  }

  void _onDeadmanLockToggle() {
    _craneController?.toggleDeadmanLock();
  }

  // ═══════════════════════════════════════════════════════════
  // Back Navigation Guard
  // ═══════════════════════════════════════════════════════════

  /// Called when Android back gesture / system back is intercepted on the
  /// Control Screen.  Immediately releases any active motion holds (safety
  /// first), then asks the operator to confirm before disconnecting.
  Future<void> _onBackAttempted(
    BuildContext context,
    CraneController controller,
  ) async {
    // Safety: stop all crane motion the instant back navigation is detected.
    await controller.releaseAllDirectionalHolds();

    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Row(
          children: [
            Icon(
              Icons.warning_amber_rounded,
              color: ConnectionColors.warning,
              size: 22,
            ),
            SizedBox(width: 8),
            Text(
              'Exit Control Screen?',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        content: const Text(
          'Leaving the control screen will disconnect from the crane '
          'controller.\n\nEnsure the crane is in a safe, stopped position '
          'before exiting.',
          style: TextStyle(
            color: ConnectionColors.textSecondary,
            fontSize: 13.5,
            height: 1.5,
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            style: OutlinedButton.styleFrom(
              foregroundColor: ConnectionColors.primary,
              side: const BorderSide(color: ConnectionColors.primary),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 12,
              ),
            ),
            child: const Text(
              'STAY',
              style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.6),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: ConnectionColors.error,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
            ),
            child: const Text(
              'DISCONNECT & EXIT',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await controller.disconnect();
    }
  }

  // ═══════════════════════════════════════════════════════════
  // Build
  // ═══════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Consumer<CraneController>(
      builder: (ctx, controller, _) {
        return PopScope(
          // Block all Android back gestures and system back actions while on
          // the Control Screen. Navigation away requires explicit confirmation.
          canPop: false,
          onPopInvokedWithResult: (bool didPop, Object? result) {
            if (didPop) return;
            unawaited(_onBackAttempted(ctx, controller));
          },
          child: Scaffold(
            backgroundColor: ConnectionColors.background,
            resizeToAvoidBottomInset: false,
            // For compact screens, use this layout:
            appBar: AppBar(
            backgroundColor: ConnectionColors.surface,
            elevation: 0,
            automaticallyImplyLeading: false,
            titleSpacing: 0,

            // ── Leading: Device Icon ──────────────────────────
            leading: Container(
              margin: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: ConnectionColors.primarySoft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.developer_board_rounded,
                color: ConnectionColors.primary,
                size: 22,
              ),
            ),

            // ── Title: Device Info ────────────────────────────
            title: Row(
              children: [
                // Device name & status
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Device name
                      Text(
                        controller.connectedDeviceName ??
                            BLEConstants.deviceName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: ConnectionColors.textPrimary,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      // Status row with animated dot
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _StatusDot(isConnected: controller.isConnected),
                          const SizedBox(width: 6),
                          Text(
                            controller.isConnected
                                ? 'Connected'
                                : 'Disconnected',
                            style: TextStyle(
                              color: controller.isConnected
                                  ? ConnectionColors.connected
                                  : ConnectionColors.error,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (controller.isConnected) ...[
                            const SizedBox(width: 8),
                            // RSSI badge (if available)
                            _RSSIBadge(rssi: controller.connectedDeviceRssi),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // ── Actions ───────────────────────────────────────
            actions: [
              // Connection info tooltip
              if (controller.isConnected)
                Tooltip(
                  message:
                      'Device: ${controller.connectedDeviceName}\n'
                      'RSSI: ${controller.connectedDeviceRssi ?? "N/A"} dBm\n'
                      'Status: Authenticated',
                  child: Container(
                    margin: const EdgeInsets.only(right: 4),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: ConnectionColors.connectedBg,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.info_outline_rounded,
                      color: ConnectionColors.connected,
                      size: 18,
                    ),
                  ),
                ),

              // Sign out button
              TextButton.icon(
                onPressed: () async {
                  await controller.releaseAllDirectionalHolds();
                  controller.disconnect();
                },
                icon: const Icon(
                  Icons.logout_rounded,
                  size: 16,
                  color: ConnectionColors.textSecondary,
                ),
                label: const Text(
                  'SIGN OUT',
                  style: TextStyle(
                    color: ConnectionColors.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(width: 4),
            ],

            // ── Bottom Divider ─────────────────────────────────
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(1),
              child: Container(height: 1, color: ConnectionColors.divider),
            ),
          ),
          body: SafeArea(
            maintainBottomViewPadding: true,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final height = constraints.maxHeight;
                final isCompactWidth = width < 390;
                final isCompactHeight = height < 720;
                final outerPadding = isCompactWidth ? 10.0 : 12.0;
                final sectionSpacing = isCompactHeight ? 8.0 : 12.0;
                final isCompact = isCompactWidth || isCompactHeight;

                return Padding(
                  padding: EdgeInsets.fromLTRB(
                    outerPadding,
                    sectionSpacing,
                    outerPadding,
                    sectionSpacing,
                  ),
                  child: Column(
                    children: [
                      _buildSafetyActionPanel(
                        controller: controller,
                        compact: isCompact,
                      ),
                      SizedBox(height: sectionSpacing),
                      IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: _liveLEDs(controller, compact: isCompact),
                            ),
                            const SizedBox(width: 8),
                            _DeadmanControlButton(
                              isHeld: controller.deadmanHeld,
                              isLocked: controller.deadmanLocked,
                              isEstopActive: controller.estopLatched,
                              onHeld: _onDeadmanHeld,
                              onLockToggle: _onDeadmanLockToggle,
                              compact: isCompact,
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: sectionSpacing),
                      Expanded(
                        child: _buildButtonGrid(
                          isCompact: isCompact,
                          isDisabled:
                              controller.estopLatched ||
                              !controller.isConnected ||
                              !controller.deadmanActive,
                          upPressed: controller.upHoldActive,
                          downPressed: controller.downHoldActive,
                          leftPressed: controller.leftHoldActive,
                          rightPressed: controller.rightHoldActive,
                        ),
                      ),
                      SizedBox(height: sectionSpacing),
                      _buildStatusBar(controller, isCompact: isCompact),
                    ],
                  ),
                );
              },
            ),
          ),
        ),      // end Scaffold
      );        // end PopScope
      },
    );
  }

  Widget _buildSafetyActionPanel({
    required CraneController controller,
    required bool compact,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      width: double.infinity,
      child: controller.estopLatched
          ? _buildResetSection(compact: compact)
          : _buildEStopButton(compact: compact),
    );
  }

  Widget _buildButtonGrid({
    required bool isCompact,
    required bool isDisabled,
    required bool upPressed,
    required bool downPressed,
    required bool leftPressed,
    required bool rightPressed,
  }) {
    final buttonSpacing = isCompact ? 8.0 : 12.0;

    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              Expanded(
                child: _DeadmanButton(
                  label: isCompact ? 'UP' : 'HOIST\nUP',
                  icon: Icons.arrow_upward_rounded,
                  color: AppColors.upColor,
                  colorLight: AppColors.upColorLight,
                  isPressed: upPressed,
                  isDisabled: isDisabled || downPressed,
                  onPressed: _onUpPressed,
                  onReleased: _onUpReleased,
                  isCompact: isCompact,
                ),
              ),
              SizedBox(width: buttonSpacing),
              Expanded(
                child: _DeadmanButton(
                  label: isCompact ? 'DOWN' : 'HOIST\nDOWN',
                  icon: Icons.arrow_downward_rounded,
                  color: AppColors.downColor,
                  colorLight: AppColors.downColorLight,
                  isPressed: downPressed,
                  isDisabled: isDisabled || upPressed,
                  onPressed: _onDownPressed,
                  onReleased: _onDownReleased,
                  isCompact: isCompact,
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: buttonSpacing),
        Expanded(
          child: Row(
            children: [
              Expanded(
                child: _DeadmanButton(
                  label: isCompact ? 'LEFT' : 'TRAVEL\nLEFT',
                  icon: Icons.arrow_back_rounded,
                  color: AppColors.leftColor,
                  colorLight: AppColors.leftColorLight,
                  isPressed: leftPressed,
                  isDisabled: isDisabled || rightPressed,
                  onPressed: _onLeftPressed,
                  onReleased: _onLeftReleased,
                  isCompact: isCompact,
                ),
              ),
              SizedBox(width: buttonSpacing),
              Expanded(
                child: _DeadmanButton(
                  label: isCompact ? 'RIGHT' : 'TRAVEL\nRIGHT',
                  icon: Icons.arrow_forward_rounded,
                  color: AppColors.rightColor,
                  colorLight: AppColors.rightColorLight,
                  isPressed: rightPressed,
                  isDisabled: isDisabled || leftPressed,
                  onPressed: _onRightPressed,
                  onReleased: _onRightReleased,
                  isCompact: isCompact,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════
  // Live LED Indicators
  // ═══════════════════════════════════════════════════════════

  Widget _liveLEDs(CraneController controller, {required bool compact}) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 12,
        vertical: compact ? 6 : 8,
      ),
      decoration: BoxDecoration(
        color: ConnectionColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ConnectionColors.border),
      ),
      child: Wrap(
        spacing: compact ? 12 : 16,
        runSpacing: compact ? 8 : 10,
        alignment: WrapAlignment.center,
        children: [
          _eStopLedIndicator(
            emergencyActive: controller.estopLatched || controller.ledEstop,
            pinName: 'R0_0',
          ),
          _ledIndicator(
            label: 'UP',
            active: controller.ledUp || controller.upHoldActive,
            color: AppColors.upColor,
            pinName: 'Q0.1',
          ),
          _ledIndicator(
            label: 'DOWN',
            active: controller.ledDown || controller.downHoldActive,
            color: AppColors.downColor,
            pinName: 'Q0.2',
          ),
          _ledIndicator(
            label: 'LEFT',
            active: controller.ledLeft || controller.leftHoldActive,
            color: AppColors.leftColor,
            pinName: 'Q0.3',
          ),
          _ledIndicator(
            label: 'RIGHT',
            active: controller.ledRight || controller.rightHoldActive,
            color: AppColors.rightColor,
            pinName: 'Q0.4',
          ),
          // Container(
          //   padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          //   decoration: BoxDecoration(
          //     color: ConnectionColors.primarySoft,
          //     borderRadius: BorderRadius.circular(6),
          //   ),
          //   child: const Text(
          //     'HOLD-TO-RUN',
          //     style: TextStyle(
          //       color: ConnectionColors.primary,
          //       fontSize: 8,
          //       fontWeight: FontWeight.w800,
          //       letterSpacing: 1.0,
          //     ),
          //   ),
          // ),
        ],
      ),
    );
  }

  Widget _eStopLedIndicator({
    required bool emergencyActive,
    required String pinName,
  }) {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        final pulse = Curves.easeInOut.transform(_pulseController.value);
        final readyColor = Color.lerp(
          AppColors.upColorLight.withAlpha(20),
          const Color.fromARGB(255, 16, 154, 34),
          pulse,
        )!;
        final ledColor = emergencyActive ? AppColors.eStopColor : readyColor;
        final glowAlpha = emergencyActive ? 170 : (85 + (pulse * 75)).round();
        final glowRadius = emergencyActive ? 7.0 : 3.5 + (pulse * 4.5);

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: ledColor,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: ledColor.withAlpha(glowAlpha),
                    blurRadius: glowRadius,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              pinName,
              style: const TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.bold,
                color: ConnectionColors.textSecondary,
              ),
            ),
            Text(
              'ESTOP',
              style: TextStyle(
                fontSize: 9,
                color: emergencyActive
                    ? AppColors.eStopColor
                    : AppColors.upColorLight,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _ledIndicator({
    required String label,
    required Color color,
    required bool active,
    required String pinName,
    Color? inactiveColor,
  }) {
    final targetColor = active
        ? color
        : (inactiveColor ?? Colors.grey.shade300);
    final isLit = active || inactiveColor != null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TweenAnimationBuilder<Color?>(
          tween: ColorTween(begin: Colors.grey.shade300, end: targetColor),
          duration: const Duration(milliseconds: 300),
          builder: (context, animatedColor, child) {
            final ledColor = animatedColor ?? targetColor;
            return Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: ledColor,
                shape: BoxShape.circle,
                boxShadow: isLit
                    ? [
                        BoxShadow(
                          color: ledColor.withAlpha(active ? 153 : 128),
                          blurRadius: active ? 6 : 5,
                          spreadRadius: 1,
                        ),
                      ]
                    : [],
              ),
            );
          },
        ),
        const SizedBox(height: 4),
        Text(
          pinName,
          style: const TextStyle(
            fontSize: 8,
            fontWeight: FontWeight.bold,
            color: ConnectionColors.textSecondary,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 9,
            color: active ? color : ConnectionColors.textMuted,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════
  // Status Bar
  // ═══════════════════════════════════════════════════════════

  Widget _buildStatusBar(CraneController controller, {bool isCompact = false}) {
    final Color c;
    final String status;
    final hasAnyMotion =
        controller.upHoldActive ||
        controller.downHoldActive ||
        controller.leftHoldActive ||
        controller.rightHoldActive;

    if (controller.estopLatched) {
      c = AppColors.eStopColor;
      status = 'EMERGENCY ACTIVE - SYSTEM LOCKED';
    } else if (controller.upHoldActive) {
      c = AppColors.upColor;
      status = isCompact ? 'UP - HOLD' : 'HOIST UP - HOLD TO RUN';
    } else if (controller.downHoldActive) {
      c = AppColors.downColor;
      status = isCompact ? 'DOWN - HOLD' : 'HOIST DOWN - HOLD TO RUN';
    } else if (controller.leftHoldActive) {
      c = AppColors.leftColor;
      status = isCompact ? 'LEFT - HOLD' : 'TRAVEL LEFT - HOLD TO RUN';
    } else if (controller.rightHoldActive) {
      c = AppColors.rightColor;
      status = isCompact ? 'RIGHT - HOLD' : 'TRAVEL RIGHT - HOLD TO RUN';
    } else if (!controller.deadmanActive) {
      c = const Color(0xFFD97706);
      status = isCompact ? 'HOLD DEADMAN' : 'DEADMAN — HOLD TO ENABLE CONTROLS';
    } else {
      c = AppColors.idleColor;
      status = isCompact ? 'IDLE' : 'IDLE — PRESS AND HOLD TO OPERATE';
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: isCompact ? 10 : 14,
        vertical: isCompact ? 6 : 8,
      ),
      decoration: BoxDecoration(
        color: c.withAlpha(20),
        borderRadius: BorderRadius.circular(isCompact ? 8 : 10),
        border: Border.all(color: c.withAlpha(100)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: isCompact ? 6 : 8,
            height: isCompact ? 6 : 8,
            decoration: BoxDecoration(
              color: c,
              shape: BoxShape.circle,
              boxShadow: hasAnyMotion
                  ? [BoxShadow(color: c.withAlpha(128), blurRadius: 6)]
                  : null,
            ),
          ),
          SizedBox(width: isCompact ? 6 : 10),
          Flexible(
            child: Text(
              status,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: c,
                fontWeight: FontWeight.bold,
                fontSize: isCompact ? 11 : 12,
                letterSpacing: 0.8,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // E-Stop Button
  // ═══════════════════════════════════════════════════════════

  Widget _buildEStopButton({required bool compact}) {
    return GestureDetector(
      onTap: _onEStopTap,
      child: Container(
        width: double.infinity,
        constraints: BoxConstraints(minHeight: compact ? 90 : 58),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF6B0000), AppColors.eStopColor],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: AppColors.eStopColor.withAlpha(100),
              blurRadius: 14,
              spreadRadius: 2,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: compact ? 32 : 34,
              height: compact ? 32 : 34,
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(31),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withAlpha(64), width: 2),
              ),
              child: const Icon(
                Icons.power_settings_new,
                color: Colors.white,
                size: 18,
              ),
            ),
            SizedBox(width: compact ? 10 : 12),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'EMERGENCY STOP',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
                ),
                Text(
                  'Tap to stop all crane operations',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white60,
                    fontSize: compact ? 9 : 10,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // E-Stop Reset Section
  // ═══════════════════════════════════════════════════════════

  Widget _buildResetSection({required bool compact}) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: EdgeInsets.all(compact ? 8 : 10),
          decoration: BoxDecoration(
            color: AppColors.eStopColor.withAlpha(25),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppColors.eStopColor.withAlpha(130),
              width: 2,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: const BoxDecoration(
                  color: AppColors.eStopColor,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.white,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'EMERGENCY STOP ACTIVE',
                      style: TextStyle(
                        color: AppColors.eStopColorLight,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        letterSpacing: 0.8,
                      ),
                    ),
                    Text(
                      'All crane controls are locked',
                      style: TextStyle(
                        color: ConnectionColors.textSecondary,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: compact ? 6 : 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: EStopSwipeButton(
            onActivated: () {
              _onResetEStopTap();
            },
            instructionTitle: 'SWIPE TO RESET E-STOP',
            instructionSubtitle: 'Slide right to clear emergency lockout',
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════
// Deadman Hold-to-Run Button
// ═══════════════════════════════════════════════════════════

// ═══════════════════════════════════════════════════════════
// Deadman Hold-to-Run Button (FIXED)
// ═══════════════════════════════════════════════════════════

class _DeadmanButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final Color color;
  final Color colorLight;
  final bool isPressed;
  final bool isDisabled;
  final Future<void> Function() onPressed;
  final Future<void> Function() onReleased;
  final bool isCompact; // NEW

  const _DeadmanButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.colorLight,
    required this.isPressed,
    required this.isDisabled,
    required this.onPressed,
    required this.onReleased,
    this.isCompact = false, // NEW
  });

  @override
  State<_DeadmanButton> createState() => _DeadmanButtonState();
}

class _DeadmanButtonState extends State<_DeadmanButton>
    with TickerProviderStateMixin {
  late final AnimationController _pressAnim;
  late final Animation<double> _scaleAnim;
  late final AnimationController _glowAnim;
  late final Animation<double> _glowOpacity;

  @override
  void initState() {
    super.initState();

    _pressAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 80),
    );
    _scaleAnim = Tween<double>(
      begin: 1.0,
      end: 0.95,
    ).animate(CurvedAnimation(parent: _pressAnim, curve: Curves.easeIn));

    _glowAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _glowOpacity = Tween<double>(
      begin: 0.5,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _glowAnim, curve: Curves.easeInOut));
  }

  @override
  void didUpdateWidget(_DeadmanButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPressed && !oldWidget.isPressed) {
      _pressAnim.forward();
      _glowAnim.repeat(reverse: true);
    } else if (!widget.isPressed && oldWidget.isPressed) {
      _pressAnim.reverse();
      _glowAnim.stop();
      _glowAnim.reset();
    }
  }

  @override
  void dispose() {
    _pressAnim.dispose();
    _glowAnim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isActive = widget.isPressed && !widget.isDisabled;
    final isDisabled = widget.isDisabled;
    final compact = widget.isCompact;

    // Responsive sizing
    final double iconSize = compact
        ? (isActive ? 28 : 24)
        : (isActive ? 36 : 30);
    final double iconContainerSize = compact
        ? (isActive ? 52 : 44)
        : (isActive ? 72 : 64);
    final double fontSize = compact
        ? (isActive ? 14 : 12)
        : (isActive ? 18 : 16);
    final EdgeInsets padding = EdgeInsets.symmetric(
      vertical: compact ? 12 : 24,
      horizontal: compact ? 8 : 16,
    );
    final double instructionFontSize = compact ? 8.0 : 10.0;

    return Listener(
      onPointerDown: (_) {
        if (isDisabled) return;
        widget.onPressed();
      },
      onPointerUp: (_) {
        widget.onReleased();
      },
      onPointerCancel: (_) {
        widget.onReleased();
      },
      child: AnimatedBuilder(
        animation: Listenable.merge([_pressAnim, _glowAnim]),
        builder: (context, child) {
          final scale = widget.isPressed ? _scaleAnim.value : 1.0;
          final glow = widget.isPressed ? _glowOpacity.value : 0.0;

          return Transform.scale(
            scale: scale,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(compact ? 16 : 20),
                gradient: isActive
                    ? LinearGradient(
                        colors: [widget.color, widget.colorLight],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : null,
                color: isActive
                    ? null
                    : isDisabled
                    ? AppColors.disabled.withAlpha(50)
                    : ConnectionColors.surfaceAlt,
                border: Border.all(
                  color: isActive
                      ? widget.colorLight
                      : isDisabled
                      ? AppColors.disabled
                      : ConnectionColors.border,
                  width: isActive ? 3 : 1.5,
                ),
                boxShadow: isActive
                    ? [
                        BoxShadow(
                          color: widget.color.withAlpha(128),
                          blurRadius: compact
                              ? 12 + (6 * glow)
                              : 20 + (10 * glow),
                          spreadRadius: 2,
                        ),
                        BoxShadow(
                          color: widget.color.withAlpha(50),
                          blurRadius: 4,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : [
                        BoxShadow(
                          color: Colors.black.withAlpha(35),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
              ),
              child: Padding(
                padding: padding,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Icon
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: iconContainerSize,
                      height: iconContainerSize,
                      decoration: BoxDecoration(
                        color: isActive
                            ? Colors.white.withAlpha(40)
                            : widget.color.withAlpha(20),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isActive
                              ? Colors.white.withAlpha(100)
                              : widget.color.withAlpha(50),
                          width: isActive ? 2.5 : 1.5,
                        ),
                      ),
                      child: Icon(
                        widget.icon,
                        color: isActive
                            ? Colors.white
                            : isDisabled
                            ? AppColors.disabled
                            : widget.color,
                        size: iconSize,
                      ),
                    ),
                    SizedBox(height: compact ? 8 : 14),
                    // Label
                    Text(
                      widget.label,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isActive
                            ? Colors.white
                            : isDisabled
                            ? AppColors.disabled
                            : ConnectionColors.textPrimary,
                        fontSize: fontSize,
                        fontWeight: FontWeight.w800,
                        height: 1.3,
                        letterSpacing: 1.2,
                      ),
                    ),
                    SizedBox(height: compact ? 4 : 8),
                    // Instruction text
                    if (!compact || isActive)
                      AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 200),
                        style: TextStyle(
                          color: isActive
                              ? Colors.white.withAlpha(200)
                              : isDisabled
                              ? AppColors.disabled
                              : ConnectionColors.textMuted,
                          fontSize: instructionFontSize,
                          fontWeight: FontWeight.w600,
                        ),
                        child: Text(
                          isActive ? 'RELEASE TO STOP' : 'HOLD TO RUN',
                        ),
                      ),
                    // Active indicator bar
                    SizedBox(height: compact ? 4 : 10),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: isActive
                          ? (compact ? 36 : 48)
                          : (compact ? 16 : 24),
                      height: compact ? 3 : 4,
                      decoration: BoxDecoration(
                        color: isActive ? Colors.white : Colors.transparent,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// Deadman Control Button — Operator-Presence Safety Lock
//
// Hold to enable motion. Release to kill all motion.
// Hold 4 seconds to toggle LOCK mode (motion persists without holding).
// ═══════════════════════════════════════════════════════════

class _DeadmanControlButton extends StatefulWidget {
  const _DeadmanControlButton({
    required this.isHeld,
    required this.isLocked,
    required this.isEstopActive,
    required this.onHeld,
    required this.onLockToggle,
    required this.compact,
  });

  final bool isHeld;
  final bool isLocked;
  final bool isEstopActive;
  final Future<void> Function(bool held) onHeld;
  final VoidCallback onLockToggle;
  final bool compact;

  @override
  State<_DeadmanControlButton> createState() => _DeadmanControlButtonState();
}

class _DeadmanControlButtonState extends State<_DeadmanControlButton>
    with TickerProviderStateMixin {
  static const Duration _lockHoldDuration = Duration(seconds: 2);
  static const Color _heldColor = Color(0xFFD97706); // amber-600
  static const Color _lockedColor = Color(0xFF16A34A); // green-600

  late final AnimationController _glowAnim;
  late final AnimationController _progressAnim;
  Timer? _lockTimer;
  bool _pointerDown = false;

  @override
  void initState() {
    super.initState();
    _glowAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _progressAnim = AnimationController(
      vsync: this,
      duration: _lockHoldDuration,
    );
  }

  @override
  void dispose() {
    _glowAnim.dispose();
    _progressAnim.dispose();
    _lockTimer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(_DeadmanControlButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    // When E-stop activates mid-press, abort the interaction cleanly.
    if (widget.isEstopActive && !oldWidget.isEstopActive && _pointerDown) {
      _pointerDown = false;
      _lockTimer?.cancel();
      _lockTimer = null;
      _progressAnim.reset();
      // onHeld(false) is intentionally skipped — triggerEStop() already cleared
      // deadman state in the controller; calling it would be a no-op anyway.
    }
  }

  void _onPointerDown() {
    if (widget.isEstopActive) return; // E-stop blocks all deadman input.
    _pointerDown = true;
    widget.onHeld(true);
    _progressAnim.forward(from: 0.0);
    _lockTimer = Timer(_lockHoldDuration, () {
      if (!_pointerDown) return;
      widget.onLockToggle();
      HapticFeedback.heavyImpact();
      Vibration.vibrate(duration: 200, amplitude: 200);
      _progressAnim.reset();
    });
  }

  void _onPointerUp() {
    if (!_pointerDown) return;
    _pointerDown = false;
    _lockTimer?.cancel();
    _lockTimer = null;
    _progressAnim.reset();
    widget.onHeld(false);
  }

  @override
  Widget build(BuildContext context) {
    final isDisabled = widget.isEstopActive;
    final isActive = !isDisabled && (widget.isHeld || widget.isLocked);
    final isLocked = !isDisabled && widget.isLocked;
    final compact = widget.compact;
    final Color activeColor = isLocked ? _lockedColor : _heldColor;

    return Listener(
      onPointerDown: (_) => _onPointerDown(),
      onPointerUp: (_) => _onPointerUp(),
      onPointerCancel: (_) => _onPointerUp(),
      child: AnimatedBuilder(
        animation: Listenable.merge([_glowAnim, _progressAnim]),
        builder: (context, _) {
          final glow = isActive
              ? Curves.easeInOut.transform(_glowAnim.value)
              : 0.0;
          final progress = _progressAnim.value;

          return AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: compact ? 76.0 : 86.0,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(compact ? 12 : 14),
              color: isDisabled
                  ? AppColors.disabled.withAlpha(20)
                  : isActive
                  ? activeColor.withAlpha(25)
                  : ConnectionColors.surfaceAlt,
              border: Border.all(
                color: isDisabled
                    ? AppColors.disabled.withAlpha(60)
                    : isActive
                    ? activeColor
                    : ConnectionColors.border,
                width: isActive ? 2.0 : 1.5,
              ),
              boxShadow: isActive
                  ? [
                      BoxShadow(
                        color: activeColor.withAlpha(
                          (80 + (55 * glow)).round(),
                        ),
                        blurRadius: 6 + 5 * glow,
                        spreadRadius: 1,
                      ),
                    ]
                  : const [
                      BoxShadow(
                        color: Color(0x20000000),
                        blurRadius: 4,
                        offset: Offset(0, 2),
                      ),
                    ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Icon circle
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: compact ? 28 : 32,
                  height: compact ? 28 : 32,
                  decoration: BoxDecoration(
                    color: isDisabled
                        ? AppColors.disabled.withAlpha(25)
                        : isActive
                        ? activeColor.withAlpha(35)
                        : ConnectionColors.primarySoft,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isDisabled
                          ? AppColors.disabled.withAlpha(50)
                          : isActive
                          ? activeColor.withAlpha(110)
                          : ConnectionColors.primary.withAlpha(50),
                      width: 1.5,
                    ),
                  ),
                  child: Icon(
                    isDisabled
                        ? Icons.block_rounded
                        : isLocked
                        ? Icons.lock_rounded
                        : (widget.isHeld
                              ? Icons.pan_tool_rounded
                              : Icons.pan_tool_outlined),
                    size: compact ? 13 : 15,
                    color: isDisabled
                        ? AppColors.disabled
                        : isActive
                        ? activeColor
                        : ConnectionColors.primary,
                  ),
                ),
                SizedBox(height: compact ? 4 : 5),
                // Title
                Text(
                  'DEADMAN',
                  style: TextStyle(
                    color: isDisabled
                        ? AppColors.disabled
                        : isActive
                        ? activeColor
                        : ConnectionColors.textSecondary,
                    fontSize: compact ? 6.5 : 7.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
                ),
                SizedBox(height: compact ? 2 : 3),
                // State label
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 200),
                  style: TextStyle(
                    color: isDisabled
                        ? AppColors.eStopColor.withAlpha(180)
                        : isActive
                        ? activeColor
                        : ConnectionColors.textMuted,
                    fontSize: compact ? 7.0 : 8.0,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                  ),
                  child: Text(
                    isDisabled
                        ? 'E-STOP'
                        : isLocked
                        ? 'LOCKED'
                        : (widget.isHeld ? 'ACTIVE' : 'HOLD'),
                  ),
                ),
                // Long-press progress bar (reserved space always)
                SizedBox(height: compact ? 5 : 6),
                SizedBox(
                  height: 3,
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: compact ? 8.0 : 10.0,
                    ),
                    child: progress > 0 && !isDisabled
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: LinearProgressIndicator(
                              value: progress,
                              backgroundColor: ConnectionColors.border
                                  .withAlpha(80),
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                _lockedColor,
                              ),
                              minHeight: 3,
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _StatusDot extends StatefulWidget {
  const _StatusDot({required this.isConnected});

  final bool isConnected;

  @override
  State<_StatusDot> createState() => _StatusDotState();
}

class _StatusDotState extends State<_StatusDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _pulseAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    if (widget.isConnected) {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(_StatusDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isConnected && !oldWidget.isConnected) {
      _pulseController.repeat(reverse: true);
    } else if (!widget.isConnected && oldWidget.isConnected) {
      _pulseController.stop();
      _pulseController.reset();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.isConnected
        ? ConnectionColors.connected
        : ConnectionColors.error;

    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        final opacity = widget.isConnected ? _pulseAnimation.value : 1.0;

        return Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color.withAlpha((255 * opacity).toInt()),
            shape: BoxShape.circle,
            boxShadow: widget.isConnected
                ? [
                    BoxShadow(
                      color: color.withAlpha((77 * opacity).toInt()),
                      blurRadius: 4,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
        );
      },
    );
  }
}

class _RSSIBadge extends StatelessWidget {
  const _RSSIBadge({required this.rssi});

  final int? rssi;

  Color get _rssiColor {
    if (rssi == null) return ConnectionColors.textMuted;
    if (rssi! >= -60) return ConnectionColors.connected;
    if (rssi! >= -80) return ConnectionColors.warning;
    return ConnectionColors.error;
  }

  @override
  Widget build(BuildContext context) {
    if (rssi == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: _rssiColor.withAlpha(20),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _rssiColor.withAlpha(60), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.signal_cellular_alt_rounded, size: 10, color: _rssiColor),
          const SizedBox(width: 3),
          Text(
            '$rssi',
            style: TextStyle(
              color: _rssiColor,
              fontSize: 9,
              fontWeight: FontWeight.w700,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}
