import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_royale/core/network/api_client.dart';
import 'package:ludo_royale/core/protocol/protocol.dart';
import 'package:ludo_royale/features/authentication/application/session_controller.dart';
import 'package:ludo_royale/features/authentication/data/provider_credential.dart';
import 'package:ludo_royale/features/authentication/identity/identity_provider_client.dart';
import 'package:ludo_royale/features/profile/progression.dart';
import 'package:ludo_royale/features/wallet/wallet_controller.dart';

import '../../helpers/fake_backend.dart';
import '../../helpers/harness.dart';

void main() {
  late TestEnv env;
  late ProviderContainer container;

  SessionController session() =>
      container.read(sessionControllerProvider.notifier);
  SessionState state() => container.read(sessionControllerProvider);

  Future<void> setUpEnv({bool seed = false, bool guest = true}) async {
    env = await TestEnv.create();
    if (seed) env.seedSession(guest: guest);
    container = env.container();
    addTearDown(container.dispose);
  }

  group('restore', () {
    test(
      'stored refresh token → /auth/refresh, rotated tokens persisted',
      () async {
        await setUpEnv(seed: true);
        env.backend.json(
          'POST',
          '/auth/refresh',
          authJson(access: 'at-new', refresh: 'rt-new', coins: 777),
        );
        final outcome = await session().restore();
        expect(outcome, RestoreOutcome.restored);
        expect(state().isSignedIn, isTrue);
        expect(state().user!.uid, 'u_guest1');
        expect(
          env.backend
              .calls('POST', '/auth/refresh')
              .single
              .json['refreshToken'],
          'old-rt',
        );
        expect(env.secure.values['session.refresh_token'], 'rt-new');
        expect(container.read(walletControllerProvider).coins, 777);
        // Restore is not a login.
        expect(
          env.analytics.events.where((e) => e.startsWith('login')),
          isEmpty,
        );
        expect(env.analytics.actor, 'human');
      },
    );

    test('rejected refresh + guest secret → /auth/guest/resume', () async {
      await setUpEnv(seed: true);
      env.backend
        ..on(
          'POST',
          '/auth/refresh',
          (_) => FakeResponse.error(401, 'refresh_reused'),
        )
        ..json(
          'POST',
          '/auth/guest/resume',
          authJson(access: 'at-g', refresh: 'rt-g'),
        );
      expect(await session().restore(), RestoreOutcome.restored);
      expect(
        env.backend
            .calls('POST', '/auth/guest/resume')
            .single
            .json['guestSecret'],
        'gs_1',
      );
      expect(env.secure.values['session.refresh_token'], 'rt-g');
    });

    test(
      'rejected refresh for a non-guest session → signed out (no resume)',
      () async {
        await setUpEnv(seed: true, guest: false);
        env.backend.on(
          'POST',
          '/auth/refresh',
          (_) => FakeResponse.error(401, 'unauthorized'),
        );
        expect(await session().restore(), RestoreOutcome.signedOut);
        expect(env.backend.calls('POST', '/auth/guest/resume'), isEmpty);
        expect(state().status, SessionStatus.signedOut);
        // The guest secret stays for "Play as guest".
        expect(state().hasStoredGuest, isTrue);
      },
    );

    test('no stored session → signed out', () async {
      await setUpEnv();
      expect(await session().restore(), RestoreOutcome.signedOut);
      expect(env.backend.requests, isEmpty);
    });

    test(
      'network failure during refresh → networkError, tokens kept',
      () async {
        await setUpEnv(seed: true);
        env.backend.offline = true;
        expect(await session().restore(), RestoreOutcome.networkError);
        expect(env.secure.values['session.refresh_token'], 'old-rt');
      },
    );

    test('maintenance during refresh → policyBlocked', () async {
      await setUpEnv(seed: true);
      env.backend.on(
        'POST',
        '/auth/refresh',
        (_) => FakeResponse.error(503, 'maintenance'),
      );
      expect(await session().restore(), RestoreOutcome.policyBlocked);
    });
  });

  group('guest', () {
    test(
      'creates a guest and stores the guest secret in secure storage',
      () async {
        await setUpEnv();
        env.backend.json(
          'POST',
          '/auth/guest',
          authJson(guestSecret: 'gs_fresh'),
          status: 201,
        );
        final outcome = await session().continueAsGuest();
        expect(outcome, isA<AuthSucceeded>());
        expect(env.secure.values['session.guest_secret'], 'gs_fresh');
        expect(env.secure.values['session.last_was_guest'], '1');
        expect(env.analytics.events, [
          'login_started:guest',
          'guest_login_succeeded',
        ]);
      },
    );

    test('resumes the stored guest instead of creating a new one', () async {
      await setUpEnv();
      env.secure.values['session.guest_secret'] = 'gs_old';
      env.backend.json('POST', '/auth/guest/resume', authJson());
      await session().continueAsGuest();
      expect(env.backend.calls('POST', '/auth/guest'), isEmpty);
      expect(env.backend.calls('POST', '/auth/guest/resume'), hasLength(1));
    });

    test('a stale guest secret falls back to a new guest', () async {
      await setUpEnv();
      env.secure.values['session.guest_secret'] = 'gs_gone';
      env.backend
        ..on(
          'POST',
          '/auth/guest/resume',
          (_) => FakeResponse.error(401, 'invalid_credential'),
        )
        ..json(
          'POST',
          '/auth/guest',
          authJson(guestSecret: 'gs_new'),
          status: 201,
        );
      expect(await session().continueAsGuest(), isA<AuthSucceeded>());
      expect(env.secure.values['session.guest_secret'], 'gs_new');
    });
  });

  group('provider sign-in', () {
    test('google success exchanges the id token with the backend', () async {
      await setUpEnv();
      env.backend.json(
        'POST',
        '/auth/google',
        authJson(isGuest: false, providers: ['google'], uid: 'u_g'),
      );
      final outcome = await session().signIn(LinkedProvider.google);
      expect(outcome, isA<AuthSucceeded>());
      expect(
        env.backend.calls('POST', '/auth/google').single.json['idToken'],
        'google-id',
      );
      expect(env.analytics.events, [
        'login_started:google',
        'login_succeeded:google',
      ]);
      expect(state().user!.uid, 'u_g');
    });

    test('cancelled sign-in is silent', () async {
      await setUpEnv();
      env.identity[LinkedProvider.google]!.next = null;
      expect(
        await session().signIn(LinkedProvider.google),
        isA<AuthCancelled>(),
      );
      expect(env.backend.requests, isEmpty);
      expect(env.analytics.events, ['login_started:google']);
    });

    test('SDK failure maps to a localizable code', () async {
      await setUpEnv();
      env.identity[LinkedProvider.google]!.next =
          const IdentityProviderException(IdentityFailure.network);
      final outcome = await session().signIn(LinkedProvider.google);
      expect((outcome as AuthFailed).code, ClientErrorCodes.network);
      expect(env.analytics.events.last, 'login_failed:google');
    });

    test('backend rejection maps to its error code', () async {
      await setUpEnv();
      env.backend.on(
        'POST',
        '/auth/google',
        (_) => FakeResponse.error(401, 'invalid_credential'),
      );
      final outcome = await session().signIn(LinkedProvider.google);
      expect((outcome as AuthFailed).code, 'invalid_credential');
    });
  });

  group('save progress (linking)', () {
    Future<void> signedInGuest() async {
      await setUpEnv();
      env.backend.json(
        'POST',
        '/auth/guest',
        authJson(guestSecret: 'gs_1'),
        status: 201,
      );
      await session().continueAsGuest();
      env.analytics.events.clear();
    }

    test(
      'link success keeps the same account and clears Save Progress',
      () async {
        await signedInGuest();
        env.backend.json(
          'POST',
          '/account/link/google',
          meJson(isGuest: false, providers: ['guest', 'google']),
        );
        final outcome = await session().link(LinkedProvider.google);
        expect(outcome, isA<LinkSucceeded>());
        final req = env.backend.calls('POST', '/account/link/google').single;
        expect(req.header('Authorization'), 'Bearer at-1');
        expect(req.json['idToken'], 'google-id');
        expect(state().user!.id, 'acc-1');
        expect(state().user!.needsSaveProgress, isFalse);
        expect(env.analytics.events, ['account_link_succeeded:google']);
      },
    );

    test(
      '409 identity_conflict → nothing merged; sign in keeps guest secret',
      () async {
        await signedInGuest();
        env.backend
          ..on(
            'POST',
            '/account/link/google',
            (_) => FakeResponse.error(
              409,
              'identity_conflict',
              details: {'provider': 'google'},
            ),
          )
          ..json(
            'POST',
            '/auth/google',
            authJson(
              id: 'acc-2',
              uid: 'u_other',
              isGuest: false,
              providers: ['google'],
              access: 'at-2',
              refresh: 'rt-2',
            ),
          );
        final outcome = await session().link(LinkedProvider.google);
        expect(outcome, isA<LinkConflict>());
        final credential = (outcome as LinkConflict).credential;
        expect(credential, isA<GoogleCredential>());
        // Still the guest account: nothing changed.
        expect(state().user!.id, 'acc-1');

        final signIn = await session().signInWithCredential(credential);
        expect(signIn, isA<AuthSucceeded>());
        expect(state().user!.id, 'acc-2');
        expect(
          env.backend.calls('POST', '/auth/google').single.json['idToken'],
          'google-id',
        );
        // Guest secret kept so the user can switch back from Settings.
        expect(env.secure.values['session.guest_secret'], 'gs_1');
        expect(state().canSwitchBackToGuest, isTrue);
        expect(env.secure.values['session.refresh_token'], 'rt-2');
        await settle();
        // Previous guest session revoked server-side.
        expect(
          env.backend.calls('POST', '/auth/logout').single.json['refreshToken'],
          'rt-1',
        );
      },
    );

    test('409 provider_already_linked is reported', () async {
      await signedInGuest();
      env.backend.on(
        'POST',
        '/account/link/google',
        (_) => FakeResponse.error(409, 'provider_already_linked'),
      );
      expect(
        await session().link(LinkedProvider.google),
        isA<LinkAlreadyLinked>(),
      );
    });

    test('cancelled link is silent', () async {
      await signedInGuest();
      env.identity[LinkedProvider.google]!.next = null;
      expect(await session().link(LinkedProvider.google), isA<LinkCancelled>());
      expect(env.backend.calls('POST', '/account/link/google'), isEmpty);
    });

    test('switch back to the stored guest account', () async {
      await signedInGuest();
      env.backend
        ..on(
          'POST',
          '/account/link/google',
          (_) => FakeResponse.error(409, 'identity_conflict'),
        )
        ..json(
          'POST',
          '/auth/google',
          authJson(id: 'acc-2', isGuest: false, providers: ['google']),
        )
        ..json(
          'POST',
          '/auth/guest/resume',
          authJson(id: 'acc-1', access: 'at-g2'),
        );
      final conflict =
          await session().link(LinkedProvider.google) as LinkConflict;
      await session().signInWithCredential(conflict.credential);
      expect(state().user!.id, 'acc-2');
      final back = await session().switchBackToGuest();
      expect(back, isA<AuthSucceeded>());
      expect(state().user!.id, 'acc-1');
      expect(state().isGuest, isTrue);
    });
  });

  group('logout', () {
    test(
      'guest logout with forgetGuest clears tokens and guest secret',
      () async {
        await setUpEnv();
        env.backend
          ..json(
            'POST',
            '/auth/guest',
            authJson(guestSecret: 'gs_1'),
            status: 201,
          )
          ..json('POST', '/auth/logout', const {}, status: 204);
        await session().continueAsGuest();
        await session().logout(forgetGuest: true);
        expect(state().status, SessionStatus.signedOut);
        expect(env.secure.values.containsKey('session.refresh_token'), isFalse);
        expect(env.secure.values.containsKey('session.guest_secret'), isFalse);
        expect(container.read(walletControllerProvider).isLoaded, isFalse);
        expect(env.analytics.actor, isNull);
      },
    );

    test('provider-account logout keeps a stored guest secret', () async {
      await setUpEnv();
      env.secure.values['session.guest_secret'] = 'gs_keep';
      env.backend.json(
        'POST',
        '/auth/google',
        authJson(isGuest: false, providers: ['google']),
      );
      await session().signIn(LinkedProvider.google);
      await session().logout(forgetGuest: false);
      expect(env.secure.values['session.guest_secret'], 'gs_keep');
      expect(state().hasStoredGuest, isTrue);
      expect(env.identity[LinkedProvider.google]!.signOuts, 1);
    });
  });

  test(
    'progression.updated updates level/xp with backend level math',
    () async {
      await setUpEnv();
      env.backend.json(
        'POST',
        '/auth/guest',
        authJson(guestSecret: 'gs'),
        status: 201,
      );
      await session().continueAsGuest();
      session().applyProgression(
        ProgressionUpdatedEvent.fromJson({
          'xp': 760,
          'level': 5,
          'xpGained': 35,
          'levelUp': true,
          'unlocked': ['dice_neon', 'title_strategist'],
          'missions': [],
        }),
      );
      final p = container.read(progressionSummaryProvider)!;
      expect(p.level, 5);
      expect(p.levelXp, LevelMath.levelStart(5));
      expect(p.levelXp, 700);
      expect(p.nextLevelXp, 300);
      expect(p.xpIntoLevel, 60);
      expect(env.analytics.events, contains('level_up:5'));
    },
  );

  test('level math matches the backend formula', () {
    expect(LevelMath.toNext(1), 100);
    expect(LevelMath.toNext(4), 250);
    expect(LevelMath.levelStart(1), 0);
    expect(LevelMath.levelStart(2), 100);
    expect(LevelMath.levelStart(4), 450);
    expect(catalogKindOf('ludo_board_royal'), 'ludo_board');
    expect(catalogKindOf('snakes_board_candy'), 'snakes_board');
    expect(catalogKindOf('frame_gold'), 'frame');
    expect(catalogRarityOf('frame_royal'), 'legendary');
    expect(catalogRarityOf('dice_classic'), 'common');
  });
}
