import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/widgets/widgets.dart';
import '../../authentication/application/session_controller.dart';
import '../../progression/application/meta_support.dart';
import '../../store/application/store_controller.dart';
import '../../store/domain/store_models.dart';
import '../../store/presentation/widgets/store_picture_sheet.dart'
    show storeErrorMessage;

/// "Choose your picture" sheet: the pictures the player owns (paged) plus
/// the classic avatar, the equipped one marked. Pops with the
/// server-confirmed [User] once the choice is applied (the session already
/// holds it), or null when closed.
abstract final class ProfilePictureSheet {
  static Future<User?> show(BuildContext context) => AppBottomSheet.show<User>(
    context,
    title: AppLocalizations.of(context).profilePictureTitle,
    builder: (_) => const ProfilePicturePicker(),
  );
}

/// The picker body: a grid of choices, Show more, Cancel / Apply and a
/// link to the Store.
class ProfilePicturePicker extends ConsumerStatefulWidget {
  const ProfilePicturePicker({super.key});

  @override
  ConsumerState<ProfilePicturePicker> createState() =>
      _ProfilePicturePickerState();
}

class _ProfilePicturePickerState extends ConsumerState<ProfilePicturePicker> {
  /// The tapped choice (`null` = classic avatar); unset until a tap.
  bool _picked = false;
  String? _pickedId;
  bool _busy = false;
  ApiException? _failure;

  StoreController get _ctl => ref.read(ownedPicturesProvider.notifier);

  String? _selected(StoreState s) => _picked ? _pickedId : s.equippedId;

  void _pick(String? id) {
    if (_busy) return;
    setState(() {
      _picked = true;
      _pickedId = id;
      _failure = null;
    });
  }

  Future<void> _apply(StoreState s) async {
    final id = _selected(s);
    if (_busy || id == s.equippedId) return;
    setState(() {
      _busy = true;
      _failure = null;
    });
    final outcome = await _ctl.apply(id == null ? null : s.byId(id));
    if (!mounted) return;
    switch (outcome) {
      case StoreSucceeded():
        Navigator.of(context).pop(ref.read(sessionControllerProvider).user);
      case StoreIgnored():
        setState(() => _busy = false);
      case StoreFailed(:final error):
        setState(() {
          _busy = false;
          _failure = error;
        });
    }
  }

  void _openStore() {
    final router = GoRouter.maybeOf(context);
    Navigator.of(context).pop();
    router?.push(AppRoutes.store);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final s = ref.watch(ownedPicturesProvider);

    final Widget body;
    if (s.loading) {
      body = const SizedBox(height: 220, child: LoadingState());
    } else if (s.error case final error?) {
      body = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ErrorBanner(message: metaErrorMessage(l10n, error)),
          const SizedBox(height: AppSpacing.md),
          PremiumButton(
            key: const ValueKey('picture-picker-retry'),
            label: l10n.commonRetry,
            icon: Icons.refresh_rounded,
            size: PremiumButtonSize.medium,
            variant: PremiumButtonVariant.secondary,
            onPressed: () => _ctl.refresh().catchError((Object _) {}),
          ),
        ],
      );
    } else if (s.items.isEmpty) {
      body = _Empty(onOpenStore: _openStore);
    } else {
      body = _choices(context, s);
    }

    return PopScope(
      // Keep the sheet while the change is in flight.
      canPop: !_busy,
      child: body,
    );
  }

  Widget _choices(BuildContext context, StoreState s) {
    final l10n = AppLocalizations.of(context);
    final c = context.colors;
    final user = ref.watch(sessionControllerProvider.select((x) => x.user));
    final selected = _selected(s);
    final failure = _failure;
    final canApply = !_busy && selected != s.equippedId;

    Widget choice({
      required String? id,
      required String label,
      ProfilePicture? item,
    }) => _Choice(
      key: ValueKey('picture-choice-${id ?? 'classic'}'),
      label: label,
      selected: selected == id,
      equipped: s.equippedId == id,
      onTap: () => _pick(id),
      avatar: PlayerAvatar(
        avatarIndex: user?.avatar ?? 0,
        picture: item?.picture,
        frameId: user?.loadout.frame ?? 'frame_none',
        size: 60,
        semanticLabel: label,
      ),
    );

    final apply = PremiumButton(
      key: const ValueKey('picture-picker-apply'),
      label: l10n.storeApply,
      icon: Icons.check_rounded,
      size: PremiumButtonSize.medium,
      loading: _busy,
      onPressed: canApply ? () => _apply(s) : null,
    );
    final cancel = PremiumButton(
      key: const ValueKey('picture-picker-cancel'),
      label: l10n.commonCancel,
      variant: PremiumButtonVariant.secondary,
      size: PremiumButtonSize.medium,
      onPressed: _busy ? null : () => Navigator.of(context).maybePop(),
    );
    final textScale = MediaQuery.textScalerOf(context).scale(1);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = (constraints.maxWidth / 104).floor().clamp(3, 6);
            return GridView.count(
              crossAxisCount: columns,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              mainAxisSpacing: AppSpacing.sm,
              crossAxisSpacing: AppSpacing.sm,
              childAspectRatio:
                  ((constraints.maxWidth - AppSpacing.sm * (columns - 1)) /
                      columns) /
                  (96 + 36 * textScale),
              children: [
                choice(id: null, label: l10n.profilePictureClassic),
                for (final item in s.items)
                  choice(id: item.id, label: item.name, item: item),
              ],
            );
          },
        ),
        if (s.loadingMore)
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Center(
              child: SizedBox.square(
                dimension: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: c.brand,
                ),
              ),
            ),
          )
        else if (s.moreError != null) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            l10n.storeLoadMoreFailed,
            textAlign: TextAlign.center,
            style: context.textTheme.bodySmall,
          ),
          TextButton(
            key: const ValueKey('picture-picker-more'),
            onPressed: () => _ctl.loadMore(retry: true),
            child: Text(l10n.commonRetry),
          ),
        ] else if (s.hasMore)
          TextButton.icon(
            key: const ValueKey('picture-picker-more'),
            onPressed: () => _ctl.loadMore(),
            icon: const Icon(Icons.expand_more_rounded),
            label: Text(l10n.profilePictureShowMore),
          ),
        const SizedBox(height: AppSpacing.md),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline_rounded, size: 18, color: c.info),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                l10n.storeNextMatchNote,
                style: context.textTheme.bodySmall?.copyWith(
                  color: c.textSecondary,
                ),
              ),
            ),
          ],
        ),
        if (failure != null) ...[
          const SizedBox(height: AppSpacing.md),
          _ErrorBanner(message: storeErrorMessage(l10n, failure)),
        ],
        const SizedBox(height: AppSpacing.xl),
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth >= 340) {
              return Row(
                children: [
                  Expanded(child: cancel),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(child: apply),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                apply,
                const SizedBox(height: AppSpacing.sm),
                cancel,
              ],
            );
          },
        ),
        const SizedBox(height: AppSpacing.sm),
        Center(
          child: TextButton.icon(
            key: const ValueKey('picture-picker-get-more'),
            onPressed: _busy ? null : _openStore,
            icon: const Icon(Icons.storefront_rounded),
            label: Text(
              l10n.profilePictureGetMore,
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ],
    );
  }
}

