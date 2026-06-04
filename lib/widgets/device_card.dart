import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:tusker_trailer_rrc/utils/constants.dart';
import 'package:tusker_trailer_rrc/models/ble_scan_device.dart';
import 'package:tusker_trailer_rrc/widgets/circular_progress_indicator.dart';

class AvailableDeviceCard extends StatelessWidget {
  const AvailableDeviceCard({
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

// ═══════════════════════════════════════════════════════════
// Connected Device Card — Shows extra details and disconnect action for the active device
// ═══════════════════════════════════════════════════════════

class ConnectedDeviceCard extends StatelessWidget {
  const ConnectedDeviceCard({
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
        color: const Color.fromARGB(255, 234, 241, 249),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color.fromARGB(255, 163, 192, 223)),
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
                      color: const Color.fromARGB(
                        255,
                        163,
                        192,
                        223,
                      ).withAlpha(30),
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
                SizedBox(
                  width: 30,
                  height: 30,
                  child: CustomCircularStepProgressIndicator(
                    totalSteps: 20,
                    currentStep: 12,
                    stepSize: 20,
                    selectedColor: Colors.red,
                    unselectedColor: const Color.fromARGB(255, 71, 100, 188),
                    padding: math.pi / 80,
                    width: 30,
                    height: 30,
                    startingAngle: -math.pi * 2 / 3,
                    arcSize: math.pi * 2 / 3 * 2,
                    gradientColor: const LinearGradient(
                      colors: [
                        Color.fromARGB(255, 54, 184, 244),
                        Color.fromARGB(255, 111, 152, 224),
                      ],
                    ),
                    isAnimating: isConnecting,
                  ),
                ),
            ],
          ),

          if (isConnecting) ...[
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

  Color get _signalColor {
    if (_signalStrength >= 0.65) return ConnectionColors.connected;
    if (_signalStrength >= 0.35) return ConnectionColors.warning;
    return ConnectionColors.error;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final iconSize = (w * 0.07).clamp(14.0, 22.0);
        final containerSize = (w * 0.11).clamp(22.0, 34.0);
        final fontSize = (w * 0.028).clamp(9.0, 12.0);

        return Container(
          padding: EdgeInsets.symmetric(
            horizontal: (w * 0.02).clamp(6.0, 10.0),
            vertical: (w * 0.015).clamp(4.0, 8.0),
          ),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Container(
                width: containerSize,
                height: containerSize,
                decoration: BoxDecoration(
                  color: _signalColor.withAlpha(20),
                  borderRadius: BorderRadius.circular(containerSize * 0.28),
                ),
                child: Icon(
                  Icons.signal_cellular_alt_rounded,
                  color: _signalColor,
                  size: iconSize,
                ),
              ),

              SizedBox(width: (w * 0.015).clamp(4.0, 8.0)),
              Flexible(
                child: Text(
                  '$rssi dBm',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _signalColor,
                    fontSize: fontSize,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              Expanded(child: SizedBox(width: (w * 0.015).clamp(4.0, 8.0))),
              // Signal percentage badge
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: (w * 0.015).clamp(4.0, 7.0),
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: _signalColor.withAlpha(20),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${(_signalStrength * 100).toInt()}%',
                  style: TextStyle(
                    color: _signalColor,
                    fontSize: fontSize,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
