import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/protocol/protocol.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/time/server_clock.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../../progression/application/meta_support.dart';
import '../../../progression/presentation/widgets/meta_scaffold.dart';
import '../../application/reports_controller.dart';
import '../../domain/report_models.dart';
import '../report_text.dart';

/// Slivers of the Friends screen's "Reported" tab: today's allowance, then
/// my reports (newest first) with their moderation status.
List<Widget> reportedTabSlivers(BuildContext context, WidgetRef ref) {
  final l10n = AppLocalizations.of(context);
  final async = ref.watch(reportsProvider);
  switch (async) {
    case AsyncValue(:final value?):
      return [
        SliverPadding(
          padding: kMetaPagePadding.copyWith(bottom: AppSpacing.md),
          sliver: SliverToBoxAdapter(child: _AllowanceCard(limit: value.limit)),
        ),
        if (value.reports.isEmpty)
          MetaEmptySliver(
            title: l10n.socialNoReportsTitle,
            message: l10n.socialNoReportsMessage,
            illustration: const _FlagIllustration(),
          )
        else
          SliverPadding(
            padding: kMetaPagePadding,
            sliver: SliverList.separated(
              itemCount: value.reports.length,
              itemBuilder: (_, i) => ReportTile(
                key: ValueKey('report-${value.reports[i].id}'),
                report: value.reports[i],
              ),
              separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
            ),
          ),
      ];
    case AsyncError(:final error):
      return [
        MetaErrorSliver(
          message: metaErrorMessage(l10n, error),
          onRetry: () => ref.invalidate(reportsProvider),
        ),
      ];
    default:
      return const [MetaLoadingSliver()];
  }
}

/// "Reports left today: 1 of 2" (+ when reports come back at 0).
class _AllowanceCard extends ConsumerWidget {
  const _AllowanceCard({required this.limit});

  final ReportLimit limit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final l10n = AppLocalizations.of(context);
    final clock = ref.watch(serverClockProvider);
    final locale = Localizations.localeOf(context);
    final resetsAt = limit.resetsAt;
    final exhausted = limit.exhausted;
    return SurfaceCard(
      key: const ValueKey('reports-allowance'),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: (exhausted ? c.warning : c.brand).withValues(alpha: 0.14),
            ),
            child: Icon(
              Icons.flag_rounded,
              size: 22,
              color: exhausted ? c.warning : c.brand,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.socialReportsLeft(limit.remaining, limit.perDay),
                  style: context.textTheme.titleMedium,
                ),
                if (exhausted && resetsAt != null && resetsAt > 0) ...[
                  const SizedBox(height: 2),
                  Text(
                    l10n.socialReportsResetAt(
                      ReportText.resetTime(locale, clock, resetsAt),
                    ),
                    key: const ValueKey('reports-reset'),
                    style: context.textTheme.bodySmall?.copyWith(
                      color: c.warning,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 2),
                Text(
                  l10n.socialReportsInfo(limit.perDay),
                  style: context.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One report: who, why, when, and its status.
class ReportTile extends ConsumerWidget {
  const ReportTile({super.key, required this.report});

  final PlayerReport report;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final c = context.colors;
    final clock = ref.watch(serverClockProvider);
    final locale = Localizations.localeOf(context);
    final p = report.player;
    final reason = ReportText.reason(l10n, report.reason);
    final when = ReportText.relative(l10n, locale, clock, report.createdAt);
    final game = switch (report.game) {
      GameIds.snakesLadders => l10n.commonGameSnakesLadders,
      GameIds.ludo => l10n.commonGameLudo,
      _ => null,
    };
    final status = ReportText.status(l10n, report.status);
    final detail = [?game, when].join(' · ');
    return Semantics(
      container: true,
      label: [
        p.name,
        reason,
        detail,
        l10n.socialReportStatusA11y(status),
      ].join(', '),
      excludeSemantics: true,
      child: SurfaceCard(
        padding: const EdgeInsetsDirectional.fromSTEB(
          AppSpacing.md,
          AppSpacing.sm + 2,
          AppSpacing.md,
          AppSpacing.sm + 2,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                PlayerAvatar(avatarIndex: p.avatar, size: 44),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              p.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.textTheme.titleMedium,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xs + 2),
                          LevelBadge(level: p.level, size: 20),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(
                            Icons.flag_outlined,
                            size: 14,
                            color: c.textSecondary,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              reason,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: context.textTheme.bodySmall?.copyWith(
                                color: c.textPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ReportStatusChip(status: report.status),
                Text(
                  detail,
                  style: context.textTheme.labelSmall?.copyWith(
                    color: c.textSecondary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Status pill: icon + text + tint (never color alone).
class ReportStatusChip extends StatelessWidget {
  const ReportStatusChip({super.key, required this.status});

  final ReportStatus status;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = AppLocalizations.of(context);
    final (Color tint, IconData icon) = switch (status) {
      ReportStatus.submitted => (c.info, Icons.outbox_rounded),
      ReportStatus.reviewing => (c.warning, Icons.hourglass_top_rounded),
      ReportStatus.actionTaken => (c.success, Icons.gavel_rounded),
      ReportStatus.dismissed => (c.textMuted, Icons.do_not_disturb_on_rounded),
    };
    return Container(
      key: ValueKey('report-status-${status.name}'),
      padding: const EdgeInsetsDirectional.fromSTEB(8, 3, 10, 3),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: c.isDark ? 0.2 : 0.12),
        borderRadius: AppRadii.pillAll,
        border: Border.all(color: tint.withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: tint),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              ReportText.status(l10n, status),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.textTheme.labelSmall?.copyWith(
                color: c.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FlagIllustration extends StatelessWidget {
  const _FlagIllustration();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ExcludeSemantics(
      child: Container(
        width: 96,
        height: 96,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [c.brandSoft, c.brandSoft.withValues(alpha: 0)],
          ),
        ),
        child: Icon(Icons.verified_user_rounded, size: 48, color: c.brand),
      ),
    );
  }
}
