import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../app/shell/tab_nav.dart';
import '../../../core/analytics/analytics_providers.dart';
import '../../../core/audio_haptics/audio_service.dart';
import '../../../core/audio_haptics/haptics_service.dart';
import '../../../core/audio_haptics/reduced_motion.dart';
import '../../../core/localization/number_format.dart';
import '../../../core/state/in_match_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../missions/presentation/missions_screen.dart';
import '../../progression/application/level_up_controller.dart';
import '../../progression/presentation/widgets/reward_widgets.dart';
import '../application/playtime_toast_controller.dart';

/// Shows queued playtime milestone toasts ([playtimeToastControllerProvider])
/// one at a time: never during a match (deferred until the match screen
/// closes) and never next to a level-up celebration (shown after it). The
/// toast is non-blocking, closes itself after [visibleFor] and has a close
/// button and a "View progress" action (→ Missions tab).
///
/// Mounted once above the router by `MetaShellHost`.
class PlaytimeToastHost extends ConsumerStatefulWidget {
  const PlaytimeToastHost({
    super.key,
    required this.child,
    this.navigatorKey,
    this.visibleFor = const Duration(seconds: 8),
    this.afterMatchDelay = const Duration(milliseconds: 900),
  });

  final Widget child;

  /// Navigator whose overlay shows the toast; null = the nearest one.
  final GlobalKey<NavigatorState>? navigatorKey;

  /// Auto-dismiss delay.
  final Duration visibleFor;

  /// Pause after the match screen closes (after the level-up host's).
  final Duration afterMatchDelay;

  @override
  ConsumerState<PlaytimeToastHost> createState() => _PlaytimeToastHostState();
}

class _PlaytimeToastHostState extends ConsumerState<PlaytimeToastHost> {
  OverlayEntry? _entry;
  PlaytimeToast? _current;
  Timer? _hide;
  Timer? _delay;

  NavigatorState? get _navigator =>
      widget.navigatorKey?.currentState ?? Navigator.maybeOf(context);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShow());
  }

  bool get _blocked {
    if (ref.read(inMatchProvider)) return true;
    final lv = ref.read(levelUpControllerProvider);
    return lv.showing || lv.hasPending;
  }

  void _maybeShow() {
    if (!mounted || _entry != null || _blocked) return;
    final overlay = _navigator?.overlay;
    if (overlay == null) return;
    final toast = ref.read(playtimeToastControllerProvider.notifier).takeNext();
    if (toast == null) return;
    _current = toast;
    ref.read(hapticsServiceProvider).success();
    ref.read(audioServiceProvider).play(Sfx.rewardClaim);
    _entry = OverlayEntry(
      builder: (_) => PlaytimeMilestoneToast(
        toast: toast,
        onView: () => _close('action', open: true),
        onClose: () => _close('close'),
      ),
    );
    overlay.insert(_entry!);
    _hide = Timer(widget.visibleFor, () => _close('auto'));
  }

  void _close(String method, {bool open = false}) {
    if (_entry == null) return;
    _remove();
    ref.read(analyticsServiceProvider).playtimeToastDismissed(method);
    ref.read(playtimeToastControllerProvider.notifier).markShown();
    if (open) _openProgress();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShow());
  }

  void _remove() {
    _hide?.cancel();
    _hide = null;
    _entry?.remove();
    _entry = null;
    _current = null;
  }

  /// Opens the Missions tab (where today's playtime is listed), keeping a
  /// play-flow page underneath when one is open (see tab_nav.dart).
  void _openProgress() {
    final navigator = _navigator;
    final router = navigator == null
        ? null
        : GoRouter.maybeOf(navigator.context);
    if (navigator == null || router == null) return;
    switch (tabOpenModeFor(router.routerDelegate.currentConfiguration)) {
      case TabOpenMode.push:
        router.push(AppRoutes.missions);
      case TabOpenMode.go:
        router.go(AppRoutes.missions);
      case TabOpenMode.overlay:
        navigator.push(
          MaterialPageRoute<void>(builder: (_) => const MissionsScreen()),
        );
    }
  }

  void _scheduleAfterMatch() {
    _delay?.cancel();
    _delay = Timer(widget.afterMatchDelay, _maybeShow);
  }

  @override
  void dispose() {
    _delay?.cancel();
    _remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<PlaytimeToastState>(playtimeToastControllerProvider, (
      prev,
      next,
    ) {
      if (next.hasPending && !next.showing) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShow());
      }
    });
    ref.listen<LevelUpState>(levelUpControllerProvider, (prev, next) {
      // After a level-up celebration closes, the toast follows it.
      if (!next.showing && !next.hasPending) _scheduleAfterMatch();
    });
    ref.listen<bool>(inMatchProvider, (prev, inMatch) {
      if (inMatch) {
        _delay?.cancel();
        // A match started under the toast: put it back for later.
        final current = _current;
        if (current != null) {
          _remove();
          final ctl = ref.read(playtimeToastControllerProvider.notifier)
            ..markShown();
          ctl.requeue(current);
        }
        return;
      }
      _scheduleAfterMatch();
    });
    return widget.child;
  }
}

