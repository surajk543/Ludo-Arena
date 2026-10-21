import 'package:flutter/material.dart';

import '../../../core/app_policy/app_policy.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/widgets/widgets.dart';
import 'gate_illustrations.dart';

/// User's answer to the optional update prompt.
enum OptionalUpdateChoice { updateNow, later }

/// "A new version is available" dialog with Update now / Later. Shown at
/// most once per launch and never during a match (enforced by the gate).
abstract final class OptionalUpdateDialog {
  static Future<OptionalUpdateChoice> show(
    BuildContext context,
    AppPolicy policy,
  ) async {
    final l10n = AppLocalizations.of(context);
    final choice = await AppDialog.show<OptionalUpdateChoice>(
      context,
      title: policy.title.isNotEmpty
          ? policy.title
          : l10n.gateOptionalUpdateTitle,
      message: policy.message.isNotEmpty
          ? policy.message
          : l10n.gateOptionalUpdateMessage(
              '\u2066${policy.latestVersion}\u2069',
            ),
      illustration: const GateIllustration(art: GateArt.update, size: 112),
      barrierDismissible: false,
      actions: [
        if (policy.canOpenStore)
          AppDialogAction(
            label: l10n.gateUpdateNow,
            variant: PremiumButtonVariant.gold,
            value: OptionalUpdateChoice.updateNow,
          ),
        AppDialogAction(
          label: l10n.commonLater,
          variant: PremiumButtonVariant.ghost,
          value: OptionalUpdateChoice.later,
        ),
      ],
    );
    return choice ?? OptionalUpdateChoice.later;
  }
}
