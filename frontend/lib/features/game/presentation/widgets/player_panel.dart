import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/audio_haptics/reduced_motion.dart';
import '../../../../core/protocol/protocol.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../shared/game_visuals/game_visuals.dart';
import '../../../../shared/widgets/widgets.dart';
import '../play_text.dart';

/// Per-seat summary shown around the board: avatar with frame, name, seat color, connection / forfeit state, missed-turn strikes and
/// progress (Ludo tokens home, Snakes square). The current turn is
/// emphasised with a seat-colored glow and a server-clock [CountdownRing].
///
/// Where the pod has room (the [stacked] card and the widest row tier) the
/// progress is a narrow vertical column on the avatar's trailing side; the
/// height the horizontal progress line used to take goes to a larger
/// avatar, so the pod's outer size does not change.
class PlayerPanel extends StatelessWidget {
  const PlayerPanel({
    super.key,
    required this.player,
    required this.room,
    required this.isSelf,
    required this.isTurn,
    this.turnTotalMs = 20000,
    this.stacked = false,
    this.onTap,
  });

  final RoomPlayer player;

  /// The presented room (progress is read from its board).
  final RoomSnapshot room;
  final bool isSelf;
  final bool isTurn;

  /// Full duration of the current turn (for the ring fraction).
  final int turnTotalMs;

  /// Card layout (large avatar with the progress column beside it, full-width
  /// name below), used when the screen has spare height around the board.
  final bool stacked;

  /// Opens the player's options (opponents only). The pod then reads as a
  /// button to screen readers.
  final VoidCallback? onTap;

