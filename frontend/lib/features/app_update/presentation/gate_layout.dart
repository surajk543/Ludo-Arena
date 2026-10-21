import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/widgets.dart';
import 'gate_illustrations.dart';

/// Shared layout for full-screen gate states: layered background, painted
/// illustration, title, message, optional details and actions. Scrolls on
/// small screens, respects safe areas, centered on large ones.
class GateLayout extends StatelessWidget {
  const GateLayout({
    super.key,
    required this.art,
    required this.title,
    required this.message,
    this.details = const [],
    this.actions = const [],
    this.footer,
  });

  final GateArt art;
  final String title;
  final String message;
  final List<Widget> details;
  final List<Widget> actions;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final text = context.textTheme;
    final c = context.colors;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: LayeredBackground(
        style: LayeredBackgroundStyle.calm,
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.gutter,
                vertical: AppSpacing.xxl,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - AppSpacing.xxl * 2,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: AppSpacing.maxContentWidth,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: GateIllustration(
                            art: art,
                            size: constraints.maxHeight < 600 ? 128 : 168,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xl),
                        Semantics(
                          header: true,
                          child: Text(
                            title,
                            textAlign: TextAlign.center,
                            style: text.headlineMedium,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          message,
                          textAlign: TextAlign.center,
                          style: text.bodyLarge?.copyWith(
                            color: c.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (details.isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.xl),
                          ...details,
                        ],
                        if (actions.isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.xxl),
                          for (var i = 0; i < actions.length; i++) ...[
                            if (i > 0) const SizedBox(height: AppSpacing.md),
                            actions[i],
                          ],
                        ],
                        if (footer != null) ...[
                          const SizedBox(height: AppSpacing.xl),
                          footer!,
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Label/value row inside a gate details card (e.g. installed vs required
/// version). Values are LTR-isolated so version numbers stay readable in
/// RTL locales.
class GateInfoRow extends StatelessWidget {
  const GateInfoRow({
    super.key,
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final text = context.textTheme;
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: text.bodyMedium?.copyWith(color: c.textSecondary),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Directionality(
            textDirection: TextDirection.ltr,
            child: Text(
              value,
              style: text.titleMedium?.copyWith(
                color: emphasize ? c.brand : c.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Small status pill: colored dot + label.
class GateStatusPill extends StatelessWidget {
  const GateStatusPill({
    super.key,
    required this.label,
    required this.color,
    this.busy = false,
  });

  final String label;
  final Color color;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Container(
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: c.surface.withValues(alpha: 0.85),
          borderRadius: AppRadii.pillAll,
          border: Border.all(color: c.outline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (busy)
              SizedBox.square(
                dimension: 12,
                child: CircularProgressIndicator(strokeWidth: 2, color: color),
              )
            else
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
            const SizedBox(width: AppSpacing.sm),
            Flexible(
              child: Text(
                label,
                style: context.textTheme.labelMedium,
                overflow: TextOverflow.ellipsis,
                maxLines: 2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
