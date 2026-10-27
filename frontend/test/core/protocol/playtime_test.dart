import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_arena/core/protocol/protocol.dart';
import 'package:ludo_arena/features/daily_journey/presentation/widgets/playtime_visuals.dart';

import '../../features/daily_journey/journey_test_support.dart';

void main() {
  Playtime pt({
    int seconds = 18 * 60,
    String periodKey = 'd2026-10-21',
    Set<String>? completed,
  }) => Playtime.fromJson(
    playtimeJson(seconds: seconds, periodKey: periodKey, completed: completed),
  );

  group('Playtime', () {
    test('parses the REST object', () {
      final p = pt();
      expect(p.periodKey, 'd2026-10-21');
      expect(p.resetsAtUtc, DateTime.utc(2026, 10, 22));
      expect(p.resetsAtUtc!.isUtc, isTrue);
      expect(p.seconds, 1080);
      expect(p.minutes, 18);
      expect(p.goalMinutes, 60);
      expect(p.milestones.map((m) => m.id), [
        'playtime_10m',
        'playtime_30m',
        'playtime_60m',
      ]);
      expect(p.milestones.map((m) => m.status), [
        PlaytimeMilestoneStatus.completed,
        PlaytimeMilestoneStatus.inProgress,
        PlaytimeMilestoneStatus.locked,
      ]);
      expect(
        p.milestones[1].reward,
        const PlaytimeReward(coins: 10000, xp: 40),
      );
      expect(p.next!.id, 'playtime_30m');
      expect(p.completedIds, {'playtime_10m'});
      expect(p.fraction, closeTo(0.3, 1e-9));
    });

    test('remaining minutes round up and stop at zero', () {
      final p = pt(seconds: 30 * 60 - 1);
      final m30 = p.milestones[1];
      expect(p.remainingMinutes(m30), 1);
      expect(pt(seconds: 29 * 60).remainingMinutes(m30), 1);
      expect(pt(seconds: 28 * 60 + 1).remainingMinutes(m30), 2);
      expect(pt(seconds: 30 * 60).remainingMinutes(m30), 0);
      expect(pt(seconds: 90 * 60).remainingMinutes(m30), 0);
      expect(pt(seconds: 0).remainingMinutes(p.milestones[2]), 60);
    });

    test('malformed values never crash and are sanitized', () {
      final p = Playtime.fromJson({
        'periodKey': 'd2026-10-21',
        'seconds': -5,
        'milestones': [
          {'id': '', 'minutes': 10},
          {'id': 'x', 'minutes': 0},
          {'id': 'playtime_10m', 'minutes': 10, 'status': 'weird'},
          'nope',
        ],
      });
      expect(p.seconds, 0);
      expect(p.resetsAtUtc, isNull);
      expect(p.milestones.single.status, PlaytimeMilestoneStatus.locked);
    });

    test('merge never lowers seconds within a day', () {
      final newer = pt(seconds: 25 * 60);
      final older = pt(seconds: 20 * 60);
      expect(newer.merge(older).seconds, 25 * 60);
      expect(older.merge(newer).seconds, 25 * 60);
    });

    test('merge keeps completed milestones completed', () {
      final granted = pt(seconds: 30 * 60);
      final stale = pt(seconds: 29 * 60);
      final merged = granted.merge(stale);
      expect(merged.completedIds, {'playtime_10m', 'playtime_30m'});
      expect(merged.milestones[2].status, PlaytimeMilestoneStatus.inProgress);
    });

    test(
      'a later day replaces the previous one, an earlier one is ignored',
      () {
        final today = pt(seconds: 50 * 60);
        final tomorrow = pt(seconds: 60, periodKey: 'd2026-10-22');
        expect(today.merge(tomorrow).periodKey, 'd2026-10-22');
        expect(today.merge(tomorrow).seconds, 60);
        expect(tomorrow.merge(today).periodKey, 'd2026-10-22');
      },
    );

    test('allCompleted after the last milestone', () {
      final p = pt(seconds: 65 * 60);
      expect(p.allCompleted, isTrue);
      expect(p.next, isNull);
      expect(p.fraction, 1);
    });
  });

  group('playtime.updated', () {
    test('decodes the playtime and its granted milestones', () {
      final e = ServerEvent.parse(
        'playtime.updated',
        playtimeJson(
          seconds: 31 * 60,
          granted: [
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
      expect(e, isA<PlaytimeUpdatedEvent>());
      final p = e as PlaytimeUpdatedEvent;
      expect(p.playtime.seconds, 31 * 60);
      expect(p.granted.single.id, 'playtime_30m');
      expect(p.granted.single.reward.coins, 10000);
      expect(p.type, ServerMessageTypes.playtimeUpdated);
    });

    test('app.focus is a known client type', () {
      expect(ClientMessageTypes.all, contains('app.focus'));
      expect(ClientMessageTypes.appFocus, 'app.focus');
    });
  });

  group('milestone track fill', () {
    test('is piecewise between thresholds', () {
      expect(PlaytimeMilestoneTrack.fillFor(pt(seconds: 0)), 0);
      expect(
        PlaytimeMilestoneTrack.fillFor(pt(seconds: 5 * 60)),
        closeTo(1 / 6, 1e-9),
      );
      expect(
        PlaytimeMilestoneTrack.fillFor(pt(seconds: 10 * 60)),
        closeTo(1 / 3, 1e-9),
      );
      // 18 of 60: 8 of the 20 minutes between the 10 and 30 markers.
      expect(
        PlaytimeMilestoneTrack.fillFor(pt(seconds: 18 * 60)),
        closeTo((1 + 8 / 20) / 3, 1e-9),
      );
      expect(PlaytimeMilestoneTrack.fillFor(pt(seconds: 60 * 60)), 1);
    });
  });
}
