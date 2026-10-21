import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/audio_haptics/audio_service.dart';
import '../../../../core/audio_haptics/reduced_motion.dart';
import '../../../../core/localization/number_format.dart';
import '../../../../core/protocol/protocol.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/time/server_clock.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../shared/game_visuals/game_visuals.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../application/match_result_view.dart';
import '../../application/rematch_view.dart';
import '../play_text.dart';

/// Results after `game.finished`: winner and finishing order from
/// `result.placements`, the local outcome, server-confirmed rewards (coins
/// from `result.payout` / `wallet.updated`, XP from `progression.updated`
/// whenever it arrives) and the Rematch / Play again / Home actions.
class ResultsPanel extends ConsumerStatefulWidget {
  const ResultsPanel({
    super.key,
    required this.room,
    required this.selfUid,
    required this.rewards,
    required this.onRematch,
    required this.onPlayAgain,
    required this.onHome,
    this.onPlayerTap,
  });

  /// The finished room (server snapshot).
  final RoomSnapshot room;
  final String? selfUid;
  final MatchRewards rewards;

  /// `game.rematch` accept (true) / decline (false).
  final Future<void> Function(bool accept) onRematch;
  final FutureOr<void> Function() onPlayAgain;
  final FutureOr<void> Function() onHome;

  /// Opens an opponent's options from the finishing order.
  final ValueChanged<RoomPlayer>? onPlayerTap;

  @override
  ConsumerState<ResultsPanel> createState() => _ResultsPanelState();
}

class _ResultsPanelState extends ConsumerState<ResultsPanel> {
  Timer? _deadlineTimer;

  @override
  void initState() {
    super.initState();
    _armDeadline();
  }

  @override
  void didUpdateWidget(covariant ResultsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.room.rematch?.deadline != widget.room.rematch?.deadline) {
      _armDeadline();
    }
  }

  /// Re-evaluates the rematch stage when the offer expires (server clock).
  void _armDeadline() {
    _deadlineTimer?.cancel();
    final deadline = widget.room.rematch?.deadline ?? 0;
    if (deadline <= 0) return;
    final left = ref.read(serverClockProvider).remainingUntil(deadline);
    if (left == Duration.zero) return;
    _deadlineTimer = Timer(left + const Duration(milliseconds: 50), () {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _deadlineTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.colors;
    final room = widget.room;
    final view = MatchResultView.from(room, widget.selfUid);
    final self = room.playerByUid(widget.selfUid);
    final rematch = RematchView.from(
      room,
      self?.seat,
      nowMs: ref.read(serverClockProvider).nowMs(),
    );
    final selfRow = view.rows.where((r) => r.isSelf).firstOrNull;

    final title = switch (view.outcome) {
      MatchOutcome.won => l10n.playResultYouWon,
      MatchOutcome.forfeited => l10n.playResultYouForfeited,
      _ =>
        view.winner == null
            ? l10n.playResultGameOver
            : l10n.playResultWinnerIs(PlayText.playerName(l10n, view.winner!)),
    };
    final subtitle = view.outcome == MatchOutcome.won
        ? (view.byForfeit
              ? l10n.playResultByForfeit
              : l10n.playResultWellPlayed)
        : selfRow == null
        ? null
        : l10n.playResultYouFinished(selfRow.place);

    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      label: title,
      child: Material(
        type: MaterialType.transparency,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.xl,
                AppSpacing.lg,
                AppSpacing.xl,
              ),
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.lg),
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: AppRadii.xlAll,
                  border: Border.all(
                    color: view.selfWon
                        ? c.gold
                        : (c.isDark
                              ? Colors.white.withValues(alpha: 0.1)
                              : c.outline),
                    width: view.selfWon ? 2 : 1,
                  ),
                  boxShadow: c.shadow(AppElevation.high),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Header(view: view, title: title, subtitle: subtitle),
                    const SizedBox(height: AppSpacing.lg),
                    _Placements(view: view, onPlayerTap: widget.onPlayerTap),
                    const SizedBox(height: AppSpacing.md),
                    _Rewards(view: view, rewards: widget.rewards, room: room),
                    const SizedBox(height: AppSpacing.md),
                    _RematchCard(
                      view: rematch,
                      room: room,
                      selfSeat: self?.seat,
                      onRematch: widget.onRematch,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    PremiumButton(
                      label: l10n.playPlayAgain,
                      icon: Icons.replay_rounded,
                      variant: PremiumButtonVariant.gold,
                      size: PremiumButtonSize.medium,
                      sound: Sfx.lobbyPlay,
                      onPressed: widget.onPlayAgain,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    PremiumButton(
                      label: l10n.playHome,
                      icon: Icons.home_rounded,
                      variant: PremiumButtonVariant.ghost,
                      size: PremiumButtonSize.medium,
                      onPressed: widget.onHome,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.view, required this.title, this.subtitle});

  final MatchResultView view;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = AppLocalizations.of(context);
    final winner = view.winner;
    final palette = GamePalette.of(context);
    final seat = SeatColor.tryFromName(winner?.color);
    return Column(
      children: [
        if (winner != null)
          Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.topCenter,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 18),
                child: PlayerAvatar(
                  avatarIndex: winner.avatar,
                  picture: winner.picture,
                  frameId: winner.cosmetics.frame,
                  size: 76,
                  seatColor: seat,
                  semanticLabel: PlayText.playerName(l10n, winner),
                ),
              ),
              Icon(
                Icons.emoji_events_rounded,
                size: 30,
                color: seat == null ? c.gold : palette.seat(seat),
                shadows: [
                  Shadow(color: c.gold.withValues(alpha: 0.6), blurRadius: 8),
                ],
              ),
            ],
          ),
        const SizedBox(height: AppSpacing.md),
        Semantics(
          header: true,
          liveRegion: true,
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: context.textTheme.headlineSmall?.copyWith(
              color: view.selfWon ? c.goldStrong : c.textPrimary,
            ),
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            subtitle!,
            textAlign: TextAlign.center,
            style: context.textTheme.bodyMedium?.copyWith(
              color: c.textSecondary,
            ),
          ),
        ],
      ],
    );
  }
}

