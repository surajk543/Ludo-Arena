import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/audio_haptics/audio_service.dart';
import '../../../core/audio_haptics/haptics_service.dart';
import '../../../core/errors/error_messages.dart';
import '../../../core/localization/number_format.dart';
import '../../../core/state/in_match_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/widgets/widgets.dart';
import '../application/coin_purchase_controller.dart';

/// Shows what happened to coin pack purchases ([CoinPurchaseNotice]s):
/// a celebration when the server granted a pack, a toast when the payment
/// is pending, was refused or could not be delivered yet. Never during a
/// match (shown after it).
///
/// Mounted once above the router (`app.dart`, with the root navigator key)
/// and inside the Shop; several hosts are safe: each notice is taken by
/// exactly one of them.
class CoinPurchaseHost extends ConsumerStatefulWidget {
  const CoinPurchaseHost({super.key, required this.child, this.navigatorKey});

  final Widget child;

  /// Navigator to show the dialog on; null = the nearest one.
  final GlobalKey<NavigatorState>? navigatorKey;

  @override
  ConsumerState<CoinPurchaseHost> createState() => _CoinPurchaseHostState();
}

class _CoinPurchaseHostState extends ConsumerState<CoinPurchaseHost> {
  bool _showing = false;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  void _schedule() =>
      WidgetsBinding.instance.addPostFrameCallback((_) => _drain());

  BuildContext? get _context {
    final key = widget.navigatorKey;
    if (key != null) return key.currentContext;
    return Navigator.maybeOf(context) == null ? null : context;
  }

  Future<void> _drain() async {
    if (_showing || !mounted || ref.read(inMatchProvider)) return;
    final ctx = _context;
    if (ctx == null || !ctx.mounted) return;
    final notice = ref
        .read(coinPurchaseControllerProvider.notifier)
        .takeNotice();
    if (notice == null) return;
    _showing = true;
    try {
      await _show(ctx, notice);
    } finally {
      _showing = false;
    }
    if (mounted) _schedule();
  }

  Future<void> _show(BuildContext ctx, CoinPurchaseNotice n) async {
    final l10n = AppLocalizations.of(ctx);
    switch (n.kind) {
      case CoinNoticeKind.granted:
        final locale = Localizations.localeOf(ctx);
        ref.read(audioServiceProvider).play(Sfx.purchase);
        ref.read(hapticsServiceProvider).success();
        await AppDialog.show<void>(
          ctx,
          title: l10n.coinsGrantedTitle,
          message: l10n.coinsGrantedMessage(
            formatCoins(n.coins, locale),
            formatNumberFull(n.diamonds, locale),
          ),
          illustration: const _GrantArt(),
          actions: [
            AppDialogAction(
              label: l10n.metaNice,
              variant: PremiumButtonVariant.primary,
            ),
          ],
        );
      case CoinNoticeKind.pending:
        AppToast.show(
          ctx,
          l10n.coinsErrorPending,
          icon: Icons.schedule_rounded,
          duration: const Duration(seconds: 4),
        );
      case CoinNoticeKind.delayed:
        AppToast.show(
          ctx,
          l10n.coinsDelayed,
          kind: ToastKind.warning,
          duration: const Duration(seconds: 4),
        );
      case CoinNoticeKind.failed:
        final code = n.code;
        AppToast.show(
          ctx,
          code == null
              ? l10n.coinsBuyFailed
              : localizedErrorMessage(l10n, code),
          kind: code == 'iap_unavailable' || code == 'purchase_pending'
              ? ToastKind.info
              : ToastKind.error,
          duration: const Duration(seconds: 4),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(
      coinPurchaseControllerProvider.select((s) => s.notices.length),
      (_, count) {
        if (count > 0) _schedule();
      },
    );
    ref.listen<bool>(inMatchProvider, (_, inMatch) {
      if (!inMatch) _schedule();
    });
    return widget.child;
  }
}

/// Coins and a diamond, for the "Coins added!" dialog.
class _GrantArt extends StatelessWidget {
  const _GrantArt();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ExcludeSemantics(
      child: Container(
        width: 88,
        height: 88,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: c.goldGradient,
          boxShadow: [
            BoxShadow(
              color: c.goldStrong.withValues(alpha: 0.4),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: const Stack(
          alignment: Alignment.center,
          children: [
            CoinIcon(size: 48),
            PositionedDirectional(
              end: 10,
              bottom: 10,
              child: DiamondIcon(size: 26),
            ),
          ],
        ),
      ),
    );
  }
}
