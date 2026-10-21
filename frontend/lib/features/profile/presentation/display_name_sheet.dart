import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/error_messages.dart';
import '../../../core/network/api_models.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/widgets/widgets.dart';
import '../../authentication/application/session_controller.dart';
import '../../progression/application/meta_support.dart'
    show formatMetaDuration;
import '../domain/display_name.dart';

/// "Change your name" sheet. Pops with the server-confirmed [User] once the
/// new name is saved (the session already holds it), or null when closed.
abstract final class DisplayNameSheet {
  static Future<User?> show(BuildContext context) => AppBottomSheet.show<User>(
    context,
    title: AppLocalizations.of(context).profileEditNameTitle,
    builder: (_) => const DisplayNameForm(),
  );
}

/// Name field prefilled with the current name, live validation mirroring
/// the server rules ([DisplayNameRules]; the server stays authoritative),
/// a character counter, Save / Cancel.
class DisplayNameForm extends ConsumerStatefulWidget {
  const DisplayNameForm({super.key});

  /// Generous hard cap on input (the 16-character rule is shown as an
  /// error instead, so a pasted name can still be edited down).
  static const int inputCap = 32;

  @override
  ConsumerState<DisplayNameForm> createState() => _DisplayNameFormState();
}

class _DisplayNameFormState extends ConsumerState<DisplayNameForm> {
  late final String _current =
      ref.read(sessionControllerProvider).user?.displayName ?? '';
  late final TextEditingController _text = TextEditingController(
    text: _current,
  );

  /// The user typed something (errors stay hidden for the prefilled name).
  bool _edited = false;
  bool _busy = false;

  /// The last server failure, cleared on the next edit.
  DisplayNameFailed? _failure;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  DisplayNameProblem? get _problem => DisplayNameRules.validate(_text.text);
  bool get _unchanged => DisplayNameRules.sameName(_text.text, _current);

  /// The server rejected exactly this name: saving it again is pointless.
  bool get _rejected => _failure?.code == 'invalid_name';

  bool get _canSave => !_busy && !_unchanged && !_rejected && _problem == null;

  void _onChanged(String _) {
    setState(() {
      _edited = true;
      _failure = null;
    });
  }

  Future<void> _save() async {
    if (!_canSave) return;
    final name = DisplayNameRules.normalize(_text.text);
    setState(() {
      _busy = true;
      _failure = null;
    });
    final outcome = await ref
        .read(sessionControllerProvider.notifier)
        .updateDisplayName(name);
    if (!mounted) return;
    switch (outcome) {
      case DisplayNameChanged(:final user):
        Navigator.of(context).pop(user);
      case final DisplayNameFailed failure:
        setState(() {
          _busy = false;
          _failure = failure;
        });
    }
  }

  /// Error under the field: the server's verdict on this name, else the
  /// first client-side rule broken (once the user edited the name).
  String? _fieldError(AppLocalizations l10n) {
    final failure = _failure;
    if (failure != null && failure.code == 'invalid_name') {
      return localizedInvalidNameMessage(l10n, failure.reason);
    }
    final problem = _problem;
    if (_edited && problem != null) {
      return localizedInvalidNameMessage(l10n, problem.reason);
    }
    return null;
  }

  /// Any other failure (rate limit, network, …), shown above the buttons.
  String? _otherError(AppLocalizations l10n) {
    final f = _failure;
    if (f == null || f.code == 'invalid_name') return null;
    if (f.code == 'rate_limited') {
      final wait = f.retryAfter;
      if (wait == null || wait <= Duration.zero) {
        return l10n.profileNameChangeLimit;
      }
      // A short wait is the generic request limiter, not the daily quota.
      if (wait < const Duration(minutes: 1)) {
        return l10n.errorRateLimitedRetry(wait.inSeconds);
      }
      return l10n.profileNameChangeLimitRetry(formatMetaDuration(l10n, wait));
    }
    return localizedErrorMessage(l10n, f.code, retryAfter: f.retryAfter);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.colors;
    final length = DisplayNameRules.lengthOf(_text.text);
    const max = DisplayNameRules.maxLength;
    final tooLong = length > max;
    final otherError = _otherError(l10n);

    final counter = Semantics(
      label: l10n.profileNameCounterSemantics(length, max),
      excludeSemantics: true,
      child: Text(
        '$length/$max',
        key: const ValueKey('display-name-counter'),
        textDirection: TextDirection.ltr,
        style: context.textTheme.bodySmall?.copyWith(
          color: tooLong ? c.danger : c.textMuted,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );

    final save = PremiumButton(
      key: const ValueKey('display-name-save'),
      label: l10n.commonSave,
      icon: Icons.check_rounded,
      size: PremiumButtonSize.medium,
      loading: _busy,
      onPressed: _canSave ? _save : null,
    );
    final cancel = PremiumButton(
      key: const ValueKey('display-name-cancel'),
      label: l10n.commonCancel,
      variant: PremiumButtonVariant.secondary,
      size: PremiumButtonSize.medium,
      onPressed: _busy ? null : () => Navigator.of(context).maybePop(),
    );

    return PopScope(
      // Keep the sheet while the change is in flight.
      canPop: !_busy,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const ValueKey('display-name-field'),
            controller: _text,
            autofocus: true,
            // Not `enabled: false`: that would drop focus and the keyboard.
            readOnly: _busy,
            maxLines: 1,
            keyboardType: TextInputType.name,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            autocorrect: false,
            enableSuggestions: false,
            autofillHints: const [AutofillHints.nickname],
            inputFormatters: [
              LengthLimitingTextInputFormatter(DisplayNameForm.inputCap),
            ],
            onChanged: _onChanged,
            onSubmitted: (_) => _save(),
            style: context.textTheme.titleMedium,
            decoration: InputDecoration(
              labelText: l10n.profileNameLabel,
              helperText: l10n.profileNameRules,
              helperMaxLines: 3,
              errorText: _fieldError(l10n),
              errorMaxLines: 3,
              counter: counter,
              prefixIcon: Icon(Icons.badge_rounded, color: c.textSecondary),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded, size: 18, color: c.info),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  l10n.profileNameNote,
                  style: context.textTheme.bodySmall?.copyWith(
                    color: c.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          if (otherError != null) ...[
            const SizedBox(height: AppSpacing.md),
            _ErrorBanner(message: otherError),
          ],
          const SizedBox(height: AppSpacing.xl),
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth >= 340) {
                return Row(
                  children: [
                    Expanded(child: cancel),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(child: save),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  save,
                  const SizedBox(height: AppSpacing.sm),
                  cancel,
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      liveRegion: true,
      child: Container(
        key: const ValueKey('display-name-error'),
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: c.danger.withValues(alpha: 0.1),
          borderRadius: AppRadii.mdAll,
          border: Border.all(color: c.danger.withValues(alpha: 0.4)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline_rounded, size: 20, color: c.danger),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                message,
                style: context.textTheme.bodyMedium?.copyWith(
                  color: c.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
