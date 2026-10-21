import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/localization/language_controller.dart';
import '../features/app_update/presentation/force_update_screen.dart';
import '../features/app_update/presentation/maintenance_screen.dart';
import '../features/app_update/presentation/not_found_screen.dart';
import '../features/app_update/presentation/splash_screen.dart';
import '../features/app_update/presentation/unreachable_screen.dart';
import '../features/authentication/presentation/language_onboarding_screen.dart';
import '../features/authentication/presentation/link_account_screen.dart';
import '../features/authentication/presentation/login_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import 'feature_routes.dart';
import 'gate/app_gate_controller.dart';
import 'routes.dart';
import 'shell/main_shell.dart';

/// Root navigator key (dialogs shown from the app shell use it).
final rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

/// Pure redirect decision for the gate (unit tested).
///
/// [pending] receives the protected location the user tried to open before
/// the gate was ready; it is resumed once ready.
String? gateRedirect({
  required GatePhase phase,
  required String location,
  required bool languageChosen,
  String? pendingLocation,
  void Function(String location)? rememberPending,
}) {
  final path = Uri.parse(location).path;
  final isGate = AppRoutes.gateRoutes.contains(path);
  final isPreAuth = AppRoutes.preAuthRoutes.contains(path);
  String? to(String target) => path == target ? null : target;

  switch (phase) {
    case GatePhase.initializing:
    case GatePhase.checkingPolicy:
    case GatePhase.optionalUpdatePrompt:
    case GatePhase.restoringSession:
    case GatePhase.loadingWallet:
      if (!isGate && !isPreAuth && path != '/') rememberPending?.call(location);
      return to(AppRoutes.splash);
    case GatePhase.maintenance:
      return to(AppRoutes.maintenance);
    case GatePhase.forceUpdate:
      return to(AppRoutes.updateRequired);
    case GatePhase.unreachable:
      return to(AppRoutes.unreachable);
    case GatePhase.signedOut:
      if (!isGate && !isPreAuth && path != '/') rememberPending?.call(location);
      if (!languageChosen) return to(AppRoutes.languageOnboarding);
      return isPreAuth ? null : AppRoutes.login;
    case GatePhase.ready:
      if (isGate || isPreAuth || path == '/') {
        return pendingLocation ?? AppRoutes.home;
      }
      return null;
  }
}

final appRouterProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.listen(
    appGateControllerProvider.select((s) => s.phase),
    (_, _) => refresh.value++,
  );
  ref.listen(languageControllerProvider, (_, _) => refresh.value++);

  String? pending;

  final router = GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: AppRoutes.splash,
    refreshListenable: refresh,
    debugLogDiagnostics: false,
    redirect: (context, state) {
      final phase = ref.read(appGateControllerProvider).phase;
      final target = gateRedirect(
        phase: phase,
        location: state.uri.toString(),
        languageChosen: ref
            .read(languageControllerProvider.notifier)
            .hasExplicitChoice,
        pendingLocation: pending,
        rememberPending: (l) => pending = l,
      );
      if (phase == GatePhase.ready && target == pending) pending = null;
      return target;
    },
    routes: [
      GoRoute(path: '/', redirect: (_, _) => AppRoutes.splash),
      GoRoute(
        path: AppRoutes.splash,
        pageBuilder: (_, _) => const NoTransitionPage(child: SplashScreen()),
      ),
      GoRoute(
        path: AppRoutes.maintenance,
        pageBuilder: (_, _) => _fade(const MaintenanceScreen()),
      ),
      GoRoute(
        path: AppRoutes.updateRequired,
        pageBuilder: (_, _) => _fade(const ForceUpdateScreen()),
      ),
      GoRoute(
        path: AppRoutes.unreachable,
        pageBuilder: (_, _) => _fade(const ServiceUnreachableScreen()),
      ),
      GoRoute(
        path: AppRoutes.languageOnboarding,
        pageBuilder: (_, _) => _fade(const LanguageOnboardingScreen()),
      ),
      GoRoute(
        path: AppRoutes.login,
        pageBuilder: (_, _) => _fade(const LoginScreen()),
      ),
      // Bottom-navigation tabs: home, games, missions, friends, profile.
      buildMainTabsRoute(),
      GoRoute(
        path: AppRoutes.settings,
        builder: (_, _) => const SettingsScreen(),
      ),
      GoRoute(
        path: AppRoutes.linkAccount,
        builder: (_, _) => const LinkAccountScreen(),
      ),
      ...featureRoutes,
    ],
    errorBuilder: (_, state) => NotFoundScreen(location: state.uri.path),
  );
  ref.onDispose(() {
    router.dispose();
    refresh.dispose();
  });
  return router;
});

CustomTransitionPage<void> _fade(Widget child) => CustomTransitionPage<void>(
  child: child,
  transitionDuration: const Duration(milliseconds: 280),
  transitionsBuilder: (context, animation, _, child) => FadeTransition(
    opacity: CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
    child: child,
  ),
);
