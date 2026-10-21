import 'package:flutter/material.dart';

import '../../../../core/audio_haptics/audio_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../domain/social_models.dart';

/// A player row: avatar (+ online dot for friends), name, level and title,
/// and trailing actions.
class FriendTile extends StatelessWidget {
  const FriendTile({
    super.key,
    required this.player,
    this.trailing,
    this.showOnline = false,
    this.subtitle,
    this.footer,
  });

  final Friend player;
  final Widget? trailing;

  /// Actions rendered under the row (keeps narrow screens readable).
  final Widget? footer;
  final bool showOnline;

  /// Replaces the title chip line (e.g. "Pending").
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = AppLocalizations.of(context);
    final status = showOnline
        ? (player.online ? l10n.metaOnline : l10n.metaOffline)
        : null;
    return Semantics(
      container: true,
      label: [
        player.name,
        l10n.commonLevel(player.level),
        ?status,
        ?subtitle,
      ].join(', '),
      child: SurfaceCard(
        padding: const EdgeInsetsDirectional.fromSTEB(
          AppSpacing.md,
          AppSpacing.sm + 2,
          AppSpacing.sm,
          AppSpacing.sm + 2,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                ExcludeSemantics(
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      PlayerAvatar(
                        avatarIndex: player.avatar,
                        picture: player.picture,
                        size: 48,
                      ),
                      if (showOnline)
                        PositionedDirectional(
                          end: 0,
                          bottom: 0,
                          child: Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: player.online ? c.success : c.textMuted,
                              border: Border.all(color: c.surface, width: 2.5),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: ExcludeSemantics(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                player.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: context.textTheme.titleMedium,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.xs + 2),
                            LevelBadge(level: player.level, size: 20),
                          ],
                        ),
                        const SizedBox(height: 3),
                        if (subtitle != null)
                          Text(
                            subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.textTheme.bodySmall,
                          )
                        else
                          Row(
                            children: [
                              Flexible(child: TitleChip(titleId: player.title)),
                              if (status != null) ...[
                                const SizedBox(width: AppSpacing.xs + 2),
                                Flexible(
                                  child: Text(
                                    status,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: context.textTheme.labelSmall
                                        ?.copyWith(
                                          color: player.online
                                              ? c.success
                                              : c.textMuted,
                                        ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: AppSpacing.xs),
                  trailing!,
                ],
              ],
            ),
            if (footer != null) ...[
              const SizedBox(height: AppSpacing.sm),
              footer!,
            ],
          ],
        ),
      ),
    );
  }
}

/// Compact pill button for list rows (≥ 40 dp tall).
class RowActionButton extends StatefulWidget {
  const RowActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.primary = true,
    this.icon,
  });

  final String label;
  final Future<void> Function()? onPressed;
  final bool primary;
  final IconData? icon;

  @override
  State<RowActionButton> createState() => _RowActionButtonState();
}

class _RowActionButtonState extends State<RowActionButton> {
  bool _busy = false;

  Future<void> _tap() async {
    final cb = widget.onPressed;
    if (cb == null || _busy) return;
    playUiSound(context, Sfx.uiTap);
    setState(() => _busy = true);
    try {
      await cb();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fg = widget.primary ? c.onBrand : c.textPrimary;
    final enabled = widget.onPressed != null && !_busy;
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 40, minWidth: 48),
        child: Material(
          color: widget.primary ? c.brand : c.surfaceSunken,
          borderRadius: AppRadii.pillAll,
          child: InkWell(
            borderRadius: AppRadii.pillAll,
            onTap: enabled ? _tap : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              child: _busy
                  ? SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(fg),
                      ),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.icon != null) ...[
                          Icon(widget.icon, size: 16, color: fg),
                          const SizedBox(width: 4),
                        ],
                        Text(
                          widget.label,
                          maxLines: 1,
                          style: context.textTheme.labelMedium?.copyWith(
                            color: fg,
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
