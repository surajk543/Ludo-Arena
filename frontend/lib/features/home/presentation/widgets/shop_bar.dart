import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../shared/widgets/widgets.dart';

/// The lobby's Shop entry, pinned at the top of Home above the scrolling
/// content, so it stays in reach however far the lobby is scrolled. A gold
/// [PremiumButton] (≥ 48 dp, tap sound and haptic, RTL-aware) that pushes
/// the Shop. Once the lobby is scrolled ([scrolled]), a hairline separates
/// the bar from the content moving under its edge.
class LobbyShopBar extends StatelessWidget {
  const LobbyShopBar({super.key, required this.scrolled});

  /// Whether the lobby is scrolled away from the top.
  final ValueListenable<bool> scrolled;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = AppLocalizations.of(context);
    final button = Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppSpacing.maxContentWidth),
        child: PremiumButton(
          key: const ValueKey('lobby-shop'),
          label: l10n.homeShop,
          icon: Icons.storefront_rounded,
          variant: PremiumButtonVariant.gold,
          size: PremiumButtonSize.medium,
          onPressed: () => context.push(AppRoutes.shop),
        ),
      ),
    );
    return ValueListenableBuilder<bool>(
      valueListenable: scrolled,
      builder: (context, isScrolled, child) => AnimatedContainer(
        duration: AppDurations.fast,
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isScrolled ? c.divider : Colors.transparent,
            ),
          ),
        ),
        child: child,
      ),
      child: button,
    );
  }
}
