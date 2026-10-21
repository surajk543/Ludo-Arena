import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_royale/core/analytics/analytics_providers.dart';
import 'package:ludo_royale/core/network/api_client.dart';
import 'package:ludo_royale/core/storage/preferences_store.dart';
import 'package:ludo_royale/features/authentication/application/session_controller.dart';
import 'package:ludo_royale/features/wallet/wallet_controller.dart';

import '../../helpers/fake_backend.dart';
import '../../helpers/harness.dart';

/// Guest/account restore after an update or reinstall, keyed by the device
/// id (`/auth/device/resume`, `POST /auth/guest` with `deviceId`,
/// `PUT|DELETE /account/device`).
void main() {
  const deviceId = 'a1b2c3d4e5f60718';
  const boundKey = 'session.device_bound_uid';

  late TestEnv env;
  late ProviderContainer container;

  SessionController session() =>
      container.read(sessionControllerProvider.notifier);
  SessionState state() => container.read(sessionControllerProvider);

  Future<void> setUpEnv({
    String? device = deviceId,
    Map<String, String> secure = const {},
    Map<String, Object> prefs = const {},
    AnalyticsBackend? analyticsBackend,
  }) async {
    env = await TestEnv.create(
      secure: secure,
      prefs: prefs,
      analyticsBackend: analyticsBackend,
    );
    env.device.id = device;
    env.backend
      ..json('PUT', '/account/device', const {})
      ..json('DELETE', '/account/device', const {}, status: 204)
      ..json('POST', '/auth/logout', const {}, status: 204);
    container = env.container();
    addTearDown(container.dispose);
  }

  /// A new app process on the same device (same secure storage + backend).
  SessionController relaunch() {
    container = env.container();
    addTearDown(container.dispose);
    return session();
  }

  int puts() => env.backend.calls('PUT', '/account/device').length;

  group('restore on a fresh install / update', () {
    test('bound device → /auth/device/resume restores the same account with '
        'its coins and progress', () async {
      await setUpEnv();
      env.backend.json(
        'POST',
        '/auth/device/resume',
        authJson(uid: 'u_dev', coins: 4321, level: 9, xp: 3700),
      );
      expect(await session().restore(), RestoreOutcome.restored);
      final req = env.backend.calls('POST', '/auth/device/resume').single;
      expect(req.json, {'deviceId': deviceId});
      expect(req.header('Authorization'), isNull);
      expect(state().isSignedIn, isTrue);
      expect(state().user!.uid, 'u_dev');
      expect(state().user!.level, 9);
      expect(container.read(walletControllerProvider).coins, 4321);
      expect(env.secure.values['session.refresh_token'], 'rt-1');
      expect(env.secure.values[boundKey], 'u_dev');
      // Nothing created, no guest secret invented, no re-bind.
      await settle();
      expect(env.backend.calls('POST', '/auth/guest'), isEmpty);
      expect(env.secure.values.containsKey('session.guest_secret'), isFalse);
      expect(puts(), 0);
      // Restore is not a login.
      expect(env.analytics.events.where((e) => e.startsWith('login')), isEmpty);
    });

    test('a rejected session on a bound device falls back to the device '
        'account', () async {
      await setUpEnv();
      env.seedSession(guest: false, guestSecret: null);
      env.backend
        ..on(
          'POST',
          '/auth/refresh',
          (_) => FakeResponse.error(401, 'invalid_credential'),
        )
        ..json('POST', '/auth/device/resume', authJson(uid: 'u_dev'));
      expect(await session().restore(), RestoreOutcome.restored);
      expect(state().user!.uid, 'u_dev');
    });

    test('unbound device (404) → signed out, nothing created', () async {
      await setUpEnv();
      env.backend.on(
        'POST',
        '/auth/device/resume',
        (_) => FakeResponse.error(404, 'not_found'),
      );
      expect(await session().restore(), RestoreOutcome.signedOut);
      expect(state().status, SessionStatus.signedOut);
      expect(state().signOutReason, SignOutReason.none);
      expect(env.backend.requests.map((r) => r.path), ['/auth/device/resume']);
      expect(env.secure.values.containsKey(boundKey), isFalse);
    });

    for (final failure in ['offline', '500', '429']) {
      test('$failure → networkError, nothing cleared', () async {
        final stored = {
          'session.guest_secret': 'gs_keep',
          'session.last_was_guest': '0',
          boundKey: 'u_old',
        };
        await setUpEnv(secure: stored);
        if (failure == 'offline') {
          env.backend.offline = true;
        } else {
          env.backend.on(
            'POST',
            '/auth/device/resume',
            (_) => FakeResponse.error(int.parse(failure), 'internal'),
          );
        }
        expect(await session().restore(), RestoreOutcome.networkError);
        expect(env.secure.values, stored);
        expect(state().isSignedIn, isFalse);
      });
    }

    test('maintenance → policyBlocked', () async {
      await setUpEnv();
      env.backend.on(
        'POST',
        '/auth/device/resume',
        (_) => FakeResponse.error(503, 'maintenance'),
      );
      expect(await session().restore(), RestoreOutcome.policyBlocked);
    });

    test('existing install with a guest secret keeps using guest resume, '
        'then binds the device once', () async {
      await setUpEnv(
        secure: {'session.guest_secret': 'gs_1', 'session.last_was_guest': '1'},
      );
      env.backend.json('POST', '/auth/guest/resume', authJson());
      expect(await session().restore(), RestoreOutcome.restored);
      expect(env.backend.calls('POST', '/auth/device/resume'), isEmpty);
      expect(
        env.backend
            .calls('POST', '/auth/guest/resume')
            .single
            .json['guestSecret'],
        'gs_1',
      );
      await settle();
      final put = env.backend.calls('PUT', '/account/device').single;
      expect(put.json, {'deviceId': deviceId});
      expect(put.header('Authorization'), 'Bearer at-1');
      expect(env.secure.values[boundKey], 'u_guest1');

      // Next launch: refresh, no second bind for the same account.
      env.backend.json('POST', '/auth/refresh', authJson(access: 'at-2'));
      expect(await relaunch().restore(), RestoreOutcome.restored);
      await settle();
      expect(puts(), 1);
    });

    test('an existing signed-in install binds the device on its next '
        'launch (migration)', () async {
      await setUpEnv();
      env.seedSession();
      env.backend.json('POST', '/auth/refresh', authJson());
      expect(await session().restore(), RestoreOutcome.restored);
      await settle();
      expect(puts(), 1);
      expect(env.backend.calls('POST', '/auth/device/resume'), isEmpty);
    });
  });

  group('no automatic sign-in after a sign-out', () {
    test('session.replaced set → no device resume', () async {
      await setUpEnv(secure: {'session.replaced': '1'});
      env.backend.json('POST', '/auth/device/resume', authJson());
      expect(await session().restore(), RestoreOutcome.signedOut);
      expect(env.backend.requests, isEmpty);
    });

    test('a restore that finds session_replaced marks it; the next launch '
        'does not device-resume', () async {
      await setUpEnv();
      env.seedSession();
      env.backend
        ..on(
          'POST',
          '/auth/refresh',
          (_) => FakeResponse.error(401, 'session_replaced'),
        )
        ..json('POST', '/auth/device/resume', authJson());
      expect(await session().restore(), RestoreOutcome.signedOut);
      expect(state().signOutReason, SignOutReason.replaced);
      expect(env.secure.values['session.replaced'], '1');
      expect(await relaunch().restore(), RestoreOutcome.signedOut);
      expect(env.backend.calls('POST', '/auth/device/resume'), isEmpty);
      expect(env.backend.calls('POST', '/auth/guest/resume'), isEmpty);
    });

    test('kicked while playing → marked; an explicit Play as guest clears '
        'it', () async {
      await setUpEnv();
      env.backend
        ..json(
          'POST',
          '/auth/guest',
          authJson(guestSecret: 'gs_1', isNewUser: true),
          status: 201,
        )
        ..on(
          'POST',
          '/auth/refresh',
          (_) => FakeResponse.error(401, 'session_replaced'),
        )
        ..json('POST', '/auth/guest/resume', authJson(access: 'at-r'))
        ..json('POST', '/auth/device/resume', authJson());
      await session().continueAsGuest();
      final tokens = container.read(tokenManagerProvider);
      expect(await tokens.refreshNow(), isNull);
      await settle();
      expect(state().signOutReason, SignOutReason.replaced);
      expect(env.secure.values['session.replaced'], '1');

      final next = relaunch();
      expect(await next.restore(), RestoreOutcome.signedOut);
      expect(env.backend.calls('POST', '/auth/device/resume'), isEmpty);

      expect(await next.continueAsGuest(), isA<AuthSucceeded>());
      expect(env.secure.values.containsKey('session.replaced'), isFalse);
    });

    test('a user sign-out is not undone by the next launch; the binding '
        'stays for "Play as guest"', () async {
      await setUpEnv();
      env.backend
        ..json(
          'POST',
          '/auth/google',
          authJson(isGuest: false, providers: ['google'], uid: 'u_g'),
        )
        ..json('POST', '/auth/device/resume', authJson(uid: 'u_g'));
      await session().signIn(LinkedProvider.google);
      await settle();
      await session().logout(forgetGuest: false);
      await settle();
      expect(env.backend.calls('DELETE', '/account/device'), isEmpty);
      expect(env.secure.values[boundKey], 'u_g');

      final next = relaunch();
      expect(await next.restore(), RestoreOutcome.signedOut);
      expect(env.backend.calls('POST', '/auth/device/resume'), isEmpty);

      // An explicit sign-in lifts the block for later launches.
      await next.signIn(LinkedProvider.google);
      expect(env.secure.values.containsKey('session.signed_out'), isFalse);
    });
  });

  group('Play as guest with a device id', () {
    test('200: the device already has an account → signed in to it, no '
        'guest secret, no re-bind', () async {
      await setUpEnv();
      env.backend.json('POST', '/auth/guest', authJson(uid: 'u_dev'));
      final outcome = await session().continueAsGuest();
      expect(outcome, isA<AuthSucceeded>());
      expect((outcome as AuthSucceeded).isNewUser, isFalse);
      expect(
        env.backend.calls('POST', '/auth/guest').single.json['deviceId'],
        deviceId,
      );
      expect(state().user!.uid, 'u_dev');
      expect(env.secure.values.containsKey('session.guest_secret'), isFalse);
      expect(env.secure.values[boundKey], 'u_dev');
      await settle();
      expect(puts(), 0);
      expect(env.analytics.events, [
        'login_started:guest',
        'guest_login_succeeded',
      ]);
    });

    test(
      '201: a new guest bound to the device → its secret is stored',
      () async {
        await setUpEnv();
        env.backend.json(
          'POST',
          '/auth/guest',
          authJson(uid: 'u_new', guestSecret: 'gs_new', isNewUser: true),
          status: 201,
        );
        final outcome = await session().continueAsGuest() as AuthSucceeded;
        expect(outcome.isNewUser, isTrue);
        expect(env.secure.values['session.guest_secret'], 'gs_new');
        expect(env.secure.values[boundKey], 'u_new');
        await settle();
        expect(puts(), 0);
      },
    );

    test('a stored guest secret is still resumed first', () async {
      await setUpEnv(secure: {'session.guest_secret': 'gs_old'});
      env.backend.json('POST', '/auth/guest/resume', authJson());
      await session().continueAsGuest();
      expect(env.backend.calls('POST', '/auth/guest'), isEmpty);
      expect(env.secure.values['session.guest_secret'], 'gs_old');
    });
  });

  group('device binding', () {
    test('provider sign-in binds the device once; the next restore does not '
        're-bind', () async {
      await setUpEnv();
      env.backend
        ..json(
          'POST',
          '/auth/google',
          authJson(isGuest: false, providers: ['google'], uid: 'u_g'),
        )
        ..json(
          'POST',
          '/auth/refresh',
          authJson(isGuest: false, providers: ['google'], uid: 'u_g'),
        );
      expect(
        await session().signIn(LinkedProvider.google),
        isA<AuthSucceeded>(),
      );
      await settle();
      final put = env.backend.calls('PUT', '/account/device').single;
      expect(put.json, {'deviceId': deviceId});
      expect(put.header('Authorization'), 'Bearer at-1');
      expect(env.secure.values[boundKey], 'u_g');

      expect(await relaunch().restore(), RestoreOutcome.restored);
      await settle();
      expect(puts(), 1);
    });

    test('409 identity_conflict is silent and not retried for that '
        'account', () async {
      await setUpEnv();
      env.backend
        ..on(
          'PUT',
          '/account/device',
          (_) => FakeResponse.error(409, 'identity_conflict'),
        )
        ..json(
          'POST',
          '/auth/google',
          authJson(isGuest: false, providers: ['google'], uid: 'u_g'),
        )
        ..json(
          'POST',
          '/auth/refresh',
          authJson(isGuest: false, providers: ['google'], uid: 'u_g'),
        );
      expect(
        await session().signIn(LinkedProvider.google),
        isA<AuthSucceeded>(),
      );
      await settle();
      expect(state().isSignedIn, isTrue);
      expect(puts(), 1);
      expect(await relaunch().restore(), RestoreOutcome.restored);
      await settle();
      expect(puts(), 1);
    });

    test('other binding failures never fail sign-in and are retried on the '
        'next launch', () async {
      await setUpEnv();
      env.backend
        ..on(
          'PUT',
          '/account/device',
          (_) => FakeResponse.error(500, 'internal'),
        )
        ..json(
          'POST',
          '/auth/google',
          authJson(isGuest: false, providers: ['google'], uid: 'u_g'),
        )
        ..json(
          'POST',
          '/auth/refresh',
          authJson(isGuest: false, providers: ['google'], uid: 'u_g'),
        );
      expect(
        await session().signIn(LinkedProvider.google),
        isA<AuthSucceeded>(),
      );
      await settle();
      expect(env.secure.values.containsKey(boundKey), isFalse);
      expect(await relaunch().restore(), RestoreOutcome.restored);
      await settle();
      expect(puts(), 2);
    });

    test('a different account on the same device is bound too', () async {
      await setUpEnv(secure: {boundKey: 'u_guest1'});
      env.backend.json(
        'POST',
        '/auth/google',
        authJson(isGuest: false, providers: ['google'], uid: 'u_g'),
      );
      await session().signIn(LinkedProvider.google);
      await settle();
      expect(puts(), 1);
    });
  });

  group('logout', () {
    test('forgetGuest:true unbinds the device with the live session before '
        'revoking and clearing it', () async {
      await setUpEnv();
      env.backend
        ..json(
          'POST',
          '/auth/guest',
          authJson(guestSecret: 'gs_1', isNewUser: true),
          status: 201,
        )
        ..json('POST', '/auth/device/resume', authJson());
      await session().continueAsGuest();
      expect(env.secure.values[boundKey], 'u_guest1');
      await session().logout(forgetGuest: true);
      await settle();

      final del = env.backend.calls('DELETE', '/account/device').single;
      expect(del.header('Authorization'), 'Bearer at-1');
      final paths = env.backend.requests
          .map((r) => '${r.method} ${r.path}')
          .toList();
      expect(
        paths.indexOf('DELETE /account/device'),
        lessThan(paths.indexOf('POST /auth/logout')),
      );
      expect(env.secure.values.containsKey(boundKey), isFalse);
      expect(env.secure.values.containsKey('session.refresh_token'), isFalse);
      expect(env.secure.values.containsKey('session.guest_secret'), isFalse);
      expect(state().status, SessionStatus.signedOut);

      // The guest is not brought back by the next launch.
      expect(await relaunch().restore(), RestoreOutcome.signedOut);
      expect(env.backend.calls('POST', '/auth/device/resume'), isEmpty);
    });

    test('forgetGuest:false keeps the binding', () async {
      await setUpEnv();
      env.backend.json(
        'POST',
        '/auth/guest',
        authJson(guestSecret: 'gs_1', isNewUser: true),
        status: 201,
      );
      await session().continueAsGuest();
      await session().logout(forgetGuest: false);
      await settle();
      expect(env.backend.calls('DELETE', '/account/device'), isEmpty);
      expect(env.secure.values[boundKey], 'u_guest1');
    });

    test('a failed unbind never blocks the sign-out', () async {
      await setUpEnv();
      env.backend
        ..json(
          'POST',
          '/auth/guest',
          authJson(guestSecret: 'gs_1', isNewUser: true),
          status: 201,
        )
        ..on(
          'DELETE',
          '/account/device',
          (_) => FakeResponse.error(500, 'internal'),
        );
      await session().continueAsGuest();
      await session().logout(forgetGuest: true);
      expect(state().status, SessionStatus.signedOut);
      expect(env.secure.values.containsKey('session.refresh_token'), isFalse);
    });
  });

  group('no device id (Android 7, unreadable keychain)', () {
    test('behaves exactly like before device binding', () async {
      await setUpEnv(device: null);
      expect(await session().restore(), RestoreOutcome.signedOut);
      expect(env.backend.requests, isEmpty);

      env.backend.json(
        'POST',
        '/auth/guest',
        authJson(guestSecret: 'gs_1', isNewUser: true),
        status: 201,
      );
      final outcome = await session().continueAsGuest() as AuthSucceeded;
      expect(outcome.isNewUser, isTrue);
      expect(env.backend.calls('POST', '/auth/guest').single.json, isEmpty);
      await session().logout(forgetGuest: true);
      await settle();
      expect(env.backend.requests.map((r) => '${r.method} ${r.path}'), [
        'POST /auth/guest',
        'POST /auth/logout',
      ]);
      expect(env.secure.values.containsKey(boundKey), isFalse);
    });
  });

  test('the device id never reaches analytics, URLs or headers', () async {
    final analytics = _RecordingAnalyticsBackend();
    await setUpEnv(
      prefs: {PrefKeys.analyticsConsent: AnalyticsConsent.granted.name},
      analyticsBackend: analytics,
    );
    // The real analytics gate instead of the recording fake.
    container = ProviderContainer(
      overrides: [
        ...env.overrides.where((o) => o.origin != analyticsServiceProvider),
      ],
      retry: (_, _) => null,
    );
    addTearDown(container.dispose);
    env.backend
      ..json('POST', '/auth/device/resume', authJson(uid: 'u_dev'))
      ..json(
        'POST',
        '/auth/google',
        authJson(isGuest: false, providers: ['google'], uid: 'u_g'),
      )
      ..json(
        'POST',
        '/auth/guest',
        authJson(guestSecret: 'gs', isNewUser: true),
        status: 201,
      );

    await session().restore();
    await session().logout(forgetGuest: false);
    await session().signIn(LinkedProvider.google);
    await settle();
    await session().logout(forgetGuest: false);
    await session().continueAsGuest();
    await session().logout(forgetGuest: true);
    await settle();

    expect(analytics.events, isNotEmpty, reason: 'the gate was open');
    for (final (name, params) in analytics.events) {
      expect('$name $params', isNot(contains(deviceId)));
    }
    final withId = <String>{};
    for (final r in env.backend.requests) {
      expect('${r.path} ${r.query} ${r.headers}', isNot(contains(deviceId)));
      if ('${r.body}'.contains(deviceId)) withId.add('${r.method} ${r.path}');
    }
    expect(withId, {
      'POST /auth/device/resume',
      'PUT /account/device',
      'POST /auth/guest',
    });
  });
}

class _RecordingAnalyticsBackend implements AnalyticsBackend {
  final List<(String, Map<String, Object>)> events = [];

  @override
  Future<void> logEvent(String name, Map<String, Object> params) async =>
      events.add((name, params));

  @override
  Future<void> setCollectionEnabled(bool enabled) async {}
}
