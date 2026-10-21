import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/audio_haptics/audio_service.dart';
import '../core/audio_haptics/reduced_motion.dart';
import '../core/lifecycle/app_lifecycle.dart';
import '../core/localization/language_controller.dart';
import '../core/localization/supported_locales.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/theme_controller.dart';
import '../l10n/generated/app_localizations.dart';
import 'gate/app_gate_controller.dart';
import 'realtime_binder.dart';
import 'router.dart';
import 'shell/app_shell_host.dart';

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
    ref.watch(realtimeBinderProvider);
    final router = ref.watch(appRouterProvider);
    final themeMode = ref.watch(themeModeControllerProvider);
    final locale = ref.watch(languageControllerProvider);

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
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      routerConfig: router,
      builder: (context, child) => MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.35,
        child: ReducedMotionScope(
          child: AppShellHost(child: child ?? const SizedBox.shrink()),
        ),
      ),
    );
  }
}