/// The milestone toast: gold check, "Daily milestone completed!", the
/// minutes played, the server-confirmed rewards, View progress and close.
class PlaytimeMilestoneToast extends StatelessWidget {
  const PlaytimeMilestoneToast({
    super.key,
    required this.toast,
    required this.onView,
    required this.onClose,
  });

  final PlaytimeToast toast;
  final VoidCallback onView;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context);
    final count = toast.milestones.length;
    final title = l10n.journeyToastTitle(count);
    final body = l10n.journeyToastBody(
      toast.minutes,
      formatNumberFull(toast.minutes, locale),
    );
    final reward = toast.reward;
    final reduce = context.reduceMotion;

    Widget badge = Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: c.goldGradient,
        boxShadow: [
          BoxShadow(color: c.gold.withValues(alpha: 0.55), blurRadius: 12),
        ],
      ),
      child: Icon(Icons.timer_rounded, color: c.onGold, size: 24),
    );
    if (!reduce) {
      badge = badge
          .animate(delay: 180.ms)
          .scale(
            begin: const Offset(0.6, 0.6),
            curve: Curves.easeOutBack,
            duration: 420.ms,
          )
          .then()
          .shimmer(duration: 900.ms, color: Colors.white54);
    }

    Widget card = Material(
      color: Colors.transparent,
      child: Container(
        key: const ValueKey('playtime-toast'),
        decoration: BoxDecoration(
          color: c.isDark ? BrandPalette.royal700 : BrandPalette.royal850,
          borderRadius: AppRadii.lgAll,
          border: Border.all(color: c.gold.withValues(alpha: 0.6)),
          boxShadow: c.shadow(AppElevation.high),
        ),
        padding: const EdgeInsetsDirectional.fromSTEB(
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.xs,
          AppSpacing.sm,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            badge,
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: context.textTheme.titleSmall?.copyWith(
                      color: BrandPalette.gold300,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    body,
                    style: context.textTheme.bodyMedium?.copyWith(
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.xs + 2,
                    runSpacing: AppSpacing.xs,
                    children: [
                      if (reward.xp > 0)
                        _OnDark(
                          child: RewardChip(
                            kind: RewardKind.xp,
                            amount: reward.xp,
                          ),
                        ),
                      if (reward.coins > 0)
                        _OnDark(
                          child: RewardChip(
                            kind: RewardKind.coins,
                            amount: reward.coins,
                          ),
                        ),
                      if (reward.diamonds > 0)
                        _OnDark(
                          child: RewardChip(
                            kind: RewardKind.diamonds,
                            amount: reward.diamonds,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton(
                      key: const ValueKey('playtime-toast-view'),
                      onPressed: onView,
                      style: TextButton.styleFrom(
                        foregroundColor: BrandPalette.gold300,
                        minimumSize: const Size(48, 40),
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm,
                        ),
                      ),
                      child: Text(l10n.journeyToastView),
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              key: const ValueKey('playtime-toast-close'),
              tooltip: l10n.commonClose,
              onPressed: onClose,
              icon: const Icon(
                Icons.close_rounded,
                color: Colors.white70,
                size: 20,
              ),
            ),
          ],
        ),
      ),
    );
    if (!reduce) {
      card = card
          .animate()
          .fadeIn(duration: 220.ms)
          .slideY(begin: -0.35, curve: Curves.easeOutCubic, duration: 360.ms);
    }
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.md,
            0,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Semantics(
                liveRegion: true,
                container: true,
                label:
                    '$title $body '
                    '${_rewardLabel(l10n, locale, reward.xp, reward.coins)}',
                child: Dismissible(
                  key: const ValueKey('playtime-toast-dismissible'),
                  direction: DismissDirection.up,
                  onDismissed: (_) => onClose(),
                  child: card,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _rewardLabel(
    AppLocalizations l10n,
    Locale locale,
    int xp,
    int coins,
  ) => [
    if (xp > 0) l10n.metaRewardXpLabel(formatNumberFull(xp, locale)),
    if (coins > 0) l10n.metaRewardCoinsLabel(formatCoins(coins, locale)),
  ].join(', ');
}

/// Reward chips are themed for light surfaces: give them a soft light plate
/// on the dark toast so text and glyphs keep their contrast.
class _OnDark extends StatelessWidget {
  const _OnDark({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.92),
      borderRadius: AppRadii.pillAll,
    ),
    child: Theme(data: AppTheme.light(), child: child),
  );
}
