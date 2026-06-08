import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:tusker_trailer_rrc/utils/constants.dart';
import 'package:tusker_trailer_rrc/screens/settings_screen.dart';
import 'package:tusker_trailer_rrc/models/ble_connection_state.dart';
import 'package:tusker_trailer_rrc/services/biometric_service.dart';
import 'package:tusker_trailer_rrc/controllers/crane_controllers.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _seeded = false;
  bool _obscurePassword = true;
  bool _biometricLoading = false;
  BiometricAuthResult? _lastBiometricResult;
  AutovalidateMode _autovalidateMode = AutovalidateMode.disabled;

  late final AnimationController _introController;
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _introController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();

    _introController.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_seeded) return;

    final controller = context.read<CraneController>();
    _emailController.text = controller.savedEmail;
    _passwordController.text = controller.savedPassword;
    _seeded = true;
  }

  @override
  void dispose() {
    _introController.dispose();
    _pulseController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<CraneController>();

    return Scaffold(
      backgroundColor: ConnectionColors.background,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF8FBFF), ConnectionColors.background],
          ),
        ),
        child: Stack(
          children: [
            _buildBackgroundCircles(),
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 18,
                  ),
                  child: FadeTransition(
                    opacity: _introController.drive(
                      Tween<double>(begin: 0, end: 1),
                    ),
                    child: SlideTransition(
                      position: _introController.drive(
                        Tween<Offset>(
                          begin: const Offset(0, 0.05),
                          end: Offset.zero,
                        ),
                      ),
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 1100),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF2F7FD).withOpacity(0.86),
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(color: ConnectionColors.border),
                          boxShadow: [
                            BoxShadow(
                              color: ConnectionColors.primary.withOpacity(0.08),
                              blurRadius: 28,
                              offset: const Offset(0, 14),
                            ),
                          ],
                        ),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final isWide = constraints.maxWidth >= 920;
                            return isWide
                                ? Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Flexible(
                                        flex: 5,
                                        child: _buildContextPanel(controller),
                                      ),
                                      const SizedBox(width: 16),
                                      Flexible(
                                        flex: 6,
                                        child: _buildFormPanel(
                                          controller,
                                          isWide: true,
                                        ),
                                      ),
                                    ],
                                  )
                                : Column(
                                    children: [
                                      _buildContextPanel(controller),
                                      const SizedBox(height: 12),
                                      _buildFormPanel(
                                        controller,
                                        isWide: false,
                                      ),
                                    ],
                                  );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBackgroundCircles() {
    return Stack(
      children: [
        Positioned(
          top: -120,
          right: -90,
          child: Container(
            width: 280,
            height: 280,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: ConnectionColors.scanning.withOpacity(0.08),
            ),
          ),
        ),
        Positioned(
          bottom: -120,
          left: -100,
          child: Container(
            width: 300,
            height: 300,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: ConnectionColors.primary.withOpacity(0.06),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildContextPanel(CraneController controller) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [ConnectionColors.primary, Color(0xFF225A95)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              color: Colors.white.withOpacity(0.16),
              border: Border.all(color: Colors.white.withOpacity(0.18)),
            ),
            child: const Text(
              'SECURE BLE LINK',
              style: TextStyle(
                color: Colors.white,
                fontSize: 8,
                letterSpacing: 1.1,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 5),
          Center(
            child: _BeaconPulse(
              animation: _pulseController,
              active:
                  controller.isAuthenticating ||
                  controller.connectionState.status ==
                      BleConnectionStatus.authenticated,
            ),
          ),
          const SizedBox(height: 0),
          const Text(
            'Authenticate Operator Session',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Connection is established. Verify credentials before crane commands are enabled.',
            style: TextStyle(
              color: Colors.white.withOpacity(0.88),
              fontSize: 13,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormPanel(CraneController controller, {required bool isWide}) {
    final authSessionReady = _hasAuthenticationSession(controller);
    final errorState = _resolveErrorState(controller.errorMessage);
    final bool busy = controller.isAuthenticating || _biometricLoading;

    return Container(
      padding: EdgeInsets.all(isWide ? 26 : 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: ConnectionColors.surface,
        border: Border.all(color: ConnectionColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildLiveStatusBanner(controller),
          if (controller.isAuthenticating) ...[
            const SizedBox(height: 12),
            const _BusyCard(),
          ],
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: errorState == null
                ? const SizedBox.shrink()
                : Padding(
                    key: ValueKey(errorState.message),
                    padding: const EdgeInsets.only(top: 12),
                    child: _AuthErrorCard(
                      state: errorState,
                      onRetry: controller.isAuthenticating ? null : _submit,
                      onBackToScan: controller.disconnect,
                    ),
                  ),
          ),
          if (!authSessionReady && errorState == null) ...[
            const SizedBox(height: 12),
            _AuthErrorCard(
              state: const _AuthErrorState(
                title: 'Connection ended',
                message:
                    'The authentication link is no longer active. Return to scan and reconnect to PLC14.',
                icon: Icons.bluetooth_disabled_rounded,
              ),
              onBackToScan: controller.disconnect,
            ),
          ],
          const SizedBox(height: 16),
          Form(
            key: _formKey,
            autovalidateMode: _autovalidateMode,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _emailController,
                  enabled: !busy,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  style: const TextStyle(
                    color: ConnectionColors.textPrimary,
                    fontSize: 14,
                  ),
                  decoration: _buildInputDecoration(
                    label: 'Operator email',
                    hint: 'operator@company.com',
                    icon: Icons.alternate_email_rounded,
                  ),
                  validator: (value) {
                    final candidate = value?.trim() ?? '';
                    if (candidate.isEmpty) {
                      return 'Email is required to authenticate with PLC14.';
                    }
                    if (!candidate.contains('@') || !candidate.contains('.')) {
                      return 'Enter a valid email format (example: user@domain.com).';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _passwordController,
                  enabled: !busy,
                  obscureText: _obscurePassword,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _submit(),
                  style: const TextStyle(
                    color: ConnectionColors.textPrimary,
                    fontSize: 14,
                  ),
                  decoration: _buildInputDecoration(
                    label: 'Password',
                    hint: 'Enter your password',
                    icon: Icons.lock_outline_rounded,
                    suffix: IconButton(
                      onPressed: () {
                        setState(() {
                          _obscurePassword = !_obscurePassword;
                        });
                      },
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_off_rounded
                            : Icons.visibility_rounded,
                        color: ConnectionColors.textMuted,
                        size: 20,
                      ),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Password is required for operator access.';
                    }
                    if (value.length < 6) {
                      return 'Password must be at least 6 characters.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Remember credentials on this device',
                        style: TextStyle(
                          color: ConnectionColors.textSecondary.withOpacity(
                            0.85,
                          ),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Switch.adaptive(
                      value: controller.rememberCredentials,
                      activeThumbColor: ConnectionColors.scanning,
                      activeTrackColor: ConnectionColors.scanning.withOpacity(
                        0.35,
                      ),
                      onChanged: busy
                          ? null
                          : controller.setRememberCredentials,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton.icon(
              onPressed: busy ? null : _submit,
              icon: busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.lock_open_rounded, size: 18),
              label: Text(
                busy ? 'AUTHENTICATING...' : 'AUTHENTICATE SESSION',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: ConnectionColors.scanning,
                foregroundColor: Colors.white,
                disabledBackgroundColor: ConnectionColors.neutral,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: busy ? null : controller.disconnect,
              icon: const Icon(Icons.arrow_back_rounded, size: 16),
              label: const Text('Back to Scan'),
              style: OutlinedButton.styleFrom(
                foregroundColor: ConnectionColors.textSecondary,
                side: const BorderSide(color: ConnectionColors.border),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          if (_biometricLoginVisible(controller)) ...[
            const SizedBox(height: 14),
            const Row(
              children: [
                Expanded(child: Divider(color: ConnectionColors.border)),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 14),
                  child: Text(
                    'OR',
                    style: TextStyle(
                      color: ConnectionColors.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
                Expanded(child: Divider(color: ConnectionColors.border)),
              ],
            ),
            const SizedBox(height: 12),
            if (_lastBiometricResult != null &&
                !_lastBiometricResult!.isSuccess &&
                !_lastBiometricResult!.isCancelled)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _AuthErrorCard(
                  state: _resolveBiometricError(_lastBiometricResult!),
                ),
              ),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: OutlinedButton.icon(
                onPressed: busy ? null : _submitWithBiometrics,
                style: OutlinedButton.styleFrom(
                  foregroundColor: ConnectionColors.primary,
                  side: const BorderSide(
                    color: ConnectionColors.border,
                    width: 1.5,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: _biometricLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: ConnectionColors.primary,
                        ),
                      )
                    : const Icon(Icons.fingerprint, size: 22),
                label: Text(
                  _biometricLoading
                      ? 'VERIFYING IDENTITY...'
                      : 'BIOMETRIC LOGIN',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    fontSize: 13.5,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLiveStatusBanner(CraneController controller) {
    final status = controller.connectionState.status;
    final bool busy = controller.isAuthenticating;

    final (Color tone, String message) = switch (status) {
      BleConnectionStatus.awaitingAuthentication => (
        ConnectionColors.scanning,
        'Connected and waiting for credentials.',
      ),
      BleConnectionStatus.authenticating => (
        ConnectionColors.scanning,
        'Credentials are being verified by PLC14.',
      ),
      BleConnectionStatus.error => (
        ConnectionColors.error,
        'Authentication needs attention before continuing.',
      ),
      _ => (
        ConnectionColors.neutral,
        'Return to scanning if connection is unavailable.',
      ),
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tone.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tone.withOpacity(0.22)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 22,
            height: 22,
            child: busy
                ? CircularProgressIndicator(strokeWidth: 2.2, color: tone)
                : Icon(Icons.info_outline_rounded, color: tone, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: ConnectionColors.textSecondary,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _buildInputDecoration({
    required String label,
    required String hint,
    required IconData icon,
    Widget? suffix,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      hintStyle: const TextStyle(color: ConnectionColors.textMuted),
      labelStyle: const TextStyle(color: ConnectionColors.textMuted),
      prefixIcon: Icon(icon, color: ConnectionColors.textMuted, size: 20),
      suffixIcon: suffix,
      filled: true,
      fillColor: const Color(0xFFF8FAFD),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: ConnectionColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: ConnectionColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(
          color: ConnectionColors.scanning,
          width: 1.6,
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: ConnectionColors.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: ConnectionColors.error, width: 1.6),
      ),
    );
  }

  bool _hasAuthenticationSession(CraneController controller) {
    final status = controller.connectionState.status;
    final hasDevice = controller.connectionState.connectedDevice != null;
    return status == BleConnectionStatus.awaitingAuthentication ||
        status == BleConnectionStatus.authenticating ||
        (status == BleConnectionStatus.error && hasDevice) ||
        controller.hasPendingEnrollmentOffer;
  }

  _AuthErrorState? _resolveErrorState(String? message) {
    if (message == null || message.trim().isEmpty) return null;

    final raw = message.trim();
    final normalized = raw.toLowerCase();

    if (raw == BLEConstants.authUntrusted ||
        normalized.contains('device not authorized') ||
        normalized.contains('not registered')) {
      return const _AuthErrorState(
        title: 'Device Not Authorized',
        message:
            'This device is not in the PLC trusted-device registry. '
            'Open Device Settings to copy your Device ID and provide it '
            'to your system administrator for registration.',
        icon: Icons.block_rounded,
        isTrustRejection: true,
      );
    }

    if (normalized.contains('credentials were rejected')) {
      return const _AuthErrorState(
        title: 'Invalid credentials',
        message:
            'The PLC rejected this email or password. Check both fields and try again.',
        icon: Icons.lock_person_rounded,
      );
    }

    if (normalized.contains('timed out') || normalized.contains('timeout')) {
      return const _AuthErrorState(
        title: 'Authentication timeout',
        message:
            'PLC14 did not respond in time. Stay close to the device and retry.',
        icon: Icons.timer_off_rounded,
      );
    }

    if (normalized.contains('connection') ||
        normalized.contains('disconnect')) {
      return const _AuthErrorState(
        title: 'Connection issue',
        message:
            'The BLE session became unstable. Return to scan and reconnect.',
        icon: Icons.bluetooth_disabled_rounded,
      );
    }

    return _AuthErrorState(
      title: 'Authentication error',
      message: raw,
      icon: Icons.error_outline_rounded,
    );
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _autovalidateMode = AutovalidateMode.onUserInteraction;
    });

    if (!_formKey.currentState!.validate()) return;

    final controller = context.read<CraneController>();
    if (!_hasAuthenticationSession(controller)) {
      _showSnack('Connection session ended. Return to scan and reconnect.');
      return;
    }

    final email = _emailController.text.trim();
    final password = _passwordController.text;

    final success = await controller.authenticate(
      email: email,
      password: password,
    );

    if (!mounted) return;

    if (success) {
      if (controller.hasPendingEnrollmentOffer) {
        await _offerBiometricEnrollment(
          email: email,
          password: password,
          controller: controller,
        );
      }
      if (mounted) {
        context.read<CraneController>().completePendingEnrollmentOffer();
      }
      return;
    }
    // Auth failure is already surfaced inline via _AuthErrorCard.
    // No additional snackbar is needed.
  }

  bool _biometricLoginVisible(CraneController controller) {
    return controller.isBiometricAvailable &&
        controller.isBiometricEnrolled &&
        _hasAuthenticationSession(controller);
  }

  Future<void> _submitWithBiometrics() async {
    if (_biometricLoading || !mounted) return;

    final controller = context.read<CraneController>();
    if (!_hasAuthenticationSession(controller)) {
      _showSnack('Connection session ended. Return to scan and reconnect.');
      return;
    }

    setState(() {
      _biometricLoading = true;
      _lastBiometricResult = null;
    });

    final result = await controller.authenticateWithBiometrics();

    if (!mounted) return;

    setState(() {
      _biometricLoading = false;
      if (!result.isSuccess && !result.isCancelled) {
        _lastBiometricResult = result;
      }
    });
  }

  Future<void> _offerBiometricEnrollment({
    required String email,
    required String password,
    required CraneController controller,
  }) async {
    if (!mounted) return;
    if (!controller.isBiometricAvailable || controller.isBiometricEnrolled)
      return;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => const _BiometricEnrollmentDialog(),
    );

    if (!mounted || confirmed != true) return;

    final ctrl = context.read<CraneController>();
    final enrolled = await ctrl.enrollBiometrics(
      email: email,
      password: password,
    );

    if (mounted && enrolled) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          duration: const Duration(seconds: 3),
          backgroundColor: ConnectionColors.connected,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          content: const Row(
            children: [
              Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Fingerprint login enabled for this device.',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
  }

  _AuthErrorState _resolveBiometricError(BiometricAuthResult result) {
    return switch (result.status) {
      BiometricAuthStatus.failure => const _AuthErrorState(
        title: 'PLC authentication failed',
        message:
            'PLC rejected stored credentials. Log in manually to re-enrol.',
        icon: Icons.lock_person_rounded,
      ),
      BiometricAuthStatus.lockedOut => const _AuthErrorState(
        title: 'Biometric temporarily locked',
        message: 'Too many failed attempts. Wait briefly, then retry.',
        icon: Icons.lock_clock_rounded,
      ),
      BiometricAuthStatus.permanentlyLockedOut => const _AuthErrorState(
        title: 'Biometric permanently locked',
        message: 'Unlock your device with PIN to reset biometrics.',
        icon: Icons.lock_outline_rounded,
      ),
      BiometricAuthStatus.notEnrolled => const _AuthErrorState(
        title: 'No fingerprints enrolled',
        message: 'Configure fingerprint in device security settings.',
        icon: Icons.fingerprint,
      ),
      BiometricAuthStatus.credentialsMissing => const _AuthErrorState(
        title: 'Credentials not found',
        message: 'Stored credentials were cleared. Log in manually.',
        icon: Icons.key_off_rounded,
      ),
      _ => _AuthErrorState(
        title: 'Biometric error',
        message: result.message ?? 'An unexpected error occurred.',
        icon: Icons.error_outline_rounded,
      ),
    };
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          backgroundColor: ConnectionColors.error,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          content: Text(
            message,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
  }
}

// ============================================================================
// Supporting Widgets
// ============================================================================

class _BeaconPulse extends StatelessWidget {
  const _BeaconPulse({required this.animation, required this.active});

  final Animation<double> animation;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final progress = animation.value;
        final waveScale = 1 + (progress * 0.35);
        final innerScale = 0.88 + (progress * 0.2);
        final waveOpacity = active ? (0.4 - (progress * 0.35)) : 0.08;

        return SizedBox(
          width: 130,
          height: 130,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Transform.scale(
                scale: waveScale,
                child: Container(
                  width: 82,
                  height: 82,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(
                      waveOpacity.clamp(0.05, 0.42),
                    ),
                  ),
                ),
              ),
              Transform.scale(
                scale: innerScale,
                child: Container(
                  width: 82,
                  height: 82,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withOpacity(0.3)),
                  ),
                ),
              ),
              child!,
            ],
          ),
        );
      },
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withOpacity(0.96),
        ),
        child: const Icon(
          Icons.bluetooth_searching_rounded,
          color: ConnectionColors.primary,
          size: 34,
        ),
      ),
    );
  }
}

class _BusyCard extends StatelessWidget {
  const _BusyCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: ConnectionColors.scanningBg,
        border: Border.all(color: ConnectionColors.scanningBorder),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Authenticating with PLC14...',
            style: TextStyle(
              color: ConnectionColors.scanning,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
          SizedBox(height: 7),
          LinearProgressIndicator(
            minHeight: 4,
            backgroundColor: Color(0xFFC8DBF3),
            valueColor: AlwaysStoppedAnimation<Color>(
              ConnectionColors.scanning,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'Waiting for controller response. This usually takes a few seconds.',
            style: TextStyle(
              color: ConnectionColors.textSecondary,
              fontSize: 12,
              height: 1.25,
            ),
          ),
        ],
      ),
    );
  }
}

class _AuthErrorState {
  const _AuthErrorState({
    required this.title,
    required this.message,
    required this.icon,
    this.isTrustRejection = false,
  });

  final String title;
  final String message;
  final IconData icon;
  final bool isTrustRejection;
}

class _AuthErrorCard extends StatelessWidget {
  const _AuthErrorCard({required this.state, this.onRetry, this.onBackToScan});

  final _AuthErrorState state;
  final VoidCallback? onRetry;
  final VoidCallback? onBackToScan;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: ConnectionColors.errorBg,
        border: Border.all(color: ConnectionColors.errorBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(state.icon, color: ConnectionColors.error, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  state.title,
                  style: const TextStyle(
                    color: ConnectionColors.error,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            state.message,
            style: const TextStyle(
              color: ConnectionColors.textSecondary,
              fontSize: 12.5,
              height: 1.3,
            ),
          ),
          if (onRetry != null ||
              onBackToScan != null ||
              state.isTrustRejection) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (state.isTrustRejection)
                  OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const SettingsScreen(),
                      ),
                    ),
                    icon: const Icon(Icons.settings_rounded, size: 14),
                    label: const Text('Open Device Settings'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: ConnectionColors.error,
                      side: const BorderSide(
                        color: ConnectionColors.errorBorder,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      textStyle: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      minimumSize: Size.zero,
                    ),
                  ),
                if (onRetry != null)
                  FilledButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh_rounded, size: 14),
                    label: const Text('Retry'),
                    style: FilledButton.styleFrom(
                      backgroundColor: ConnectionColors.error,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      textStyle: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      minimumSize: Size.zero,
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _BiometricEnrollmentDialog extends StatelessWidget {
  const _BiometricEnrollmentDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: ConnectionColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      actionsPadding: const EdgeInsets.fromLTRB(12, 8, 12, 14),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: ConnectionColors.primarySoft,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.fingerprint,
              color: ConnectionColors.primary,
              size: 22,
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Enable Fingerprint Login',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: ConnectionColors.textPrimary,
                height: 1.2,
              ),
            ),
          ),
        ],
      ),
      content: const Text(
        'Access this device faster next session using your fingerprint or '
        'face ID — no need to re-enter your credentials.\n\n'
        "Your operator credentials are stored in this device's hardware "
        'keystore and are never transmitted over the network.',
        style: TextStyle(
          color: ConnectionColors.textSecondary,
          fontSize: 13.5,
          height: 1.45,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          style: TextButton.styleFrom(
            foregroundColor: ConnectionColors.textMuted,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: const Text(
            'NOT NOW',
            style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.5),
          ),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: FilledButton.styleFrom(
            backgroundColor: ConnectionColors.primary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          ),
          child: const Text(
            'ENABLE',
            style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.5),
          ),
        ),
      ],
    );
  }
}