/// One choice: the player's avatar with that picture, its name, and
/// whether it is the equipped one.
class _Choice extends StatelessWidget {
  const _Choice({
    super.key,
    required this.avatar,
    required this.label,
    required this.selected,
    required this.equipped,
    required this.onTap,
  });

  final Widget avatar;
  final String label;
  final bool selected;
  final bool equipped;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = AppLocalizations.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: equipped
          ? l10n.storeTileSemantics(label, l10n.metaEquipped)
          : label,
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: AppRadii.mdAll,
            color: selected
                ? c.brandSoft.withValues(alpha: c.isDark ? 0.18 : 0.7)
                : c.surfaceSunken,
            border: Border.all(
              color: selected ? c.brand : c.cardBorder,
              width: selected ? 2 : 1,
            ),
          ),
          child: InkWell(
            borderRadius: AppRadii.mdAll,
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xs + 2),
              child: Stack(
                children: [
                  Column(
                    children: [
                      Expanded(child: Center(child: avatar)),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: context.textTheme.labelMedium,
                      ),
                      Text(
                        equipped ? l10n.metaEquipped : '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: context.textTheme.labelSmall?.copyWith(
                          color: c.brand,
                        ),
                      ),
                    ],
                  ),
                  if (selected)
                    PositionedDirectional(
                      top: 0,
                      end: 0,
                      child: Icon(
                        Icons.check_circle_rounded,
                        size: 20,
                        color: c.brand,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// No owned pictures yet: point to the Store.
class _Empty extends StatelessWidget {
  const _Empty({required this.onOpenStore});

  final VoidCallback onOpenStore;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = AppLocalizations.of(context);
    return Column(
      key: const ValueKey('picture-picker-empty'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpacing.md),
        Icon(Icons.storefront_rounded, size: 48, color: c.brand),
        const SizedBox(height: AppSpacing.md),
        Text(
          l10n.storeEmptyOwnedTitle,
          textAlign: TextAlign.center,
          style: context.textTheme.titleMedium,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          l10n.profilePictureEmptyMessage,
          textAlign: TextAlign.center,
          style: context.textTheme.bodyMedium,
        ),
        const SizedBox(height: AppSpacing.xl),
        PremiumButton(
          key: const ValueKey('picture-picker-store'),
          label: l10n.profilePictureOpenStore,
          icon: Icons.storefront_rounded,
          size: PremiumButtonSize.medium,
          onPressed: onOpenStore,
        ),
      ],
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
        key: const ValueKey('picture-picker-error'),
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