  SeatColor get _seat => SeatColor.tryFromName(player.color) ?? SeatColor.red;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth.isFinite
          ? constraints.maxWidth
          : 240.0;
      return _buildPod(
        context,
        stacked ? _PodMetrics.stackedFor(width) : _PodMetrics.forWidth(width),
      );
    },
  );

  Widget _buildPod(BuildContext context, _PodMetrics m) {
    final c = context.colors;
    final l10n = AppLocalizations.of(context);
    final palette = GamePalette.of(context);
    final shades = palette.shades(_seat);
    final out = player.forfeited;
    final offline = !player.connected && !out;
    final name = PlayText.playerName(l10n, player);
    final reduce = ReducedMotion.of(context);
    final side = m.side;
    // A side card's avatar row is as tall as the classic card's avatar plus
    // its progress line (which follows the text scale), so the card keeps
    // its size; the avatar fills the row up to [_PodMetrics.avatar].
    final cardRow = stacked && side
        ? _PodMetrics.classicRingBox +
              m.lineGap +
              math.max(
                m.detailIcon,
                _lineHeight(context, m.detailStyle(context)),
              )
        : 0.0;
    final avatarSize = stacked && side
        ? math.min(m.avatar, (cardRow - m.ringGap).floorToDouble())
        : m.avatar;

    Widget avatar = PlayerAvatar(
      avatarIndex: player.avatar,
      picture: player.picture,
      frameId: player.cosmetics.frame,
      size: avatarSize,
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

    final shownName = isSelf ? l10n.commonYou : name;

    Widget nameLine({required bool center, bool strikes = false}) => Row(
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
        if (strikes && player.strikes > 0) ...[
          const SizedBox(width: 4),
          _Strikes(count: player.strikes),
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
        else if (progress != null && !side)
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

    final pod = AnimatedContainer(
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
      child: switch ((stacked, side)) {
        // Card: [avatar | progress column] above the name.
        (true, true) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: cardRow,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    children: [
                      avatar,
                      if (out || offline)
                        // Offline / left: a stamp on the dimmed avatar.
                        Positioned.fill(
                          child: Align(
                            alignment: Alignment.topCenter,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: _StatusStamp(out: out),
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (progress != null) ...[
                    SizedBox(width: m.sideGap),
                    Flexible(child: progress.$1),
                  ],
                ],
              ),
            ),
            SizedBox(height: m.lineGap + 2),
            nameLine(center: true, strikes: true),
          ],
        ),
        (true, false) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            avatar,
            SizedBox(height: m.lineGap + 2),
            nameLine(center: true),
            SizedBox(height: m.lineGap),
            detailLine(center: true),
          ],
        ),
        (false, _) => Row(
          children: [
            avatar,
            if (side && progress != null) ...[
              SizedBox(width: m.sideGap),
              progress.$1,
            ],
            SizedBox(width: m.gap),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  nameLine(center: false),
                  // With the progress beside the avatar the second line
                  // only carries the offline / left state and strikes.
                  if (!side || out || offline || player.strikes > 0) ...[
                    SizedBox(height: m.lineGap),
                    detailLine(center: false),
                  ],
                ],
              ),
            ),
          ],
        ),
      },
    );
    final tap = onTap;
    return Semantics(
      container: true,
      label: semantics,
      button: tap != null,
      onTap: tap,
      onTapHint: tap == null ? null : l10n.socialPodOptionsHint,
      excludeSemantics: true,
      child: tap == null
          ? pod
          : GestureDetector(
              key: ValueKey('pod-${player.seat}'),
              behavior: HitTestBehavior.opaque,
              excludeFromSemantics: true,
              onTap: tap,
              child: pod,
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
      Widget token(int i, double size) => Icon(
        i < home ? Icons.star_rounded : Icons.circle_outlined,
        size: size,
        color: i < home ? c.gold : c.textMuted,
      );
      if (m.side) {
        return (
          Column(
            key: const ValueKey('pod-progress-column'),
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < total; i++)
                Padding(
                  padding: EdgeInsets.only(top: i == 0 ? 0 : m.sideSpacing),
                  child: token(i, m.sideIcon),
                ),
              if (m.showCount) ...[
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text('$home/$total', maxLines: 1, style: style),
                ),
              ],
            ],
          ),
          text,
        );
      }
      return (
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < total; i++)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 2),
                child: token(i, m.detailIcon),
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
    if (m.side) {
      // The square number under a position pin (0: not on the board yet).
      return (
        Column(
          key: const ValueKey('pod-progress-column'),
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.place_rounded,
              size: m.sideIcon + 2,
              color: GamePalette.of(context).shades(_seat).base,
            ),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text('${math.max(square, 0)}', maxLines: 1, style: style),
            ),
          ],
        ),
        text,
      );
    }
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

