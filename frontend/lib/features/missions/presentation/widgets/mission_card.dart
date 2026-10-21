import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/audio_haptics/audio_service.dart';
import '../../../../core/audio_haptics/haptics_service.dart';
import '../../../../core/audio_haptics/reduced_motion.dart';
import '../../../../core/localization/number_format.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../../meta_routes.dart';
import '../../../progression/application/meta_support.dart';
import '../../../progression/presentation/widgets/reward_widgets.dart';
import '../../application/missions_controller.dart';
import '../../domain/mission_models.dart';
import '../../domain/mission_texts.dart';
import 'claim_feedback.dart';

/// A mission: localized title/description, game icon, progress, rewards and
/// its state — in progress, completed (claimable, gentle gold glow) or
/// claimed. Claiming is exactly-once (see [MissionsController.claim]).
class MissionCard extends ConsumerStatefulWidget {
  const MissionCard({
    super.key,
    required this.periodKey,
    required this.mission,
  });

  final String periodKey;
  final Mission mission;

  @override
  ConsumerState<MissionCard> createState() => _MissionCardState();
}

class _MissionCardState extends ConsumerState<MissionCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _glow = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  /// Server-confirmed claim of this card (drives the "collected" strip).
  ClaimSucceeded? _collected;
  bool _confetti = false;

  bool get _claimable =>
      widget.mission.status == MissionStatus.claimable && _collected == null;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncGlow();
  }

  @override
  void didUpdateWidget(covariant MissionCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncGlow();
  }

  void _syncGlow() {
    final animate = _claimable && !context.reduceMotion;
    if (animate && !_glow.isAnimating) {
      _glow.repeat(reverse: true);
    } else if (!animate && _glow.isAnimating) {
      _glow.stop();
    }
  }

  @override
  void dispose() {
    _glow.dispose();
    super.dispose();
  }

  Future<void> _claim() async {
    final outcome = await ref
        .read(missionsProvider.notifier)
        .claim(widget.periodKey, widget.mission.id);
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    switch (outcome) {
      case ClaimSucceeded(:final result):
        ref.read(audioServiceProvider).play(Sfx.rewardClaim);
        ref.read(hapticsServiceProvider).success();
        setState(() {
          _collected = outcome;
          _confetti = true;
        });
        _syncGlow();
        // Level-ups are celebrated by the level-up host (with the items);
        // otherwise show newly granted items here.
        if (result.granted.isNotEmpty && !result.progression.levelUp) {
          final open = await GrantedItemsDialog.show(context, result.granted);
          if (open && mounted) {
            context.push(
              MetaRoutes.collectionFor(kind: result.granted.first.kind),
            );
          }
        }
      case ClaimIgnored():
        break;
      case ClaimFailed(:final error, :final canRetry):
        if (error.code == 'already_claimed') {
          AppToast.show(context, l10n.errorAlreadyClaimed);
          return;
        }
        final msg = metaErrorMessage(
          l10n,
          error,
          context: MetaErrorContext.mission,
        );
        AppToast.show(
          context,
          canRetry ? l10n.metaRetryHint(msg) : msg,
          kind: canRetry ? ToastKind.warning : ToastKind.error,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context);
    final c = context.colors;
    final m = widget.mission;
    final status = _collected != null ? MissionStatus.claimed : m.status;
    final title = MissionTexts.title(l10n, m);
    final desc = MissionTexts.description(l10n, m);
    final progressText = l10n.metaProgressCount(
      formatNumberFull(m.shownProgress, locale),
      formatNumberFull(m.target, locale),
    );
    final stateText = switch (status) {
      MissionStatus.inProgress => l10n.metaStatusInProgress,
      MissionStatus.claimable => l10n.metaStatusReady,
      MissionStatus.claimed => l10n.metaStatusClaimed,
    };
    final claimed = status == MissionStatus.claimed;

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _GameIcon(game: m.game, periodKey: widget.periodKey),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: context.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    desc,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: context.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(
              child: _ProgressTrack(
                fraction: claimed ? 1 : m.fraction,
                complete: status != MissionStatus.inProgress,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              progressText,
              textDirection: TextDirection.ltr,
              style: context.textTheme.labelMedium?.copyWith(
                color: c.textSecondary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        RewardChips(
          coins: m.reward.coins,
          diamonds: m.reward.diamonds,
          xp: m.reward.xp,
          items: m.reward.items,
          muted: claimed,
        ),
        if (status == MissionStatus.claimable) ...[
          const SizedBox(height: AppSpacing.md),
          PremiumButton(
            key: ValueKey('claim-${widget.periodKey}-${m.id}'),
            label: l10n.metaClaim,
            icon: Icons.redeem_rounded,
            variant: PremiumButtonVariant.gold,
            size: PremiumButtonSize.medium,
            sound: null,
            onPressed: _claim,
          ),
        ] else if (claimed) ...[
          const SizedBox(height: AppSpacing.sm),
          _ClaimedRow(collected: _collected != null),
        ],
      ],
    );

    final card = Stack(
      children: [
        SurfaceCard(
          padding: const EdgeInsets.all(AppSpacing.lg),
          color: claimed ? c.surface.withValues(alpha: 0.82) : null,
          border: status == MissionStatus.claimable
              ? Border.all(color: c.gold.withValues(alpha: 0.85), width: 1.5)
              : null,
          child: content,
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: ClipRRect(
              borderRadius: AppRadii.lgAll,
              child: ConfettiBurst(play: _confetti),
            ),
          ),
        ),
      ],
    );

    return Semantics(
      container: true,
      label: l10n.metaMissionSemantics(title, progressText, stateText),
      child: status == MissionStatus.claimable
          ? AnimatedBuilder(
              animation: _glow,
              builder: (context, child) => DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: AppRadii.lgAll,
                  boxShadow: [
                    BoxShadow(
                      color: c.gold.withValues(
                        alpha: 0.18 + 0.22 * _glow.value,
                      ),
                      blurRadius: 14 + 10 * _glow.value,
                      spreadRadius: 0.5,
                    ),
                  ],
                ),
                child: child,
              ),
              child: card,
            )
          : card,
    );
  }
}

