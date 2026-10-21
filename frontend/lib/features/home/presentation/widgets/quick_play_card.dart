import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/localization/number_format.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../../wallet/wallet_controller.dart';
import '../../application/play_options.dart';

/// The game choices Quick Play offers: every game / rules variant the
/// backend matches publicly.
enum QuickPlayGame {
  ludo(GameId.ludo, 'classic', Icons.grid_view_rounded),
  quickLudo(GameId.ludo, 'quick', Icons.bolt_rounded),
  snakesLadders(GameId.snakesLadders, 'classic', Icons.stairs_rounded);

  const QuickPlayGame(this.game, this.variant, this.icon);

  final String game;
  final String variant;
  final IconData icon;

  static QuickPlayGame of(PlayConfig config) => switch (config.game) {
    GameId.snakesLadders => snakesLadders,
    _ => config.effectiveVariant == 'quick' ? quickLudo : ludo,
  };

  String label(AppLocalizations l10n) => switch (this) {
    ludo => l10n.commonGameLudo,
    quickLudo => l10n.homeQuickLudo,
    snakesLadders => l10n.commonGameSnakesLadders,
  };
}

/// Seat counts public matchmaking supports.
const List<int> kQuickPlayCapacities = [2, 3, 4];

/// Hero card: pick a game and a player count, then Play Now goes straight
/// into public matchmaking (`/matchmaking?…`). The selection is remembered
/// through [quickPlayProvider]. Play Now is disabled (with a note) when the
/// server-confirmed balance cannot cover the live entry fee; the server still
/// re-checks when the match starts.
class QuickPlayCard extends ConsumerStatefulWidget {
  const QuickPlayCard({super.key});

  @override
  ConsumerState<QuickPlayCard> createState() => _QuickPlayCardState();
}

class _QuickPlayCardState extends ConsumerState<QuickPlayCard> {
  /// True from the tap until the matchmaking route closes or this card is
  /// on screen again: guards double taps while the route opens.
  bool _launching = false;

