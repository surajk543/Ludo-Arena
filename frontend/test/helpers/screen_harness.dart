import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ludo_royale/core/audio_haptics/reduced_motion.dart';
import 'package:ludo_royale/core/localization/language_controller.dart';
import 'package:ludo_royale/core/localization/number_system_delegate.dart';
import 'package:ludo_royale/core/settings/app_settings.dart';
import 'package:ludo_royale/core/theme/app_theme.dart';
import 'package:ludo_royale/l10n/generated/app_localizations.dart';

import 'harness.dart';

/// Viewport presets.
abstract final class Viewports {
  static const Size small = Size(320, 640);
  static const Size phone = Size(390, 844);
  static const Size tablet = Size(900, 1200);
}

void setViewportSize(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Pumps [screen] inside the real theme/localization stack, backed by the
/// fakes in [env]. [prepare] runs real async work (e.g. signing in) before
/// the first frame.
Future<ProviderContainer> pumpScreen(
  WidgetTester tester,
  TestEnv env,
  Widget screen, {
  Locale locale = const Locale('en'),
  ThemeMode themeMode = ThemeMode.light,
  Size size = Viewports.phone,
  double textScale = 1.0,
  List<Override> extra = const [],
  Future<void> Function(ProviderContainer container)? prepare,
  GoRouter? router,
}) async {
  setViewportSize(tester, size);
  final container = env.container(extra: extra);
  addTearDown(container.dispose);
  if (prepare != null) {
    await tester.runAsync(() async {
      await prepare(container);
      await settle();
    });
  }
  // Keep the controller's locale in sync with the forced test locale.
  await tester.runAsync(
    () => container.read(languageControllerProvider.notifier).setLocale(locale),
  );

  Widget wrap(BuildContext context, Widget? child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(
      disableAnimations: true,
      textScaler: TextScaler.linear(textScale),
    ),
    child: ReducedMotionScope(child: child ?? const SizedBox()),
  );

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      // Same number-system wiring as the app root: changing the setting
      // reformats every amount.
      child: Consumer(
        builder: (context, ref, _) {
          final delegates = appLocalizationsDelegates(
            ref.watch(settingsControllerProvider.select((s) => s.numberSystem)),
          );
          return router != null
              ? MaterialApp.router(
                  debugShowCheckedModeBanner: false,
                  theme: AppTheme.light(),
                  darkTheme: AppTheme.dark(),
                  themeMode: themeMode,
                  locale: locale,
                  localizationsDelegates: delegates,
                  supportedLocales: AppLocalizations.supportedLocales,
                  routerConfig: router,
                  builder: wrap,
                )
              : MaterialApp(
                  debugShowCheckedModeBanner: false,
                  theme: AppTheme.light(),
                  darkTheme: AppTheme.dark(),
                  themeMode: themeMode,
                  locale: locale,
                  localizationsDelegates: delegates,
                  supportedLocales: AppLocalizations.supportedLocales,
                  builder: wrap,
                  home: screen,
                );
        },
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
  return container;
}

/// Scrolls every scrollable to its end so lazily built children are laid
/// out (and overflow errors surface), then back to the top.
Future<void> scrollThrough(WidgetTester tester) async {
  final scrollables = find.byType(Scrollable);
  for (var i = 0; i < scrollables.evaluate().length; i++) {
    final s = scrollables.at(i);
    for (var n = 0; n < 12; n++) {
      await tester.drag(s, const Offset(0, -400), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 50));
    }
  }
}

/// Completes async work started from widget interactions: alternates real
/// event-loop turns with fake-async pumps (Dio continuations created inside
/// the test zone only advance when pumped).
Future<void> drain(WidgetTester tester, [int rounds = 15]) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 20));
  }
}

/// Scrolls the main list until [finder] is built and fully on screen.
Future<void> reveal(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    250,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}
