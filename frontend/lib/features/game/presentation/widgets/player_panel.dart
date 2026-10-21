import 'package:flutter/material.dart';

import '../../../../core/audio_haptics/reduced_motion.dart';
import '../../../../core/protocol/protocol.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../shared/game_visuals/game_visuals.dart';
import '../../../../shared/widgets/widgets.dart';
import '../play_text.dart';

/// Per-seat summary shown around the board: avatar with frame + BOT badge,
/// name, seat color, connection / forfeit state, missed-turn strikes and
/// progress (Ludo tokens home, Snakes square). The current turn is
/// emphasised with a seat-colored glow and a server-clock [CountdownRing].
class PlayerPanel extends StatelessWidget {
  const PlayerPanel({
    super.key,
    required this.player,
    required this.room,
    required this.isSelf,
    required this.isTurn,
    this.turnTotalMs = 20000,
    this.compact = false,
  });

  final RoomPlayer player;

  /// The presented room (progress is read from its board).
  final RoomSnapshot room;
  final bool isSelf;
  final bool isTurn;

  /// Full duration of the current turn (for the ring fraction).
  final int turnTotalMs;

  /// Narrow layout (≤ 120 dp wide).
  final bool compact;

  SeatColor get _seat => SeatColor.tryFromName(player.color) ?? SeatColor.red;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = AppLocalizations.of(context);
    final palette = GamePalette.of(context);
    final shades = palette.shades(_seat);
    final out = player.forfeited;
    final offline = !player.connected && !out;
    final name = PlayText.playerName(l10n, player);
    // ≤ 34 dp: the avatar's BOT badge shows its robot glyph only; the
    // textual BOT badge is shown next to the name instead (the shared badge
    // overflows at 36–44 dp avatars).
    const avatarSize = 34.0;
    final reduce = ReducedMotion.of(context);

    Widget avatar = PlayerAvatar(
      avatarIndex: player.avatar,
      frameId: player.cosmetics.frame,
      size: avatarSize,
      isBot: player.bot,
      seatColor: _seat,
      dimmed: out || offline,
      semanticLabel: name,
    );
    final ring = avatarSize + 10;
    avatar = SizedBox.square(
      dimension: ring,
      child: isTurn && room.isPlaying && room.turn.deadline > 0
          ? CountdownRing(
              deadlineMs: room.turn.deadline,
              totalMs: turnTotalMs,
              size: ring,
              strokeWidth: 3.5,
              color: shades.base,
              child: avatar,
            )
          : Center(child: avatar),
    );

    final progress = _progress(context, l10n);
    final status = _statusChip(context, l10n, offline: offline, out: out);

    final semantics = [
      name,
      if (isSelf) l10n.commonYou,
      if (player.bot) l10n.commonBotPlayerLabel,
      if (isTurn) l10n.playPanelTurnA11y,
      if (offline) l10n.playPlayerDisconnected,
      if (out) l10n.playPlayerForfeited,
      if (player.strikes > 0) l10n.playStrikesA11y(player.strikes),
      ?progress?.$2,
    ].join(', ');

    final border = isTurn
        ? shades.base
        : (c.isDark
              ? Colors.white.withValues(alpha: 0.08)
              : c.outline.withValues(alpha: 0.7));

    return Semantics(
      container: true,
      label: semantics,
      excludeSemantics: true,
      child: AnimatedContainer(
        duration: reduce ? Duration.zero : AppDurations.medium,
        curve: AppCurves.standard,
        padding: EdgeInsetsDirectional.fromSTEB(
          compact ? 4 : 6,
          compact ? 4 : 6,
          compact ? 6 : 10,
          compact ? 4 : 6,
        ),
        decoration: BoxDecoration(
          color: isTurn
              ? Color.lerp(c.surface, shades.base, c.isDark ? 0.22 : 0.12)
              : c.surface.withValues(alpha: c.isDark ? 0.72 : 0.86),
          borderRadius: AppRadii.mdAll,
          border: Border.all(color: border, width: isTurn ? 2 : 1),
          boxShadow: isTurn
              ? [
                  BoxShadow(
                    color: shades.glow.withValues(alpha: 0.45),
                    blurRadius: 14,
                    spreadRadius: 0.5,
                  ),
                ]
              : c.shadow(AppElevation.low),
        ),
        child: Row(
          children: [
            avatar,
            SizedBox(width: compact ? 4 : 6),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: shades.base,
                          shape: BoxShape.circle,
                          border: Border.all(color: shades.outline, width: 1),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        flex: 3,
                        child: Text(
                          isSelf ? l10n.commonYou : name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.textTheme.labelLarge?.copyWith(
                            fontSize: compact ? 13 : 14,
                            color: out ? c.textMuted : c.textPrimary,
                          ),
                        ),
                      ),
                      if (player.bot) ...[
                        const SizedBox(width: 3),
                        const Flexible(
                          flex: 2,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: AlignmentDirectional.centerStart,
                            child: BotBadge(height: 16),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      if (status != null)
                        Flexible(child: status)
                      else if (progress != null)
                        Flexible(child: progress.$1),
                      if (player.strikes > 0) ...[
                        const SizedBox(width: 4),
                        _Strikes(count: player.strikes),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// (widget, accessibility text)
  (Widget, String)? _progress(BuildContext context, AppLocalizations l10n) {
    final c = context.colors;
    final style = context.textTheme.labelSmall?.copyWith(
      color: c.textSecondary,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    if (room.isLudo) {
      final tokens = room.board.ludoTokens;
      if (tokens == null || player.seat >= tokens.length) return null;
      final mine = tokens[player.seat];
      final home = mine.where((p) => p >= 56).length;
      final total = mine.length;
      final text = l10n.playTokensHome(home, total);
      return (
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < total; i++)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 2),
                child: Icon(
                  i < home ? Icons.star_rounded : Icons.circle_outlined,
                  size: 10,
                  color: i < home ? c.gold : c.textMuted,
                ),
              ),
            const SizedBox(width: 2),
            Flexible(
              child: Text(
                '$home/$total',
                maxLines: 1,
                overflow: TextOverflow.clip,
                style: style,
              ),
            ),
          ],
        ),
        text,
      );
    }
    final squares = room.board.snakesPositions;
    if (squares == null || player.seat >= squares.length) return null;
    final square = squares[player.seat];
    final text = square <= 0 ? l10n.playAtStart : l10n.playSquare(square);
    return (
      Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: style),
      text,
    );
  }

  Widget? _statusChip(
    BuildContext context,
    AppLocalizations l10n, {
    required bool offline,
    required bool out,
  }) {
    if (!offline && !out) return null;
    final c = context.colors;
    final color = out ? c.textMuted : c.warning;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          out ? Icons.logout_rounded : Icons.wifi_off_rounded,
          size: 12,
          color: color,
        ),
        const SizedBox(width: 2),
        Flexible(
          child: Text(
            out ? l10n.playPlayerForfeited : l10n.playPlayerDisconnected,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.textTheme.labelSmall?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}

/// Missed-turn strikes (3 → forfeit).
class _Strikes extends StatelessWidget {
  const _Strikes({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 3; i++)
          Container(
            width: 5,
            height: 5,
            margin: const EdgeInsetsDirectional.only(end: 1.5),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i < count ? c.danger : c.outline.withValues(alpha: 0.6),
            ),
          ),
      ],
    );
  }
}
