import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_arena/core/lifecycle/app_lifecycle.dart';
import 'package:ludo_arena/core/protocol/protocol.dart';
import 'package:ludo_arena/features/daily_journey/application/playtime_controller.dart';
import 'package:ludo_arena/features/daily_journey/application/playtime_toast_controller.dart';
import 'package:ludo_arena/features/missions/application/missions_controller.dart';

import '../progression/meta_test_support.dart';
import 'journey_test_support.dart';

void main() {
  late TestEnv env;
  late JourneyFakes fakes;
  late ProviderContainer c;

  Future<void> start({Map<String, dynamic>? playtime}) async {
    env.backend.json('GET', '/playtime', playtime ?? playtimeJson());
    c = metaContainer(env, fakes);
    await signIn(c);
    c.listen(playtimeToastControllerProvider, (_, _) {});
    await settle();
  }

  setUp(() async {
    env = await TestEnv.create();
    env.routeHappyPath();
    routeMeta(env);
    fakes = JourneyFakes();
  });

  tearDown(() => fakes.close());

  Playtime? playtime() => c.read(playtimeControllerProvider).playtime;
  int fetches() => env.backend.calls('GET', '/playtime').length;

  group('PlaytimeController', () {
    test('seeds from GET /playtime once the session is ready', () async {
      await start();
      expect(fetches(), 1);
      expect(playtime()!.seconds, 18 * 60);
      expect(c.read(playtimeControllerProvider).loading, isFalse);
    });

    test('404 not_found means disabled (nothing shown)', () async {
      env.backend.on(
        'GET',
        '/playtime',
        (_) => FakeResponse.error(404, 'not_found'),
      );
      c = metaContainer(env, fakes);
      await signIn(c);
      c.listen(playtimeControllerProvider, (_, _) {});
      await settle();
      final s = c.read(playtimeControllerProvider);
      expect(s.disabled, isTrue);
      expect(s.playtime, isNull);
    });

    test('pushes apply; seconds never move backwards in a day', () async {
      await start();
      fakes.push(playtimeJson(seconds: 25 * 60));
      await settle();
      expect(playtime()!.seconds, 25 * 60);
      fakes.push(playtimeJson(seconds: 22 * 60)); // late, out of order
      await settle();
      expect(playtime()!.seconds, 25 * 60);
    });

    test('a new day replaces the previous one', () async {
      await start(playtime: playtimeJson(seconds: 59 * 60));
      fakes.push(
        playtimeJson(
          seconds: 30,
          periodKey: 'd2026-10-22',
          resetsAt: '2026-10-23T00:00:00Z',
        ),
      );
      await settle();
      expect(playtime()!.periodKey, 'd2026-10-22');
      expect(playtime()!.seconds, 30);
      expect(playtime()!.completedIds, isEmpty);
    });

    test('a failed refresh keeps the value and marks it stale', () async {
      await start();
      env.backend.offline = true;
      await c.read(playtimeControllerProvider.notifier).refresh();
      final s = c.read(playtimeControllerProvider);
      expect(s.failed, isTrue);
      expect(s.playtime!.seconds, 18 * 60);
      env.backend.offline = false;
      await c.read(playtimeControllerProvider.notifier).refresh();
      expect(c.read(playtimeControllerProvider).failed, isFalse);
    });

    test('resume refetches, but not twice in a row', () async {
      await start();
      final lifecycle = c.read(appLifecycleProvider);
      env.clock.advance(const Duration(seconds: 5));
      lifecycle
        ..emit(AppLifecycleState.paused)
        ..emit(AppLifecycleState.resumed);
      await settle();
      expect(fetches(), 2);
      lifecycle
        ..emit(AppLifecycleState.paused)
        ..emit(AppLifecycleState.resumed);
      await settle();
      expect(fetches(), 2); // within PlaytimeController.minRefetchGap
    });

    test('GET /missions shares its playtime', () async {
      env.backend.json('GET', '/missions', {
        ...missionsJson(),
        'playtime': playtimeJson(seconds: 31 * 60),
      });
      await start();
      c.listen(missionsProvider, (_, _) {});
      await c.read(missionsProvider.future);
      await settle();
      expect(playtime()!.seconds, 31 * 60);
      expect(playtime()!.completedIds, {'playtime_10m', 'playtime_30m'});
    });
  });

  group('PlaytimeToastController', () {
    PlaytimeToastState toasts() => c.read(playtimeToastControllerProvider);

    test('announces completed milestones once and combines them', () async {
      await start(playtime: playtimeJson(seconds: 0));
      expect(toasts().pending, isEmpty);
      fakes.push(
        playtimeJson(
          seconds: 31 * 60,
          granted: [
            milestoneJson('playtime_10m', 10, status: 'completed'),
            milestoneJson(
              'playtime_30m',
              30,
              coins: 10000,
              xp: 40,
              status: 'completed',
            ),
          ],
        ),
      );
      await settle();
      expect(toasts().pending.map((m) => m.id), [
        'playtime_10m',
        'playtime_30m',
      ]);
      final toast = c
          .read(playtimeToastControllerProvider.notifier)
          .takeNext()!;
      expect(toast.minutes, 30);
      expect(toast.reward, const PlaytimeReward(coins: 15000, xp: 65));
      expect(
        c.read(playtimeToastControllerProvider.notifier).takeNext(),
        isNull,
      );
      expect(
        fakes.analytics.events,
        containsAll(<String>[
          'playtime_reward_granted:10:25:5000',
          'playtime_reward_granted:30:40:10000',
          'playtime_milestone_completed:10',
          'playtime_milestone_completed:30',
        ]),
      );
      // A duplicate push does not announce again.
      c.read(playtimeToastControllerProvider.notifier).markShown();
      fakes.push(playtimeJson(seconds: 32 * 60));
      await settle();
      expect(toasts().pending, isEmpty);
    });

    test('a grant made while offline is announced on the next fetch, '
        'and only once per device', () async {
      await start(playtime: playtimeJson(seconds: 12 * 60));
      expect(toasts().pending.single.id, 'playtime_10m');
      c.read(playtimeToastControllerProvider.notifier)
        ..takeNext()
        ..markShown();

      // App restart: same prefs, fresh container.
      c.dispose();
      fakes = JourneyFakes();
      await start(playtime: playtimeJson(seconds: 12 * 60));
      expect(toasts().pending, isEmpty);
      expect(
        fakes.analytics.events.where(
          (e) => e.startsWith('playtime_milestone_completed'),
        ),
        isEmpty,
      );
    });

    test('a new day starts a fresh acknowledgement set', () async {
      await start(playtime: playtimeJson(seconds: 12 * 60));
      c.read(playtimeToastControllerProvider.notifier)
        ..takeNext()
        ..markShown();
      fakes.push(
        playtimeJson(
          seconds: 11 * 60,
          periodKey: 'd2026-10-22',
          resetsAt: '2026-10-23T00:00:00Z',
        ),
      );
      await settle();
      expect(toasts().pending.single.id, 'playtime_10m');
    });

    test('requeue puts an interrupted toast back in order', () async {
      await start(playtime: playtimeJson(seconds: 12 * 60));
      final ctl = c.read(playtimeToastControllerProvider.notifier);
      final toast = ctl.takeNext()!;
      expect(toasts().showing, isTrue);
      ctl
        ..markShown()
        ..requeue(toast);
      expect(toasts().pending.single.id, 'playtime_10m');
      expect(toasts().showing, isFalse);
    });
  });
}
