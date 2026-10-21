import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/error_messages.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/widgets/widgets.dart';
import '../application/session_controller.dart';

/// Settings → Delete account: explains what is deleted, requires a
/// deliberate second confirmation (an "I understand" checkbox — accessible,
/// no typing), then calls `DELETE /account`.
///
/// On success the session is signed out and the app gate routes to login,
/// which confirms "Your account was deleted". On failure nothing was deleted:
/// the dialog stays open with an inline message so the user can retry.
/// Resolves `true` when the account was deleted.
class DeleteAccountDialog extends ConsumerStatefulWidget {
  const DeleteAccountDialog({super.key});

  static Future<bool> show(BuildContext context) async =>
      await showDialog<bool>(
        context: context,
        barrierColor: Colors.black.withValues(alpha: 0.55),
        builder: (_) => const DeleteAccountDialog(),
      ) ??
      false;

  @override
  ConsumerState<DeleteAccountDialog> createState() =>
      _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends ConsumerState<DeleteAccountDialog> {
  bool _understood = false;
  bool _busy = false;
  String? _error;

  Future<void> _delete() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final outcome = await ref
        .read(sessionControllerProvider.notifier)
        .deleteAccount();
    if (!mounted) return;
    switch (outcome) {
      case DeleteAccountSucceeded():
        Navigator.of(context).pop(true);
      case DeleteAccountFailed(code: 'session_replaced'):
        // Signed in on another device: that sign-out flow takes over.
        Navigator.of(context).pop(false);
      case DeleteAccountFailed(:final code, :final retryAfter):
        final l10n = AppLocalizations.of(context);
        setState(() {
          _busy = false;
          _error = code == 'rate_limited'
              ? localizedErrorMessage(l10n, code, retryAfter: retryAfter)
              : l10n.authDeleteAccountFailed;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.colors;
    final text = context.textTheme;
    final items = [
      (Icons.monetization_on_rounded, l10n.authDeleteAccountItemWallet),
      (Icons.trending_up_rounded, l10n.authDeleteAccountItemProgress),
      (Icons.style_rounded, l10n.authDeleteAccountItemCollection),
      (Icons.group_rounded, l10n.authDeleteAccountItemFriends),
    ];
    final error = _error;

    return PopScope(
      canPop: !_busy,
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xl,
          vertical: AppSpacing.xxl,
        ),
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: AppRadii.xlAll),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              AppSpacing.xxl,
              AppSpacing.xl,
              AppSpacing.xl,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Icon(
                    Icons.delete_forever_rounded,
                    size: 48,
                    color: c.danger,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Semantics(
                  header: true,
                  child: Text(
                    l10n.authDeleteAccountTitle,
                    textAlign: TextAlign.center,
                    style: text.headlineSmall,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  l10n.authDeleteAccountIntro,
                  style: text.bodyMedium?.copyWith(color: c.textSecondary),
                ),
                const SizedBox(height: AppSpacing.sm),
                for (final (icon, label) in items)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.xs,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ExcludeSemantics(
                          child: Icon(icon, size: 20, color: c.danger),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(child: Text(label, style: text.bodyMedium)),
                      ],
                    ),
                  ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  l10n.authDeleteAccountWarning,
                  style: text.bodyMedium?.copyWith(
                    color: c.danger,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                CheckboxListTile(
                  value: _understood,
                  onChanged: _busy
                      ? null
                      : (v) => setState(() => _understood = v ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  activeColor: c.danger,
                  title: Text(l10n.authDeleteAccountConfirmCheck),
                ),
                if (error != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      error,
                      style: text.bodyMedium?.copyWith(color: c.danger),
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.xl),
                PremiumButton(
                  label: l10n.authDeleteAccountConfirm,
                  variant: PremiumButtonVariant.danger,
                  size: PremiumButtonSize.medium,
                  icon: Icons.delete_forever_rounded,
                  loading: _busy,
                  onPressed: _understood ? _delete : null,
                ),
                const SizedBox(height: AppSpacing.sm),
                PremiumButton(
                  label: l10n.commonCancel,
                  variant: PremiumButtonVariant.ghost,
                  size: PremiumButtonSize.medium,
                  onPressed: _busy ? null : () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
