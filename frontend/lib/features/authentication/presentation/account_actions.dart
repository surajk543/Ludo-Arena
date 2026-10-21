import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/errors/error_messages.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/widgets/widgets.dart';
import '../application/session_controller.dart';
import 'delete_account_dialog.dart';

enum _SignOutChoice { saveFirst, signOut, cancel }

/// Confirmation flows shared by Settings and Profile.
abstract final class AccountActions {
  /// Sign out. A guest loses nothing — "Play as guest" on this device brings
  /// the same account back — and is offered Save Progress to keep it on
  /// other devices too.
  static Future<void> confirmSignOut(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final l10n = AppLocalizations.of(context);
    final user = ref.read(sessionControllerProvider).user;
    final unsavedGuest = user?.needsSaveProgress ?? false;

    final choice = await AppDialog.show<_SignOutChoice>(
      context,
      title: unsavedGuest ? l10n.authGuestLogoutTitle : l10n.authLogoutTitle,
      message: unsavedGuest
          ? l10n.authGuestLogoutKeptMessage
          : l10n.authLogoutMessage,
      actions: [
        if (unsavedGuest)
          AppDialogAction(
            label: l10n.authSaveProgressFirst,
            variant: PremiumButtonVariant.primary,
            value: _SignOutChoice.saveFirst,
          ),
        AppDialogAction(
          label: l10n.authLogoutConfirm,
          variant: PremiumButtonVariant.danger,
          value: _SignOutChoice.signOut,
        ),
        AppDialogAction(
          label: l10n.commonCancel,
          variant: PremiumButtonVariant.ghost,
          value: _SignOutChoice.cancel,
        ),
      ],
    );
    if (!context.mounted) return;
    switch (choice) {
      case _SignOutChoice.saveFirst:
        await context.push(AppRoutes.linkAccount);
      case _SignOutChoice.signOut:
        await ref.read(sessionControllerProvider.notifier).logout();
      case _SignOutChoice.cancel:
      case null:
        break;
    }
  }

  /// Settings → "Delete account" (guests too: their data is deleted as
  /// well). See [DeleteAccountDialog]; on success the gate routes to login,
  /// which confirms the deletion.
  static Future<void> confirmDeleteAccount(
    BuildContext context,
    WidgetRef ref,
  ) => DeleteAccountDialog.show(context);

  /// Settings → "Switch back to guest" (guest secret kept on device after a
  /// Save-Progress conflict sign-in).
  static Future<void> confirmSwitchToGuest(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await AppDialog.show<bool>(
      context,
      title: l10n.authSwitchToGuestTitle,
      message: l10n.authSwitchToGuestMessage,
      actions: [
        AppDialogAction(
          label: l10n.authSwitchToGuestConfirm,
          variant: PremiumButtonVariant.primary,
          value: true,
        ),
        AppDialogAction(
          label: l10n.commonCancel,
          variant: PremiumButtonVariant.ghost,
          value: false,
        ),
      ],
    );
    if (confirmed != true || !context.mounted) return;
    final outcome = await ref
        .read(sessionControllerProvider.notifier)
        .switchBackToGuest();
    if (!context.mounted) return;
    switch (outcome) {
      case AuthSucceeded(:final user):
        AppToast.show(
          context,
          l10n.authWelcomeBack(user.displayName),
          kind: ToastKind.success,
        );
        context.go(AppRoutes.home);
      case AuthFailed(:final code):
        AppToast.show(
          context,
          code == 'not_found'
              ? l10n.authGuestUnavailable
              : localizedErrorMessage(l10n, code),
          kind: ToastKind.error,
        );
      case AuthCancelled():
        break;
    }
  }
}
