import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/protocol/protocol.dart';

/// Consecutive missed turns that got the local player ([selfUid]) removed
/// from [room] by the server (`forfeited` with `forfeitWhy: timeouts`), or
/// null when they were not removed that way (still playing, left on their
/// own, spectating). Works for a live `player.forfeited` delta (the reducer
/// sets `forfeitWhy` and `strikes`) and for a snapshot after a resync.
int? inactivityRemovalOf(RoomSnapshot? room, String? selfUid) {
  final self = room?.playerByUid(selfUid);
  if (self == null ||
      !self.forfeited ||
      self.forfeitWhy != ForfeitReasons.timeouts) {
    return null;
  }
  return self.strikes > 0 ? self.strikes : ForfeitReasons.defaultMaxStrikes;
}

/// Remembers which room rounds already told the user they were removed for
/// missing turns, so the notice is shown once per room round (the match
/// screen and the launch resume path share it).
class InactivityRemovalNotices {
  final Set<String> _shown = {};

  /// True the first time it is called for [room]'s round.
  bool claim(RoomSnapshot room) => _shown.add('${room.id}#${room.round}');
}

final inactivityRemovalNoticesProvider = Provider<InactivityRemovalNotices>(
  (ref) => InactivityRemovalNotices(),
);
