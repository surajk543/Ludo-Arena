import 'package:flutter/material.dart';

import '../../../../core/localization/number_format.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../domain/leaderboard_models.dart';

/// One ranked player. Top three get soft medal tints; "me" is highlighted.
class LeaderboardRow extends StatelessWidget {
  const LeaderboardRow({super.key, required this.entry});

  final LeaderboardEntry entry;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context);
    final xp = l10n.metaWeeklyXp(formatNumberFull(entry.weeklyXp, locale));
    final name = entry.isMe ? l10n.metaYouName(entry.name) : entry.name;
    final medal = switch (entry.rank) {
      1 => const Color(0xFFE9B949),
      2 => const Color(0xFFB8C1CC),
      3 => const Color(0xFFCD8B5A),
      _ => null,
    };

    return Semantics(
      container: true,
      selected: entry.isMe,
      label: l10n.metaLeaderboardRowSemantics(entry.rank, name, xp),
      excludeSemantics: true,
      child: Container(
        key: entry.isMe ? const ValueKey('lb-me') : null,
        padding: const EdgeInsetsDirectional.fromSTEB(
          AppSpacing.sm,
          AppSpacing.sm,
          AppSpacing.md,
          AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: entry.isMe
              ? Color.lerp(c.surface, c.brandSoft, c.isDark ? 0.25 : 0.85)
              : c.surface,
          borderRadius: AppRadii.lgAll,
          border: Border.all(
            color: entry.isMe
                ? c.brand
                : c.outline.withValues(alpha: c.isDark ? 0.3 : 0.8),
            width: entry.isMe ? 1.5 : 1,
          ),
          boxShadow: c.shadow(AppElevation.low),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 40,
              child: Center(
                child: Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: medal?.withValues(alpha: 0.22) ?? c.surfaceSunken,
                    border: medal == null ? null : Border.all(color: medal),
                  ),
                  child: Text(
                    formatNumberFull(entry.rank, locale),
                    textDirection: TextDirection.ltr,
                    style: context.textTheme.titleSmall?.copyWith(
                      color: medal == null ? c.textSecondary : c.textPrimary,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            PlayerAvatar(avatarIndex: entry.avatar, size: 42),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.textTheme.titleMedium?.copyWith(
                      color: entry.isMe ? c.brand : null,
                    ),
                  ),
                  Text(
                    l10n.commonLevel(entry.level),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              xp,
              style: context.textTheme.titleSmall?.copyWith(
                color: c.textPrimary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
