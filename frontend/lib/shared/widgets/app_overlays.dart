import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/audio_haptics/audio_service.dart';
import '../../core/theme/app_theme.dart';
import '../../l10n/generated/app_localizations.dart';
import 'premium_button.dart';

/// Open / close cues for modal sheets and dialogs. The open sound wins over
/// the tap that opened it (same gesture); the close sound only plays when
/// nothing else just played (closing by an action keeps that action's sound).
Future<T?> withOverlaySounds<T>(BuildContext context, Future<T?> route) {
  final audio = audioServiceOf(context)?..play(Sfx.uiOpen);
  return route.whenComplete(() => audio?.play(Sfx.uiClose));
}

/// Premium modal bottom sheet: drag handle, optional title with a close
/// button, safe areas, keyboard insets, ≤ 90 % height, scrollable content.
abstract final class AppBottomSheet {
  static Future<T?> show<T>(
    BuildContext context, {
    required WidgetBuilder builder,
    String? title,
    bool isScrollControlled = true,
    bool isDismissible = true,
  }) {
    return withOverlaySounds(
      context,
      _show(
        context,
        builder: builder,
        title: title,
        isScrollControlled: isScrollControlled,
        isDismissible: isDismissible,
      ),
    );
  }

  static Future<T?> _show<T>(
    BuildContext context, {
    required WidgetBuilder builder,
    String? title,
    required bool isScrollControlled,
    required bool isDismissible,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      // Above the bottom-navigation bar (like dialogs), not inside a tab.
      useRootNavigator: true,
      isScrollControlled: isScrollControlled,
      isDismissible: isDismissible,
      enableDrag: isDismissible,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      elevation: 0,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (sheetContext) => AppBottomSheetFrame(
        title: title,
        showClose: isDismissible,
        child: Builder(builder: builder),
      ),
    );
  }
}

/// The visual frame used by [AppBottomSheet] (exposed for custom sheets).
class AppBottomSheetFrame extends StatelessWidget {
  const AppBottomSheetFrame({
    super.key,
    required this.child,
    this.title,
    this.showClose = true,
  });

  final Widget child;
  final String? title;
  final bool showClose;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = AppLocalizations.of(context);
    final media = MediaQuery.of(context);
    final maxHeight = media.size.height * 0.9;
    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppRadii.xl),
            ),
            border: Border(
              top: BorderSide(
                color: c.isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : c.outline.withValues(alpha: 0.5),
              ),
            ),
            boxShadow: c.shadow(AppElevation.high),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: AppSpacing.sm),
                Center(
                  child: Container(
                    width: 40,
                    height: 5,
                    decoration: BoxDecoration(
                      color: c.outline,
                      borderRadius: AppRadii.pillAll,
                    ),
                  ),
                ),
                if (title != null || showClose)
                  Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(
                      AppSpacing.xl,
                      AppSpacing.sm,
                      AppSpacing.sm,
                      0,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: title == null
                              ? const SizedBox.shrink()
                              : Semantics(
                                  header: true,
                                  child: Text(
                                    title!,
                                    style: context.textTheme.headlineSmall,
                                  ),
                                ),
                        ),
                        if (showClose)
                          IconButton(
                            tooltip: l10n.commonClose,
                            onPressed: () => Navigator.of(context).maybePop(),
                            icon: Icon(
                              Icons.close_rounded,
                              color: c.textSecondary,
                            ),
                          ),
                      ],
                    ),
                  ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsetsDirectional.fromSTEB(
                      AppSpacing.xl,
                      AppSpacing.sm,
                      AppSpacing.xl,
                      AppSpacing.xl,
                    ),
                    child: child,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A dialog button. Tapping runs [onPressed] (awaited) and then closes the
/// dialog returning [value].
class AppDialogAction<T> {
  const AppDialogAction({
    required this.label,
    this.variant = PremiumButtonVariant.secondary,
    this.value,
    this.onPressed,
  });

  final String label;
  final PremiumButtonVariant variant;
  final T? value;
  final FutureOr<void> Function()? onPressed;
}

