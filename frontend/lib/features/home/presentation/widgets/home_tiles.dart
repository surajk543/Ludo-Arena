import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../application/play_options.dart';
import '../join_code_sheet.dart';
import '../play_options_sheet.dart';

/// Quick Play (one tap into matchmaking with the remembered setup), Private
/// Room and Join with Code.
class QuickActions extends ConsumerWidget {
  const QuickActions({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final c = context.colors;
    final config = ref.watch(quickPlayProvider);
    final details = l10n.homeQuickPlayDetails(
      gameName(l10n, config.game),
      variantName(l10n, config.effectiveVariant),
      l10n.commonPlayerCount(config.capacity),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: true,
          label: '${l10n.homeQuickPlay}, $details',
          excludeSemantics: true,
          child: Material(
            color: Colors.transparent,
            child: Ink(
              decoration: BoxDecoration(
                gradient: c.brandGradient,
                borderRadius: AppRadii.lgAll,
                boxShadow: c.shadow(AppElevation.medium),
              ),
              child: InkWell(
                borderRadius: AppRadii.lgAll,
                onTap: () => context.push(config.routeFor(PlayMode.online)),
                child: Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(
                    AppSpacing.lg,
                    AppSpacing.lg,
                    AppSpacing.sm,
                    AppSpacing.lg,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: c.goldGradient,
                        ),
                        child: Icon(
                          Icons.bolt_rounded,
                          color: c.onGold,
                          size: 32,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.homeQuickPlay,
                              style: context.textTheme.titleLarge?.copyWith(
                                color: c.onBrand,
                              ),
                            ),
                            Text(
                              details,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: context.textTheme.bodySmall?.copyWith(
                                color: c.onBrand.withValues(alpha: 0.85),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: l10n.homeModeLabel,
                        icon: Icon(Icons.tune_rounded, color: c.onBrand),
                        onPressed: () => PlayOptionsSheet.show(
                          context,
                          mode: PlayMode.online,
                          quickPlay: true,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _ActionTile(
                icon: Icons.meeting_room_rounded,
                color: c.seats.blue,
                title: l10n.homePrivateRoom,
                subtitle: l10n.homePrivateRoomSubtitle,
                onTap: () =>
                    PlayOptionsSheet.show(context, mode: PlayMode.friends),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: _ActionTile(
                icon: Icons.vpn_key_rounded,
                color: c.seats.yellow,
                title: l10n.homeJoinWithCode,
                subtitle: l10n.homeJoinWithCodeSubtitle,
                onTap: () => JoinCodeSheet.show(context),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Entry tiles for Missions, Collection Room, Friends and Events.
class ExploreGrid extends StatelessWidget {
  const ExploreGrid({super.key, required this.tiles});

  final List<ExploreTileData> tiles;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 640 ? 4 : 2;
        final gap = AppSpacing.md;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final t in tiles)
              SizedBox(
                width: width,
                child: _ActionTile(
                  icon: t.icon,
                  color: t.color,
                  title: t.title,
                  subtitle: t.subtitle,
                  onTap: t.onTap,
                ),
              ),
          ],
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

class _ActionTile extends StatelessWidget {
  const _ActionTile({
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

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: title,
      hint: subtitle,
      excludeSemantics: true,
      child: SurfaceCard(
        onTap: onTap,
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                borderRadius: AppRadii.smAll,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color.lerp(color, Colors.white, 0.25)!, color],
                ),
              ),
              child: Icon(
                icon,
                color: color.computeLuminance() > 0.5
                    ? const Color(0xFF2A1F00)
                    : Colors.white,
                size: 22,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: context.textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: context.textTheme.bodySmall?.copyWith(color: c.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}
