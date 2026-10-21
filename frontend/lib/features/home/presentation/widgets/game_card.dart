import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/localization/number_format.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../application/play_options.dart';
import '../play_options_sheet.dart';
import 'mini_boards.dart';

/// One reusable card per game (Home lobby and the Games tab): board
/// thumbnail, name, tagline and live entry fee, then Play Online (public
/// matchmaking options), Play with Friends (private room for this game) and
/// Practice vs Bots. Every action opens the existing options sheet first;
/// nothing is charged until the server starts a match.
class GameCard extends ConsumerWidget {
  const GameCard({super.key, required this.game});

  /// `ludo` | `snakes_ladders`.
  final String game;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context);
    final c = context.colors;
    final isLudo = game == GameId.ludo;
    final fee = ref.watch(entryFeeProvider(game));
    // Ludo keeps the royal violet; Snakes & Ladders gets a subtle mint.
    final accent = isLudo ? c.brand : c.accentMint;

    // Block body on purpose: PremiumButton shows a spinner while a returned
    // Future runs, and the sheet's Future only completes when it closes.
    void open(PlayMode mode) {
      PlayOptionsSheet.show(context, mode: mode, game: game);
    }

    final friends = PremiumButton(
      label: l10n.homePlayWithFriends,
      icon: Icons.group_rounded,
      variant: PremiumButtonVariant.secondary,
      size: PremiumButtonSize.small,
      onPressed: () => open(PlayMode.friends),
    );
    final practice = PremiumButton(
      label: l10n.homePracticeVsBots,
      icon: Icons.smart_toy_rounded,
      variant: PremiumButtonVariant.secondary,
      size: PremiumButtonSize.small,
      onPressed: () => open(PlayMode.practice),
    );

    return SurfaceCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      borderRadius: AppRadii.xlAll,
      elevation: c.isDark ? AppElevation.flat : AppElevation.low,
      gradient: LinearGradient(
        begin: AlignmentDirectional.topStart,
        end: AlignmentDirectional.bottomEnd,
        colors: [
          c.surface,
          Color.lerp(c.surface, accent, c.isDark ? 0.10 : 0.05)!,
        ],
      ),
      border: Border.all(
        color: Color.lerp(c.cardBorder, accent, c.isDark ? 0.12 : 0.18)!,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final scale = MediaQuery.textScalerOf(context).scale(1);
          final thumb = (width * 0.34).clamp(80.0, 124.0);
          // Two secondary buttons side by side while each keeps ~150 dp.
          final pairRow = (width - AppSpacing.sm) / 2 >= 136 * scale;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  // Boards are drawn left-to-right in every locale.
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: isLudo
                        ? MiniLudoBoard(size: thumb)
                        : MiniSnakesBoard(size: thumb),
                  ),
                  const SizedBox(width: AppSpacing.lg),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Semantics(
                          header: true,
                          child: Text(
                            gameName(l10n, game),
                            style: context.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          isLudo
                              ? l10n.homeLudoTagline
                              : l10n.homeSnakesTagline,
                          style: context.textTheme.bodyMedium,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        _FeePill(
                          label: l10n.commonEntryFee(formatCoins(fee, locale)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              PremiumButton(
                label: l10n.homePlayOnline,
                icon: Icons.public_rounded,
                variant: PremiumButtonVariant.gold,
                size: PremiumButtonSize.medium,
                onPressed: () => open(PlayMode.online),
              ),
              const SizedBox(height: AppSpacing.sm),
              if (pairRow)
                Row(
                  children: [
                    Expanded(child: friends),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(child: practice),
                  ],
                )
              else ...[
                friends,
                const SizedBox(height: AppSpacing.xs),
                practice,
              ],
            ],
          );
        },
      ),
    );
  }
}

class _FeePill extends StatelessWidget {
  const _FeePill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(
        AppSpacing.xs,
        AppSpacing.xs,
        AppSpacing.md,
        AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: c.goldSoft,
        borderRadius: AppRadii.pillAll,
        border: Border.all(color: c.gold.withValues(alpha: 0.55)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CoinIcon(size: 18),
          const SizedBox(width: AppSpacing.xs),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.textTheme.labelMedium?.copyWith(
                color: c.onGoldSoft,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
