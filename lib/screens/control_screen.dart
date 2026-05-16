import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:provider/provider.dart';
import 'package:vibration/vibration.dart';

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
    with SingleTickerProviderStateMixin {

  late final AnimationController _pulseController;
  CraneController? _craneController;
  bool _wasDisconnected = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
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
    _pulseController.dispose();
    _craneController?.removeListener(_onControllerChange);
    super.dispose();
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
    if (controller.currentScreen != AppScreen.control || !controller.isConnected) {
      return;
    }
    await controller.resetEStop();
    Vibration.vibrate(duration: 100);
  }

  // ═══════════════════════════════════════════════════════════
  // Build
  // ═══════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Consumer<CraneController>(
      builder: (ctx, controller, _) {
        return Scaffold(
          backgroundColor: ConnectionColors.background,
          resizeToAvoidBottomInset: false,
          appBar: AppBar(
            backgroundColor: ConnectionColors.surface,
            elevation: 0,
            automaticallyImplyLeading: false,
            titleSpacing: 12,
            title: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  controller.connectedDeviceName ?? BLEConstants.deviceName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: ConnectionColors.textPrimary,
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      margin: const EdgeInsets.only(right: 5),
                      decoration: BoxDecoration(
                        color: controller.isConnected
                            ? AppColors.upColorLight
                            : AppColors.danger,
                        shape: BoxShape.circle,
                      ),
                    ),
                    Flexible(
                      child: Text(
                        controller.isConnected ? 'Connected' : 'Disconnected',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: controller.isConnected
                              ? AppColors.upColorLight
                              : AppColors.danger,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  await controller.releaseAllDirectionalHolds();
                  controller.disconnect();
                },
                child: const Text(
                  'SIGN OUT',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: ConnectionColors.textSecondary),
                ),
              ),
            ],
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
                final isLandscape = width > height;
                final isCompact = isCompactWidth || isCompactHeight;
                final outerPadding = isCompactWidth ? 10.0 : 12.0;
                final sectionSpacing = isCompactHeight ? 8.0 : 12.0;

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
                        landscape: isLandscape,
                      ),
                      SizedBox(height: sectionSpacing),
                      _liveLEDs(
                        controller,
                        compact: isCompact,
                      ),
                      SizedBox(height: sectionSpacing),
                      Expanded(
                        child: _buildButtonGrid(
                          isCompact: isCompact,
                          isLandscape: isLandscape,
                          isDisabled: controller.estopLatched || !controller.isConnected,
                          upPressed: controller.upHoldActive,
                          downPressed: controller.downHoldActive,
                          leftPressed: controller.leftHoldActive,
                          rightPressed: controller.rightHoldActive,
                        ),
                      ),
                      SizedBox(height: sectionSpacing),
                      _buildStatusBar(
                        controller,
                        isCompact: isCompact,
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildSafetyActionPanel({
    required CraneController controller,
    required bool compact,
    required bool landscape,
  }) {
    return SizedBox(
      width: double.infinity,
      child: controller.estopLatched
          ? _buildResetSection(compact: compact, landscape: landscape)
          : _buildEStopButton(compact: compact),
    );
  }

  Widget _buildButtonGrid({
    required bool isCompact,
    required bool isLandscape,
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
        SizedBox(height: isCompact ? 8 : 12),
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
          _ledIndicator(
            label: 'ESTOP',
            active: controller.ledEstop,
            color: AppColors.eStopColor,
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

  Widget _ledIndicator({
    required String label,
    required Color color,
    required bool active,
    required String pinName,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: active ? 1.0 : 0.0),
          duration: const Duration(milliseconds: 300),
          builder: (context, value, child) {
            return Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: active ? color : Colors.grey.shade300,
                shape: BoxShape.circle,
                boxShadow: active
                    ? [
                        BoxShadow(
                          color: color.withAlpha(153),
                          blurRadius: 6 * value,
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
    final hasAnyMotion = controller.upHoldActive ||
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
  // Safety Notice
  // ═══════════════════════════════════════════════════════════

  Widget _buildSafetyNotice() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: ConnectionColors.warning.withAlpha(25),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: ConnectionColors.warning.withAlpha(50)),
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.safety_check_rounded, size: 14, color: ConnectionColors.warning),
          // SizedBox(width: 6),
          // Text(
          //   'DEADMAN CONTROL: Release button to stop immediately',
          //   style: TextStyle(
          //     color: ConnectionColors.warning,
          //     fontSize: 9,
          //     fontWeight: FontWeight.w600,
          //   ),
          // ),
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
        constraints: BoxConstraints(minHeight: compact ? 54 : 58),
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
                  style: TextStyle(color: Colors.white60, fontSize: compact ? 9 : 10),
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

  Widget _buildResetSection({
    required bool compact,
    required bool landscape,
  }) {
    if (compact || landscape) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Container(
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
                    width: compact ? 28 : 32,
                    height: compact ? 28 : 32,
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
                  SizedBox(width: compact ? 8 : 10),
                  const Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'EMERGENCY STOP ACTIVE',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.eStopColorLight,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            letterSpacing: 0.8,
                          ),
                        ),
                        Text(
                          'All crane controls are locked',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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
          ),
          SizedBox(width: compact ? 8 : 10),
          Expanded(
            child: EStopSwipeButton(
              onActivated: _onResetEStopTap,
              instructionTitle: compact ? 'RESET LOCKOUT' : 'SWIPE TO RESET',
              instructionSubtitle: compact
                  ? 'Slide right to clear emergency lockout'
                  : 'Slide right to clear emergency lockout',
            ),
          ),
        ],
      );
    }

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
                width: compact ? 30 : 32,
                height: compact ? 30 : 32,
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
              SizedBox(width: compact ? 8 : 10),
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
        SizedBox(
          width: double.infinity,
          child: EStopSwipeButton(
            onActivated: _onResetEStopTap,
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
    _scaleAnim = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _pressAnim, curve: Curves.easeIn),
    );
    
    _glowAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _glowOpacity = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _glowAnim, curve: Curves.easeInOut),
    );
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
    final double iconSize = compact ? (isActive ? 28 : 24) : (isActive ? 36 : 30);
    final double iconContainerSize = compact ? (isActive ? 52 : 44) : (isActive ? 72 : 64);
    final double fontSize = compact ? (isActive ? 14 : 12) : (isActive ? 18 : 16);
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
                          blurRadius: compact ? 12 + (6 * glow) : 20 + (10 * glow),
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
                      width: isActive ? (compact ? 36 : 48) : (compact ? 16 : 24),
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
