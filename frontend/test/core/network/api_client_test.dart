import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_arena/core/app_policy/policy_signal.dart';
import 'package:ludo_arena/core/config/app_config.dart';
import 'package:ludo_arena/core/config/app_info.dart';
import 'package:ludo_arena/core/network/api_client.dart';
import 'package:ludo_arena/core/network/token_manager.dart';
import 'package:ludo_arena/core/storage/secure_session_store.dart';
import 'package:ludo_arena/core/time/server_clock.dart';

import '../../helpers/fake_backend.dart';

void main() {
  late FakeBackend backend;
  late InMemorySecureKeyValue kv;
  late SecureSessionStore store;
  late TokenManager tokens;
  late PolicySignalBus bus;
  late ApiClient api;
  late List<Duration> delays;

  const config = AppConfig(
    apiBaseUrl: 'http://test.local',
    environment: AppEnvironment.development,
  );
  const info = AppInfo(platform: 'android', version: '1.2.0', build: 42);

  setUp(() async {
    backend = FakeBackend();
    kv = InMemorySecureKeyValue();
    store = SecureSessionStore(kv);
    tokens = TokenManager(store: store, clock: ServerClock());
    bus = PolicySignalBus();
    delays = [];
    api = ApiClient(
      config: config,
      info: info,
      tokens: tokens,
      policySignals: bus,
      languageCode: () => 'hi',
      adapter: backend,
      delay: (d) async => delays.add(d),
    );
  });

  tearDown(() => bus.dispose());

  Future<void> signIn({int accessExpiresAt = 4102444800000}) => tokens.adopt(
    AuthResponse.fromJson(
      authJson(
        access: 'at-1',
        refresh: 'rt-1',
        accessExpiresAt: accessExpiresAt,
      ),
    ),
  );

  test('adds X-App-* headers, Accept-Language and bearer token', () async {
    await signIn();
    backend.json('GET', '/me', meJson());
    await api.get('/me');
    final req = backend.requests.single;
    expect(req.header('X-App-Platform'), 'android');
    expect(req.header('X-App-Version'), '1.2.0');
    expect(req.header('X-App-Build'), '42');
    expect(req.header('Accept-Language'), 'hi');
    expect(req.header('Authorization'), 'Bearer at-1');
  });

  test('auth:false requests carry app headers but no Authorization', () async {
    await signIn();
    backend.json('GET', '/app/config', policyJson());
    await api.get('/app/config', auth: false, query: {'platform': 'android'});
    final req = backend.requests.single;
    expect(req.header('X-App-Platform'), 'android');
    expect(req.header('Authorization'), isNull);
    expect(req.query['platform'], 'android');
  });

  test('maps the error body to a typed ApiException', () async {
    await signIn();
    backend.on(
      'POST',
      '/account/link/google',
      (_) => FakeResponse.error(
        409,
        'identity_conflict',
        details: {'provider': 'google'},
      ),
    );
    final error = await api
        .post('/account/link/google', body: {'idToken': 'x'})
        .then<Object?>((_) => null, onError: (Object e) => e);
    expect(error, isA<ApiException>());
    final e = error! as ApiException;
    expect(e.code, 'identity_conflict');
    expect(e.status, 409);
    expect(e.details['provider'], 'google');
  });

  test('missing error body falls back to a status-based code', () async {
    backend.on('GET', '/thing', (_) => const FakeResponse(500));
    await expectLater(
      api.get('/thing', auth: false),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 'internal')),
    );
  });

  test('network failures map to network_error', () async {
    backend.offline = true;
    await expectLater(
      api.get('/app/config', auth: false),
      throwsA(
        isA<ApiException>()
            .having((e) => e.code, 'code', ClientErrorCodes.network)
            .having((e) => e.isNetwork, 'isNetwork', true),
      ),
    );
  });

  test(
    '401 → single-flight refresh, rotation persisted, both retried',
    () async {
      await signIn();
      var refreshCalls = 0;
      final refreshGate = Completer<void>();
      backend.on('POST', '/auth/refresh', (req) async {
        refreshCalls++;
        expect(req.json['refreshToken'], 'rt-1');
        await refreshGate.future;
        return FakeResponse(200, authJson(access: 'at-2', refresh: 'rt-2'));
      });
      backend.on('GET', '/me', (req) {
        return req.header('Authorization') == 'Bearer at-2'
            ? FakeResponse(200, meJson())
            : FakeResponse.error(401, 'unauthorized');
      });
      backend.on('GET', '/wallet', (req) {
        return req.header('Authorization') == 'Bearer at-2'
            ? const FakeResponse(200, {'coins': 5, 'diamonds': 1})
            : FakeResponse.error(401, 'unauthorized');
      });

      final a = api.get('/me');
      final b = api.get('/wallet');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      refreshGate.complete();
      final results = await Future.wait([a, b]);

      expect(refreshCalls, 1);
      expect(results[1]['coins'], 5);
      expect(tokens.accessToken, 'at-2');
      expect(kv.values['session.refresh_token'], 'rt-2');
      expect(kv.values['session.access_token'], 'at-2');
    },
  );

  test('expiring access token is refreshed before the request', () async {
    await signIn(accessExpiresAt: 1); // already expired
    backend.json(
      'POST',
      '/auth/refresh',
      authJson(access: 'at-9', refresh: 'rt-9'),
    );
    backend.json('GET', '/me', meJson());
    await api.get('/me');
    expect(backend.calls('POST', '/auth/refresh'), hasLength(1));
    expect(
      backend.calls('GET', '/me').single.header('Authorization'),
      'Bearer at-9',
    );
  });

  test('rejected refresh clears tokens and emits onExpired', () async {
    await signIn();
    final expired = expectLater(tokens.onExpired, emits(anything));
    backend.on(
      'POST',
      '/auth/refresh',
      (_) => FakeResponse.error(401, 'refresh_reused'),
    );
    backend.on('GET', '/me', (_) => FakeResponse.error(401, 'unauthorized'));
    await expectLater(
      api.get('/me'),
      throwsA(isA<ApiException>().having((e) => e.status, 'status', 401)),
    );
    await expired;
    expect(tokens.hasSession, isFalse);
    expect(kv.values.containsKey('session.refresh_token'), isFalse);
  });

  test(
    '426 / 503 maintenance notify the gate; provider_unavailable does not',
    () async {
      final signals = <PolicySignalReason>[];
      final sub = bus.signals.listen(signals.add);
      await signIn();
      backend.on(
        'GET',
        '/a',
        (_) => FakeResponse.error(426, 'update_required'),
      );
      backend.on('GET', '/b', (_) => FakeResponse.error(503, 'maintenance'));
      backend.on(
        'GET',
        '/c',
        (_) => FakeResponse.error(503, 'provider_unavailable'),
      );
      for (final p in ['/a', '/b', '/c']) {
        await api.get(p).then((_) {}, onError: (_) {});
      }
      await Future<void>.delayed(Duration.zero);
      expect(signals, [
        PolicySignalReason.restUpdateRequired,
        PolicySignalReason.restMaintenance,
      ]);
      await sub.cancel();
    },
  );

  test('429 with a short Retry-After retries a GET once', () async {
    await signIn();
    var n = 0;
    backend.on('GET', '/missions', (_) {
      n++;
      return n == 1
          ? FakeResponse.error(
              429,
              'rate_limited',
              headers: {
                'retry-after': ['2'],
              },
            )
          : const FakeResponse(200, {'ok': true});
    });
    final res = await api.get('/missions');
    expect(res['ok'], true);
    expect(n, 2);
    expect(delays, [const Duration(seconds: 2)]);
  });

  test('429 with a long Retry-After surfaces retryAfter, no retry', () async {
    await signIn();
    backend.on(
      'GET',
      '/rooms/code/ABC123',
      (_) => FakeResponse.error(
        429,
        'rate_limited',
        headers: {
          'retry-after': ['40'],
        },
      ),
    );
    await expectLater(
      api.get('/rooms/code/ABC123'),
      throwsA(
        isA<ApiException>()
            .having((e) => e.code, 'code', 'rate_limited')
            .having(
              (e) => e.retryAfter,
              'retryAfter',
              const Duration(seconds: 40),
            ),
      ),
    );
    expect(backend.requests, hasLength(1));
    expect(delays, isEmpty);
  });

  test('POST without Idempotency-Key is never auto-retried on 429', () async {
    await signIn();
    backend.on(
      'POST',
      '/friends/requests',
      (_) => FakeResponse.error(
        429,
        'rate_limited',
        headers: {
          'retry-after': ['1'],
        },
      ),
    );
    await api.post('/friends/requests').then((_) {}, onError: (_) {});
    expect(backend.requests, hasLength(1));
  });

  test('Idempotency-Key header is sent', () async {
    await signIn();
    backend.json('POST', '/collection/items/dice_neon/purchase', const {});
    await api.post(
      '/collection/items/dice_neon/purchase',
      idempotencyKey: 'key-12345678',
    );
    expect(backend.requests.single.header('Idempotency-Key'), 'key-12345678');
  });

  test('parseRetryAfter handles seconds and HTTP dates', () {
    expect(ApiClient.parseRetryAfter('7'), const Duration(seconds: 7));
    final now = DateTime.utc(2026, 10, 21, 12);
    expect(
      ApiClient.parseRetryAfter('Wed, 21 Oct 2026 12:00:30 GMT', now),
      const Duration(seconds: 30),
    );
    expect(ApiClient.parseRetryAfter('garbage'), isNull);
    expect(ApiClient.parseRetryAfter(null), isNull);
  });

  test('base URL normalization and websocket URI', () {
    expect(
      AppConfig.normalizeBaseUrl('http://h:8080/api/v1/'),
      'http://h:8080',
    );
    const https = AppConfig(
      apiBaseUrl: 'https://api.ludoarena.app',
      environment: AppEnvironment.production,
    );
    expect(https.webSocketUri.toString(), 'wss://api.ludoarena.app/api/v1/ws');
    expect(config.webSocketUri.toString(), 'ws://test.local/api/v1/ws');
    expect(config.apiV1, 'http://test.local/api/v1');
  });

  test('provider availability follows config', () {
    const c = AppConfig(
      apiBaseUrl: 'x',
      environment: AppEnvironment.development,
      googleServerClientId: 's',
    );
    expect(c.googleEnabledFor('android'), isTrue);
    expect(c.googleEnabledFor('ios'), isFalse); // needs the iOS client id
    expect(c.appleEnabledFor('ios'), isTrue);
    expect(c.appleEnabledFor('android'), isFalse); // web flow not configured
    expect(c.facebookAvailable, isFalse);
  });
}
