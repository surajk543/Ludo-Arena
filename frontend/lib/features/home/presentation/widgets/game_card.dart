import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/localization/number_format.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../application/play_options.dart';
import '../play_options_sheet.dart';
import 'mini_boards.dart';

/// Large premium card for one game with Play Online / Play with Friends /
/// Practice vs Bots.
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
    final accent = isLudo ? c.brand : c.seats.green;
    final narrow = MediaQuery.sizeOf(context).width < 360;

    return SurfaceCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      elevation: AppElevation.medium,
      gradient: LinearGradient(
        begin: AlignmentDirectional.topStart,
        end: AlignmentDirectional.bottomEnd,
        colors: [
          c.surfaceRaised,
          Color.lerp(c.surfaceRaised, accent, c.isDark ? 0.18 : 0.10)!,
        ],
      ),
      border: Border.all(color: accent.withValues(alpha: 0.25)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              isLudo
                  ? MiniLudoBoard(size: narrow ? 84 : 104)
                  : MiniSnakesBoard(size: narrow ? 84 : 104),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      gameName(l10n, game),
                      style: context.textTheme.headlineSmall,
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      isLudo ? l10n.homeLudoTagline : l10n.homeSnakesTagline,
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
            onPressed: () {
              PlayOptionsSheet.show(context, mode: PlayMode.online, game: game);
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: PremiumButton(
                  label: l10n.homePlayWithFriends,
                  icon: Icons.group_rounded,
                  variant: PremiumButtonVariant.secondary,
                  size: PremiumButtonSize.small,
                  onPressed: () {
                    PlayOptionsSheet.show(
                      context,
                      mode: PlayMode.friends,
                      game: game,
                    );
                  },
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: PremiumButton(
                  label: l10n.homePracticeVsBots,
                  icon: Icons.smart_toy_rounded,
                  variant: PremiumButtonVariant.secondary,
                  size: PremiumButtonSize.small,
                  onPressed: () {
                    PlayOptionsSheet.show(
                      context,
                      mode: PlayMode.practice,
                      game: game,
                    );
                  },
                ),
              ),
            ],
          ),
        ],
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
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: c.goldSoft,
        borderRadius: AppRadii.pillAll,
        border: Border.all(color: c.gold.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CoinIcon(size: 14),
          const SizedBox(width: AppSpacing.xs),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.textTheme.labelSmall?.copyWith(
                color: c.goldStrong,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
