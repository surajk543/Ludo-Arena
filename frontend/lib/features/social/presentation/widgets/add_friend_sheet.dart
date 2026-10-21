import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../../authentication/application/session_controller.dart';
import '../../../progression/application/meta_support.dart';
import '../../application/friends_controller.dart';
import '../../domain/friend_code.dart';
import '../../domain/social_models.dart';

/// "Add a friend" sheet: validated, always-LTR friend-code input. Pops with
/// the server's [Friend] on success.
abstract final class AddFriendSheet {
  static Future<Friend?> show(BuildContext context, {String? initialCode}) =>
      AppBottomSheet.show<Friend>(
        context,
        title: AppLocalizations.of(context).metaAddFriendTitle,
        builder: (_) => AddFriendForm(initialCode: initialCode),
      );
}

class AddFriendForm extends ConsumerStatefulWidget {
  const AddFriendForm({super.key, this.initialCode});

  final String? initialCode;

  @override
  ConsumerState<AddFriendForm> createState() => _AddFriendFormState();
}

class _AddFriendFormState extends ConsumerState<AddFriendForm> {
  late final TextEditingController _text = TextEditingController(
    text: widget.initialCode ?? '',
  );
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  String? _problemText(AppLocalizations l10n, FriendCodeProblem? p) =>
      switch (p) {
        FriendCodeProblem.empty => l10n.metaFriendCodeRequired,
        FriendCodeProblem.invalid => l10n.metaInvalidFriendCode,
        FriendCodeProblem.own => l10n.metaErrorCannotFriendSelf,
        null => null,
      };

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final t = data?.text?.trim();
    if (t == null || t.isEmpty || !mounted) return;
    setState(() {
      _text.text = t;
      _error = null;
    });
  }

  Future<void> _submit() async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    final myUid = ref.read(sessionControllerProvider).user?.uid;
    final problem = FriendCode.validate(_text.text, myUid: myUid);
    if (problem != null) {
      setState(() => _error = _problemText(l10n, problem));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final code = FriendCode.normalize(_text.text);
    final outcome = await ref.read(friendsProvider.notifier).sendRequest(code);
    if (!mounted) return;
    setState(() => _busy = false);
    switch (outcome) {
      case FriendActionSucceeded(:final friend):
        Navigator.of(context).pop(friend);
      case FriendActionIgnored():
        break;
      case FriendActionFailed(:final error):
        setState(
          () => _error = error.code == 'already_friends'
              ? l10n.metaAlreadyFriends
              : metaErrorMessage(
                  l10n,
                  error,
                  context: MetaErrorContext.friendCode,
                ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.colors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.metaAddFriendHelp, style: context.textTheme.bodyMedium),
        const SizedBox(height: AppSpacing.lg),
        Directionality(
          textDirection: TextDirection.ltr,
          child: TextField(
            key: const ValueKey('friend-code-field'),
            controller: _text,
            autofocus: true,
            enabled: !_busy,
            autocorrect: false,
            enableSuggestions: false,
            textCapitalization: TextCapitalization.none,
            keyboardType: TextInputType.visiblePassword,
            textInputAction: TextInputAction.send,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9_\-\s.]')),
              LengthLimitingTextInputFormatter(48),
            ],
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            onSubmitted: (_) => _submit(),
            style: context.textTheme.titleLarge?.copyWith(letterSpacing: 1),
            decoration: InputDecoration(
              labelText: l10n.metaFriendCodeLabel,
              hintText: l10n.metaFriendCodeHintExample,
              errorText: _error,
              errorMaxLines: 3,
              prefixIcon: Icon(Icons.tag_rounded, color: c.textSecondary),
              suffixIcon: IconButton(
                tooltip: l10n.metaPaste,
                icon: const Icon(Icons.content_paste_rounded),
                onPressed: _busy ? null : _paste,
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        PremiumButton(
          key: const ValueKey('send-friend-request'),
          label: l10n.metaSendRequest,
          icon: Icons.send_rounded,
          loading: _busy,
          size: PremiumButtonSize.medium,
          onPressed: _submit,
        ),
      ],
    );
  }
}