  /// The card was covered (tickers off) since the last launch.
  bool _coveredSinceLaunch = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = TickerMode.valuesOf(context).enabled;
    if (!_launching) return;
    if (!visible) {
      _coveredSinceLaunch = true;
    } else if (_coveredSinceLaunch) {
      // Back on screen (e.g. the stack was replaced without a pop).
      _launching = false;
      _coveredSinceLaunch = false;
    }
  }

  void _play() {
    if (_launching) return;
    final config = ref.read(quickPlayProvider);
    setState(() {
      _launching = true;
      _coveredSinceLaunch = false;
    });
    GoRouter.of(context).push(config.routeFor(PlayMode.online)).whenComplete(
      () {
        if (mounted) setState(() => _launching = false);
      },
    );
  }

  Future<void> _remember(PlayConfig next) =>
      ref.read(quickPlayProvider.notifier).remember(next);

  Future<void> _pickGame(PlayConfig config) {
    final l10n = AppLocalizations.of(context);
    final current = QuickPlayGame.of(config);
    return AppBottomSheet.show<void>(
      context,
      title: l10n.homeGameLabel,
      builder: (sheet) => ChoiceChips<QuickPlayGame>(
        value: current,
        options: [
          for (final g in QuickPlayGame.values)
            ChoiceOption(
              value: g,
              label: g.label(l10n),
              icon: g.icon,
              caption: switch (g) {
                QuickPlayGame.ludo => l10n.homeModeClassicCaption,
                QuickPlayGame.quickLudo => l10n.homeModeQuickCaption,
                QuickPlayGame.snakesLadders => null,
              },
            ),
        ],
        onChanged: (g) {
          Navigator.of(sheet).pop();
          _remember(config.copyWith(game: g.game, variant: g.variant));
        },
      ),
    );
  }

  Future<void> _pickPlayers(PlayConfig config) {
    final l10n = AppLocalizations.of(context);
    return AppBottomSheet.show<void>(
      context,
      title: l10n.homePlayersLabel,
      builder: (sheet) => ChoiceChips<int>(
        value: config.capacity,
        options: [
          for (final n in kQuickPlayCapacities)
            ChoiceOption(value: n, label: l10n.commonPlayerCount(n)),
        ],
        onChanged: (n) {
          Navigator.of(sheet).pop();
          _remember(config.copyWith(capacity: n));
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context);
    final c = context.colors;
    final config = ref.watch(quickPlayProvider);
    final game = QuickPlayGame.of(config);
    final fee = ref.watch(entryFeeProvider(config.game));
    // Rebuilds only when affordability flips, not on every wallet tick.
    final short = ref.watch(
      walletControllerProvider.select((w) => w.isLoaded && w.coins < fee),
    );
    final onHero = c.onBrand;

    final gameSelector = _HeroSelector(
      icon: game.icon,
      label: game.label(l10n),
      hint: l10n.homeChangeGameHint,
      onTap: () => _pickGame(config),
    );
    final playersSelector = _HeroSelector(
      icon: Icons.group_rounded,
      label: l10n.commonPlayerCount(config.capacity),
      hint: l10n.homeChangePlayersHint,
      onTap: () => _pickPlayers(config),
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: AppRadii.xlAll,
        boxShadow: [
          BoxShadow(
            color: c.brand.withValues(alpha: c.isDark ? 0.45 : 0.35),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: AppRadii.xlAll,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: c.heroGradient,
            border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
            borderRadius: AppRadii.xlAll,
          ),
          child: CustomPaint(
            painter: _HeroGlowPainter(
              rtl: Directionality.of(context) == TextDirection.rtl,
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const _BoltBadge(),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Semantics(
                              header: true,
                              child: Text(
                                l10n.homeQuickPlay,
                                style: context.textTheme.headlineSmall
                                    ?.copyWith(
                                      color: onHero,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.xxs),
                            Text(
                              l10n.homeQuickPlaySubtitle,
                              style: context.textTheme.bodyMedium?.copyWith(
                                color: onHero.withValues(alpha: 0.88),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final scale = MediaQuery.textScalerOf(context).scale(1);
                      if (constraints.maxWidth < 270 * scale) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            gameSelector,
                            const SizedBox(height: AppSpacing.sm),
                            playersSelector,
                          ],
                        );
                      }
                      return Row(
                        children: [
                          Expanded(flex: 11, child: gameSelector),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(flex: 9, child: playersSelector),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: AppSpacing.md),
                  PremiumButton(
                    label: l10n.homePlayNow,
                    icon: Icons.play_arrow_rounded,
                    variant: PremiumButtonVariant.gold,
                    loading: _launching,
                    onPressed: short ? null : _play,
                  ),
                  if (short) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      children: [
                        Icon(
                          Icons.info_rounded,
                          size: 18,
                          color: onHero.withValues(alpha: 0.9),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Expanded(
                          child: Text(
                            l10n.homeNotEnoughCoins(formatCoins(fee, locale)),
                            style: context.textTheme.bodySmall?.copyWith(
                              color: onHero,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Large gold disc with a lightning bolt.
class _BoltBadge extends StatelessWidget {
  const _BoltBadge();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ExcludeSemantics(
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: c.goldGradient,
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.55),
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: c.goldStrong.withValues(alpha: 0.45),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Icon(Icons.bolt_rounded, color: c.onGold, size: 34),
      ),
    );
  }
}

/// White pill selector on the hero card (icon, value, chevron).
class _HeroSelector extends StatelessWidget {
  const _HeroSelector({
    required this.icon,
    required this.label,
    required this.hint,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String hint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fg = c.onHeroControlText;
    return Semantics(
      button: true,
      label: label,
      hint: hint,
      excludeSemantics: true,
      child: Material(
        color: c.onHeroControl,
        borderRadius: AppRadii.mdAll,
        child: InkWell(
          borderRadius: AppRadii.mdAll,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(
                AppSpacing.md,
                AppSpacing.xs,
                AppSpacing.sm,
                AppSpacing.xs,
              ),
              child: Row(
                children: [
                  Icon(icon, size: 20, color: fg),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        label,
                        maxLines: 1,
                        style: context.textTheme.titleSmall?.copyWith(
                          color: fg,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xxs),
                  Icon(Icons.expand_more_rounded, size: 22, color: fg),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Soft highlight blobs and a faint diamond on the hero card. Static; paints
/// once.
class _HeroGlowPainter extends CustomPainter {
  const _HeroGlowPainter({required this.rtl});

  final bool rtl;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final w = size.width;
    double x(double fx) => rtl ? w * (1 - fx) : w * fx;
    void glow(Offset center, double radius, double alpha) {
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [
              Colors.white.withValues(alpha: alpha),
              Colors.white.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromCircle(center: center, radius: radius)),
      );
    }

    glow(Offset(x(0.08), 0), w * 0.55, 0.16);
    glow(Offset(x(0.98), size.height * 0.95), w * 0.45, 0.08);

    // Two outlined diamonds in the top-end corner.
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = Colors.white.withValues(alpha: 0.10);
    for (final (cx, cy, r) in [(0.9, 0.12, 34.0), (0.78, 0.04, 16.0)]) {
      final c = Offset(x(cx), size.height * cy);
      canvas.drawPath(
        Path()
          ..moveTo(c.dx, c.dy - r)
          ..lineTo(c.dx + r, c.dy)
          ..lineTo(c.dx, c.dy + r)
          ..lineTo(c.dx - r, c.dy)
          ..close(),
        stroke,
      );
    }
  }

  @override
  bool shouldRepaint(_HeroGlowPainter old) => old.rtl != rtl;
}
