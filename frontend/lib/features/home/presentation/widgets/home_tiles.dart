import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../application/play_options.dart';
import '../join_code_sheet.dart';
import '../play_options_sheet.dart';

/// Private Room (create a room for friends, game chosen in the sheet) and
/// Join with Code, side by side with equal heights.
class RoomActions extends StatelessWidget {
  const RoomActions({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.colors;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: LobbyTile(
              icon: Icons.meeting_room_rounded,
              color: c.accentSky,
              title: l10n.homePrivateRoom,
              subtitle: l10n.homePrivateRoomSubtitle,
              onTap: () =>
                  PlayOptionsSheet.show(context, mode: PlayMode.friends),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: LobbyTile(
              icon: Icons.vpn_key_rounded,
              color: c.accentAmber,
              title: l10n.homeJoinWithCode,
              subtitle: l10n.homeJoinWithCodeSubtitle,
              onTap: () => JoinCodeSheet.show(context),
            ),
          ),
        ],
      ),
    );
  }
}

/// Two-column grid (four columns on wide screens) of entry tiles with equal
/// heights per row. A short last row (an odd tile count on phones) is
/// stretched across the full width, so the grid never shows a hole.
class ExploreGrid extends StatelessWidget {
  const ExploreGrid({super.key, required this.tiles});

  final List<ExploreTileData> tiles;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 640 ? 4 : 2;
        const gap = AppSpacing.md;
        // Badge beside the text only while the text keeps ~80 dp.
        final scale = MediaQuery.textScalerOf(context).scale(1);
        final rows = <Widget>[];
        for (var i = 0; i < tiles.length; i += columns) {
          if (rows.isNotEmpty) rows.add(const SizedBox(height: gap));
          // A short last row shares the full width (no empty holes).
          final inRow = (tiles.length - i).clamp(1, columns);
          final tileWidth = (constraints.maxWidth - gap * (inRow - 1)) / inRow;
          final beside = tileWidth - 2 * AppSpacing.md >= 128 * scale;
          rows.add(
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var j = 0; j < inRow; j++) ...[
                    if (j > 0) const SizedBox(width: gap),
                    Expanded(
                      child: LobbyTile(
                        icon: tiles[i + j].icon,
                        color: tiles[i + j].color,
                        title: tiles[i + j].title,
                        subtitle: tiles[i + j].subtitle,
                        onTap: tiles[i + j].onTap,
                        badgeBeside: beside,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: rows,
        );
      },
    );
  }
}

class ExploreTileData {
  const ExploreTileData({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
}

/// Tappable card with a colored icon badge, a title and a short subtitle
/// (lobby room actions and More to Explore).
class LobbyTile extends StatelessWidget {
  const LobbyTile({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.badgeBeside = false,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  /// Badge beside the text (wide tiles) instead of above it. Decided by the
  /// parent: tiles sit in `IntrinsicHeight` rows, so they cannot measure
  /// themselves with a `LayoutBuilder`.
  final bool badgeBeside;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final badge = ExcludeSemantics(
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          borderRadius: AppRadii.mdAll,
          gradient: c.badgeGradient(color),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: c.isDark ? 0.30 : 0.28),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Icon(icon, color: c.onAccent(color), size: 24),
      ),
    );
    final texts = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: context.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          subtitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          // bodySmall uses textSecondary: ≥ 4.5:1 on cards in both modes.
          style: context.textTheme.bodySmall,
        ),
      ],
    );

    return Semantics(
      button: true,
      label: title,
      hint: subtitle,
      excludeSemantics: true,
      child: SurfaceCard(
        onTap: onTap,
        borderRadius: AppRadii.lgAll,
        elevation: c.isDark ? AppElevation.flat : AppElevation.low,
        border: Border.all(color: c.cardBorder),
        padding: const EdgeInsets.all(AppSpacing.md),
        child: badgeBeside
            ? Row(
                children: [
                  badge,
                  const SizedBox(width: AppSpacing.md),
                  Expanded(child: texts),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  badge,
                  const SizedBox(height: AppSpacing.sm),
                  texts,
                ],
              ),
      ),
    );
  }
}
