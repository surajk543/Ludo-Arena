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
/// progress (Ludo tokens home, Snakes square). A presence mark sits on the
/// avatar's edge: a green dot while the player is connected, a wifi-off
/// badge while they are disconnected (none once they left). The current turn is
/// emphasised with a seat-colored glow and a server-clock [CountdownRing].
///
/// Where the pod has room (the [stacked] card and the widest row tier) the
/// progress is a narrow vertical column on the avatar's trailing side; the
/// height the horizontal progress line used to take goes to a larger
/// avatar, so the pod's outer size does not change.
///
/// Around a portrait board the match layout gives every pod the [height]
/// the full-width board leaves; the pod then fills it and its avatar grows
/// with it (see [_PodMetrics.fill]).
class PlayerPanel extends StatelessWidget {
  const PlayerPanel({
    super.key,
    required this.player,
    required this.room,
    required this.isSelf,
    required this.isTurn,
    this.turnTotalMs = 20000,
    this.stacked = false,
    this.height,
    this.muted = false,
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
  /// name below) at its natural size; without it, the compact row. Pods
  /// given a [height] choose for themselves.
  final bool stacked;

  /// Height to fill (portrait match rows), the same on and off turn. The
  /// pod is then a card or a row, whichever shows the larger avatar at its
  /// width and this height, and [stacked] is ignored. Null — or less than a
  /// row pod needs at this width — keeps the pod's natural size.
  final double? height;

  /// The user muted this player from their pod (a muted icon by the name).
  final bool muted;

  /// Opens the player's options (opponents only). The pod then reads as a
  /// button to screen readers.
  final VoidCallback? onTap;

  /// Width from which a pod filling [height] no longer grows its avatar
  /// (wider only adds empty space): the match layout lets the dice dock
  /// grow only into width beyond it.
  static double fillWidthFor(BuildContext context, double height) =>
      _PodMetrics.fillCardWidth(context, height);

  SeatColor get _seat => SeatColor.tryFromName(player.color) ?? SeatColor.red;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth.isFinite
          ? constraints.maxWidth
          : 240.0;
      final target = height;
      final fill = target == null
          ? null
          : _PodMetrics.fill(context, width, target);
      if (fill != null) {
        return _buildPod(
          context,
          fill.metrics,
          card: fill.card,
          height: fill.height,
        );
      }
      return _buildPod(
        context,
        stacked ? _PodMetrics.stackedFor(width) : _PodMetrics.forWidth(width),
        card: stacked,
      );
    },
  );