class _GameIcon extends StatelessWidget {
  const _GameIcon({required this.game, required this.periodKey});

  final String game;
  final String periodKey;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final period = MissionPeriod.ofKey(periodKey);
    final (icon, color) = switch (game) {
      'ludo' => (Icons.grid_view_rounded, c.seats.red),
      'snakes_ladders' => (Icons.stairs_rounded, c.seats.green),
      _ =>
        period == MissionPeriod.weekly
            ? (Icons.emoji_events_rounded, c.gold)
            : (Icons.sports_esports_rounded, c.brand),
    };
    return ExcludeSemantics(
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.lerp(color, Colors.white, 0.18)!,
              Color.lerp(color, Colors.black, 0.12)!,
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.35),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Icon(icon, color: Colors.white, size: 24),
      ),
    );
  }
}

class _ProgressTrack extends StatelessWidget {
  const _ProgressTrack({required this.fraction, required this.complete});

  final double fraction;
  final bool complete;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ExcludeSemantics(
      child: Container(
        height: 10,
        decoration: BoxDecoration(
          color: c.surfaceSunken,
          borderRadius: AppRadii.pillAll,
          border: Border.all(color: c.outline.withValues(alpha: 0.5)),
        ),
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: fraction.clamp(0.0, 1.0)),
            duration: context.motion(AppDurations.slow),
            curve: AppCurves.standard,
            builder: (context, v, _) => FractionallySizedBox(
              widthFactor: v <= 0 ? 0 : v.clamp(0.06, 1.0),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: AppRadii.pillAll,
                  gradient: complete ? c.goldGradient : c.brandGradient,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ClaimedRow extends StatelessWidget {
  const _ClaimedRow({required this.collected});

  final bool collected;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = AppLocalizations.of(context);
    Widget row = Row(
      children: [
        Icon(Icons.check_circle_rounded, size: 20, color: c.success),
        const SizedBox(width: AppSpacing.xs + 2),
        Expanded(
          child: Text(
            collected ? l10n.metaCollected : l10n.metaStatusClaimed,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: context.textTheme.labelLarge?.copyWith(color: c.success),
          ),
        ),
      ],
    );
    if (collected && !context.reduceMotion) {
      row = row
          .animate()
          .fadeIn(duration: 220.ms)
          .scale(
            begin: const Offset(0.9, 0.9),
            curve: Curves.easeOutBack,
            duration: 360.ms,
          );
    }
    return Semantics(liveRegion: collected, child: row);
  }
}
