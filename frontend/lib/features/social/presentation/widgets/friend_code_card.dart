import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../domain/friend_code.dart';

/// My friend code (public uid) in a readable, always-LTR form, with copy and
/// share (friendly localized message containing the raw code).
class FriendCodeCard extends StatelessWidget {
  const FriendCodeCard({super.key, required this.uid, this.onAddFriend});

  final String uid;
  final VoidCallback? onAddFriend;

  Future<void> _copy(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    await Clipboard.setData(ClipboardData(text: uid));
    if (context.mounted) {
      AppToast.show(context, l10n.commonCopied, kind: ToastKind.success);
    }
  }

  void _share(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final box = context.findRenderObject() as RenderBox?;
    SharePlus.instance.share(
      ShareParams(
        text: l10n.metaShareFriendCodeMessage(uid),
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = AppLocalizations.of(context);
    final formatted = FriendCode.format(uid);
    return SurfaceCard(
      elevation: AppElevation.medium,
      gradient: LinearGradient(
        begin: AlignmentDirectional.topStart,
        end: AlignmentDirectional.bottomEnd,
        colors: [c.surfaceRaised, Color.lerp(c.surface, c.brandSoft, 0.75)!],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.metaYourFriendCode,
                      style: context.textTheme.titleSmall,
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Semantics(
                      label: l10n.metaFriendCodeSemantics(
                        uid.split('').join(' '),
                      ),
                      excludeSemantics: true,
                      child: Directionality(
                        textDirection: TextDirection.ltr,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: AlignmentDirectional.centerStart,
                          child: SelectableText(
                            formatted,
                            key: const ValueKey('my-friend-code'),
                            maxLines: 1,
                            style: context.textTheme.headlineSmall?.copyWith(
                              color: c.brand,
                              letterSpacing: 1.2,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              IconCircleButton(
                icon: Icons.copy_rounded,
                tooltip: l10n.commonCopy,
                size: 44,
                onPressed: () => _copy(context),
              ),
              const SizedBox(width: AppSpacing.sm),
              IconCircleButton(
                icon: Icons.share_rounded,
                tooltip: l10n.commonShare,
                size: 44,
                onPressed: () => _share(context),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(l10n.metaFriendCodeHint, style: context.textTheme.bodySmall),
          if (onAddFriend != null) ...[
            const SizedBox(height: AppSpacing.md),
            PremiumButton(
              key: const ValueKey('add-friend'),
              label: l10n.metaAddFriend,
              icon: Icons.person_add_alt_1_rounded,
              size: PremiumButtonSize.medium,
              variant: PremiumButtonVariant.secondary,
              onPressed: onAddFriend,
            ),
          ],
        ],
      ),
    );
  }
}