/// Height of one line of [style] as a [Text] lays it out here (font size,
/// line height and the ambient text scaling).
double _lineHeight(BuildContext context, TextStyle? style) {
  final defaults = DefaultTextStyle.of(context);
  final painter = TextPainter(
    text: TextSpan(text: '0', style: defaults.style.merge(style)),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    textHeightBehavior: defaults.textHeightBehavior,
    maxLines: 1,
  )..layout();
  final height = painter.height;
  painter.dispose();
  return height;
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
    this.side = false,
    this.sideIcon = 0,
    this.sideSpacing = 0,
    this.sideGap = 0,
  });

  /// Avatar size; for a [side] card the largest size, capped further by the
  /// avatar row's height (see [PlayerPanel]).
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

  /// Show the numeric "home/total" with the token stars.
  final bool showCount;

  /// Progress as a vertical column beside the avatar (instead of a line
  /// under the name), [sideGap] from the turn ring, with [sideIcon]-sized
  /// token marks [sideSpacing] apart.
  final bool side;
  final double sideIcon;
  final double sideSpacing;
  final double sideGap;

  /// Ring box (avatar + turn ring) of the classic card. A [side] card's
  /// avatar row is this plus the progress line it replaces, which keeps the
  /// card's height.
  static double get classicRingBox => stacked.avatar + stacked.ringGap;

  /// Classic card preset: avatar on top, name and progress lines below.
  /// Used by [stackedFor] when the card is too narrow for a side column.
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

  /// Largest card avatar: fills the avatar row (classic ring box + progress
  /// line, 86.6 dp at the default text size) with its turn ring.
  static const double _cardAvatar = 74;

  /// Width kept for the progress column next to the card avatar (token
  /// marks and the "0/4" count; the count scales down below this).
  static const double _cardColumn = 22;

  /// Card preset (see [PlayerPanel.stacked]) for a pod [width]: the progress
  /// column beside an avatar as large as the width allows, or the classic
  /// card when not even the classic avatar fits next to the column.
  static _PodMetrics stackedFor(double width) {
    const sideGap = 4.0;
    // Paddings, the turn border (2 dp per side), the gap and the column.
    final ringRoom =
        width - stacked.padStart - stacked.padEnd - 4 - sideGap - _cardColumn;
    final avatar = math.min(
      _cardAvatar,
      (ringRoom - stacked.ringGap).floorToDouble(),
    );
    if (avatar < stacked.avatar) return stacked;
    return _PodMetrics(
      avatar: avatar,
      ringGap: stacked.ringGap,
      ringStroke: stacked.ringStroke,
      nameFont: stacked.nameFont,
      padStart: stacked.padStart,
      padEnd: stacked.padEnd,
      padVertical: stacked.padVertical,
      gap: stacked.gap,
      dot: stacked.dot,
      lineGap: stacked.lineGap,
      minHeight: stacked.minHeight,
      detailIcon: stacked.detailIcon,
      largeDetail: stacked.largeDetail,
      showCount: true,
      side: true,
      sideIcon: 14,
      sideSpacing: 2,
      sideGap: sideGap,
    );
  }

  static _PodMetrics forWidth(double width) {
    if (width >= 220) {
      // Progress beside the avatar; the avatar takes 4 dp of the vertical
      // padding (same 90 dp pod height as with 56 dp + 10 dp padding).
      return const _PodMetrics(
        avatar: 64,
        ringGap: 12,
        ringStroke: 4,
        nameFont: 17,
        padStart: 10,
        padEnd: 14,
        padVertical: 6,
        gap: 10,
        dot: 10,
        lineGap: 4,
        minHeight: 84,
        detailIcon: 13,
        largeDetail: true,
        side: true,
        sideIcon: 14,
        sideSpacing: 2,
        sideGap: 4,
      );
    }
    // Narrower rows keep the progress line under the name: a column beside
    // the avatar would leave the name only a few characters.
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

/// Missed-turn strikes, one dot per allowed miss (server `MAX_STRIKES`, 5
/// by default → removed). The row keeps a fixed 19.5 dp footprint.
class _Strikes extends StatelessWidget {
  const _Strikes({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final dots = math.max(count, ForfeitReasons.defaultMaxStrikes);
    final slot = 19.5 / dots;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < dots; i++)
          Container(
            width: slot * 0.8,
            height: slot * 0.8,
            margin: EdgeInsetsDirectional.only(end: slot * 0.2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i < count ? c.danger : c.outline.withValues(alpha: 0.6),
            ),
          ),
      ],
    );
  }
}

/// "Offline" / "Left" stamp across the top of a card's (dimmed) avatar.
class _StatusStamp extends StatelessWidget {
  const _StatusStamp({required this.out});

  final bool out;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = AppLocalizations.of(context);
    final color = out ? c.textMuted : c.warning;
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(5, 1, 6, 1),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: AppRadii.pillAll,
        border: Border.all(color: color, width: 1.2),
        boxShadow: c.shadow(AppElevation.low),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            out ? Icons.logout_rounded : Icons.wifi_off_rounded,
            size: 12,
            color: color,
          ),
          const SizedBox(width: 3),
          Text(
            out ? l10n.playPlayerForfeited : l10n.playPlayerDisconnected,
            maxLines: 1,
            style: context.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
