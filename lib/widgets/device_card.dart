import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:tusker_trailer_rrc/models/app_enums.dart';
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
    final staleStatus = device.staleStatus;
    final isStale = staleStatus != DeviceStaleStatus.active;
    final isExpired = staleStatus == DeviceStaleStatus.expired;

    // Dimmer when another device is connecting; slightly dimmer when stale.
    final double opacity = connecting ? 0.45 : (isExpired ? 0.70 : 1.0);

    final Color borderColor = connecting
        ? ConnectionColors.border.withAlpha(120)
        : isStale
        ? ConnectionColors.warningBorder
        : ConnectionColors.border;

    final Color cardBg = isStale
        ? ConnectionColors.warningBg.withAlpha(90)
        : ConnectionColors.surfaceAlt;

    return AnimatedOpacity(
      opacity: opacity,
      duration: const Duration(milliseconds: 300),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isStale
                    ? ConnectionColors.warningBg
                    : ConnectionColors.primarySoft,
              ),
              child: Image.asset(
                'assets/icons/Connector.png',
                color: isStale
                    ? ConnectionColors.warning
                    : ConnectionColors.primary,
                width: 20,
                height: 20,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        device.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isStale
                              ? ConnectionColors.textSecondary
                              : ConnectionColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      
                    ],
                  ),
                  const SizedBox(height: 3),
                  _PlcTypeBadge(plcType: device.plcType, compact: true),
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
                  const SizedBox(height: 6),
                  if (isStale)
                    _StaleIndicatorRow(isExpired: isExpired)
                  else
                    _SignalPill(rssi: device.rssi, label: device.signalLabel),
                ],
              ),
            ),
            // Hide the connect button while another device is connecting.
            if (!connecting) ...[
              const SizedBox(width: 8),
              SizedBox(
                width: 92,
                child: isStale
                    ? OutlinedButton(
                        onPressed: onConnect,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: ConnectionColors.warning,
                          side: const BorderSide(
                            color: ConnectionColors.warningBorder,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          textStyle: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                          backgroundColor: ConnectionColors.warningBg,
                        ),
                        child: const Text('CONNECT'),
                      )
                    : FilledButton(
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

// ═══════════════════════════════════════════════════════════
// Stale Indicator Row — shown below device info when no recent advertisement
// ═══════════════════════════════════════════════════════════
class _StaleIndicatorRow extends StatelessWidget {
  const _StaleIndicatorRow({required this.isExpired});

  final bool isExpired;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: ConnectionColors.warningBg,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: ConnectionColors.warningBorder),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.signal_wifi_statusbar_connected_no_internet_4_rounded,
            size: 10,
            color: ConnectionColors.warning,
          ),
          SizedBox(width: 4),
          Flexible(
            child: Text(
              'STALE',
              style: TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.w800,
                color: ConnectionColors.warning,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
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
    final Color tone = rssi >= -68
        ? ConnectionColors.connected
        : rssi >= -80
        ? ConnectionColors.warning
        : ConnectionColors.error;

    return Row(
      children: [
        Icon(Icons.signal_cellular_alt_rounded, size: 12, color: tone),
        const SizedBox(width: 5),
        Text(
          '$rssi dBm',
          style: TextStyle(
            color: tone,
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            fontFamily: 'monospace',
          ),
        ),
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
    required this.onCancel,
    this.isCancelling = false,
  });

  final BleScanDevice device;
  final VoidCallback onCancel;
  final bool isCancelling;

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
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
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
                child: Image.asset(
                  'assets/icons/plc.png',
                  color: ConnectionColors.primary,
                  width: 20,
                  height: 20,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
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
                        const SizedBox(width: 4),
                        _PlcTypeBadge(plcType: device.plcType, compact: true),
                      ],
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
                  // Stop rotating during cancellation to signal the abort
                  isAnimating: !isCancelling,
                ),
              ),
            ],
          ),

          const SizedBox(height: 4),

          // ── RSSI Bar
          _RSSIBar(rssi: device.rssi),

          const SizedBox(height: 4),

          // ── Cancel Button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: isCancelling ? null : onCancel,
              icon: isCancelling
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: ConnectionColors.textSecondary,
                      ),
                    )
                  : const Icon(Icons.close_rounded, size: 16),
              label: Text(isCancelling ? 'CANCELLING...' : 'CANCEL'),
              style: OutlinedButton.styleFrom(
                foregroundColor: ConnectionColors.textSecondary,
                side: BorderSide(
                  color: isCancelling
                      ? ConnectionColors.border.withAlpha(80)
                      : ConnectionColors.border,
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                textStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
                backgroundColor: ConnectionColors.surfaceAlt,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// PLC Type Badge — shows the PLC hardware model from manufacturer data
// ═══════════════════════════════════════════════════════════

class _PlcTypeBadge extends StatelessWidget {
  const _PlcTypeBadge({required this.plcType, this.compact = true});

  final PlcType plcType;

  /// When true, uses tighter padding for the smaller AvailableDeviceCard.
  final bool compact;

  bool get _isKnown => plcType != PlcType.unknown;

  @override
  Widget build(BuildContext context) {
    final Color bg = _isKnown
        ? ConnectionColors.primary.withAlpha(20)
        : ConnectionColors.surfaceAlt;
    final Color border = _isKnown
        ? ConnectionColors.primary.withAlpha(70)
        : ConnectionColors.border;
    final Color textColor = _isKnown
        ? ConnectionColors.primary
        : ConnectionColors.textMuted;
    final double fontSize = compact ? 9.5 : 11.0;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 2 : 3,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
         
         
          Text(
            plcType.displayName,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w800,
              color: textColor,
              letterSpacing: 0.4,
            ),
          ),
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
    if (_signalStrength >= 0.65) return ConnectionColors.textSecondary;
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
