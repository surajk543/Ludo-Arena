import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_royale/app/gate/app_gate_controller.dart';
import 'package:ludo_royale/app/router.dart';
import 'package:ludo_royale/app/routes.dart';
import 'package:ludo_royale/core/lifecycle/app_lifecycle.dart';
import 'package:ludo_royale/core/network/api_client.dart';
import 'package:ludo_royale/core/state/in_match_provider.dart';
import 'package:ludo_royale/core/storage/preferences_store.dart';
import 'package:ludo_royale/features/authentication/application/session_controller.dart';
import 'package:ludo_royale/features/wallet/wallet_controller.dart';

import '../../helpers/fake_backend.dart';
import '../../helpers/harness.dart';

void main() {
  late TestEnv env;
  late ProviderContainer container;

  AppGateController gate() =>
      container.read(appGateControllerProvider.notifier);
  GateState state() => container.read(appGateControllerProvider);
  int policyCalls() => env.backend.calls('GET', '/app/config').length;

  Future<void> boot({
    String mode = 'normal',
    bool seed = true,
    Map<String, Object> prefs = const {},
  }) async {
    env = await TestEnv.create(prefs: prefs);
    env.routeHappyPath(mode: mode);
    if (seed) env.seedSession();
    container = env.container();
    addTearDown(container.dispose);
    container.read(appGateControllerProvider);
  }

  void resume() {
    final bus = container.read(appLifecycleProvider);
    bus.emit(AppLifecycleState.paused);
    bus.emit(AppLifecycleState.resumed);
  }

  test(
    'normal policy + stored session → restoringSession → loadingWallet → ready',
    () async {
      await boot();
      final phases = <GatePhase>[];
      container.listen(
        appGateControllerProvider.select((s) => s.phase),
        (_, p) => phases.add(p),
      );
      await gate().start();
      await settle();
      expect(state().phase, GatePhase.ready);
      expect(phases, [
        GatePhase.checkingPolicy,
        GatePhase.restoringSession,
        GatePhase.loadingWallet,
        GatePhase.ready,
      ]);
      expect(container.read(walletControllerProvider).coins, 1000000);
      final config = env.backend.calls('GET', '/app/config').single;
      expect(config.query['platform'], 'android');
      expect(config.query['version'], '1.0.0');
      expect(config.query['build'], '1');
      expect(config.query['environment'], 'development');
      expect(config.query['locale'], 'en');
      // Cached for display only.
      expect(env.prefs.getString(PrefKeys.cachedPolicy), isNotNull);
    },
  );

  test('normal policy without a session → signedOut (login)', () async {
    await boot(seed: false);
    await gate().start();
    await settle();
    expect(state().phase, GatePhase.signedOut);
  });

  test('explicit sign-in from signedOut moves to ready', () async {
    await boot(seed: false);
    await gate().start();
    await settle();
    await container.read(sessionControllerProvider.notifier).continueAsGuest();
    await settle();
    expect(state().phase, GatePhase.ready);
  });

  test('logout from ready returns to signedOut', () async {
    await boot();
    await gate().start();
    await settle();
    await container.read(sessionControllerProvider.notifier).logout();
    await settle();
    expect(state().phase, GatePhase.signedOut);
  });

  group('optional update', () {
    Map<String, dynamic> optional() => policyJson(
      mode: 'optional_update',
      latestVersion: '1.4.0',
      latestBuild: 140,
    );

    test('prompts once at startup; Later defers by reminder hours', () async {
      await boot();
      env.backend.json('GET', '/app/config', optional());
      await gate().start();
      await settle();
      expect(state().phase, GatePhase.optionalUpdatePrompt);
      expect(
        env.analytics.events,
        contains('app_update_prompt_shown:optional_update'),
      );

      await gate().resolveOptionalUpdate(later: true);
      await settle();
      expect(state().phase, GatePhase.ready);
      expect(
        env.prefs.getString(PrefKeys.optionalUpdateDeferredVersion),
        '1.4.0',
      );

      // Re-check in the same launch: never prompted again.
      env.clock.advance(const Duration(minutes: 5));
      resume();
      await settle();
      expect(state().optionalPromptPending, isFalse);
    });

    test(
      'deferred version is not prompted again until the reminder elapses',
      () async {
        await boot();
        env.backend.json('GET', '/app/config', optional());
        await gate().start();
        await settle();
        await gate().resolveOptionalUpdate(later: true);
        await settle();
        final deferral = {
          PrefKeys.optionalUpdateDeferredVersion: '1.4.0',
          PrefKeys.optionalUpdateDeferredUntil: env.prefs.getInt(
            PrefKeys.optionalUpdateDeferredUntil,
          )!,
        };

        // "Next launch" within 24 h.
        await boot(prefs: deferral);
        env.backend.json('GET', '/app/config', optional());
        await gate().start();
        await settle();
        expect(state().phase, GatePhase.ready);

        // Next launch after the reminder window.
        await boot(prefs: deferral);
        env.backend.json('GET', '/app/config', optional());
        env.clock.advance(const Duration(hours: 25));
        await gate().start();
        await settle();
        expect(state().phase, GatePhase.optionalUpdatePrompt);
      },
    );

    test(
      'a newer latestVersion prompts even inside the old deferral',
      () async {
        await boot(
          prefs: {
            PrefKeys.optionalUpdateDeferredVersion: '1.3.0',
            PrefKeys.optionalUpdateDeferredUntil: DateTime(
              2100,
            ).millisecondsSinceEpoch,
          },
        );
        env.backend.json('GET', '/app/config', optional());
        await gate().start();
        await settle();
        expect(state().phase, GatePhase.optionalUpdatePrompt);
      },
    );

    test(
      'post-startup optional update is queued, never during a match',
      () async {
        await boot();
        await gate().start();
        await settle();
        expect(state().phase, GatePhase.ready);
        container.read(inMatchProvider.notifier).set(true);
        env.backend.json('GET', '/app/config', optional());
        env.clock.advance(const Duration(minutes: 1));
        resume();
        await settle();
        expect(state().optionalPromptPending, isFalse);
        container.read(inMatchProvider.notifier).set(false);
        await settle();
        expect(state().optionalPromptPending, isTrue);
      },
    );
  });

  group('force update', () {
    test('blocks and stays blocked on retry until the server allows', () async {
      await boot(mode: 'force_update');
      await gate().start();
      await settle();
      expect(state().phase, GatePhase.forceUpdate);
      expect(
        env.analytics.events,
        contains('app_update_prompt_shown:force_update'),
      );
      expect(env.backend.calls('POST', '/auth/refresh'), isEmpty);

      await gate().retry();
      await settle();
      expect(state().phase, GatePhase.forceUpdate);

      env.backend.json('GET', '/app/config', policyJson());
      await gate().retry();
      await settle();
      expect(state().phase, GatePhase.ready);
    });

    test('returning from the store re-checks immediately on resume', () async {
      await boot(mode: 'force_update');
      await gate().start();
      await settle();
      final before = policyCalls();
      gate().markVisitingStore();
      env.backend.json('GET', '/app/config', policyJson());
      resume();
      await settle();
      expect(policyCalls(), before + 1);
      expect(state().phase, GatePhase.ready);
    });

    test(
      'resume always re-checks on a blocking screen (no throttle)',
      () async {
        await boot(mode: 'force_update');
        await gate().start();
        await settle();
        final before = policyCalls();
        resume();
        await settle();
        resume();
        await settle();
        expect(policyCalls(), before + 2);
      },
    );
  });

  group('maintenance', () {
    test('auto re-checks every 30 s and continues when maintenance ends', () {
      fakeAsync((async) {
        late TestEnv e;
        late ProviderContainer c;
        TestEnv.create().then((value) => e = value);
        async.flushMicrotasks();
        e.routeHappyPath(mode: 'maintenance');
        e.seedSession();
        c = e.container();
        c.read(appGateControllerProvider.notifier).start();
        async.elapse(const Duration(seconds: 1));
        expect(c.read(appGateControllerProvider).phase, GatePhase.maintenance);
        final first = e.backend.calls('GET', '/app/config').length;

        async.elapse(const Duration(seconds: 30));
        expect(e.backend.calls('GET', '/app/config').length, first + 1);
        expect(c.read(appGateControllerProvider).phase, GatePhase.maintenance);

        e.backend.json('GET', '/app/config', policyJson());
        async.elapse(const Duration(seconds: 30));
        expect(c.read(appGateControllerProvider).phase, GatePhase.ready);

        // No more automatic checks once ready.
        final after = e.backend.calls('GET', '/app/config').length;
        async.elapse(const Duration(minutes: 2));
        expect(e.backend.calls('GET', '/app/config').length, after);
        c.dispose();
      });
    });

    test(
      'server-provided maintenance message and estimated end are kept',
      () async {
        await boot();
        env.backend.json(
          'GET',
          '/app/config',
          policyJson(
            mode: 'maintenance',
            maintenance: {
              'enabled': true,
              'message': 'Back soon',
              'startsAtUtc': '2026-11-02T01:00:00Z',
              'scheduledEndUtc': '2026-11-02T02:00:00Z',
            },
          ),
        );
        await gate().start();
        await settle();
        expect(state().phase, GatePhase.maintenance);
        expect(state().policy!.maintenance.message, 'Back soon');
        expect(
          state().policy!.maintenance.scheduledEndUtc,
          DateTime.utc(2026, 11, 2, 2),
        );
      },
    );

    test('REST 503 while ready → re-check → maintenance screen', () async {
      await boot();
      await gate().start();
      await settle();
      expect(state().phase, GatePhase.ready);
      env.backend
        ..on('GET', '/wallet', (_) => FakeResponse.error(503, 'maintenance'))
        ..json('GET', '/app/config', policyJson(mode: 'maintenance'));
      await container
          .read(walletControllerProvider.notifier)
          .refresh()
          .then((_) {}, onError: (_) {});
      await settle();
      expect(state().phase, GatePhase.maintenance);
    });

    test('REST 426 while ready → force update', () async {
      await boot();
      await gate().start();
      await settle();
      env.backend
        ..on('GET', '/me', (_) => FakeResponse.error(426, 'update_required'))
        ..json('GET', '/app/config', policyJson(mode: 'force_update'));
      await container
          .read(sessionControllerProvider.notifier)
          .refreshMe()
          .then((_) {}, onError: (_) {});
      await settle();
      expect(state().phase, GatePhase.forceUpdate);
    });
  });

  group('unreachable', () {
    test(
      'offline at startup → unreachable; retry when online → ready',
      () async {
        await boot();
        env.backend.offline = true;
        await gate().start();
        await settle();
        expect(state().phase, GatePhase.unreachable);
        env.backend.offline = false;
        await gate().retry();
        await settle();
        expect(state().phase, GatePhase.ready);
      },
    );

    test('a cached policy is context only and never grants access', () async {
      await boot(
        prefs: {
          PrefKeys.cachedPolicy: jsonEncode(policyJson(mode: 'maintenance')),
        },
      );
      env.backend.offline = true;
      await gate().start();
      await settle();
      expect(state().phase, GatePhase.unreachable);
      expect(state().cachedPolicy?.mode.name, 'maintenance');
      expect(env.backend.calls('POST', '/auth/refresh'), isEmpty);
    });

    test(
      'a failed background re-check does not kick a ready user out',
      () async {
        await boot();
        await gate().start();
        await settle();
        env.backend.offline = true;
        env.clock.advance(const Duration(minutes: 1));
        resume();
        await settle();
        expect(state().phase, GatePhase.ready);
      },
    );
  });

  group('resume throttling', () {
    test('ready: at most one check per 30 s', () async {
      await boot();
      await gate().start();
      await settle();
      final base = policyCalls();
      env.clock.advance(const Duration(seconds: 10));
      resume();
      await settle();
      expect(policyCalls(), base);
      env.clock.advance(const Duration(seconds: 25));
      resume();
      await settle();
      expect(policyCalls(), base + 1);
    });
  });

  group('router redirect', () {
    String? go(
      GatePhase phase,
      String location, {
      bool lang = true,
      bool intro = false,
      String? pending,
    }) => gateRedirect(
      phase: phase,
      location: location,
      languageChosen: lang,
      introPlaying: intro,
      pendingLocation: pending,
    );

    test('the launch intro holds the splash whatever the gate phase', () {
      for (final phase in GatePhase.values) {
        for (final lang in [true, false]) {
          expect(
            go(phase, AppRoutes.home, lang: lang, intro: true),
            AppRoutes.splash,
            reason: '${phase.name} lang=$lang',
          );
          expect(go(phase, AppRoutes.splash, lang: lang, intro: true), isNull);
        }
      }
      String? remembered;
      gateRedirect(
        phase: GatePhase.ready,
        location: AppRoutes.game('r_3'),
        languageChosen: true,
        introPlaying: true,
        rememberPending: (l) => remembered = l,
      );
      expect(remembered, AppRoutes.game('r_3'));
    });

    test('first launch: the language comes first, signed in or not (the '
        'gate keeps working underneath); blocking screens still win', () {
      for (final phase in [
        GatePhase.initializing,
        GatePhase.checkingPolicy,
        GatePhase.optionalUpdatePrompt,
        GatePhase.restoringSession,
        GatePhase.loadingWallet,
        GatePhase.signedOut,
        GatePhase.ready,
      ]) {
        expect(
          go(phase, AppRoutes.splash, lang: false),
          AppRoutes.languageOnboarding,
          reason: phase.name,
        );
        expect(go(phase, AppRoutes.languageOnboarding, lang: false), isNull);
      }
      expect(
        go(GatePhase.maintenance, AppRoutes.splash, lang: false),
        AppRoutes.maintenance,
      );
      expect(
        go(GatePhase.forceUpdate, AppRoutes.splash, lang: false),
        AppRoutes.updateRequired,
      );
      expect(
        go(GatePhase.unreachable, AppRoutes.splash, lang: false),
        AppRoutes.unreachable,
      );
      // Once chosen: the lobby (ready), the loading splash (still signing
      // in) or the login screen (signed out).
      expect(go(GatePhase.ready, AppRoutes.languageOnboarding), AppRoutes.home);
      expect(
        go(GatePhase.restoringSession, AppRoutes.languageOnboarding),
        AppRoutes.splash,
      );
      expect(
        go(GatePhase.signedOut, AppRoutes.languageOnboarding),
        isNull,
        reason: 'its Continue button goes on to the login screen',
      );
    });

    test('nothing behind the gate is reachable before ready', () {
      for (final phase in [
        GatePhase.initializing,
        GatePhase.checkingPolicy,
        GatePhase.optionalUpdatePrompt,
        GatePhase.restoringSession,
        GatePhase.loadingWallet,
      ]) {
        expect(go(phase, AppRoutes.home), AppRoutes.splash);
        expect(go(phase, AppRoutes.game('r_1')), AppRoutes.splash);
        expect(go(phase, AppRoutes.splash), isNull);
      }
      expect(go(GatePhase.maintenance, AppRoutes.home), AppRoutes.maintenance);
      expect(
        go(GatePhase.forceUpdate, AppRoutes.game('r')),
        AppRoutes.updateRequired,
      );
      expect(
        go(GatePhase.unreachable, AppRoutes.settings),
        AppRoutes.unreachable,
      );
      expect(go(GatePhase.forceUpdate, AppRoutes.updateRequired), isNull);
    });

    test('signed out → language onboarding first, then login', () {
      expect(
        go(GatePhase.signedOut, AppRoutes.home, lang: false),
        AppRoutes.languageOnboarding,
      );
      expect(go(GatePhase.signedOut, AppRoutes.home), AppRoutes.login);
      expect(go(GatePhase.signedOut, AppRoutes.login), isNull);
      expect(go(GatePhase.signedOut, AppRoutes.languageOnboarding), isNull);
    });

    test('ready leaves gate routes for home or the remembered deep link', () {
      expect(go(GatePhase.ready, AppRoutes.splash), AppRoutes.home);
      expect(go(GatePhase.ready, AppRoutes.login), AppRoutes.home);
      expect(go(GatePhase.ready, AppRoutes.home), isNull);
      expect(go(GatePhase.ready, AppRoutes.settings), isNull);
      expect(
        go(GatePhase.ready, AppRoutes.splash, pending: AppRoutes.game('r_9')),
        AppRoutes.game('r_9'),
      );
    });

    test('protected deep links are remembered while not ready', () {
      String? remembered;
      gateRedirect(
        phase: GatePhase.checkingPolicy,
        location: AppRoutes.game('r_7'),
        languageChosen: true,
        rememberPending: (l) => remembered = l,
      );
      expect(remembered, AppRoutes.game('r_7'));
    });
  });

  test('ApiException helpers', () {
    expect(
      const ApiException(code: 'maintenance', status: 503).isPolicyBlock,
      isTrue,
    );
    expect(
      const ApiException(
        code: 'provider_unavailable',
        status: 503,
      ).isPolicyBlock,
      isFalse,
    );
  });
}
