import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../shared/widgets/widgets.dart';

/// Page frame shared by the meta screens: transparent app bar over the
/// layered background, centered max-width content, pull-to-refresh and a
/// sliver body.
class MetaScaffold extends StatelessWidget {
  const MetaScaffold({
    super.key,
    required this.title,
    required this.slivers,
    this.onRefresh,
    this.actions = const [],
    this.maxWidth = 640,
  });

  final String title;
  final List<Widget> slivers;
  final Future<void> Function()? onRefresh;
  final List<Widget> actions;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final bottom = MediaQuery.paddingOf(context).bottom;
    Widget scroll = CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        ...slivers,
        SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xxl + bottom)),
      ],
    );
    if (onRefresh != null) {
      scroll = RefreshIndicator(
        color: c.brand,
        onRefresh: onRefresh!,
        child: scroll,
      );
    }
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          ...actions,
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: LayeredBackground(
        child: SafeArea(
          bottom: false,
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: scroll,
            ),
          ),
        ),
      ),
    );
  }
}

/// Horizontal page padding for meta slivers.
const EdgeInsets kMetaPagePadding = EdgeInsets.symmetric(
  horizontal: AppSpacing.lg,
);

/// Fills the remaining viewport (at least [minHeight]) with [child]. Unlike
/// `SliverFillRemaining(hasScrollBody: false)` it never asks the child for
/// intrinsic sizes (the shared state views contain scroll views/buttons).
class MetaFillSliver extends StatelessWidget {
  const MetaFillSliver({super.key, required this.child, this.minHeight = 360});

  final Widget child;
  final double minHeight;

  @override
  Widget build(BuildContext context) => SliverLayoutBuilder(
    builder: (context, constraints) => SliverToBoxAdapter(
      child: SizedBox(
        height: constraints.remainingPaintExtent < minHeight
            ? minHeight
            : constraints.remainingPaintExtent,
        child: child,
      ),
    ),
  );
}

/// Full-height loading sliver.
class MetaLoadingSliver extends StatelessWidget {
  const MetaLoadingSliver({super.key});

  @override
  Widget build(BuildContext context) =>
      const MetaFillSliver(child: LoadingState());
}

/// Full-height error sliver with Retry.
class MetaErrorSliver extends StatelessWidget {
  const MetaErrorSliver({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => MetaFillSliver(
    child: ErrorState(
      title: AppLocalizations.of(context).commonSomethingWentWrong,
      message: message,
      onRetry: onRetry,
    ),
  );
}

/// Full-height empty sliver.
class MetaEmptySliver extends StatelessWidget {
  const MetaEmptySliver({
    super.key,
    required this.title,
    this.message,
    this.action,
    this.illustration,
  });

  final String title;
  final String? message;
  final Widget? action;
  final Widget? illustration;

  @override
  Widget build(BuildContext context) => MetaFillSliver(
    child: EmptyState(
      title: title,
      message: message,
      action: action,
      illustration: illustration,
    ),
  );
}

/// A soft informational note (calm, never urgent).
class MetaNote extends StatelessWidget {
  const MetaNote({
    super.key,
    required this.text,
    this.icon = Icons.favorite_rounded,
  });

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: c.brandSoft.withValues(alpha: c.isDark ? 0.12 : 0.6),
        borderRadius: AppRadii.mdAll,
        border: Border.all(color: c.brand.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: c.brand),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(text, style: context.textTheme.bodySmall)),
        ],
      ),
    );
  }
}