class _Placements extends StatelessWidget {
  const _Placements({required this.view, this.onPlayerTap});

  final MatchResultView view;
  final ValueChanged<RoomPlayer>? onPlayerTap;

  /// Opponent rows open the player's options (my own row never does).
  Widget _tappable(BuildContext context, PlacementRow row, Widget child) {
    final tap = onPlayerTap;
    if (tap == null || row.isSelf) return child;
    return Semantics(
      button: true,
      onTapHint: AppLocalizations.of(context).socialPodOptionsHint,
      child: InkWell(
        key: ValueKey('placement-${row.player.seat}'),
        borderRadius: AppRadii.smAll,
        onTap: () => tap(row.player),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.colors;
    return _Card(
      title: l10n.playResultFinishingOrder,
      child: Column(
        children: [
          for (final row in view.rows)
            _tappable(
              context,
              row,
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    _Medal(place: row.place, forfeited: row.player.forfeited),
                    const SizedBox(width: AppSpacing.sm),
                    PlayerAvatar(
                      avatarIndex: row.player.avatar,
                      picture: row.player.picture,
                      frameId: row.player.cosmetics.frame,
                      size: 34,
                      seatColor: SeatColor.tryFromName(row.player.color),
                      dimmed: row.player.forfeited,
                      semanticLabel: PlayText.playerName(l10n, row.player),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        row.isSelf
                            ? l10n.playNameYou(
                                PlayText.playerName(l10n, row.player),
                              )
                            : PlayText.playerName(l10n, row.player),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.textTheme.labelLarge?.copyWith(
                          color: row.isSelf ? c.brand : c.textPrimary,
                        ),
                      ),
                    ),
                    if (row.player.forfeited) ...[
                      const SizedBox(width: AppSpacing.xs),
                      Text(
                        l10n.playPlayerForfeited,
                        style: context.textTheme.labelSmall?.copyWith(
                          color: c.textMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Medal extends StatelessWidget {
  const _Medal({required this.place, required this.forfeited});

  final int place;
  final bool forfeited;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = AppLocalizations.of(context);
    final color = forfeited
        ? c.textMuted
        : switch (place) {
            1 => BrandPalette.gold500,
            2 => const Color(0xFFB8C2CC),
            3 => const Color(0xFFCD8A4E),
            _ => c.outline,
          };
    return Semantics(
      label: l10n.playResultPlaceA11y(place),
      excludeSemantics: true,
      child: Container(
        width: 28,
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: 0.22),
          border: Border.all(color: color, width: 2),
        ),
        child: Text(
          l10n.playResultPlaceShort(place),
          style: context.textTheme.labelMedium?.copyWith(
            color: c.textPrimary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}

class _Rewards extends StatelessWidget {
  const _Rewards({
    required this.view,
    required this.rewards,
    required this.room,
  });

  final MatchResultView view;
  final MatchRewards rewards;
  final RoomSnapshot room;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.colors;
    final locale = Localizations.localeOf(context);
    final reduce = ReducedMotion.of(context);
    final progression = rewards.progression;
    final payoutConfirmed = rewards.payout;

    final coinsRow = view.selfPayout > 0
        ? _RewardRow(
            leading: const CoinIcon(size: 24),
            text: l10n.playRewardCoins(formatCoins(view.selfPayout, locale)),
            detail: payoutConfirmed == null
                ? null
                : l10n.playRewardCoinsBalance(
                    formatCoins(payoutConfirmed.coins, locale),
                  ),
            confirmed: payoutConfirmed != null,
          )
        : _RewardRow(
            leading: Icon(Icons.toll_rounded, color: c.textMuted, size: 22),
            text: view.botMatch
                ? l10n.playRewardNoCoinsMatch
                : l10n.playRewardNoCoins,
            muted: true,
          );

    final Widget xpRow;
    if (progression != null) {
      xpRow = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _RewardRow(
            leading: Icon(Icons.auto_awesome_rounded, color: c.brand, size: 22),
            text: l10n.playRewardXp(progression.xpGained),
            confirmed: true,
          ),
          if (progression.levelUp) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                LevelUpBurst(
                  size: 56,
                  reducedMotion: reduce,
                  child: LevelBadge(level: progression.level, size: 30),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    l10n.playRewardLevelUp(progression.level),
                    style: context.textTheme.titleSmall?.copyWith(
                      color: c.goldStrong,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (progression.unlocked.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(l10n.playRewardUnlocked, style: context.textTheme.labelMedium),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                for (final id in progression.unlocked)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    avatar: Icon(
                      Icons.lock_open_rounded,
                      size: 16,
                      color: c.gold,
                    ),
                    label: Text(cosmeticName(l10n, id)),
                  ),
              ],
            ),
          ],
        ],
      );
    } else if (rewards.progressionTimedOut) {
      xpRow = _RewardRow(
        leading: Icon(Icons.auto_awesome_rounded, color: c.textMuted, size: 22),
        text: l10n.playRewardXpLater,
        muted: true,
      );
    } else {
      xpRow = _RewardRow(
        leading: SizedBox.square(
          dimension: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2.4,
            valueColor: AlwaysStoppedAnimation(c.brand),
          ),
        ),
        text: l10n.playRewardXpPending,
        muted: true,
      );
    }

    return _Card(
      title: l10n.playRewardsTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          coinsRow,
          const SizedBox(height: AppSpacing.sm),
          xpRow,
        ],
      ),
    );
  }
}

class _RewardRow extends StatelessWidget {
  const _RewardRow({
    required this.leading,
    required this.text,
    this.detail,
    this.confirmed = false,
    this.muted = false,
  });

  final Widget leading;
  final String text;
  final String? detail;
  final bool confirmed;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      children: [
        SizedBox(width: 28, child: Center(child: leading)),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                text,
                style:
                    (muted
                            ? context.textTheme.bodyMedium
                            : context.textTheme.titleSmall)
                        ?.copyWith(
                          color: muted ? c.textSecondary : c.textPrimary,
                        ),
              ),
              if (detail != null)
                Text(
                  detail!,
                  style: context.textTheme.bodySmall?.copyWith(
                    color: c.textSecondary,
                  ),
                ),
            ],
          ),
        ),
        if (confirmed)
          Icon(Icons.check_circle_rounded, color: c.success, size: 20),
      ],
    );
  }
}

