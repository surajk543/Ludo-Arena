import 'package:flutter/material.dart';

import '../../core/audio_haptics/audio_service.dart';
import '../../core/audio_haptics/reduced_motion.dart';
import '../../core/localization/number_format.dart';
import '../../core/theme/app_theme.dart';
import '../../l10n/generated/app_localizations.dart';
import 'currency_icons.dart';

/// Which virtual currency a [BalanceChip] shows.
enum BalanceKind { coins, diamonds }

/// Pill showing a server-confirmed balance. When [value] changes (e.g. after
/// `wallet.updated`) the number counts up/down to the new value and the chip
/// briefly glows; reduced motion jumps straight to the value.
class BalanceChip extends StatefulWidget {
  const BalanceChip({
    super.key,
    required this.kind,
    required this.value,
    this.onTap,
    this.compact = true,
  });

  final BalanceKind kind;
  final int value;
  final VoidCallback? onTap;

  /// Compact (`12.34 Lakh`) vs exact-or-words (`12,34,567`).
  final bool compact;

  @override
  State<BalanceChip> createState() => _BalanceChipState();
}

class _BalanceChipState extends State<BalanceChip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppDurations.countUp,
  );
  late int _from = widget.value;
  late int _to = widget.value;

  @override
  void didUpdateWidget(covariant BalanceChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _from = _displayed;
      _to = widget.value;
      if (ReducedMotion.of(context)) {
        _from = _to;
        _controller.value = 1;
      } else {
        _controller
          ..duration = AppDurations.countUp
          ..forward(from: 0);
      }
    }
  }

  int get _displayed {
    final t = Curves.easeOutCubic.transform(_controller.value);
    if (_controller.isDismissed && _from == _to) return _to;
    return (_from + (_to - _from) * t).round();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context);
    final coins = widget.kind == BalanceKind.coins;
    final accent = coins ? c.coin : c.diamond;
    String fmt(int v) =>
        widget.compact ? formatCoinsCompact(v, locale) : formatCoins(v, locale);
    final full = formatNumberFull(widget.value, locale);
    final label = coins
        ? l10n.widgetsCoinsBalance(full)
        : l10n.widgetsDiamondsBalance(full);

    return Semantics(
      label: label,
      button: widget.onTap != null,
      excludeSemantics: true,
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final running = _controller.isAnimating;
          final glow = running ? (1 - _controller.value) : 0.0;
          return Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: widget.onTap == null
                  ? null
                  : () {
                      playUiSound(context, Sfx.uiTap);
                      widget.onTap!();
                    },
              borderRadius: AppRadii.pillAll,
              child: Container(
                constraints: const BoxConstraints(minHeight: 36),
                padding: const EdgeInsetsDirectional.fromSTEB(4, 4, 12, 4),
                decoration: BoxDecoration(
                  color: c.glassFill,
                  borderRadius: AppRadii.pillAll,
                  border: Border.all(
                    color: Color.lerp(
                      c.glassBorder,
                      accent,
                      0.35 + glow * 0.6,
                    )!,
                    width: 1.2,
                  ),
                  boxShadow: [
                    ...c.shadow(AppElevation.low),
                    if (glow > 0)
                      BoxShadow(
                        color: accent.withValues(alpha: 0.45 * glow),
                        blurRadius: 16,
                      ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: accent.withValues(alpha: 0.16),
                      ),
                      alignment: Alignment.center,
                      child: coins
                          ? const CoinIcon(size: 22)
                          : const DiamondIcon(size: 20),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Flexible(
                      // Digit runs keep LTR order automatically (bidi), while
                      // unit words (لاکھ) follow the locale direction.
                      child: Text(
                        fmt(_displayed),
                        maxLines: 1,
                        overflow: TextOverflow.fade,
                        softWrap: false,
                        style: context.textTheme.titleMedium?.copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()],
                          color: c.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
