import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/audio_haptics/audio_service.dart';
import '../core/audio_haptics/reduced_motion.dart';
import '../core/lifecycle/app_lifecycle.dart';
import '../core/localization/language_controller.dart';
import '../core/localization/number_system_delegate.dart';
import '../core/localization/supported_locales.dart';
import '../core/settings/app_settings.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/theme_controller.dart';
import '../l10n/generated/app_localizations.dart';
import 'gate/app_gate_controller.dart';
import 'lobby_music.dart';
import 'match_resume.dart';
import 'offline/offline_blocking_host.dart';
import 'realtime_binder.dart';
import 'router.dart';
import 'shell/app_shell_host.dart';
import '../features/private_rooms/presentation/invite_banner_host.dart';
import '../features/progression/presentation/meta_shell_host.dart';
import '../features/store/application/coin_purchase_controller.dart';
import '../features/store/presentation/coin_purchase_host.dart';

/// Root widget. Theme mode and locale are restored synchronously from
/// preferences (loaded in bootstrap) so the first frame is already right.
class LudoRoyaleApp extends ConsumerStatefulWidget {
  const LudoRoyaleApp({super.key});

  @override
  ConsumerState<LudoRoyaleApp> createState() => _LudoRoyaleAppState();
}

class _LudoRoyaleAppState extends ConsumerState<LudoRoyaleApp> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    final bus = ref.read(appLifecycleProvider);
    _lifecycle = AppLifecycleListener(onStateChange: bus.emit);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(appGateControllerProvider.notifier).start();
      ref.read(audioServiceProvider).warmUp();
    });
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Resume first: it builds the room controller before the socket starts.
    ref.watch(matchResumeProvider);
    ref.watch(realtimeBinderProvider);
    // Sound settings + lifecycle → audio, then the lobby music.
    ref.watch(audioSettingsBinderProvider);
    ref.watch(lobbyMusicProvider);
    // Coin pack purchases: listens to the store from app start, so paid but
    // undelivered purchases are delivered (state changes don't rebuild).
    ref.listen(coinPurchaseControllerProvider, (_, _) {});
    final router = ref.watch(appRouterProvider);
    final themeMode = ref.watch(themeModeControllerProvider);
    final locale = ref.watch(languageControllerProvider);
    final numberSystem = ref.watch(
      settingsControllerProvider.select((s) => s.numberSystem),
    );

    return MaterialApp.router(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      themeAnimationDuration: AppDurations.theme,
      themeAnimationCurve: Curves.easeInOutCubic,
      locale: locale,
      supportedLocales: SupportedLocales.all,
      // Includes the number system: changing it reformats every amount.
      localizationsDelegates: appLocalizationsDelegates(numberSystem),
      routerConfig: router,
      builder: (context, child) => MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.35,
        child: ReducedMotionScope(
          // "Connection lost" overlay: blocks every screen past the gate
          // (routes, dialogs, sheets, banners) while the socket is down.
          child: OfflineBlockingHost(
            backButtonDispatcher: router.backButtonDispatcher,
            child: AppShellHost(
              // Incoming private-room invites from friends.
              child: PlayInviteHost(
                router: router,
                // Global level-up celebration (deferred during matches) and
                // the app-wide friend-request banner.
                child: MetaShellHost(
                  navigatorKey: rootNavigatorKey,
                  // Coin pack results delivered outside the Shop (e.g. a
                  // purchase re-delivered at startup).
                  child: CoinPurchaseHost(
                    navigatorKey: rootNavigatorKey,
                    child: child ?? const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
