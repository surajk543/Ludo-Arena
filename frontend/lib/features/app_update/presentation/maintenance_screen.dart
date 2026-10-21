import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/gate/app_gate_controller.dart';
import '../../../core/localization/number_format.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/widgets/widgets.dart';
import 'gate_illustrations.dart';
import 'gate_layout.dart';

/// Maintenance screen. The gate re-checks automatically every 30 s while
/// this is shown, on resume, and on Retry. Matches are paused server-side.
class MaintenanceScreen extends ConsumerWidget {
  const MaintenanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context);
    final gate = ref.watch(appGateControllerProvider);
    final policy = gate.policy;
    final c = context.colors;

    final serverMessage = (policy?.maintenance.message.isNotEmpty ?? false)
        ? policy!.maintenance.message
        : (policy?.message ?? '');
    final end = policy?.maintenance.scheduledEndUtc?.toLocal();
    final lastChecked = gate.lastCheckedAt;

    return GateLayout(
      art: GateArt.maintenance,
      title: (policy?.title.isNotEmpty ?? false)
          ? policy!.title
          : l10n.gateMaintenanceTitle,
      message: serverMessage.isNotEmpty
          ? serverMessage
          : l10n.gateMaintenanceMessage,
      details: [
        if (end != null)
          SurfaceCard(
            child: Row(
              children: [
                Icon(Icons.schedule_rounded, color: c.brand),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.gateMaintenanceEstimatedEnd(
                          AppNumberFormat.dateTime(end, locale),
                        ),
                        style: context.textTheme.titleMedium,
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        l10n.gateMaintenanceEstimateNote,
                        style: context.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        if (end != null) const SizedBox(height: AppSpacing.lg),
        GateStatusPill(
          label: gate.rechecking
              ? l10n.gateCheckingNow
              : l10n.gateServiceReachable,
          color: c.success,
          busy: gate.rechecking,
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          l10n.gateMaintenanceAutoCheck,
          textAlign: TextAlign.center,
          style: context.textTheme.bodySmall,
        ),
        if (lastChecked != null) ...[
          const SizedBox(height: AppSpacing.xxs),
          Text(
            l10n.gateLastChecked(AppNumberFormat.time(lastChecked, locale)),
            textAlign: TextAlign.center,
            style: context.textTheme.bodySmall?.copyWith(color: c.textMuted),
          ),
        ],
      ],
      actions: [
        PremiumButton(
          label: l10n.commonRetry,
          icon: Icons.refresh_rounded,
          loading: gate.rechecking,
          onPressed: () => ref.read(appGateControllerProvider.notifier).retry(),
        ),
      ],
    );
  }
}
