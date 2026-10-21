import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_royale/core/protocol/protocol.dart';
import 'package:ludo_royale/features/game/application/inactivity_removal.dart';

import 'support/play_test_support.dart';

void main() {
  RoomSnapshot room(RoomPlayer self, {int round = 1, String id = 'r_1'}) =>
      ludoRoom(id: id, round: round, players: [self, player(1), player(2)]);

  RoomPlayer removed({String why = ForfeitReasons.timeouts, int strikes = 5}) =>
      player(0, forfeited: true, strikes: strikes).copyWith(forfeitWhy: why);

  group('inactivityRemovalOf', () {
    final cases = <(String, RoomSnapshot?, String?, int?)>[
      ('removed for timeouts', room(removed()), 'u_0', 5),
      ('custom MAX_STRIKES', room(removed(strikes: 3)), 'u_0', 3),
      (
        'no strikes from an older server → default',
        room(removed(strikes: 0)),
        'u_0',
        ForfeitReasons.defaultMaxStrikes,
      ),
      (
        'left on their own',
        room(removed(why: ForfeitReasons.left)),
        'u_0',
        null,
      ),
      (
        'forfeited without a reason (older server)',
        room(player(0, forfeited: true, strikes: 5)),
        'u_0',
        null,
      ),
      ('still playing', room(player(0, strikes: 4)), 'u_0', null),
      ('another player was removed', room(removed()), 'u_1', null),
      ('spectator', room(removed()), 'u_9', null),
      ('no room', null, 'u_0', null),
      ('no user yet', room(removed()), null, null),
    ];
    for (final (name, r, uid, want) in cases) {
      test(name, () => expect(inactivityRemovalOf(r, uid), want));
    }
  });

  test('the notice is claimed once per room round', () {
    final notices = InactivityRemovalNotices();
    expect(notices.claim(room(removed())), isTrue);
    expect(notices.claim(room(removed())), isFalse);
    expect(notices.claim(room(removed(), round: 2)), isTrue);
    expect(notices.claim(room(removed(), id: 'r_2')), isTrue);
  });
}
