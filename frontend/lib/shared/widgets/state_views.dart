import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../l10n/generated/app_localizations.dart';
import 'premium_button.dart';

/// Centered loading indicator with an optional message.
class LoadingState extends StatelessWidget {
  const LoadingState({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = AppLocalizations.of(context);
    final text = message ?? l10n.commonLoading;
    return Center(
      child: Semantics(
        liveRegion: true,
        label: text,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: c.surface,
                  boxShadow: c.shadow(AppElevation.medium),
                ),
                padding: const EdgeInsets.all(16),
                child: CircularProgressIndicator(
                  strokeWidth: 3.2,
                  strokeCap: StrokeCap.round,
                  valueColor: AlwaysStoppedAnimation(c.brand),
                  backgroundColor: c.goldSoft,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              ExcludeSemantics(
                child: Text(
                  text,
                  textAlign: TextAlign.center,
                  style: context.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Friendly empty state with a painted illustration.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    this.message,
    this.illustration,
    this.action,
  });

  final String title;
  final String? message;
  final Widget? illustration;
  final Widget? action;

  @override
  Widget build(BuildContext context) => _StateLayout(
    illustration:
        illustration ??
        CustomPaint(
          size: const Size(120, 96),
          painter: _EmptyChestPainter(context.colors),
        ),
    title: title,
    message: message,
    action: action,
  );
}

/// Error state with a Retry button.
class ErrorState extends StatelessWidget {
  const ErrorState({super.key, this.title, this.message, this.onRetry});

  final String? title;
  final String? message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _StateLayout(
      illustration: CustomPaint(
        size: const Size(120, 96),
        painter: _ErrorCloudPainter(context.colors),
      ),
      title: title ?? l10n.commonSomethingWentWrong,
      message: message,
      action: onRetry == null
          ? null
          : PremiumButton(
              label: l10n.commonRetry,
              icon: Icons.refresh_rounded,
              expand: false,
              size: PremiumButtonSize.medium,
              variant: PremiumButtonVariant.secondary,
              onPressed: onRetry,
            ),
    );
  }
}

class _StateLayout extends StatelessWidget {
  const _StateLayout({
    required this.illustration,
    required this.title,
    this.message,
    this.action,
  });

  final Widget illustration;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ExcludeSemantics(child: illustration),
              const SizedBox(height: AppSpacing.lg),
              Text(
                title,
                textAlign: TextAlign.center,
                style: context.textTheme.titleLarge,
              ),
              if (message != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: context.textTheme.bodyMedium?.copyWith(
                    color: c.textSecondary,
                  ),
                ),
              ],
              if (action != null) ...[
                const SizedBox(height: AppSpacing.xl),
                action!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyChestPainter extends CustomPainter {
  _EmptyChestPainter(this.c);

  final AppColors c;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    // Glow.
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(w / 2, h * 0.9),
        width: w * 0.9,
        height: h * 0.18,
      ),
      Paint()..color = c.shadowColor.withValues(alpha: c.isDark ? 0.4 : 0.12),
    );
    // Chest body.
    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.18, h * 0.45, w * 0.64, h * 0.42),
      const Radius.circular(10),
    );
    canvas.drawRRect(
      body,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [BrandPalette.royal400, BrandPalette.royal600],
        ).createShader(body.outerRect),
    );
    // Open lid (tilted back).
    final lid = Path()
      ..moveTo(w * 0.18, h * 0.45)
      ..lineTo(w * 0.24, h * 0.18)
      ..quadraticBezierTo(w * 0.5, h * 0.06, w * 0.76, h * 0.18)
      ..lineTo(w * 0.82, h * 0.45)
      ..close();
    canvas.drawPath(lid, Paint()..color = BrandPalette.royal300);
    // Gold bands.
    final gold = Paint()..color = BrandPalette.gold500;
    canvas.drawRect(
      Rect.fromLTWH(w * 0.18, h * 0.43, w * 0.64, h * 0.06),
      gold,
    );
    canvas.drawRect(
      Rect.fromLTWH(w * 0.46, h * 0.45, w * 0.08, h * 0.42),
      gold,
    );
    canvas.drawCircle(
      Offset(w * 0.5, h * 0.6),
      w * 0.05,
      Paint()..color = BrandPalette.gold300,
    );
    // Sparkles.
    for (final p in [
      Offset(w * 0.12, h * 0.2),
      Offset(w * 0.88, h * 0.28),
      Offset(w * 0.6, h * 0.02),
    ]) {
      _sparkle(canvas, p, w * 0.045, BrandPalette.gold400);
    }
  }

  @override
  bool shouldRepaint(_EmptyChestPainter old) => old.c != c;
}

class _ErrorCloudPainter extends CustomPainter {
  _ErrorCloudPainter(this.c);

  final AppColors c;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cloud = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          c.isDark ? BrandPalette.royal600 : BrandPalette.royal200,
          c.isDark ? BrandPalette.royal700 : BrandPalette.royal300,
        ],
      ).createShader(Offset.zero & size);
    canvas.drawCircle(Offset(w * 0.35, h * 0.5), h * 0.24, cloud);
    canvas.drawCircle(Offset(w * 0.55, h * 0.38), h * 0.3, cloud);
    canvas.drawCircle(Offset(w * 0.72, h * 0.52), h * 0.22, cloud);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.2, h * 0.5, w * 0.62, h * 0.24),
        Radius.circular(h * 0.12),
      ),
      cloud,
    );
    // Warning badge.
    final center = Offset(w * 0.58, h * 0.56);
    canvas.drawCircle(center, h * 0.17, Paint()..color = c.warning);
    final mark = Paint()
      ..color = Colors.white
      ..strokeWidth = h * 0.045
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      center.translate(0, -h * 0.08),
      center.translate(0, h * 0.02),
      mark,
    );
    canvas.drawCircle(
      center.translate(0, h * 0.08),
      h * 0.025,
      Paint()..color = Colors.white,
    );
    // Little falling dice pips.
    for (var i = 0; i < 3; i++) {
      canvas.drawCircle(
        Offset(w * (0.3 + i * 0.18), h * (0.86 + (i.isEven ? 0 : 0.05))),
        h * 0.025,
        Paint()..color = c.textMuted.withValues(alpha: 0.6),
      );
    }
  }

  @override
  bool shouldRepaint(_ErrorCloudPainter old) => old.c != c;
}

void _sparkle(Canvas canvas, Offset c, double r, Color color) {
  final p = Path();
  for (var i = 0; i < 8; i++) {
    final rr = i.isEven ? r : r * 0.3;
    final ang = -math.pi / 2 + i * math.pi / 4;
    final pt = Offset(c.dx + math.cos(ang) * rr, c.dy + math.sin(ang) * rr);
    i == 0 ? p.moveTo(pt.dx, pt.dy) : p.lineTo(pt.dx, pt.dy);
  }
  canvas.drawPath(p..close(), Paint()..color = color);
}

/// Section title with an optional trailing action.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
    this.trailing,
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsetsDirectional.only(
        top: AppSpacing.sm,
        bottom: AppSpacing.sm,
      ),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 18,
            decoration: BoxDecoration(
              gradient: c.goldGradient,
              borderRadius: AppRadii.pillAll,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            flex: 3,
            child: Semantics(
              header: true,
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.textTheme.titleLarge,
              ),
            ),
          ),
          ?trailing,
          if (actionLabel != null && onAction != null)
            Flexible(
              flex: 2,
              child: TextButton(
                onPressed: onAction,
                style: TextButton.styleFrom(minimumSize: const Size(48, 40)),
                child: Text(
                  actionLabel!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
