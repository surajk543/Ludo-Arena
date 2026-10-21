import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/widgets/widgets.dart';

/// Room code entry (6 letters/digits, upper-cased). Navigates to
/// `/rooms/join?code=XXXXXX`, where the private-rooms screen previews the
/// room (`GET /rooms/code/{code}`) and joins over WebSocket.
abstract final class JoinCodeSheet {
  static final RegExp codePattern = RegExp(r'^[A-Z0-9]{6}$');

  /// Normalizes user input (trims, removes spaces/dashes, upper-cases).
  static String normalize(String raw) =>
      raw.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();

  static Future<void> show(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppBottomSheet.show<void>(
      context,
      title: l10n.homeJoinCodeTitle,
      builder: (_) => const _JoinCodeBody(),
    );
  }
}

class _JoinCodeBody extends StatefulWidget {
  const _JoinCodeBody();

  @override
  State<_JoinCodeBody> createState() => _JoinCodeBodyState();
}

class _JoinCodeBodyState extends State<_JoinCodeBody> {
  final _controller = TextEditingController();
  bool _showError = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _code => JoinCodeSheet.normalize(_controller.text);
  bool get _valid => JoinCodeSheet.codePattern.hasMatch(_code);

  void _submit() {
    if (!_valid) {
      setState(() => _showError = true);
      return;
    }
    final router = GoRouter.of(context);
    Navigator.of(context).pop();
    router.push(AppRoutes.joinRoomFor(code: _code));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.colors;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        AppSpacing.xl,
        AppSpacing.sm,
        AppSpacing.xl,
        AppSpacing.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Room codes are Latin identifiers: always LTR.
          Directionality(
            textDirection: TextDirection.ltr,
            child: TextField(
              controller: _controller,
              autofocus: true,
              textAlign: TextAlign.center,
              textCapitalization: TextCapitalization.characters,
              autocorrect: false,
              enableSuggestions: false,
              keyboardType: TextInputType.visiblePassword,
              textInputAction: TextInputAction.go,
              maxLength: 6,
              style: context.textTheme.headlineMedium?.copyWith(
                letterSpacing: 6,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]')),
                TextInputFormatter.withFunction(
                  (old, next) => next.copyWith(text: next.text.toUpperCase()),
                ),
              ],
              decoration: InputDecoration(
                hintText: l10n.homeJoinCodeLabel,
                hintStyle: context.textTheme.titleMedium?.copyWith(
                  color: c.textMuted,
                ),
                counterText: '',
                prefixIcon: Icon(Icons.vpn_key_rounded, color: c.brand),
              ),
              onChanged: (_) {
                if (_showError) setState(() => _showError = false);
                setState(() {});
              },
              onSubmitted: (_) => _submit(),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            _showError ? l10n.homeJoinCodeInvalid : l10n.homeJoinCodeHelper,
            textAlign: TextAlign.center,
            style: context.textTheme.bodySmall?.copyWith(
              color: _showError ? c.danger : null,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          PremiumButton(
            label: l10n.homeJoinCodeAction,
            icon: Icons.login_rounded,
            onPressed: _code.isEmpty ? null : _submit,
          ),
        ],
      ),
    );
  }
}
