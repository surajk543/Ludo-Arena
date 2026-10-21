import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/gate/app_gate_controller.dart';
import '../../../core/app_policy/app_policy.dart';
import '../../../core/localization/number_format.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/widgets/widgets.dart';
import 'gate_illustrations.dart';
import 'gate_layout.dart';

/// Shown when the game service can't be reached at startup. A connection
/// is required for online play; the cached policy only adds context.
class ServiceUnreachableScreen extends ConsumerWidget {
  const ServiceUnreachableScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context);
    final gate = ref.watch(appGateControllerProvider);
    final cached = gate.cachedPolicy;
    final c = context.colors;

    final context0 = switch (cached?.mode) {
      PolicyMode.maintenance => l10n.gateUnreachableLastKnownMaintenance,
      PolicyMode.forceUpdate => l10n.gateUnreachableLastKnownUpdate,
      _ => null,
    };

    return GateLayout(
      art: GateArt.unreachable,
      title: l10n.gateUnreachableTitle,
      message: l10n.gateUnreachableMessage,
      details: [
        GateStatusPill(
          label: gate.rechecking
              ? l10n.gateCheckingNow
              : l10n.gateServiceUnreachableShort,
          color: c.danger,
          busy: gate.rechecking,
        ),
        if (context0 != null) ...[
          const SizedBox(height: AppSpacing.lg),
          SurfaceCard(
            color: c.surfaceSunken,
            child: Row(
              children: [
                Icon(Icons.history_rounded, color: c.textSecondary),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(context0, style: context.textTheme.bodyMedium),
                ),
              ],
            ),
          ),
        ],
        if (gate.lastCheckedAt != null) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            l10n.gateLastChecked(
              AppNumberFormat.time(gate.lastCheckedAt!, locale),
            ),
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
