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
    this.stacked = false,
  });

  final RoomPlayer player;

  /// The presented room (progress is read from its board).
  final RoomSnapshot room;
  final bool isSelf;
  final bool isTurn;

  /// Full duration of the current turn (for the ring fraction).
  final int turnTotalMs;

  /// Card layout (large avatar on top, full-width name and progress below),
  /// used when the screen has spare height around the board.
  final bool stacked;

  SeatColor get _seat => SeatColor.tryFromName(player.color) ?? SeatColor.red;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => _buildPod(
      context,
      stacked
          ? _PodMetrics.stacked
          : _PodMetrics.forWidth(
              constraints.maxWidth.isFinite ? constraints.maxWidth : 240,
            ),
    ),
  );

  Widget _buildPod(BuildContext context, _PodMetrics m) {
    final c = context.colors;
    final l10n = AppLocalizations.of(context);
    final palette = GamePalette.of(context);
    final shades = palette.shades(_seat);
    final out = player.forfeited;
    final offline = !player.connected && !out;
    final name = PlayText.playerName(l10n, player);
    final avatarSize = m.avatar;
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
    final ring = avatarSize + m.ringGap;
    avatar = SizedBox.square(
      dimension: ring,
      child: isTurn && room.isPlaying && room.turn.deadline > 0
          ? CountdownRing(
              deadlineMs: room.turn.deadline,
              totalMs: turnTotalMs,
              size: ring,
              strokeWidth: m.ringStroke,
              color: shades.base,
              child: avatar,
            )
          : Center(child: avatar),
    );

    final progress = _progress(context, l10n, m);
    final status = _statusChip(context, l10n, m, offline: offline, out: out);

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

    // In the compact row layout the avatar's own badge already reads
    // "BOT", so a leading "Bot " in the name is dropped to make room.
    final shownName = isSelf
        ? l10n.commonYou
        : (!stacked && player.bot && avatarSize >= 36)
        ? _withoutBotPrefix(name)
        : name;

    Widget nameLine({required bool center}) => Row(
      mainAxisAlignment: center
          ? MainAxisAlignment.center
          : MainAxisAlignment.start,
      children: [
        Container(
          width: m.dot,
          height: m.dot,
          decoration: BoxDecoration(
            color: shades.base,
            shape: BoxShape.circle,
            border: Border.all(color: shades.outline, width: 1),
          ),
        ),
        SizedBox(width: m.dot * 0.6),
        Flexible(
          child: Text(
            shownName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.textTheme.labelLarge?.copyWith(
              fontSize: m.nameFont,
              color: out ? c.textMuted : c.textPrimary,
            ),
          ),
        ),
        // Below 36 dp the avatar badge shows only a glyph: repeat the label.
        if (player.bot && avatarSize < 36) ...[
          const SizedBox(width: 3),
          const FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: BotBadge(height: 16),
          ),
        ],
      ],
    );

    Widget detailLine({required bool center}) => Row(
      mainAxisAlignment: center
          ? MainAxisAlignment.center
          : MainAxisAlignment.start,
      children: [
        // Scale down rather than overflow in the narrowest pods.
        if (status != null)
          Flexible(child: status)
        else if (progress != null)
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: center
                  ? Alignment.center
                  : AlignmentDirectional.centerStart,
              child: progress.$1,
            ),
          ),
        if (player.strikes > 0) ...[
          const SizedBox(width: 4),
          _Strikes(count: player.strikes),
        ],
      ],
    );

    return Semantics(
      container: true,
      label: semantics,
      excludeSemantics: true,
      child: AnimatedContainer(
        duration: reduce ? Duration.zero : AppDurations.medium,
        curve: AppCurves.standard,
        constraints: BoxConstraints(minHeight: m.minHeight),
        padding: EdgeInsetsDirectional.fromSTEB(
          m.padStart,
          m.padVertical,
          m.padEnd,
          m.padVertical,
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
        child: stacked
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  avatar,
                  SizedBox(height: m.lineGap + 2),
                  nameLine(center: true),
                  SizedBox(height: m.lineGap),
                  detailLine(center: true),
                ],
              )
            : Row(
                children: [
                  avatar,
                  SizedBox(width: m.gap),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        nameLine(center: false),
                        SizedBox(height: m.lineGap),
                        detailLine(center: false),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  /// (widget, accessibility text)
  (Widget, String)? _progress(
    BuildContext context,
    AppLocalizations l10n,
    _PodMetrics m,
  ) {
    final c = context.colors;
    final style = m
        .detailStyle(context)
        ?.copyWith(
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
                  size: m.detailIcon,
                  color: i < home ? c.gold : c.textMuted,
                ),
              ),
            if (m.showCount) ...[
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
    AppLocalizations l10n,
    _PodMetrics m, {
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
          size: m.detailIcon + 2,
          color: color,
        ),
        const SizedBox(width: 2),
        Flexible(
          child: Text(
            out ? l10n.playPlayerForfeited : l10n.playPlayerDisconnected,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: m.detailStyle(context)?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}

String _withoutBotPrefix(String name) {
  final m = RegExp(r'^bot\s+', caseSensitive: false).firstMatch(name);
  if (m == null) return name;
  final rest = name.substring(m.end).trim();
  return rest.isEmpty ? name : rest;
}

/// Pod dimensions by available width: the pod grows on roomy layouts
/// (most phones in portrait, landscape side column, tablets) and stays
/// compact on the narrowest screens.
class _PodMetrics {
  const _PodMetrics({
    required this.avatar,
    required this.ringGap,
    required this.ringStroke,
    required this.nameFont,
    required this.padStart,
    required this.padEnd,
    required this.padVertical,
    required this.gap,
    required this.dot,
    required this.lineGap,
    required this.minHeight,
    required this.detailIcon,
    required this.largeDetail,
    this.showCount = false,
  });

  final double avatar;
  final double ringGap;
  final double ringStroke;
  final double nameFont;
  final double padStart;
  final double padEnd;
  final double padVertical;
  final double gap;
  final double dot;
  final double lineGap;
  final double minHeight;
  final double detailIcon;
  final bool largeDetail;

  /// Show the numeric "home/total" next to the token stars.
  final bool showCount;

  /// Card layout preset (see [PlayerPanel.stacked]).
  static const stacked = _PodMetrics(
    avatar: 56,
    ringGap: 12,
    ringStroke: 4,
    nameFont: 16,
    padStart: 8,
    padEnd: 8,
    padVertical: 10,
    gap: 0,
    dot: 10,
    lineGap: 3,
    minHeight: 0,
    detailIcon: 13,
    largeDetail: true,
    showCount: true,
  );

  static _PodMetrics forWidth(double width) {
    if (width >= 220) {
      return const _PodMetrics(
        avatar: 56,
        ringGap: 12,
        ringStroke: 4,
        nameFont: 17,
        padStart: 10,
        padEnd: 14,
        padVertical: 10,
        gap: 12,
        dot: 10,
        lineGap: 4,
        minHeight: 84,
        detailIcon: 13,
        largeDetail: true,
      );
    }
    if (width >= 150) {
      return const _PodMetrics(
        avatar: 48,
        ringGap: 12,
        ringStroke: 4,
        nameFont: 16,
        padStart: 8,
        padEnd: 12,
        padVertical: 8,
        gap: 10,
        dot: 10,
        lineGap: 3,
        minHeight: 74,
        detailIcon: 12,
        largeDetail: true,
      );
    }
    if (width >= 124) {
      return const _PodMetrics(
        avatar: 44,
        ringGap: 10,
        ringStroke: 3.5,
        nameFont: 15,
        padStart: 6,
        padEnd: 10,
        padVertical: 7,
        gap: 8,
        dot: 9,
        lineGap: 3,
        minHeight: 66,
        detailIcon: 11,
        largeDetail: false,
      );
    }
    return const _PodMetrics(
      avatar: 40,
      ringGap: 10,
      ringStroke: 3.5,
      nameFont: 14,
      padStart: 5,
      padEnd: 7,
      padVertical: 6,
      gap: 6,
      dot: 8,
      lineGap: 2,
      minHeight: 60,
      detailIcon: 10,
      largeDetail: false,
    );
  }

  TextStyle? detailStyle(BuildContext context) => largeDetail
      ? context.textTheme.labelMedium
      : context.textTheme.labelSmall;
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
