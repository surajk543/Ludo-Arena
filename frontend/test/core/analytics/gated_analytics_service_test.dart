import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_royale/core/analytics/analytics_catalog.dart';
import 'package:ludo_royale/core/analytics/analytics_providers.dart';
import 'package:ludo_royale/core/analytics/gated_analytics_service.dart';
import 'package:ludo_royale/core/storage/preferences_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeBackend implements AnalyticsBackend {
  final List<(String, Map<String, Object>)> events = [];
  final List<bool> collection = [];
  bool throwOnLog = false;

  @override
  Future<void> logEvent(String name, Map<String, Object> params) async {
    if (throwOnLog) throw StateError('backend down');
    events.add((name, params));
  }

  @override
  Future<void> setCollectionEnabled(bool enabled) async =>
      collection.add(enabled);

  List<String> get names => [for (final e in events) e.$1];
}

const game = AnalyticsGameContext(
  gameType: AnalyticsGameType.ludo,
  matchType: AnalyticsMatchType.public,
  seatCount: 4,
  opponentMix: OpponentMix.mixed,
  dedupeKey: 'r_abc#1',
  variant: 'classic',
);

Future<ProviderContainer> makeContainer(
  FakeBackend? backend, {
  Map<String, Object> prefs = const {},
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final store = await PreferencesStore.load();
  final c = ProviderContainer.test(
    overrides: [
      preferencesStoreProvider.overrideWithValue(store),
      analyticsBackendProvider.overrideWithValue(backend),
    ],
  );
  return c;
}

Future<void> flush() => Future<void>.delayed(Duration.zero);

void main() {
  group('gate', () {
    test('human + consent + backend → event logged', () async {
      final backend = FakeBackend();
      final c = await makeContainer(backend);
      await c.read(analyticsConsentProvider.notifier).grant();
      final a = c.read(analyticsServiceProvider)..setActorType('human');
      a.loginSucceeded(LoginMethod.google);
      await flush();
      expect(backend.names, ['login_succeeded']);
      expect(backend.events.single.$2, {'method': 'google'});
      expect(backend.collection, [true]);
    });

    test('bot actor → nothing logged', () async {
      final backend = FakeBackend();
      final c = await makeContainer(backend);
      await c.read(analyticsConsentProvider.notifier).grant();
      final a = c.read(analyticsServiceProvider)..setActorType('bot');
      a.gameStarted(game);
      a.loginSucceeded(LoginMethod.guest);
      await flush();
      expect(backend.events, isEmpty);
    });

    test('unknown (null) actor → nothing logged', () async {
      final backend = FakeBackend();
      final c = await makeContainer(backend);
      await c.read(analyticsConsentProvider.notifier).grant();
      c.read(analyticsServiceProvider).tutorialBegin();
      await flush();
      expect(backend.events, isEmpty);
    });

    test('consent unknown → nothing logged', () async {
      final backend = FakeBackend();
      final c = await makeContainer(backend);
      expect(c.read(analyticsConsentProvider), AnalyticsConsent.unknown);
      c.read(analyticsServiceProvider)
        ..setActorType('human')
        ..tutorialBegin();
      await flush();
      expect(backend.events, isEmpty);
    });

    test('consent denied → nothing logged', () async {
      final backend = FakeBackend();
      final c = await makeContainer(backend);
      await c.read(analyticsConsentProvider.notifier).deny();
      c.read(analyticsServiceProvider)
        ..setActorType('human')
        ..tutorialBegin();
      await flush();
      expect(backend.events, isEmpty);
      expect(backend.collection, [false]);
    });

    test('no backend (Firebase not configured) → no-op, no throw', () async {
      final c = await makeContainer(null);
      await c.read(analyticsConsentProvider.notifier).grant();
      final a = c.read(analyticsServiceProvider)..setActorType('human');
      expect(() => a.gameStarted(game), returnsNormally);
      expect((a as GatedAnalyticsService).isOpen, isFalse);
    });

    test('sign-out (actor cleared) stops logging', () async {
      final backend = FakeBackend();
      final c = await makeContainer(backend);
      await c.read(analyticsConsentProvider.notifier).grant();
      final a = c.read(analyticsServiceProvider)..setActorType('human');
      a.tutorialBegin();
      a.setActorType(null);
      a.tutorialComplete();
      await flush();
      expect(backend.names, ['tutorial_begin']);
    });
  });

  group('consent', () {
    test('withdrawal disables collection and blocks later events', () async {
      final backend = FakeBackend();
      final c = await makeContainer(backend);
      final consent = c.read(analyticsConsentProvider.notifier);
      await consent.grant();
      final a = c.read(analyticsServiceProvider)..setActorType('human');
      a.tutorialBegin();
      final withdrawal = consent.deny();
      // The gate closes synchronously, before the async work completes.
      a.tutorialComplete();
      await withdrawal;
      a.collectionViewed();
      await flush();
      expect(backend.names, ['tutorial_begin']);
      expect(backend.collection, [true, false]);
    });

    test('persisted denial survives a new container', () async {
      final backend = FakeBackend();
      final c1 = await makeContainer(backend);
      await c1.read(analyticsConsentProvider.notifier).deny();
      final store = c1.read(preferencesStoreProvider);
      expect(store.getString(PrefKeys.analyticsConsent), 'denied');

      // Second "launch" with the same stored preferences.
      final c2 = ProviderContainer.test(
        overrides: [
          preferencesStoreProvider.overrideWithValue(store),
          analyticsBackendProvider.overrideWithValue(backend),
        ],
      );
      expect(c2.read(analyticsConsentProvider), AnalyticsConsent.denied);
      expect(
        AnalyticsConsentController.readPersisted(store),
        AnalyticsConsent.denied,
      );
      c2.read(analyticsServiceProvider)
        ..setActorType('human')
        ..tutorialBegin();
      await flush();
      expect(backend.events, isEmpty);
    });

    test('persisted grant restores', () async {
      final c = await makeContainer(
        FakeBackend(),
        prefs: {PrefKeys.analyticsConsent: 'granted'},
      );
      expect(c.read(analyticsConsentProvider), AnalyticsConsent.granted);
    });
  });

  group('dedupe', () {
    late FakeBackend backend;
    late AnalyticsService a;

    setUp(() async {
      backend = FakeBackend();
      final c = await makeContainer(backend);
      await c.read(analyticsConsentProvider.notifier).grant();
      a = c.read(analyticsServiceProvider)..setActorType('human');
    });

    test('game_completed twice for the same key → once', () async {
      a.gameCompleted(
        game,
        outcome: GameOutcome.win,
        duration: const Duration(minutes: 4),
      );
      a.gameCompleted(
        game,
        outcome: GameOutcome.win,
        duration: const Duration(minutes: 4),
      );
      await flush();
      expect(backend.names, ['game_completed']);
      expect(backend.events.single.$2, {
        'game_type': 'ludo',
        'match_type': 'public',
        'seat_count': 4,
        'opponent_mix': 'mixed',
        'variant': 'classic',
        'outcome': 'win',
        'duration_bucket': '3_5m',
      });
    });

    test('different rounds are distinct', () async {
      const round2 = AnalyticsGameContext(
        gameType: AnalyticsGameType.ludo,
        matchType: AnalyticsMatchType.public,
        seatCount: 4,
        opponentMix: OpponentMix.mixed,
        dedupeKey: 'r_abc#2',
      );
      a.gameStarted(game);
      a.gameStarted(round2);
      a.gameStarted(game);
      await flush();
      expect(backend.names, ['game_started', 'game_started']);
    });

    test('level_up per level and update prompt per mode', () async {
      a.levelUp(5);
      a.levelUp(5);
      a.levelUp(6);
      a.appUpdatePromptShown('optional_update');
      a.appUpdatePromptShown('optional_update');
      await flush();
      expect(backend.names, [
        'level_up',
        'level_up',
        'app_update_prompt_shown',
      ]);
    });

    test('LRU is bounded', () async {
      final service = GatedAnalyticsService(
        backend: () => backend,
        consent: () => AnalyticsConsent.granted,
        dedupeCapacity: 2,
      )..setActorType('human');
      AnalyticsGameContext ctx(String k) => AnalyticsGameContext(
        gameType: AnalyticsGameType.snakesLadders,
        matchType: AnalyticsMatchType.practice,
        seatCount: 2,
        opponentMix: OpponentMix.botOnly,
        dedupeKey: k,
      );
      service.gameStarted(ctx('a'));
      service.gameStarted(ctx('b'));
      service.gameStarted(ctx('c')); // evicts 'a'
      service.gameStarted(ctx('a')); // sent again
      await flush();
      expect(backend.names.length, 4);
    });
  });

  group('validation', () {
    late FakeBackend backend;
    late AnalyticsService a;

    setUp(() async {
      backend = FakeBackend();
      final c = await makeContainer(backend);
      await c.read(analyticsConsentProvider.notifier).grant();
      a = c.read(analyticsServiceProvider)..setActorType('human');
    });

    test('unknown error code is bucketed to other', () async {
      a.privateRoomJoinFailed('K7Q2MX');
      a.privateRoomJoinFailed('room_full');
      await flush();
      expect(backend.events.map((e) => e.$2['error_code']), [
        'other',
        'room_full',
      ]);
    });

    test('invalid values are dropped, never forwarded', () async {
      a.languageChanged('fr');
      a.themeChanged('Neon Dark');
      a.settingsChanged('push_token', true);
      a.cosmeticUnlocked('dice', 'mythic');
      await flush();
      expect(backend.names, [
        'language_changed',
        'theme_changed',
        'settings_changed',
        'cosmetic_unlocked',
      ]);
      expect(backend.events[0].$2, isEmpty);
      expect(backend.events[1].$2, isEmpty);
      expect(backend.events[2].$2, {'enabled': 'true'});
      expect(backend.events[3].$2, {'item_kind': 'dice'});
    });

    test('level is clamped, seat count range enforced', () async {
      a.levelUp(99);
      a.matchmakingStarted(AnalyticsGameType.ludo, 9);
      await flush();
      expect(backend.events[0].$2, {'level': 50});
      expect(backend.events[1].$2, {'game_type': 'ludo'});
    });

    test('social events carry only the reason / source enum', () async {
      a.playerReported('offensive_name');
      a.playerReported('u_3f9a1c2b7d4e'); // never an id
      a.friendRequestSent('match');
      a.friendRequestSent('Ravi'); // never a name
      await flush();
      expect(backend.names, [
        'player_reported',
        'player_reported',
        'friend_request_sent',
        'friend_request_sent',
      ]);
      expect(backend.events[0].$2, {'reason': 'offensive_name'});
      expect(backend.events[1].$2, isEmpty);
      expect(backend.events[2].$2, {'source': 'match'});
      expect(backend.events[3].$2, isEmpty);
    });

    test('catalog rejects unknown events and unknown params', () {
      expect(AnalyticsCatalog.sanitize('purchase', {'value': 1}), isNull);
      expect(
        AnalyticsCatalog.sanitize('login_started', {
          'method': 'google',
          'email': 'a@b.c',
          'room_code': 'K7Q2MX',
        }),
        {'method': 'google'},
      );
    });

    test('every catalogued value is a safe low-cardinality token', () {
      final token = RegExp(r'^[a-z0-9_]{1,40}$');
      for (final name in AnalyticsCatalog.events.keys) {
        expect(name, matches(token));
        expect(name.startsWith('firebase_'), isFalse);
        expect(name.startsWith('google_'), isFalse);
        expect(name.startsWith('ga_'), isFalse);
      }
    });
  });

  test('backend failure never throws', () async {
    final backend = FakeBackend()..throwOnLog = true;
    final c = await makeContainer(backend);
    await c.read(analyticsConsentProvider.notifier).grant();
    final a = c.read(analyticsServiceProvider)..setActorType('human');
    expect(() => a.gameStarted(game), returnsNormally);
    expect(() => a.loginFailed(LoginMethod.apple), returnsNormally);
    await flush();
    expect(backend.events, isEmpty);
  });

  test('duration buckets', () {
    expect(DurationBucket.of(const Duration(seconds: 30)), 'lt_1m');
    expect(DurationBucket.of(const Duration(minutes: 2)), '1_3m');
    expect(DurationBucket.of(const Duration(minutes: 7)), '5_10m');
    expect(DurationBucket.of(const Duration(minutes: 45)), 'gt_20m');
  });

  test('opponent mix from known computer seats', () {
    expect(OpponentMix.from([false, false]), OpponentMix.humanOnly);
    expect(OpponentMix.from([true, false]), OpponentMix.mixed);
    expect(OpponentMix.from([true, true, true]), OpponentMix.botOnly);
  });

  test('opponent mix per room mode (public is unknown)', () {
    for (final (mode, opponents, want) in [
      ('practice', const <bool>[], OpponentMix.botOnly),
      ('practice', const [false, false], OpponentMix.botOnly),
      ('private', const [false], OpponentMix.humanOnly),
      ('private', const [true, false], OpponentMix.mixed),
      ('private', const [true, true], OpponentMix.botOnly),
      ('public', const [false, false, false], OpponentMix.unknown),
      ('public', const [true], OpponentMix.unknown),
    ]) {
      expect(
        OpponentMix.forRoom(mode: mode, opponentIsComputer: opponents),
        want,
        reason: '$mode $opponents',
      );
    }
    expect(AnalyticsValues.opponentMixes, contains('unknown'));
  });
}
