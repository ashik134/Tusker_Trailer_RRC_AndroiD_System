import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:tusker_trailer_rrc/controllers/crane_controllers.dart';
import 'package:tusker_trailer_rrc/utils/constants.dart';

/// Industrial-grade device settings and security information screen.
///
/// Provides operators and administrators with:
///   - Permanent device identity (UUID) for PLC trusted-device registration.
///   - Real-time authorization/trust status.
///   - Biometric authentication management.
///   - Key security configuration facts.
///
/// The device ID shown here must be manually registered in the PLC web
/// interface to authorize this mobile device for control access.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: AppColors.textPrimary,
            size: 20,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Device Settings',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.border),
        ),
      ),
      body: Consumer<CraneController>(
        builder: (context, controller, _) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
            children: [
              // ── Section: Device Identity ──────────────────────────────────
              const _SectionHeader(
                icon: Icons.fingerprint_rounded,
                label: 'DEVICE IDENTITY',
                iconColor: AppColors.accent,
              ),
              const SizedBox(height: 8),
              _DeviceIdentityCard(controller: controller),
              const SizedBox(height: 24),

              // ── Section: Authorization Status ─────────────────────────────
              // const _SectionHeader(
              //   icon: Icons.verified_user_rounded,
              //   label: 'AUTHORIZATION STATUS',
              //   iconColor: AppColors.info,
              // ),
              // const SizedBox(height: 8),
              // _AuthorizationStatusCard(controller: controller),
              // const SizedBox(height: 24),

              // ── Section: Biometric Security ───────────────────────────────
              const _SectionHeader(
                icon: Icons.face_unlock_rounded,
                label: 'BIOMETRIC SECURITY',
                iconColor: AppColors.success,
              ),
              const SizedBox(height: 8),
              _BiometricCard(controller: controller),
              const SizedBox(height: 24),

              // ── Section: Security Information ─────────────────────────────
              const _SectionHeader(
                icon: Icons.security_rounded,
                label: 'SECURITY INFORMATION',
                iconColor: AppColors.textSecondary,
              ),
              const SizedBox(height: 8),
              const _SecurityInfoCard(),
              const SizedBox(height: 24),

              // ── Section: Session ──────────────────────────────────────────
              if (controller.isAuthenticated) ...[
                const _SectionHeader(
                  icon: Icons.link_rounded,
                  label: 'ACTIVE SESSION',
                  iconColor: AppColors.success,
                ),
                const SizedBox(height: 8),
                _ActiveSessionCard(controller: controller),
              ],
            ],
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Section header
// ─────────────────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.label,
    required this.iconColor,
  });

  final IconData icon;
  final String label;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: iconColor, size: 14),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            color: iconColor,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.4,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Device Identity Card
// ─────────────────────────────────────────────────────────────────────────────

class _DeviceIdentityCard extends StatefulWidget {
  const _DeviceIdentityCard({required this.controller});

  final CraneController controller;

  @override
  State<_DeviceIdentityCard> createState() => _DeviceIdentityCardState();
}

class _DeviceIdentityCardState extends State<_DeviceIdentityCard> {
  bool _copied = false;

