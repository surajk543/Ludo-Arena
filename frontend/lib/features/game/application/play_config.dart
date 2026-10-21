import 'package:flutter/foundation.dart';

import '../../../app/routes.dart';
import '../../../core/protocol/protocol.dart';

/// A validated play configuration parsed from route query parameters
/// (`/matchmaking?game=&variant=&capacity=`, `/rooms/create?…`,
/// `/practice?game=&variant=&bots=`).
@immutable
class PlayRequest {
  const PlayRequest({
    this.game = GameIds.ludo,
    this.variant = GameVariants.classic,
    this.capacity = 4,
    this.bots = 3,
    this.explicit = false,
  });

  /// [GameIds].
  final String game;

  /// [GameVariants]; always `classic` for Snakes & Ladders.
  final String variant;

  /// 2..4 seats.
  final int capacity;

  /// 1..3 practice bots.
  final int bots;

  /// True when the route carried a game choice (Home already confirmed the
  /// configuration, so the screen starts right away).
  final bool explicit;

  bool get isLudo => game == GameIds.ludo;

  static String normalizeGame(String? raw) =>
      raw == GameIds.snakesLadders ? GameIds.snakesLadders : GameIds.ludo;

  static String normalizeVariant(String game, String? raw) =>
      game == GameIds.ludo && raw == GameVariants.quick
      ? GameVariants.quick
      : GameVariants.classic;

  factory PlayRequest.fromQuery(Map<String, String> q) {
    final game = normalizeGame(q[AppRoutes.qGame]);
    return PlayRequest(
      game: game,
      variant: normalizeVariant(game, q[AppRoutes.qVariant]),
      capacity: (int.tryParse(q[AppRoutes.qCapacity] ?? '') ?? 4).clamp(2, 4),
      bots: (int.tryParse(q[AppRoutes.qBots] ?? '') ?? 3).clamp(1, 3),
      explicit:
          q[AppRoutes.qGame] == GameIds.ludo ||
          q[AppRoutes.qGame] == GameIds.snakesLadders,
    );
  }

  PlayRequest copyWith({
    String? game,
    String? variant,
    int? capacity,
    int? bots,
  }) {
    final g = game ?? this.game;
    return PlayRequest(
      game: g,
      variant: normalizeVariant(g, variant ?? this.variant),
      capacity: (capacity ?? this.capacity).clamp(2, 4),
      bots: (bots ?? this.bots).clamp(1, 3),
      explicit: explicit,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PlayRequest &&
      other.game == game &&
      other.variant == variant &&
      other.capacity == capacity &&
      other.bots == bots &&
      other.explicit == explicit;

  @override
  int get hashCode => Object.hash(game, variant, capacity, bots, explicit);
}
