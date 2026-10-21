import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_royale/core/analytics/analytics_catalog.dart';
import 'package:ludo_royale/core/analytics/analytics_providers.dart';
import 'package:ludo_royale/core/analytics/gated_analytics_service.dart';
import 'package:ludo_royale/core/realtime/realtime_providers.dart';
import 'package:ludo_royale/core/storage/preferences_store.dart';
import 'package:ludo_royale/features/authentication/application/session_controller.dart';
import 'package:ludo_royale/core/network/api_models.dart';
import 'package:ludo_royale/features/wallet/wallet_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_backend.dart';
import '../../helpers/harness.dart';

/// Settings → Delete account (`DELETE /account`, docs/rest-api.md): the
/// server deletes everything; the app forgets the account locally and never
/// restores it on its own.
void main() {
  const deviceId = 'a1b2c3d4e5f60718';

  late TestEnv env;
  late ProviderContainer container;

  SessionController session() =>
      container.read(sessionControllerProvider.notifier);
  SessionState state() => container.read(sessionControllerProvider);

  /// A signed-in guest bound to this device, with a stored guest secret.
  Future<void> signedInGuest() async {
    env = await TestEnv.create();
    env.device.id = deviceId;
    env.routeHappyPath();
    env.backend
      ..json('DELETE', '/account', const {}, status: 204)
      // Must never be called after a deletion; routed so a call would
      // succeed (and the test would notice).
      ..json('POST', '/auth/device/resume', authJson(uid: 'u_dev'));
    container = env.container();
    addTearDown(container.dispose);
    final r = await session().continueAsGuest();
    expect(r, isA<AuthSucceeded>());
    await settle();
    expect(env.secure.values['session.guest_secret'], 'gs_new');
    expect(env.secure.values['session.device_bound_uid'], 'u_guest1');
    env.analytics.events.clear();
  }

  void expectWiped() {
    final v = env.secure.values;
    for (final k in const [
      'session.access_token',
      'session.refresh_token',
      'session.guest_secret',
      'session.device_bound_uid',
      'session.replaced',
    ]) {
      expect(v.containsKey(k), isFalse, reason: k);
    }
    expect(v['session.last_was_guest'], '0');
    expect(v['session.signed_out'], '1');
    expect(state().status, SessionStatus.signedOut);
    expect(state().signOutReason, SignOutReason.accountDeleted);
    expect(state().hasStoredGuest, isFalse);
    expect(state().user, isNull);
    expect(container.read(walletControllerProvider).wallet, isNull);
  }

  int restoreCalls() =>
      env.backend.calls('POST', '/auth/refresh').length +
      env.backend.calls('POST', '/auth/guest/resume').length +
      env.backend.calls('POST', '/auth/device/resume').length +
      env.backend.calls('POST', '/auth/guest').length;

  test('204: sends the literal confirmation, logs account_deleted while '
      'still human, wipes the device and never auto-restores', () async {
    await signedInGuest();
    final outcome = await session().deleteAccount();
    expect(outcome, isA<DeleteAccountSucceeded>());

    final req = env.backend.calls('DELETE', '/account').single;
    expect(req.json, {'confirm': 'DELETE'});
    expect(req.header('Authorization'), 'Bearer at-1');
    expect(req.header('X-App-Version'), isNotNull);

    expect(env.analytics.events, ['account_deleted']);
    expect(env.analytics.actorAtAccountDeleted, 'human');
    expect(env.analytics.actor, isNull);
    expectWiped();
    await settle();
    expect(env.identity[LinkedProvider.google]!.signOuts, 1);
    // No revoke/unbind round trips: the server already ended everything.
    expect(env.backend.calls('POST', '/auth/logout'), isEmpty);
    expect(env.backend.calls('DELETE', '/account/device'), isEmpty);

    // Relaunch (new process, same device storage): nothing is restored —
    // no refresh, guest resume, device resume or new guest.
    final before = restoreCalls();
    final relaunched = env.container();
    addTearDown(relaunched.dispose);
    expect(
      await relaunched.read(sessionControllerProvider.notifier).restore(),
      RestoreOutcome.signedOut,
    );
    expect(restoreCalls(), before);
    expect(relaunched.read(sessionControllerProvider).isSignedIn, isFalse);
  });

  test('after deleting, "Play as guest" creates a new account', () async {
    await signedInGuest();
    await session().deleteAccount();
    env.backend.json(
      'POST',
      '/auth/guest',
      authJson(id: 'acc-new', uid: 'u_new', guestSecret: 'gs_2'),
      status: 201,
    );
    final r = await session().continueAsGuest();
    expect(r, isA<AuthSucceeded>());
    final create = env.backend.calls('POST', '/auth/guest').last;
    expect(create.json, {'deviceId': deviceId});
    expect(state().user!.uid, 'u_new');
    // The explicit sign-in lifts the block on automatic sign-in.
    expect(env.secure.values.containsKey('session.signed_out'), isFalse);
  });

  test('401 (already deleted): signed out locally without analytics and '
      'without a silent guest resume', () async {
    await signedInGuest();
    env.backend
      ..on('DELETE', '/account', (_) => FakeResponse.error(401, 'unauthorized'))
      ..on(
        'POST',
        '/auth/refresh',
        (_) => FakeResponse.error(401, 'invalid_credential'),
      );
    final resumes = env.backend.calls('POST', '/auth/guest/resume').length;
    final outcome = await session().deleteAccount();
    await settle();
    expect(outcome, isA<DeleteAccountSucceeded>());
    expect(env.analytics.events, isEmpty);
    expectWiped();
    expect(env.backend.calls('POST', '/auth/guest/resume'), hasLength(resumes));
  });

  for (final (name, response, code) in [
    ('network error', null, 'network_error'),
    ('500', FakeResponse.error(500, 'internal'), 'internal'),
    (
      '429',
      FakeResponse.error(
        429,
        'rate_limited',
        headers: {
          'retry-after': ['120'],
        },
      ),
      'rate_limited',
    ),
  ]) {
    test('$name: nothing changes locally and it can be retried', () async {
      await signedInGuest();
      if (response == null) {
        env.backend.offline = true;
      } else {
        env.backend.on('DELETE', '/account', (_) => response);
      }
      final outcome = await session().deleteAccount();
      expect(outcome, isA<DeleteAccountFailed>());
      final failed = outcome as DeleteAccountFailed;
      expect(failed.code, code);
      if (code == 'rate_limited') {
        expect(failed.retryAfter, const Duration(seconds: 120));
      }
      expect(state().isSignedIn, isTrue);
      expect(env.secure.values['session.refresh_token'], 'rt-1');
      expect(env.secure.values['session.guest_secret'], 'gs_new');
      expect(env.secure.values['session.device_bound_uid'], 'u_guest1');
      expect(env.analytics.events, isEmpty);

      env.backend
        ..offline = false
        ..json('DELETE', '/account', const {}, status: 204);
      expect(await session().deleteAccount(), isA<DeleteAccountSucceeded>());
      expectWiped();
    });
  }

  test('session_replaced: the usual "another device" sign-out, nothing '
      'wiped', () async {
    await signedInGuest();
    env.backend
      ..on(
        'DELETE',
        '/account',
        (_) => FakeResponse.error(401, 'session_replaced'),
      )
      ..on(
        'POST',
        '/auth/refresh',
        (_) => FakeResponse.error(401, 'session_replaced'),
      );
    final outcome = await session().deleteAccount();
    await settle();
    expect(outcome, isA<DeleteAccountFailed>());
    expect((outcome as DeleteAccountFailed).code, 'session_replaced');
    expect(state().status, SessionStatus.signedOut);
    expect(state().signOutReason, SignOutReason.replaced);
    expect(env.secure.values['session.guest_secret'], 'gs_new');
    expect(env.secure.values['session.replaced'], '1');
    expect(env.analytics.events, isEmpty);
  });

  test('signed out → no request', () async {
    env = await TestEnv.create();
    container = env.container();
    addTearDown(container.dispose);
    final outcome = await session().deleteAccount();
    expect(outcome, isA<DeleteAccountFailed>());
    expect(env.backend.requests, isEmpty);
  });

  test('socket closed with "account deleted" (signal) signs out the same '
      'way, without analytics', () async {
    await signedInGuest();
    container.read(accountDeletedSignalProvider).notify();
    await settle();
    expect(env.analytics.events, isEmpty);
    expectWiped();
    expect(env.backend.calls('DELETE', '/account'), isEmpty);
  });

  test('the signal during an in-flight delete is ignored (one sign-out, one '
      'analytics event)', () async {
    await signedInGuest();
    env.backend.on('DELETE', '/account', (_) async {
      container.read(accountDeletedSignalProvider).notify();
      await Future<void>.delayed(Duration.zero);
      return const FakeResponse(204);
    });
    expect(await session().deleteAccount(), isA<DeleteAccountSucceeded>());
    await settle();
    expect(env.analytics.events, ['account_deleted']);
    expectWiped();
  });

  group('analytics gate', () {
    test('account_deleted: human + consent → logged without params; '
        'bot → nothing', () async {
      expect(AnalyticsCatalog.isKnown('account_deleted'), isTrue);
      expect(AnalyticsCatalog.sanitize('account_deleted', {'uid': 'u_1'}), {});

      SharedPreferences.setMockInitialValues({});
      final store = await PreferencesStore.load();
      final backend = _RecordingBackend();
      final c = ProviderContainer.test(
        overrides: [
          preferencesStoreProvider.overrideWithValue(store),
          analyticsBackendProvider.overrideWithValue(backend),
        ],
      );
      await c.read(analyticsConsentProvider.notifier).grant();
      final a = c.read(analyticsServiceProvider);
      expect(a, isA<GatedAnalyticsService>());
      a
        ..setActorType('bot')
        ..accountDeleted();
      await Future<void>.delayed(Duration.zero);
      expect(backend.events, isEmpty);
      a
        ..setActorType('human')
        ..accountDeleted();
      await Future<void>.delayed(Duration.zero);
      expect(backend.events, hasLength(1));
      expect(backend.events.single.$1, 'account_deleted');
      expect(backend.events.single.$2, isEmpty);
    });
  });
}

class _RecordingBackend implements AnalyticsBackend {
  final events = <(String, Map<String, Object>)>[];

  @override
  Future<void> logEvent(String name, Map<String, Object> params) async =>
      events.add((name, params));

  @override
  Future<void> setCollectionEnabled(bool enabled) async {}
}
