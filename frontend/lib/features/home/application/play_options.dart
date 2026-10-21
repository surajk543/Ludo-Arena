import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/gate/app_gate_controller.dart';
import '../../../app/routes.dart';
import '../../../core/storage/preferences_store.dart';

/// Game ids used by the protocol.
abstract final class GameId {
  static const ludo = 'ludo';
  static const snakesLadders = 'snakes_ladders';
}

/// How the user wants to play.
enum PlayMode { online, friends, practice }

/// A complete play configuration (game, variant, seats, bots).
@immutable
class PlayConfig {
  const PlayConfig({
    this.game = GameId.ludo,
    this.variant = 'classic',
    this.capacity = 4,
    this.bots = 3,
  });

  final String game;

  /// `classic` | `quick` (Snakes & Ladders is always `classic`).
  final String variant;

  /// 2..4 seats for online / private rooms.
  final int capacity;

  /// 1..3 bots for practice.
  final int bots;

  String get effectiveVariant => game == GameId.ludo ? variant : 'classic';

  PlayConfig copyWith({
    String? game,
    String? variant,
    int? capacity,
    int? bots,
  }) => PlayConfig(
    game: game ?? this.game,
    variant: variant ?? this.variant,
    capacity: capacity ?? this.capacity,
    bots: bots ?? this.bots,
  );

  /// Route for [mode] using this configuration.
  String routeFor(PlayMode mode) => switch (mode) {
    PlayMode.online => AppRoutes.matchmakingFor(
      game: game,
      variant: effectiveVariant,
      capacity: capacity,
    ),
    PlayMode.friends => AppRoutes.createRoomFor(
      game: game,
      variant: effectiveVariant,
      capacity: capacity,
    ),
    PlayMode.practice => AppRoutes.practiceFor(
      game: game,
      variant: effectiveVariant,
      bots: bots,
    ),
  };

  String encode() => '$game|$variant|$capacity|$bots';

  static PlayConfig decode(String? raw) {
    final parts = raw?.split('|') ?? const [];
    if (parts.length != 4) return const PlayConfig();
    final game = parts[0] == GameId.snakesLadders
        ? GameId.snakesLadders
        : GameId.ludo;
    final variant = parts[1] == 'quick' ? 'quick' : 'classic';
    final capacity = (int.tryParse(parts[2]) ?? 4).clamp(2, 4);
    final bots = (int.tryParse(parts[3]) ?? 3).clamp(1, 3);
    return PlayConfig(
      game: game,
      variant: variant,
      capacity: capacity,
      bots: bots,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PlayConfig &&
      other.game == game &&
      other.variant == variant &&
      other.capacity == capacity &&
      other.bots == bots;

  @override
  int get hashCode => Object.hash(game, variant, capacity, bots);
}

/// The Quick Play configuration (last used, persisted).
class QuickPlayController extends Notifier<PlayConfig> {
  @override
  PlayConfig build() => PlayConfig.decode(
    ref.read(preferencesStoreProvider).getString(PrefKeys.lastQuickPlay),
  );

  Future<void> remember(PlayConfig config) async {
    state = config;
    await ref
        .read(preferencesStoreProvider)
        .setString(PrefKeys.lastQuickPlay, config.encode());
  }
}

final quickPlayProvider = NotifierProvider<QuickPlayController, PlayConfig>(
  QuickPlayController.new,
);

/// Server-configured coin entry fee for [game] (docs defaults until the
/// policy is known). Practice and rooms with bots are free (server rule).
final entryFeeProvider = Provider.family<int, String>((ref, game) {
  final fees = ref.watch(
    appGateControllerProvider.select((s) => s.policy?.entryFees),
  );
  final fee = fees?[game];
  if (fee != null) return fee;
  return game == GameId.snakesLadders ? 500 : 1000;
});
