import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart'
    show AppleLogoPainter;

import '../../../../core/audio_haptics/audio_service.dart';
import '../../../../core/audio_haptics/haptics_service.dart';
import '../../../../core/network/api_models.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../l10n/generated/app_localizations.dart';

/// Localized provider brand name.
String providerName(AppLocalizations l10n, LinkedProvider p) => switch (p) {
  LinkedProvider.google => l10n.authProviderGoogle,
  LinkedProvider.facebook => l10n.authProviderFacebook,
  LinkedProvider.apple => l10n.authProviderApple,
  LinkedProvider.guest => l10n.authProviderGuest,
};

/// Brand-styled provider button (Google: light surface, Facebook: blue,
/// Apple: black/white per Apple's guidelines). Shows a spinner while
/// [onPressed]'s future runs and ignores taps meanwhile.
class ProviderButton extends ConsumerStatefulWidget {
  const ProviderButton({
    super.key,
    required this.provider,
    required this.label,
    required this.onPressed,
  });

  final LinkedProvider provider;
  final String label;

  /// Null disables the button (e.g. while another sign-in runs).
  final Future<void> Function()? onPressed;

  @override
  ConsumerState<ProviderButton> createState() => _ProviderButtonState();
}

class _ProviderButtonState extends ConsumerState<ProviderButton> {
  bool _busy = false;

  Future<void> _tap() async {
    final action = widget.onPressed;
    if (action == null || _busy) return;
    ref.read(hapticsServiceProvider).light();
    ref.read(audioServiceProvider).play(Sfx.uiTap);
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (Color bg, Color fg, Color? border) = switch (widget.provider) {
      LinkedProvider.google => (
        c.isDark ? const Color(0xFF131314) : Colors.white,
        c.isDark ? const Color(0xFFE3E3E3) : const Color(0xFF1F1F1F),
        c.isDark ? const Color(0xFF8E918F) : const Color(0xFF747775),
      ),
      LinkedProvider.facebook => (const Color(0xFF1877F2), Colors.white, null),
      LinkedProvider.apple => (
        c.isDark ? Colors.white : Colors.black,
        c.isDark ? Colors.black : Colors.white,
        null,
      ),
      LinkedProvider.guest => (c.surface, c.textPrimary, c.outline),
    };
    final enabled = widget.onPressed != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      excludeSemantics: true,
      child: Opacity(
        opacity: enabled || _busy ? 1 : 0.55,
        child: Material(
          color: bg,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: AppRadii.mdAll,
            side: border == null ? BorderSide.none : BorderSide(color: border),
          ),
          child: InkWell(
            borderRadius: AppRadii.mdAll,
            onTap: enabled && !_busy ? () => unawaited(_tap()) : null,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 52),
              child: Padding(
                padding: const EdgeInsetsDirectional.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.sm,
                ),
                child: Row(
                  children: [
                    SizedBox.square(
                      dimension: 22,
                      child: _busy
                          ? CircularProgressIndicator(
                              strokeWidth: 2.4,
                              color: fg,
                            )
                          : ProviderLogo(provider: widget.provider, color: fg),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Text(
                        widget.label,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: context.textTheme.labelLarge?.copyWith(
                          color: fg,
                        ),
                      ),
                    ),
                    const SizedBox(width: 22 + AppSpacing.md),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Vector provider marks (no bitmap assets).
class ProviderLogo extends StatelessWidget {
  const ProviderLogo({super.key, required this.provider, required this.color});

  final LinkedProvider provider;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final CustomPainter painter = switch (provider) {
      LinkedProvider.google => const _GoogleMarkPainter(),
      LinkedProvider.facebook => const _FacebookMarkPainter(),
      LinkedProvider.apple => AppleLogoPainter(color: color),
      LinkedProvider.guest => _GuestMarkPainter(color),
    };
    return CustomPaint(painter: painter, size: const Size.square(22));
  }
}

class _GoogleMarkPainter extends CustomPainter {
  const _GoogleMarkPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final stroke = s * 0.2;
    final rect = Rect.fromCircle(
      center: Offset(s / 2, s / 2),
      radius: s / 2 - stroke / 2,
    );
    Paint arc(Color c) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = c;
    const blue = Color(0xFF4285F4);
    const green = Color(0xFF34A853);
    const yellow = Color(0xFFFBBC05);
    const red = Color(0xFFEA4335);
    // Angles: 0 = 3 o'clock, clockwise.
    canvas.drawArc(rect, -math.pi * 0.02, math.pi * 0.27, false, arc(blue));
    canvas.drawArc(rect, math.pi * 0.25, math.pi * 0.5, false, arc(green));
    canvas.drawArc(rect, math.pi * 0.75, math.pi * 0.28, false, arc(yellow));
    canvas.drawArc(rect, math.pi * 1.03, math.pi * 0.72, false, arc(red));
    // Crossbar.
    canvas.drawRect(
      Rect.fromLTWH(
        s * 0.5,
        s * 0.5 - stroke / 2,
        s * 0.5 - stroke * 0.1,
        stroke,
      ),
      Paint()..color = blue,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _FacebookMarkPainter extends CustomPainter {
  const _FacebookMarkPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    canvas.drawCircle(
      Offset(s / 2, s / 2),
      s / 2,
      Paint()..color = Colors.white,
    );
    final f = Path()
      ..moveTo(s * 0.56, s)
      ..lineTo(s * 0.56, s * 0.6)
      ..lineTo(s * 0.69, s * 0.6)
      ..lineTo(s * 0.71, s * 0.45)
      ..lineTo(s * 0.56, s * 0.45)
      ..lineTo(s * 0.56, s * 0.36)
      ..quadraticBezierTo(s * 0.56, s * 0.29, s * 0.64, s * 0.29)
      ..lineTo(s * 0.72, s * 0.29)
      ..lineTo(s * 0.72, s * 0.16)
      ..lineTo(s * 0.6, s * 0.16)
      ..quadraticBezierTo(s * 0.41, s * 0.16, s * 0.41, s * 0.35)
      ..lineTo(s * 0.41, s * 0.45)
      ..lineTo(s * 0.29, s * 0.45)
      ..lineTo(s * 0.29, s * 0.6)
      ..lineTo(s * 0.41, s * 0.6)
      ..lineTo(s * 0.41, s)
      ..close();
    canvas.save();
    canvas.clipPath(Path()..addOval(Offset.zero & size));
    canvas.drawPath(f, Paint()..color = const Color(0xFF1877F2));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _GuestMarkPainter extends CustomPainter {
  const _GuestMarkPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final p = Paint()..color = color;
    canvas.drawCircle(Offset(s / 2, s * 0.32), s * 0.2, p);
    canvas.drawPath(
      Path()
        ..moveTo(s * 0.12, s * 0.95)
        ..quadraticBezierTo(s * 0.12, s * 0.58, s * 0.5, s * 0.58)
        ..quadraticBezierTo(s * 0.88, s * 0.58, s * 0.88, s * 0.95)
        ..close(),
      p,
    );
  }

  @override
  bool shouldRepaint(_GuestMarkPainter old) => old.color != color;
}