  void _copyDeviceId() {
    final id = widget.controller.deviceId;
    if (id.isEmpty) return;
    Clipboard.setData(ClipboardData(text: id));
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.controller.deviceId;
    final displayId = id.isEmpty ? 'Initializing…' : id;

    return _IndustrialCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.accentSoft,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: AppColors.accent.withValues(alpha: 0.3),
                  ),
                ),
                child: const Text(
                  'PERMANENT IDENTITY',
                  style: TextStyle(
                    color: AppColors.accent,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              const Spacer(),
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: AppColors.success,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              const Text(
                'ACTIVE',
                style: TextStyle(
                  color: AppColors.success,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            'Device ID',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF0A1520),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: Text(
              displayId,
              style: const TextStyle(
                color: AppColors.accent,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
                fontFamily: 'monospace',
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Register this Device ID in the PLC web interface to authorize this '
            'device for control access.',
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 11.5,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _ActionButton(
                  icon: _copied ? Icons.check_rounded : Icons.copy_rounded,
                  label: _copied ? 'Copied' : 'Copy Device ID',
                  color: _copied ? AppColors.success : AppColors.accent,
                  onTap: id.isEmpty ? null : _copyDeviceId,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Biometric Card
// ─────────────────────────────────────────────────────────────────────────────

class _BiometricCard extends StatelessWidget {
  const _BiometricCard({required this.controller});

  final CraneController controller;

  @override
  Widget build(BuildContext context) {
    final available = controller.isBiometricAvailable;
    final enrolled = controller.isBiometricEnrolled;

    return _IndustrialCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.face_unlock_rounded,
                color: enrolled ? AppColors.success : AppColors.disabled,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Biometric Quick-Auth',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      enrolled
                          ? 'Credentials enrolled. Fingerprint/face login active.'
                          : available
                          ? 'Hardware available. Log in manually to enroll.'
                          : 'No biometric hardware detected on this device.',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11.5,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: enrolled
                      ? AppColors.successSoft
                      : AppColors.border.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  enrolled ? 'ON' : 'OFF',
                  style: TextStyle(
                    color: enrolled ? AppColors.success : AppColors.disabled,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ],
          ),
          if (enrolled) ...[
            const SizedBox(height: 14),
            Container(height: 1, color: AppColors.border),
            const SizedBox(height: 14),
            _ActionButton(
              icon: Icons.delete_outline_rounded,
              label: 'Revoke Biometric Access',
              color: AppColors.danger,
              outlined: true,
              onTap: () => _confirmRevoke(context, controller),
            ),
          ],
        ],
      ),
    );
  }

  void _confirmRevoke(BuildContext context, CraneController controller) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.panelAlt,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.border),
        ),
        title: const Text(
          'Revoke Biometric Access',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: const Text(
          'Stored operator credentials will be permanently removed from this '
          'device keystore. You will need to log in manually to re-enroll.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(
              'Cancel',
              style: TextStyle(color: AppColors.textMuted),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              controller.clearBiometricEnrollment();
            },
            child: const Text(
              'Revoke',
              style: TextStyle(
                color: AppColors.danger,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Security Information Card
// ─────────────────────────────────────────────────────────────────────────────

class _SecurityInfoCard extends StatelessWidget {
  const _SecurityInfoCard();

  @override
  Widget build(BuildContext context) {
    return const _IndustrialCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SecurityFact(
            icon: Icons.lock_rounded,
            label: 'AES-128-GCM Encrypted Communication',
            // detail:
            //     'All BLE traffic is encrypted and authenticated. Replay attacks '
            //     'are prevented by a monotonic session counter.',
          ),
          SizedBox(height: 12),
          _SecurityFact(
            icon: Icons.verified_user_rounded,
            label: 'Triple Authorization Gate',
            // detail:
            //     'Control access requires (1) trusted device, (2) valid operator '
            //     'credentials, and (3) an active encrypted session — all three '
            //     'must pass.',
          ),
          SizedBox(height: 12),
          _SecurityFact(
            icon: Icons.phonelink_lock_rounded,
            label: 'Device Identity — Android Keystore',
            // detail:
            //     'The Device ID is stored in hardware-backed Android Keystore '
            //     '(EncryptedSharedPreferences). It is never transmitted in '
            //     'plaintext.',
          ),
          SizedBox(height: 12),
          _SecurityFact(
            icon: Icons.shield_rounded,
            label: 'Fail-Safe Default',
            // detail:
            //     'On any validation failure the PLC enters safe state: all '
            //     'outputs OFF, heartbeat ignored, session cleared. The system '
            //     'never defaults to an unsafe state.',
          ),
        ],
      ),
    );
  }
}

class _SecurityFact extends StatelessWidget {
  const _SecurityFact({
    required this.icon,
    required this.label,
    // required this.detail,
  });

  final IconData icon;
  final String label;
  // final String detail;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: AppColors.panelStroke.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: AppColors.textSecondary, size: 16),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              // Text(
              //   detail,
              //   style: const TextStyle(
              //     color: AppColors.textMuted,
              //     fontSize: 11.5,
              //     height: 1.45,
              //   ),
              // ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Active Session Card
// ─────────────────────────────────────────────────────────────────────────────

class _ActiveSessionCard extends StatelessWidget {
  const _ActiveSessionCard({required this.controller});

  final CraneController controller;

  @override
  Widget build(BuildContext context) {
    return _IndustrialCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _InfoRow(
            label: 'Operator',
            value: controller.sessionEmail ?? '—',
            valueColor: AppColors.success,
          ),
          const SizedBox(height: 8),
          _InfoRow(
            label: 'PLC Device',
            value: controller.connectedDeviceName ?? '—',
          ),
          const SizedBox(height: 8),
          _InfoRow(
            label: 'Signal',
            value: controller.connectedDeviceRssi != null
                ? '${controller.connectedDeviceRssi} dBm'
                : '—',
          ),
          const SizedBox(height: 8),
          const _InfoRow(label: 'Encryption', value: 'AES-128-GCM Active'),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value, this.valueColor});

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textMuted,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: valueColor ?? AppColors.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared primitives
// ─────────────────────────────────────────────────────────────────────────────

class _IndustrialCard extends StatelessWidget {
  const _IndustrialCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.panelStroke),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    this.outlined = false,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final bool outlined;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: outlined ? Colors.transparent : color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: onTap != null
                ? color.withValues(alpha: outlined ? 0.6 : 0.35)
                : AppColors.border,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: onTap != null ? color : AppColors.disabled,
              size: 16,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: onTap != null ? color : AppColors.disabled,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
