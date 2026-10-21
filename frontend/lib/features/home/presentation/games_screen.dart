import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/widgets/widgets.dart';
import '../application/play_options.dart';
import 'widgets/game_card.dart';
import 'widgets/home_tiles.dart';

/// Games tab: every game as the shared [GameCard] (Play Online / Play with
/// Friends / Practice vs Bots) plus the private-room entry points.
class GamesScreen extends StatelessWidget {
  const GamesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 720;
    const ludo = GameCard(game: GameId.ludo);
    const snakes = GameCard(game: GameId.snakesLadders);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: LayeredBackground(
        child: SafeArea(
          bottom: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1040),
              child: CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      AppSpacing.lg,
                      AppSpacing.lg,
                      AppSpacing.xxl + MediaQuery.paddingOf(context).bottom,
                    ),
                    sliver: SliverList.list(
                      children: [
                        Semantics(
                          header: true,
                          child: Text(
                            l10n.homeNavGames,
                            style: context.textTheme.headlineLarge,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          l10n.homeGamesSubtitle,
                          style: context.textTheme.bodyMedium,
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        if (wide)
                          const Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: ludo),
                              SizedBox(width: AppSpacing.lg),
                              Expanded(child: snakes),
                            ],
                          )
                        else ...const [
                          ludo,
                          SizedBox(height: AppSpacing.lg),
                          snakes,
                        ],
                        const SizedBox(height: AppSpacing.lg),
                        SectionHeader(title: l10n.homePlayWithFriends),
                        const SizedBox(height: AppSpacing.xs),
                        const RoomActions(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
