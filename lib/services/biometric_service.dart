import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth/error_codes.dart' as auth_error;

/// Describes device-level biometric hardware and enrollment status.
enum BiometricAvailability {
 
  available,

 
  notAvailable,

  
  notEnrolled,

  lockedOut,

 
  unknown,
}


enum BiometricAuthStatus {
  /// Biometric verified successfully.
  success,

  /// Operator dismissed or cancelled the system biometric prompt.
  cancelled,

  /// PLC rejected the stored operator credentials retrieved after biometric
  /// verification. Stored credentials may be stale.
  failure,

  /// Too many failed attempts — biometric authentication is temporarily locked.
  lockedOut,

  /// Biometric permanently locked — device PIN required to reset.
  permanentlyLockedOut,

  /// Biometric hardware not available on this device.
  notAvailable,

  /// No biometrics enrolled on the device.
  notEnrolled,

  /// App-level biometric credentials are absent or corrupted in secure storage.
  credentialsMissing,

  /// An unexpected error occurred.
  unknown,
}

/// Result returned by [BiometricService.authenticate].
///
/// Never throws — failures are communicated through [status] and [message].
class BiometricAuthResult {
  const BiometricAuthResult({required this.status, this.message});

  final BiometricAuthStatus status;

  /// Human-readable description, present for all non-success outcomes.
  final String? message;

  bool get isSuccess => status == BiometricAuthStatus.success;
  bool get isCancelled => status == BiometricAuthStatus.cancelled;
}

/// Static service for biometric availability checks and authentication.
///
/// All methods are static. The [LocalAuthentication] instance is retained at
/// module scope so [stopAuthentication] can interrupt an in-progress prompt.
class BiometricService {
  BiometricService._();

  static final LocalAuthentication _auth = LocalAuthentication();

  //  Availability 

  
  static Future<BiometricAvailability> checkAvailability() async {
    try {
      final isSupported = await _auth.isDeviceSupported();
      if (!isSupported) return BiometricAvailability.notAvailable;

      final canCheck = await _auth.canCheckBiometrics;
      if (!canCheck) return BiometricAvailability.notEnrolled;

      final enrolled = await _auth.getAvailableBiometrics();
      if (enrolled.isEmpty) return BiometricAvailability.notEnrolled;

      return BiometricAvailability.available;
    } on PlatformException catch (e) {
      final code = e.code;
      if (code == auth_error.lockedOut ||
          code == auth_error.permanentlyLockedOut) {
        return BiometricAvailability.lockedOut;
      }
      return BiometricAvailability.unknown;
    } catch (_) {
      return BiometricAvailability.unknown;
    }
  }

 
  static Future<bool> isAvailableAndEnrolled() async =>
      (await checkAvailability()) == BiometricAvailability.available;

  
  static Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _auth.getAvailableBiometrics();
    } catch (_) {
      return const [];
    }
  }

  // ── Authentication

 
  static Future<BiometricAuthResult> authenticate() async {
    try {
      final authenticated = await _auth.authenticate(
        localizedReason:
            'Authenticate to access the Tusker crane control session.',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
          sensitiveTransaction: true,
          useErrorDialogs: true,
        ),
      );

      if (authenticated) {
        return const BiometricAuthResult(status: BiometricAuthStatus.success);
      }

      
      return const BiometricAuthResult(
        status: BiometricAuthStatus.cancelled,
        message: 'Biometric authentication cancelled.',
      );
    } on PlatformException catch (e) {
      return _fromPlatformException(e);
    } catch (e) {
      return BiometricAuthResult(
        status: BiometricAuthStatus.unknown,
        message: 'Unexpected authentication error: ${e.toString()}',
      );
    }
  }

 
  static BiometricAuthResult _fromPlatformException(PlatformException e) {
    final code = e.code;

    if (code == auth_error.notAvailable) {
      return const BiometricAuthResult(
        status: BiometricAuthStatus.notAvailable,
        message: 'Biometric hardware not available on this device.',
      );
    }
    if (code == auth_error.notEnrolled || code == auth_error.passcodeNotSet) {
      return const BiometricAuthResult(
        status: BiometricAuthStatus.notEnrolled,
        message:
            'No biometrics enrolled. Add a fingerprint in device security settings.',
      );
    }
    if (code == auth_error.lockedOut) {
      return const BiometricAuthResult(
        status: BiometricAuthStatus.lockedOut,
        message:
            'Biometric authentication is temporarily locked. Please wait before retrying.',
      );
    }
    if (code == auth_error.permanentlyLockedOut) {
      return const BiometricAuthResult(
        status: BiometricAuthStatus.permanentlyLockedOut,
        message:
            'Biometric permanently locked. Unlock your device with PIN to reset, then re-enroll.',
      );
    }

    return BiometricAuthResult(
      status: BiometricAuthStatus.unknown,
      message: e.message ?? 'Biometric authentication failed (code: $code).',
    );
  }

  static Future<void> stopAuthentication() async {
    try {
      await _auth.stopAuthentication();
    } catch (_) {}
  }
}
