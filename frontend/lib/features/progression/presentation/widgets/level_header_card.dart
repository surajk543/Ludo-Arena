import 'package:flutter/material.dart';

import '../../../../core/localization/number_format.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../shared/widgets/widgets.dart';

/// Level badge + XP bar (shared `LevelBadge` / `XpProgressBar`). Progress =
/// (xp − levelXp) / nextLevelXp; "MAX" at the level cap.
class LevelHeaderCard extends StatelessWidget {
  const LevelHeaderCard({
    super.key,
    required this.level,
    required this.xp,
    required this.levelXp,
    required this.nextLevelXp,
    this.maxLevel = 50,
    this.large = false,
    this.onTap,
    this.trailing,
  });

  final int level;
  final int xp;
  final int levelXp;
  final int nextLevelXp;
  final int maxLevel;
  final bool large;
  final VoidCallback? onTap;
  final Widget? trailing;

  bool get _isMax => level >= maxLevel;

  int get _into {
    final v = xp - levelXp;
    if (v < 0) return 0;
    return v > nextLevelXp ? nextLevelXp : v;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context);
    final c = context.colors;
    final remaining = _isMax ? 0 : nextLevelXp - _into;
    final caption = _isMax
        ? l10n.metaMaxLevelReached
        : l10n.metaXpToNextLevel(
            formatNumberFull(remaining, locale),
            level + 1,
          );

    return SurfaceCard(
      onTap: onTap,
      elevation: large ? AppElevation.medium : AppElevation.low,
      padding: EdgeInsets.all(large ? AppSpacing.xl : AppSpacing.lg),
      gradient: LinearGradient(
        begin: AlignmentDirectional.topStart,
        end: AlignmentDirectional.bottomEnd,
        colors: [c.surfaceRaised, Color.lerp(c.surface, c.brandSoft, 0.6)!],
      ),
      child: Row(
        children: [
          LevelBadge(level: level, size: large ? 58 : 42),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        l10n.commonLevel(level),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: large
                            ? context.textTheme.headlineSmall
                            : context.textTheme.titleMedium,
                      ),
                    ),
                    if (_isMax) ...[
                      const SizedBox(width: AppSpacing.sm),
                      _MaxPill(label: l10n.metaMaxBadge),
                    ],
                  ],
                ),
                const SizedBox(height: AppSpacing.xs + 2),
                XpProgressBar(
                  current: _isMax ? 1 : _into,
                  total: _isMax ? 1 : (nextLevelXp <= 0 ? 1 : nextLevelXp),
                  showLabel: large && !_isMax,
                  height: large ? 12 : 10,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  caption,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: AppSpacing.sm),
            trailing!,
          ],
        ],
      ),
    );
  }
}

class _MaxPill extends StatelessWidget {
  const _MaxPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        gradient: c.goldGradient,
        borderRadius: AppRadii.pillAll,
      ),
      child: Text(
        label,
        style: context.textTheme.labelSmall?.copyWith(color: c.onGold),
      ),
    );
  }
}
