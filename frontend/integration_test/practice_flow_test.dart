// End-to-end smoke test on a simulator/emulator against a live backend with
// bot-play running in practice mode:
//
//   flutter test integration_test/practice_flow_test.dart -d <device> \
//     --dart-define=API_BASE_URL=http://localhost:8080
//
// It walks the real app from launch to a running practice Ludo game against
// three bots, rolls the dice on the player's turns, and keeps the game on
// screen for a while (prints SCREENSHOT_WINDOW_OPEN so screenshots can be
// captured from the host, e.g. `xcrun simctl io booted screenshot`).
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ludo_arena/app/routes.dart';
import 'package:ludo_arena/features/home/presentation/home_screen.dart';
import 'package:ludo_arena/features/ludo/presentation/screens/ludo_game_screen.dart';
import 'package:ludo_arena/main.dart' as app;
import 'package:ludo_arena/shared/game_visuals/game_visuals.dart';

Future<bool> pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 30),
  Future<void> Function()? onEachTick,
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 250));
    if (condition()) return true;
    if (onEachTick != null) await onEachTick();
  }
  return false;
}

Future<void> tapIfPresent(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isNotEmpty) {
    await tester.tap(finder.first, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 400));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('launch → guest → practice Ludo vs 3 bots', (tester) async {
    await app.main();

    // Whatever the first-run state is: language picker, sign-in, analytics
    // prompt, or an already restored session.
    final reachedHome = await pumpUntil(
      tester,
      () => find.byType(HomeScreen).evaluate().isNotEmpty,
      timeout: const Duration(seconds: 60),
      onEachTick: () async {
        await tapIfPresent(tester, find.text('Continue'));
        await tapIfPresent(tester, find.text('Play as guest'));
        await tapIfPresent(tester, find.text('No thanks'));
        await tapIfPresent(tester, find.text('Later'));
      },
    );
    expect(reachedHome, isTrue, reason: 'Home screen not reached');
    await tester.pump(const Duration(seconds: 1));
    await tapIfPresent(tester, find.text('No thanks'));

    final homeContext = tester.element(find.byType(HomeScreen));
    GoRouter.of(homeContext).go(AppRoutes.practiceFor(game: 'ludo', bots: 3));

    final inGame = await pumpUntil(
      tester,
      () => find.byType(LudoGameScreen).evaluate().isNotEmpty,
      timeout: const Duration(seconds: 45),
    );
    expect(inGame, isTrue, reason: 'practice game did not start (is bot-play running?)');

    // ignore: avoid_print
    print('SCREENSHOT_WINDOW_OPEN');
    // Keep playing for ~45 s: roll whenever the dice is tappable.
    await pumpUntil(
      tester,
      () => false,
      timeout: const Duration(seconds: 45),
      onEachTick: () async {
        await tapIfPresent(tester, find.byType(DiceView));
      },
    );
    // ignore: avoid_print
    print('SCREENSHOT_WINDOW_CLOSED');
    expect(find.byType(LudoGameScreen), findsOneWidget);
  });
}
