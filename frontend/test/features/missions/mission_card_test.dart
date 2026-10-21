import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:ludo_royale/core/audio_haptics/audio_service.dart';
import 'package:ludo_royale/core/localization/number_format.dart';
import 'package:ludo_royale/features/missions/presentation/missions_screen.dart';
import 'package:ludo_royale/features/missions/presentation/widgets/reset_label.dart';
import 'package:ludo_royale/features/progression/application/meta_support.dart';
import 'package:ludo_royale/l10n/generated/app_localizations_ar.dart';
import 'package:ludo_royale/l10n/generated/app_localizations_en.dart';
import 'package:ludo_royale/l10n/generated/app_localizations_hi.dart';

import '../progression/meta_test_support.dart';

const _claimPath = '/missions/d2026-10-21/daily_ludo_match/claim';

void main() {
  setUpAll(() async => initializeDateFormatting());

  group('mission card states and claim flow', () {
    late TestEnv env;
    late MetaFakes fakes;

    setUp(() async {
      env = await TestEnv.create();
      env.routeHappyPath();
      routeMeta(env);
      fakes = MetaFakes();
    });
    tearDown(() => fakes.close());

    Finder claimButton() => byKeyString('claim-d2026-10-21-daily_ludo_match');

    testWidgets('shows in-progress, claimable and claimed states', (
      tester,
    ) async {
      env.backend.json(
        'GET',
        '/missions',
        missionsJson(
          daily: [
            missionJson('daily_ludo_match', game: 'ludo', progress: 1),
            missionJson('daily_play_two', progress: 1, target: 2),
            missionJson('daily_win_one', progress: 1, claimed: true),
          ],
        ),
      );
      await pumpMeta(tester, env, fakes, const MissionsScreen());

      // Localized client-side from ids (not the server's English text).
      expect(find.text('Ludo Time'), findsOneWidget);
      expect(find.text('Complete 1 Ludo match.'), findsOneWidget);
      expect(find.text('Complete 2 matches in any game.'), findsOneWidget);
      expect(find.textContaining('Server'), findsNothing);
      expect(find.text('1 / 2'), findsOneWidget);
      expect(claimButton(), findsOneWidget);
      expect(find.text('Claim'), findsOneWidget);
      expect(find.text('Claimed'), findsOneWidget);
      expect(fakes.analytics.events, contains('mission_viewed'));
    });

    testWidgets('claim taps send one request and show the confirmation', (
      tester,
    ) async {
      final gate = Completer<void>();
      env.backend.on('POST', _claimPath, (_) async {
        await gate.future;
        return FakeResponse(
          200,
          claimJson(missionJson('daily_ludo_match', progress: 1)),
        );
      });
      await pumpMeta(tester, env, fakes, const MissionsScreen());
      await tester.ensureVisible(claimButton());
      await tester.tap(claimButton());
      await tester.pump();
      await tester.tap(claimButton(), warnIfMissed: false);
      await tester.pump();
      // Pending: no reward sound before the server agrees (the claim button
      // itself is silent: the reward is the sound).
      expect(env.audio.played, isEmpty);
      await tester.runAsync(() async {
        gate.complete();
        await settle();
      });
      await flush(tester);
      expect(env.audio.played, [Sfx.rewardClaim]);

      expect(env.backend.calls('POST', _claimPath), hasLength(1));
      expect(
        find.text('Reward collected — added to your account'),
        findsOneWidget,
      );
      expect(claimButton(), findsNothing);
      expect(fakes.analytics.events, contains('mission_reward_claimed:daily'));
    });

    testWidgets('a failed claim shows a localized, retryable message', (
      tester,
    ) async {
      env.backend.on(
        'POST',
        _claimPath,
        (_) => FakeResponse.error(503, 'internal'),
      );
      await pumpMeta(tester, env, fakes, const MissionsScreen());
      await tester.ensureVisible(claimButton());
      await tester.tap(claimButton());
      await flush(tester);
      final l10n = AppLocalizationsEn();
      expect(find.text(l10n.metaRetryHint(l10n.errorInternal)), findsOneWidget);
      // Failure: the subtle error cue, never the reward sound.
      expect(env.audio.played, [Sfx.uiError]);
      // Still claimable; the next tap reuses the same key.
      expect(claimButton(), findsOneWidget);
      await tester.tap(claimButton());
      await flush(tester);
      final keys = env.backend
          .calls('POST', _claimPath)
          .map((r) => r.header('Idempotency-Key'))
          .toSet();
      expect(keys, hasLength(1));
    });

    testWidgets('error state offers retry', (tester) async {
      env.backend.on(
        'GET',
        '/missions',
        (_) => FakeResponse.error(500, 'internal'),
      );
      await pumpMeta(tester, env, fakes, const MissionsScreen());
      expect(find.text('Retry'), findsOneWidget);
      env.backend.json('GET', '/missions', missionsJson());
      await tester.tap(find.text('Retry'));
      await flush(tester);
      expect(find.text('Ludo Time'), findsOneWidget);
    });
  });

  group('reset countdown', () {
    final resetUtc = DateTime.utc(2026, 10, 22);

    test('daily reset is shown in local time with a calm countdown', () {
      final l10n = AppLocalizationsEn();
      const locale = Locale('en');
      final local = resetUtc.toLocal();
      final text = resetDescription(
        l10n,
        locale,
        kind: ResetKind.daily,
        resetsAtLocal: local,
        remaining: const Duration(hours: 4, minutes: 12, seconds: 59),
      );
      expect(
        text,
        'New missions at ${AppNumberFormat.time(local, locale)} · in 4 h 12 min',
      );
      expect(text, isNot(contains('59')));
    });

    test('weekly reset names the local weekday', () {
      final l10n = AppLocalizationsEn();
      final weekly = DateTime.utc(2026, 10, 26).toLocal();
      final text = resetDescription(
        l10n,
        const Locale('en'),
        kind: ResetKind.weekly,
        resetsAtLocal: weekly,
        remaining: const Duration(days: 4, hours: 17),
      );
      final weekday = const [
        'Monday',
        'Tuesday',
        'Wednesday',
        'Thursday',
        'Friday',
        'Saturday',
        'Sunday',
      ][weekly.weekday - 1];
      expect(text, startsWith('Resets $weekday at '));
      expect(text, endsWith('· in 4 d 17 h'));
    });

    test('durations are localized and never negative', () {
      expect(
        formatMetaDuration(AppLocalizationsHi(), const Duration(minutes: 5)),
        '5 मिनट',
      );
      expect(
        formatMetaDuration(AppLocalizationsAr(), const Duration(hours: 2)),
        '2 س 0 د',
      );
      expect(
        formatMetaDuration(AppLocalizationsEn(), const Duration(seconds: -4)),
        '1 min',
      );
    });

    testWidgets('the label converts the server UTC instant to local time', (
      tester,
    ) async {
      final env = await TestEnv.create();
      env.routeHappyPath();
      final fakes = MetaFakes();
      addTearDown(fakes.close);
      await pumpMeta(
        tester,
        env,
        fakes,
        Scaffold(
          body: PeriodResetLabel(resetsAtUtc: resetUtc, kind: ResetKind.daily),
        ),
        signedIn: false,
      );
      final time = AppNumberFormat.time(resetUtc.toLocal(), const Locale('en'));
      expect(find.textContaining('New missions at $time'), findsOneWidget);
      // FakeClock: 2026-10-21 12:00 local.
      final remaining = resetUtc.difference(DateTime(2026, 10, 21, 12));
      expect(
        find.textContaining(
          formatMetaDuration(AppLocalizationsEn(), remaining),
        ),
        findsOneWidget,
      );
    });
  });
}
