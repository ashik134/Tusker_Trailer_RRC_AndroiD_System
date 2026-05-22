import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'package:tusker_trailer_rrc/controllers/crane_controllers.dart';
import 'package:tusker_trailer_rrc/security/crypto_service.dart';
import 'package:tusker_trailer_rrc/security/secure_key_store.dart';

typedef StartupProgressCallback = void Function(String message);

class AppStartupInitializer {
  AppStartupInitializer({required CraneController controller})
    : _controller = controller;

  final CraneController _controller;

  Future<void> initialize({StartupProgressCallback? onProgress}) async {
    // ── Phase 1: Security layer ──────────────────────────────────────────────
    // Must complete before any BLE write is permitted.
    onProgress?.call('Initializing security layer');
    await _initializeSecurity();

    // ── Phase 2: Runtime policies ────────────────────────────────────────────
    onProgress?.call('Applying runtime policies');
    await Future.wait<void>([
      _safeTask(() async {
        await SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
        ]);
      }),
      _safeTask(() async {
        await WakelockPlus.enable();
      }),
    ]);

    // ── Phase 3: BLE and safety services ────────────────────────────────────
    onProgress?.call('Preparing BLE and safety services');
    await _controller.initialize();

    onProgress?.call('Startup checks complete');
  }

  /// Load the deployment AES-128 key from Android Keystore / iOS Keychain
  /// and initialize the [CryptoService] singleton.
  ///
  /// In release builds, a missing key causes a [StateError] and the app will
  /// not proceed past the splash screen — the unit must be recommissioned.
  /// In debug builds a development key is used with a console warning.
  Future<void> _initializeSecurity() async {
    try {
      final keyBytes = await SecureKeyStore.instance.loadKey();
      await CryptoService.instance.initialize(keyBytes);
      debugPrint(
        '[Security] CryptoService initialized. '
        'Provisioned key: ${SecureKeyStore.instance.isProvisioned}',
      );
    } catch (e) {
      debugPrint('[Security] ⚠  CryptoService initialization failed: $e');
      // Re-throw in release builds — the app must not run without encryption.
      if (!kDebugMode) rethrow;
    }
  }

  Future<void> _safeTask(Future<void> Function() task) async {
    try {
      await task();
    } catch (_) {
      // Non-fatal startup tasks must never crash the app launch.
    }
  }
}