  /// [card]: avatar row above the name. [height]: a filled pod's fixed
  /// outer height (its content centered in it).
  Widget _buildPod(
    BuildContext context,
    _PodMetrics m, {
    required bool card,
    double? height,
  }) {
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
    // its size; the avatar fills the row up to [_PodMetrics.avatar]. A
    // filled card's row is exactly its turn-ring box.
    final cardRow = card && side
        ? m.cardRow ??
              _PodMetrics.classicRingBox +
                  m.lineGap +
                  math.max(
                    m.detailIcon,
                    _lineHeight(context, m.detailStyle(context)),
                  )
        : 0.0;
    final avatarSize = card && side
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
    if (!out) {
      avatar = _withPresence(
        avatar,
        ring: ring,
        avatarSize: avatarSize,
        online: player.connected,
        reduce: reduce,
      );
    }

    final progress = _progress(context, l10n, m);
    final status = _statusChip(context, l10n, m, offline: offline, out: out);

    final semantics = [
      name,
      if (isSelf) l10n.commonYou,
      if (isTurn) l10n.playPanelTurnA11y,
      if (!out && player.connected) l10n.playPlayerOnline,
      if (offline) l10n.playPlayerDisconnected,
      if (muted) l10n.playPlayerMuted,
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
        if (muted) ...[
          const SizedBox(width: 3),
          Icon(
            Icons.volume_off_rounded,
            key: ValueKey('pod-muted-${player.seat}'),
            size: m.nameFont - 2,
            color: c.textMuted,
          ),
        ],
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
      height: height,
      alignment: height == null ? null : Alignment.center,
      constraints: height == null
          ? BoxConstraints(minHeight: m.minHeight)
          : null,
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
      child: switch ((card, side)) {
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

  /// [avatar] (its turn-ring box, [ring] wide) with the presence mark
  /// centred on the avatar circle's bottom-end edge (mirrored in RTL).
  Widget _withPresence(
    Widget avatar, {
    required double ring,
    required double avatarSize,
    required bool online,
    required bool reduce,
  }) {
    final dot = (avatarSize * 0.22).clamp(9.0, 16.0);
    final box = (dot * 1.45).roundToDouble();
    // Distance from the box's bottom-end corner to the avatar circle at 45°.
    final edge = ring / 2 - avatarSize / 2 * math.sqrt1_2;
    final inset = math.max(0.0, edge - box / 2);
    return SizedBox.square(
      dimension: ring,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(child: avatar),
          PositionedDirectional(
            end: inset,
            bottom: inset,
            child: SizedBox.square(
              dimension: box,
              child: Center(
                child: AnimatedSwitcher(
                  duration: reduce ? Duration.zero : AppDurations.fast,
                  child: _PresenceMark(
                    key: ValueKey(
                      '${online ? 'pod-online' : 'pod-offline'}-${player.seat}',
                    ),
                    online: online,
                    dot: dot,
                    box: box,
                  ),
                ),
              ),
            ),
          ),
        ],
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
    this.cardRow,
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

  /// A filled card's avatar row height (its turn-ring box); null for the
  /// natural card, whose row keeps the classic card's height.
  final double? cardRow;

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

  // ------------------------------------------------------------- fill

  /// Border budgeted on each side of a filled pod: the turn border (1 dp off
  /// turn), so a filled pod keeps its size when the turn changes.
  static const double _fillBorder = 2;

  /// Largest avatar of a filled pod.
  static const double maxFillAvatar = 96;

  /// Tallest filled pod; a taller row leaves the rest around the board.
  static const double maxFillHeight = 176;

  /// Room a filled row pod keeps for the name beside a grown avatar.
  static const double _fillNameRoom = 72;

  /// Filled card: paddings, the gap above the name and the name's size.
  static const double _fillCardPad = 8;
  static const double _fillCardPadV = 5;
  static const double _fillCardGap = 3;
  static const double _fillCardName = 15;

  /// Smallest avatar worth a filled card.
  static const double _minFillCardAvatar = 36;

  /// A pod filling [target] dp of height at [width]: a card (avatar row
  /// above the full-width name) or a row (name beside the avatar),
  /// whichever shows the larger avatar — on phones the card, since a row
  /// pod's avatar is limited by its width. Ties go to the card, which shows
  /// more of the name. The avatar grows with the height up to
  /// [maxFillAvatar] (and what the width allows); text grows modestly.
  /// Null when [target] is shorter than this width's row pod.
  static ({_PodMetrics metrics, bool card, double height})? fill(
    BuildContext context,
    double width,
    double target,
  ) {
    final height = math.min(target, maxFillHeight).floorToDouble();
    final row = _fillRow(width, height);
    if (row == null) return null;
    final card = _fillCard(context, width, height);
    if (card != null && card.avatar >= row.avatar) {
      return (metrics: card, card: true, height: height);
    }
    return (metrics: row, card: false, height: height);
  }

  /// Row pod of this width's tier with the avatar grown into [height],
  /// as long as the name keeps [_fillNameRoom].
  static _PodMetrics? _fillRow(double width, double height) {
    final t = forWidth(width);
    final ring = height - 2 * _fillBorder - 2 * t.padVertical;
    if (ring < t.avatar + t.ringGap) return null;
    final column = t.side ? t.sideGap + _cardColumn : 0.0;
    final byWidth =
        width -
        2 * _fillBorder -
        t.padStart -
        t.padEnd -
        t.gap -
        column -
        _fillNameRoom -
        t.ringGap;
    final avatar = math
        .max(
          t.avatar,
          math.min(math.min(ring - t.ringGap, byWidth), maxFillAvatar),
        )
        .floorToDouble();
    // One step of name size per 16 dp of avatar growth, at most two.
    final grown = ((avatar - t.avatar) / 16).floorToDouble().clamp(0.0, 2.0);
    return _PodMetrics(
      avatar: avatar,
      ringGap: t.ringGap,
      ringStroke: t.ringStroke,
      nameFont: t.nameFont + grown,
      padStart: t.padStart,
      padEnd: t.padEnd,
      padVertical: t.padVertical,
      gap: t.gap,
      dot: t.dot,
      lineGap: t.lineGap,
      minHeight: 0,
      detailIcon: t.detailIcon,
      largeDetail: t.largeDetail,
      showCount: t.showCount,
      side: t.side,
      sideIcon: t.sideIcon,
      sideSpacing: t.sideSpacing,
      sideGap: t.sideGap,
    );
  }

  /// Gap between a filled card's turn ring and its progress column.
  static const double _fillCardSideGap = 4;

  /// A filled card's avatar row box (ring) for a pod [height] — what is
  /// left under the name line and paddings — and the turn-ring gap in it
  /// (thinner around smaller avatars: 10 dp up to a 67 dp ring, 12 dp from
  /// 80 dp; the stroke is a third of it).
  static ({double ring, double ringGap}) _fillCardRing(
    BuildContext context,
    double height,
  ) {
    final nameLine = math.max(
      10.0, // the seat dot
      _lineHeight(
        context,
        context.textTheme.labelLarge?.copyWith(fontSize: _fillCardName),
      ),
    );
    final ring =
        height - 2 * _fillBorder - 2 * _fillCardPadV - _fillCardGap - nameLine;
    return (ring: ring, ringGap: (ring * 0.15).clamp(10.0, 12.0));
  }

  /// A filled card's width besides its avatar: paddings, turn border,
  /// ring gap and the progress column.
  static double _fillCardChrome(double ringGap) =>
      2 * _fillCardPad +
      2 * _fillBorder +
      _fillCardSideGap +
      _cardColumn +
      ringGap;

  /// Width from which a card filling [target] dp of height shows its
  /// largest avatar (wider pods only add empty space).
  static double fillCardWidth(BuildContext context, double target) {
    final r = _fillCardRing(
      context,
      math.min(target, maxFillHeight).floorToDouble(),
    );
    final avatar = math.min(r.ring - r.ringGap, maxFillAvatar).floorToDouble();
    return avatar + _fillCardChrome(r.ringGap);
  }

  /// Card with the progress column beside an avatar that fills [height]
  /// (above the name line); null when too narrow or short for one.
  static _PodMetrics? _fillCard(
    BuildContext context,
    double width,
    double height,
  ) {
    final (:ring, :ringGap) = _fillCardRing(context, height);
    final byWidth = width - _fillCardChrome(ringGap);
    final avatar = math
        .min(math.min(ring - ringGap, byWidth), maxFillAvatar)
        .floorToDouble();
    if (avatar < _minFillCardAvatar) return null;
    final cardRow = avatar + ringGap;
    // Token marks fill the column; the "0/4" count stays while the marks
    // keep 12 dp with it (screen readers always get the full progress).
    const spacing = 2.0;
    final countLine = math.max(
      13.0,
      _lineHeight(context, context.textTheme.labelMedium),
    );
    var icon = ((cardRow - 3 * spacing - 2 - countLine) / 4).floorToDouble();
    final showCount = icon >= 12;
    if (!showCount) icon = ((cardRow - 3 * spacing) / 4).floorToDouble();
    return _PodMetrics(
      avatar: avatar,
      ringGap: ringGap,
      ringStroke: ringGap / 3,
      nameFont: _fillCardName,
      padStart: _fillCardPad,
      padEnd: _fillCardPad,
      padVertical: _fillCardPadV,
      gap: 0,
      dot: 10,
      // The card puts lineGap + 2 between the avatar row and the name.
      lineGap: _fillCardGap - 2,
      minHeight: 0,
      detailIcon: 13,
      largeDetail: true,
      showCount: showCount,
      side: true,
      sideIcon: icon.clamp(8.0, 18.0),
      sideSpacing: spacing,
      sideGap: _fillCardSideGap,
      cardRow: cardRow,
    );
  }

  TextStyle? detailStyle(BuildContext context) => largeDetail
      ? context.textTheme.labelMedium
      : context.textTheme.labelSmall;
}

/// Presence on the avatar: a green dot (connected) or a small wifi-off
/// badge (disconnected). Both are ringed with the surface color so they
/// read on any avatar, frame and theme.
class _PresenceMark extends StatelessWidget {
  const _PresenceMark({
    super.key,
    required this.online,
    required this.dot,
    required this.box,
  });

  final bool online;
  final double dot;
  final double box;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (online) {
      return Container(
        width: dot,
        height: dot,
        decoration: BoxDecoration(
          color: c.success,
          shape: BoxShape.circle,
          border: Border.all(color: c.surface, width: math.max(1.5, dot / 6)),
        ),
      );
    }
    return Container(
      width: box,
      height: box,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.surface,
        shape: BoxShape.circle,
        border: Border.all(color: c.warning, width: 1.2),
        boxShadow: c.shadow(AppElevation.low),
      ),
      child: Icon(Icons.wifi_off_rounded, size: box * 0.62, color: c.warning),
    );
  }
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
