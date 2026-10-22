import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_arena/core/network/api_client.dart';
import 'package:ludo_arena/core/protocol/protocol.dart';
import 'package:ludo_arena/features/authentication/application/session_controller.dart';
import 'package:ludo_arena/features/missions/application/missions_controller.dart';
import 'package:ludo_arena/features/missions/domain/mission_models.dart';
import 'package:ludo_arena/features/progression/application/level_up_controller.dart';
import 'package:ludo_arena/features/progression/application/meta_support.dart';
import 'package:ludo_arena/features/wallet/wallet_controller.dart';
import 'package:ludo_arena/l10n/generated/app_localizations_en.dart';

import '../progression/meta_test_support.dart';

const _claimPath = '/missions/d2026-10-21/daily_ludo_match/claim';

void main() {
  late TestEnv env;
  late MetaFakes fakes;
  late ProviderContainer c;

  setUp(() async {
    env = await TestEnv.create();
    env.routeHappyPath();
    routeMeta(env);
    fakes = MetaFakes();
    c = metaContainer(env, fakes);
    await signIn(c);
    // Keep the auto-dispose controller alive for the whole test.
    c.listen(missionsProvider, (_, _) {});
    await c.read(missionsProvider.future);
  });

  tearDown(() => fakes.close());

  MissionsController ctl() => c.read(missionsProvider.notifier);
  Mission mission(String id) =>
      c.read(missionsProvider).value!.all.firstWhere((p) => p.$2.id == id).$2;

  group('models', () {
    test('period keys map to analytics periods', () {
      expect(MissionPeriod.ofKey('d2026-10-21'), MissionPeriod.daily);
      expect(MissionPeriod.ofKey('w2026-W43'), MissionPeriod.weekly);
      expect(MissionPeriod.ofKey('e-autumn_cup'), MissionPeriod.event);
    });

    test('board parses sets, statuses and UTC reset times', () {
      final board = c.read(missionsProvider).value!;
      expect(board.daily.missions, hasLength(3));
      expect(board.daily.resetsAtUtc, DateTime.utc(2026, 10, 22));
      expect(board.daily.resetsAtUtc!.isUtc, isTrue);
      expect(board.events.single.periodKey, 'e-autumn_cup');
      expect(mission('daily_ludo_match').status, MissionStatus.claimable);
      expect(mission('daily_play_two').status, MissionStatus.inProgress);
      expect(mission('weekly_ten_matches').reward.items, hasLength(2));
      expect(board.claimableCount, 1);
    });
  });

  test(
    'a successful claim applies server-confirmed wallet, XP and state',
    () async {
      env.backend.json(
        'POST',
        _claimPath,
        claimJson(missionJson('daily_ludo_match', progress: 1)),
      );
      final outcome = await ctl().claim('d2026-10-21', 'daily_ludo_match');

      expect(outcome, isA<ClaimSucceeded>());
      final req = env.backend.calls('POST', _claimPath).single;
      expect(req.header('Idempotency-Key'), fakes.issuedKeys.single);
      expect(c.read(walletControllerProvider).coins, 1000500);
      expect(c.read(sessionControllerProvider).user!.xp, 550);
      expect(mission('daily_ludo_match').status, MissionStatus.claimed);
      expect(fakes.analytics.events, contains('mission_reward_claimed:daily'));
      expect(ctl().pendingIntentKey('d2026-10-21', 'daily_ludo_match'), isNull);
    },
  );

  test('double tap sends exactly one claim', () async {
    final gate = Completer<void>();
    env.backend.on('POST', _claimPath, (_) async {
      await gate.future;
      return FakeResponse(200, claimJson(missionJson('daily_ludo_match')));
    });
    final first = ctl().claim('d2026-10-21', 'daily_ludo_match');
    final second = await ctl().claim('d2026-10-21', 'daily_ludo_match');
    expect(second, isA<ClaimIgnored>());
    expect(ctl().isClaiming('d2026-10-21', 'daily_ludo_match'), isTrue);
    gate.complete();
    expect(await first, isA<ClaimSucceeded>());
    expect(env.backend.calls('POST', _claimPath), hasLength(1));
    expect(
      fakes.analytics.events.where((e) => e.startsWith('mission_reward')),
      hasLength(1),
    );
  });

  test('a retry of the same intent reuses the Idempotency-Key', () async {
    env.backend.offline = true;
    final failed = await ctl().claim('d2026-10-21', 'daily_ludo_match');
    expect(failed, isA<ClaimFailed>());
    expect((failed as ClaimFailed).canRetry, isTrue);
    expect(failed.error.code, ClientErrorCodes.network);
    final firstKey = env.backend
        .calls('POST', _claimPath)
        .single
        .header('Idempotency-Key');
    expect(ctl().pendingIntentKey('d2026-10-21', 'daily_ludo_match'), firstKey);

    // The server answers the retry (a real server would replay the stored
    // result for the same key).
    env.backend
      ..offline = false
      ..json(
        'POST',
        _claimPath,
        claimJson(missionJson('daily_ludo_match', progress: 1)),
      );
    final retried = await ctl().claim('d2026-10-21', 'daily_ludo_match');
    expect(retried, isA<ClaimSucceeded>());
    final calls = env.backend.calls('POST', _claimPath);
    expect(calls, hasLength(2));
    expect(calls.last.header('Idempotency-Key'), firstKey);
    expect(fakes.issuedKeys, hasLength(1));
  });

  test('a 5xx keeps the key; a definitive error discards it', () async {
    env.backend.on(
      'POST',
      _claimPath,
      (_) => FakeResponse.error(500, 'internal'),
    );
    await ctl().claim('d2026-10-21', 'daily_ludo_match');
    expect(
      ctl().pendingIntentKey('d2026-10-21', 'daily_ludo_match'),
      'idem-key-1',
    );

    env.backend.on(
      'POST',
      _claimPath,
      (_) => FakeResponse.error(422, 'not_completed'),
    );
    final r = await ctl().claim('d2026-10-21', 'daily_ludo_match');
    expect((r as ClaimFailed).error.code, 'not_completed');
    expect(r.canRetry, isFalse);
    expect(ctl().pendingIntentKey('d2026-10-21', 'daily_ludo_match'), isNull);

    // A new tap-intent gets a fresh key.
    await ctl().claim('d2026-10-21', 'daily_ludo_match');
    expect(
      env.backend.calls('POST', _claimPath).last.header('Idempotency-Key'),
      'idem-key-2',
    );
  });

  test('already_claimed marks the mission claimed and resyncs', () async {
    env.backend
      ..on(
        'POST',
        _claimPath,
        (_) => FakeResponse.error(409, 'already_claimed'),
      )
      ..json('GET', '/wallet', {'coins': 1000500, 'diamonds': 50});
    final r = await ctl().claim('d2026-10-21', 'daily_ludo_match');
    expect((r as ClaimFailed).error.code, 'already_claimed');
    expect(mission('daily_ludo_match').claimed, isTrue);
    await settle();
    expect(env.backend.calls('GET', '/wallet'), isNotEmpty);
    expect(
      fakes.analytics.events.where((e) => e.startsWith('mission_reward')),
      isEmpty,
    );
  });

  test('error codes map to localized messages', () {
    final l10n = AppLocalizationsEn();
    expect(
      metaErrorMessage(
        l10n,
        const ApiException(code: 'not_found', status: 404),
        context: MetaErrorContext.mission,
      ),
      l10n.metaErrorMissionEnded,
    );
    expect(
      metaErrorMessage(
        l10n,
        const ApiException(code: 'already_claimed', status: 409),
      ),
      l10n.errorAlreadyClaimed,
    );
    expect(
      metaErrorMessage(
        l10n,
        const ApiException(code: 'request_in_progress', status: 409),
      ),
      l10n.metaErrorRequestInProgress,
    );
    expect(metaErrorMessage(l10n, StateError('x')), l10n.errorGeneric);
  });

  test(
    'a level-up claim queues one celebration with the granted items',
    () async {
      env.backend.json(
        'POST',
        _claimPath,
        claimJson(
          missionJson('daily_ludo_match', progress: 1),
          level: 5,
          xp: 705,
          levelUp: true,
          granted: [
            itemRef('dice_neon', 'dice', 'rare'),
            itemRef('title_strategist', 'title', 'rare'),
          ],
        ),
      );
      await ctl().claim('d2026-10-21', 'daily_ludo_match');
      final s = c.read(levelUpControllerProvider);
      expect(s.pending.single.level, 5);
      expect(s.pending.single.unlocked, ['dice_neon', 'title_strategist']);
      expect(fakes.analytics.events, contains('level_up:5'));
      expect(c.read(sessionControllerProvider).user!.level, 5);
    },
  );

  test('mission_completed is logged once per mission and period', () async {
    expect(
      fakes.analytics.events.where((e) => e == 'mission_completed:daily'),
      hasLength(1),
    );
    await ctl().refresh();
    expect(
      fakes.analytics.events.where((e) => e == 'mission_completed:daily'),
      hasLength(1),
    );
  });

  test('progression.updated pushes update mission progress live', () async {
    fakes.progression.add(
      const ProgressionUpdatedEvent(
        xp: 560,
        level: 4,
        xpGained: 20,
        missions: [
          MissionProgress(
            id: 'daily_play_two',
            progress: 2,
            target: 2,
            completed: true,
          ),
          MissionProgress(
            id: 'autumn_quick_ludo',
            progress: 3,
            target: 3,
            completed: true,
          ),
        ],
      ),
    );
    await settle();
    expect(mission('daily_play_two').status, MissionStatus.claimable);
    expect(mission('autumn_quick_ludo').status, MissionStatus.claimable);
    expect(fakes.analytics.events, contains('mission_completed:event'));
  });
}
