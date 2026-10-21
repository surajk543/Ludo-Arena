import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/audio_haptics/reduced_motion.dart';
import '../../../../core/realtime/realtime_providers.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../shared/widgets/widgets.dart';

/// Non-blocking connection banner shown over the top of the match while the
/// socket reconnects or a resync is in flight. The board stays visible and
/// the server keeps the match running (it plays timed-out turns).
class ReconnectBanner extends ConsumerWidget {
  const ReconnectBanner({super.key, required this.syncing});

  final bool syncing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(realtimeStatusProvider);
    final l10n = AppLocalizations.of(context);
    final c = context.colors;
    final reduce = ReducedMotion.of(context);
    final offline = status != RealtimeStatus.connected;
    final visible = offline || syncing;
    final text = offline
        ? (status == RealtimeStatus.replaced
              ? ConnectionIndicator.label(l10n, status)
              : l10n.playReconnecting)
        : l10n.playSyncing;

    return IgnorePointer(
      ignoring: !visible || status != RealtimeStatus.replaced,
      child: AnimatedSlide(
        duration: reduce ? Duration.zero : AppDurations.medium,
        curve: AppCurves.standard,
        offset: visible ? Offset.zero : const Offset(0, -1.4),
        child: AnimatedOpacity(
          duration: reduce ? Duration.zero : AppDurations.fast,
          opacity: visible ? 1 : 0,
          child: Center(
            child: Semantics(
              liveRegion: true,
              child: Container(
                margin: const EdgeInsets.only(top: AppSpacing.xs),
                padding: const EdgeInsetsDirectional.fromSTEB(10, 6, 14, 6),
                decoration: BoxDecoration(
                  color: c.surfaceRaised,
                  borderRadius: AppRadii.pillAll,
                  border: Border.all(
                    color: (offline ? c.warning : c.info).withValues(
                      alpha: 0.6,
                    ),
                  ),
                  boxShadow: c.shadow(AppElevation.medium),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox.square(
                      dimension: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(
                          offline ? c.warning : c.info,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Flexible(
                      child: Text(
                        text,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: context.textTheme.labelMedium,
                      ),
                    ),
                    if (status == RealtimeStatus.replaced) ...[
                      const SizedBox(width: AppSpacing.xs),
                      TextButton(
                        onPressed: () =>
                            ref.read(realtimeConnectionProvider).reconnectNow(),
                        child: Text(l10n.commonReconnect),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Leave / forfeit confirmation. Resolves true when the user confirms.
Future<bool> confirmLeaveMatch(
  BuildContext context, {
  required bool practice,
}) async {
  final l10n = AppLocalizations.of(context);
  final result = await AppDialog.show<bool>(
    context,
    title: l10n.playLeaveMatchTitle,
    message: practice
        ? l10n.playLeavePracticeMessage
        : l10n.playLeaveMatchMessage,
    illustration: Icon(
      Icons.flag_rounded,
      size: 44,
      color: context.colors.danger,
    ),
    actions: [
      AppDialogAction(
        label: l10n.playKeepPlaying,
        variant: PremiumButtonVariant.secondary,
        value: false,
      ),
      AppDialogAction(
        label: l10n.playLeaveMatchConfirm,
        variant: PremiumButtonVariant.danger,
        value: true,
      ),
    ],
  );
  return result ?? false;
}