class _RematchCard extends StatelessWidget {
  const _RematchCard({
    required this.view,
    required this.room,
    required this.selfSeat,
    required this.onRematch,
  });

  final RematchView view;
  final RoomSnapshot room;
  final int? selfSeat;
  final Future<void> Function(bool accept) onRematch;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.colors;
    final open = view.isOpen && view.deadline > 0;
    final others = view.seats.where((s) => s.player.seat != selfSeat).toList();

    final Widget body = switch (view.stage) {
      RematchStage.canRequest => PremiumButton(
        label: l10n.playRematchRequest,
        icon: Icons.restart_alt_rounded,
        size: PremiumButtonSize.medium,
        onPressed: () => onRematch(true),
      ),
      RematchStage.incomingRequest => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            liveRegion: true,
            child: Text(
              l10n.playRematchIncoming(
                PlayText.playerName(l10n, view.requester!),
              ),
              textAlign: TextAlign.center,
              style: context.textTheme.titleSmall,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: PremiumButton(
                  label: l10n.playRematchDecline,
                  variant: PremiumButtonVariant.secondary,
                  size: PremiumButtonSize.medium,
                  onPressed: () => onRematch(false),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: PremiumButton(
                  label: l10n.playRematchAccept,
                  icon: Icons.check_rounded,
                  size: PremiumButtonSize.medium,
                  onPressed: () => onRematch(true),
                ),
              ),
            ],
          ),
        ],
      ),
      RematchStage.waitingForOthers => _Note(
        icon: Icons.hourglass_top_rounded,
        text: l10n.playRematchWaiting,
      ),
      RematchStage.declined => _Note(
        icon: Icons.do_not_disturb_on_rounded,
        text: l10n.playRematchYouDeclined,
      ),
      RematchStage.closed || RematchStage.notEligible => _Note(
        icon: Icons.timer_off_rounded,
        text: l10n.playRematchClosed,
      ),
    };

    return _Card(
      title: l10n.playRematchTitle,
      trailing: open
          ? CountdownRing(
              deadlineMs: view.deadline,
              totalMs: 30000,
              size: 34,
              strokeWidth: 3,
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          body,
          if (others.isNotEmpty && view.stage != RematchStage.closed) ...[
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [for (final s in others) _ConsentChip(seat: s)],
            ),
          ],
          if (room.mode == RoomModes.public &&
              view.stage != RematchStage.closed) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              l10n.playRematchPublicNote,
              style: context.textTheme.bodySmall?.copyWith(
                color: c.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ConsentChip extends StatelessWidget {
  const _ConsentChip({required this.seat});

  final RematchSeat seat;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.colors;
    final (IconData icon, Color color, String label) = switch (seat.answer) {
      RematchAnswer.accepted => (
        Icons.check_circle_rounded,
        c.success,
        l10n.playRematchStatusAccepted,
      ),
      RematchAnswer.declined => (
        Icons.cancel_rounded,
        c.danger,
        l10n.playRematchStatusDeclined,
      ),
      RematchAnswer.pending => (
        Icons.more_horiz_rounded,
        c.warning,
        l10n.playRematchStatusPending,
      ),
      RematchAnswer.ineligible => (
        Icons.remove_circle_outline_rounded,
        c.textMuted,
        l10n.playRematchStatusOut,
      ),
    };
    final name = PlayText.playerName(l10n, seat.player);
    return Semantics(
      label: l10n.playRematchSeatA11y(name, label),
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsetsDirectional.fromSTEB(4, 3, 10, 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: AppRadii.pillAll,
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            PlayerAvatar(
              avatarIndex: seat.player.avatar,
              picture: seat.player.picture,
              size: 24,
              animatePicture: false,
            ),
            const SizedBox(width: 4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 96),
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.textTheme.labelMedium,
              ),
            ),
            const SizedBox(width: 4),
            Icon(icon, size: 16, color: color),
          ],
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      liveRegion: true,
      child: Row(
        children: [
          Icon(icon, color: c.textSecondary, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: context.textTheme.bodyMedium?.copyWith(
                color: c.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.child, this.trailing});

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: c.surfaceSunken.withValues(alpha: c.isDark ? 0.6 : 0.7),
        borderRadius: AppRadii.lgAll,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(title, style: context.textTheme.titleSmall),
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          child,
        ],
      ),
    );
  }
}
