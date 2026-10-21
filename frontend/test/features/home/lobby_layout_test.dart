import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_royale/app/shell/main_shell.dart';
import 'package:ludo_royale/features/authentication/application/session_controller.dart';
import 'package:ludo_royale/features/home/presentation/games_screen.dart';
import 'package:ludo_royale/features/home/presentation/home_screen.dart';
import 'package:ludo_royale/features/home/presentation/widgets/quick_play_card.dart';

import '../../helpers/harness.dart';
import '../../helpers/screen_harness.dart';

/// The lobby, the Games tab and the bottom bar lay out without overflow on
/// the smallest supported phone (320×640) at the largest text scale the app
/// allows (1.35), in English and Arabic (RTL), light and dark.
void main() {
  const configs = <(Locale, ThemeMode)>[
    (Locale('en'), ThemeMode.light),
    (Locale('en'), ThemeMode.dark),
    (Locale('ar'), ThemeMode.light),
    (Locale('ar'), ThemeMode.dark),
  ];

  for (final screen in const [HomeScreen(), GamesScreen()]) {
    testWidgets('${screen.runtimeType} tablet (cards side by side)', (
      tester,
    ) async {
      final env = await TestEnv.create();
      env.routeHappyPath();
      await pumpScreen(
        tester,
        env,
        screen,
        size: Viewports.tablet,
        prepare: (c) =>
            c.read(sessionControllerProvider.notifier).continueAsGuest(),
      );
      await scrollThrough(tester);
      expect(tester.takeException(), isNull);
    });
  }

  for (final (locale, mode) in configs) {
    final tag = '${locale.languageCode} ${mode.name} @320x640 x1.35';

    for (final (name, screen) in [
      ('lobby', const HomeScreen() as Widget),
      ('games', const GamesScreen() as Widget),
    ]) {
      testWidgets('$name $tag', (tester) async {
        final env = await TestEnv.create();
        env.routeHappyPath();
        await pumpScreen(
          tester,
          env,
          screen,
          locale: locale,
          themeMode: mode,
          size: Viewports.small,
          textScale: 1.35,
          prepare: (c) =>
              c.read(sessionControllerProvider.notifier).continueAsGuest(),
        );
        expect(tester.takeException(), isNull);
        final rtl = locale.languageCode == 'ar';
        expect(
          Directionality.of(tester.element(find.byType(screen.runtimeType))),
          rtl ? TextDirection.rtl : TextDirection.ltr,
        );
        if (name == 'lobby') {
          expect(find.byType(QuickPlayCard), findsOneWidget);
        }
        await scrollThrough(tester);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('bottom bar $tag', (tester) async {
      final env = await TestEnv.create();
      for (final index in [0, 4]) {
        await pumpScreen(
          tester,
          env,
          Scaffold(
            body: const SizedBox.expand(),
            bottomNavigationBar: AppBottomNav(
              currentIndex: index,
              onSelect: (_) {},
            ),
          ),
          locale: locale,
          themeMode: mode,
          size: Viewports.small,
          textScale: 1.35,
        );
        expect(tester.takeException(), isNull);
        // Every item is a ≥ 48 dp target.
        final items = find.descendant(
          of: find.byType(AppBottomNav),
          matching: find.byType(InkWell),
        );
        expect(items, findsNWidgets(5));
        for (final e in items.evaluate()) {
          final size = (e.renderObject! as RenderBox).size;
          expect(size.height, greaterThanOrEqualTo(48));
          expect(size.width, greaterThanOrEqualTo(48));
        }
      }
    });
  }
}