/// Premium centered dialog.
abstract final class AppDialog {
  static Future<T?> show<T>(
    BuildContext context, {
    required String title,
    String? message,
    Widget? content,
    Widget? illustration,
    required List<AppDialogAction<T>> actions,
    bool barrierDismissible = true,
    bool canPop = true,
  }) {
    return withOverlaySounds(
      context,
      showDialog<T>(
        context: context,
        barrierDismissible: barrierDismissible && canPop,
        barrierColor: Colors.black.withValues(alpha: 0.55),
        builder: (dialogContext) => PopScope(
          canPop: canPop,
          child: _AppDialogBody<T>(
            title: title,
            message: message,
            content: content,
            illustration: illustration,
            actions: actions,
          ),
        ),
      ),
    );
  }
}

class _AppDialogBody<T> extends StatelessWidget {
  const _AppDialogBody({
    required this.title,
    required this.actions,
    this.message,
    this.content,
    this.illustration,
  });

  final String title;
  final String? message;
  final Widget? content;
  final Widget? illustration;
  final List<AppDialogAction<T>> actions;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget button(AppDialogAction<T> a) => PremiumButton(
      label: a.label,
      variant: a.variant,
      size: PremiumButtonSize.medium,
      onPressed: () async {
        await a.onPressed?.call();
        if (context.mounted) Navigator.of(context).pop(a.value);
      },
    );

    return Dialog(
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
              if (illustration != null) ...[
                Center(child: illustration),
                const SizedBox(height: AppSpacing.lg),
              ],
              Semantics(
                header: true,
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  style: context.textTheme.headlineSmall,
                ),
              ),
              if (message != null) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: context.textTheme.bodyMedium?.copyWith(
                    color: c.textSecondary,
                  ),
                ),
              ],
              if (content != null) ...[
                const SizedBox(height: AppSpacing.lg),
                content!,
              ],
              const SizedBox(height: AppSpacing.xl),
              LayoutBuilder(
                builder: (context, constraints) {
                  final horizontal =
                      actions.length == 2 && constraints.maxWidth >= 340;
                  if (horizontal) {
                    return Row(
                      children: [
                        Expanded(child: button(actions[0])),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(child: button(actions[1])),
                      ],
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < actions.length; i++) ...[
                        if (i > 0) const SizedBox(height: AppSpacing.sm),
                        button(actions[i]),
                      ],
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Toast flavors.
enum ToastKind { info, success, warning, error }

/// Floating, styled snackbar.
abstract final class AppToast {
  static void show(
    BuildContext context,
    String message, {
    ToastKind kind = ToastKind.info,
    IconData? icon,
    Duration duration = const Duration(seconds: 3),
  }) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    // A failed action gets a subtle error cue (successes have their own).
    if (kind == ToastKind.error || kind == ToastKind.warning) {
      playUiSound(context, Sfx.uiError);
    }
    final c = context.colors;
    final accent = switch (kind) {
      ToastKind.info =>
        c.isDark ? BrandPalette.royal300 : BrandPalette.royal300,
      ToastKind.success => c.isDark ? c.success : const Color(0xFF3DD68C),
      ToastKind.warning => c.isDark ? c.warning : const Color(0xFFFFB224),
      ToastKind.error => c.isDark ? c.danger : const Color(0xFFFF6369),
    };
    final glyph =
        icon ??
        switch (kind) {
          ToastKind.info => Icons.info_rounded,
          ToastKind.success => Icons.check_circle_rounded,
          ToastKind.warning => Icons.warning_amber_rounded,
          ToastKind.error => Icons.error_rounded,
        };
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: duration,
          behavior: SnackBarBehavior.floating,
          backgroundColor: c.isDark
              ? BrandPalette.royal700
              : BrandPalette.royal850,
          elevation: 8,
          margin: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            0,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: AppRadii.mdAll,
            side: BorderSide(color: accent.withValues(alpha: 0.5)),
          ),
          content: Row(
            children: [
              Icon(glyph, color: accent, size: 22),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  message,
                  style: context.textTheme.bodyMedium?.copyWith(
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
  }
}
