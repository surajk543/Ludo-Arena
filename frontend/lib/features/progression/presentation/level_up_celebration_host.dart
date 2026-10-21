import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/audio_haptics/audio_service.dart';
import '../../../core/audio_haptics/haptics_service.dart';
import '../../../core/audio_haptics/reduced_motion.dart';
import '../../../core/state/in_match_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/game_visuals/game_visuals.dart';
import '../../../shared/widgets/widgets.dart';
import '../../meta_routes.dart';
import '../../missions/presentation/widgets/claim_feedback.dart';
import '../application/level_up_controller.dart';
import '../domain/progression_models.dart';

/// Shows queued level-up celebrations ([levelUpControllerProvider]) — but
/// never while the user is in a match: a level-up earned in a game is shown
/// after the match screen closes (when `inMatchProvider` turns false).
///
/// Mount once above the router with the root navigator key (see
/// `MetaShellHost`), and/or inside a screen (it then uses its own
/// navigator). Several hosts are safe: the controller hands each
/// celebration to exactly one of them.
class LevelUpCelebrationHost extends ConsumerStatefulWidget {
  const LevelUpCelebrationHost({
    super.key,
    required this.child,
    this.navigatorKey,
    this.afterMatchDelay = const Duration(milliseconds: 700),
  });

  final Widget child;

  /// Navigator to show the dialog on; null = the nearest one.
  final GlobalKey<NavigatorState>? navigatorKey;

  /// Pause after the match screen closes (lets its exit transition finish).
  final Duration afterMatchDelay;

  @override
  ConsumerState<LevelUpCelebrationHost> createState() =>
      _LevelUpCelebrationHostState();
}

class _LevelUpCelebrationHostState
    extends ConsumerState<LevelUpCelebrationHost> {
  Timer? _delay;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShow());
  }

  @override
  void dispose() {
    _delay?.cancel();
    super.dispose();
  }

  BuildContext? get _dialogContext {
    final key = widget.navigatorKey;
    if (key != null) return key.currentContext;
    return Navigator.maybeOf(context) == null ? null : context;
  }

  Future<void> _maybeShow() async {
    if (!mounted || ref.read(inMatchProvider)) return;
    final ctx = _dialogContext;
    if (ctx == null || !ctx.mounted) return;
    final controller = ref.read(levelUpControllerProvider.notifier);
    final next = controller.takeNext();
    if (next == null) return;
    String? choice;
    try {
      ref.read(audioServiceProvider).play(Sfx.levelUp);
      ref.read(hapticsServiceProvider).success();
      choice = await LevelUpDialog.show(ctx, next);
    } finally {
      controller.markShown();
    }
    if (choice == LevelUpDialog.viewCollection && ctx.mounted) {
      final kind = next.unlocked.isEmpty
          ? null
          : ItemRef.fromId(next.unlocked.first).kind;
      GoRouter.maybeOf(ctx)?.push(MetaRoutes.collectionFor(kind: kind));
    }
    if (mounted) unawaited(_maybeShow());
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<LevelUpState>(levelUpControllerProvider, (prev, next) {
      if (next.hasPending && !next.showing) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShow());
      }
    });
    ref.listen<bool>(inMatchProvider, (prev, inMatch) {
      if (inMatch) {
        _delay?.cancel();
        return;
      }
      _delay?.cancel();
      _delay = Timer(widget.afterMatchDelay, _maybeShow);
    });
    return widget.child;
  }
}

/// The level-up celebration: burst + new level + unlocked items.
abstract final class LevelUpDialog {
  static const String viewCollection = 'collection';

  static Future<String?> show(BuildContext context, LevelUpCelebration c) {
    return showDialog<String>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      builder: (_) => _LevelUpDialogBody(celebration: c),
    );
  }
}

class _LevelUpDialogBody extends StatelessWidget {
  const _LevelUpDialogBody({required this.celebration});

  final LevelUpCelebration celebration;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = AppLocalizations.of(context);
    final items = celebration.unlocked.map(ItemRef.fromId).toList();
    final reduce = context.reduceMotion;
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
            AppSpacing.lg,
            AppSpacing.xl,
            AppSpacing.xl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: LevelUpBurst(
                  size: 150,
                  reducedMotion: reduce,
                  child: LevelBadge(level: celebration.level, size: 64),
                ),
              ),
              Semantics(
                header: true,
                liveRegion: true,
                child: Text(
                  l10n.metaLevelUpTitle,
                  textAlign: TextAlign.center,
                  style: context.textTheme.headlineMedium,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                l10n.metaLevelUpMessage(celebration.level),
                textAlign: TextAlign.center,
                style: context.textTheme.bodyMedium,
              ),
              if (items.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.lg),
                Text(
                  l10n.metaUnlockedHeader,
                  textAlign: TextAlign.center,
                  style: context.textTheme.titleSmall,
                ),
                const SizedBox(height: AppSpacing.sm),
                GrantedItemsGrid(items: items),
              ],
              const SizedBox(height: AppSpacing.xl),
              PremiumButton(
                label: l10n.metaLevelUpContinue,
                size: PremiumButtonSize.medium,
                onPressed: () => Navigator.of(context).pop(),
              ),
              if (items.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                PremiumButton(
                  label: l10n.metaViewCollection,
                  variant: PremiumButtonVariant.ghost,
                  size: PremiumButtonSize.medium,
                  onPressed: () =>
                      Navigator.of(context).pop(LevelUpDialog.viewCollection),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
