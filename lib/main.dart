import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

import 'package:tusker_trailer_rrc/models/app_enums.dart';
import 'package:tusker_trailer_rrc/utils/constants.dart';

import 'package:tusker_trailer_rrc/theme/app_theme.dart';

import 'package:tusker_trailer_rrc/screens/login_screen.dart';
import 'package:tusker_trailer_rrc/screens/splash_screen.dart';
import 'package:tusker_trailer_rrc/screens/control_screen.dart';
import 'package:tusker_trailer_rrc/screens/connection_screen.dart';

import 'package:tusker_trailer_rrc/controllers/crane_controllers.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TuskerRRCApp());
}

class TuskerRRCApp extends StatelessWidget {
  const TuskerRRCApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => CraneController(),
      child: MaterialApp(
        title: AppConstants.appTitle,
        theme: AppTheme.theme,
        showPerformanceOverlay: false,
        debugShowCheckedModeBanner: false,
        home: StartupSplashScreen(
          destinationBuilder: (_) => const CraneAppShell(),
        ),
      ),
    );
  }
}

class CraneAppShell extends StatelessWidget {
  const CraneAppShell({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<CraneController>(
      builder: (context, controller, _) {
        final currentScreen = controller.currentScreen;
        final destination = switch (currentScreen) {
          AppScreen.connection => const ConnectionScreen(),
          AppScreen.authentication => const LoginScreen(),
          AppScreen.control => const ControlScreen(),
        };

        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 320),
          reverseDuration: const Duration(milliseconds: 240),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) {
            final offsetAnimation =
                Tween<Offset>(
                  begin: const Offset(0.025, 0),
                  end: Offset.zero,
                ).animate(
                  CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutCubic,
                  ),
                );
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(position: offsetAnimation, child: child),
            );
          },
          child: KeyedSubtree(key: ValueKey(currentScreen), child: destination),
        );
      },
    );
  }
}
