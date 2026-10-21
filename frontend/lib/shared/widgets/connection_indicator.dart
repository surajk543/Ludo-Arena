import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio_haptics/reduced_motion.dart';
import '../../core/realtime/realtime_status.dart';
import '../../core/theme/app_theme.dart';
import '../../l10n/generated/app_localizations.dart';

/// Shows the realtime connection state: a colored dot (pulsing while
/// connecting) and a label. When the session was replaced by another device
/// (close 4409) it offers a Reconnect action.
class ConnectionIndicator extends ConsumerWidget {
  const ConnectionIndicator({
    super.key,
    this.status,
    this.onReconnect,
    this.compact = false,
  });

  /// Explicit status; when null the live [realtimeStatusProvider] is used.
  final RealtimeStatus? status;
  final VoidCallback? onReconnect;

  /// Dot only (label kept for screen readers).
  final bool compact;

  static String label(AppLocalizations l10n, RealtimeStatus s) => switch (s) {
    RealtimeStatus.connected => l10n.commonConnectionConnected,
    RealtimeStatus.connecting ||
    RealtimeStatus.idle => l10n.commonConnectionConnecting,
    RealtimeStatus.reconnecting => l10n.commonConnectionReconnecting,
    RealtimeStatus.offline => l10n.commonConnectionOffline,
    RealtimeStatus.replaced => l10n.commonConnectionReplaced,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final RealtimeStatus s =
        status ?? ref.watch<RealtimeStatus>(realtimeStatusProvider);
    final c = context.colors;
    final l10n = AppLocalizations.of(context);
    final color = switch (s) {
      RealtimeStatus.connected => c.success,
      RealtimeStatus.connecting ||
      RealtimeStatus.reconnecting ||
      RealtimeStatus.idle => c.warning,
      RealtimeStatus.offline || RealtimeStatus.replaced => c.danger,
    };
    final text = label(l10n, s);
    final pulsing =
        s == RealtimeStatus.connecting || s == RealtimeStatus.reconnecting;
    final dot = _StatusDot(color: color, pulsing: pulsing);
    final showReconnect = s == RealtimeStatus.replaced && onReconnect != null;

    if (compact && !showReconnect) {
      return Semantics(
        label: l10n.widgetsConnectionLabel(text),
        liveRegion: true,
        excludeSemantics: true,
        child: Tooltip(
          message: text,
          excludeFromSemantics: true,
          child: SizedBox.square(dimension: 24, child: Center(child: dot)),
        ),
      );
    }

    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        padding: const EdgeInsetsDirectional.fromSTEB(10, 6, 12, 6),
        decoration: BoxDecoration(
          color: c.glassFill,
          borderRadius: AppRadii.pillAll,
          border: Border.all(color: color.withValues(alpha: 0.45)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            dot,
            const SizedBox(width: AppSpacing.sm),
            Flexible(
              child: Text(
                text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                semanticsLabel: l10n.widgetsConnectionLabel(text),
                style: context.textTheme.labelMedium?.copyWith(
                  color: c.textPrimary,
                ),
              ),
            ),
            if (showReconnect) ...[
              const SizedBox(width: AppSpacing.xs),
              Flexible(
                child: TextButton(
                  onPressed: onReconnect,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(48, 36),
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                    ),
                    textStyle: context.textTheme.labelMedium,
                  ),
                  child: Text(
                    l10n.commonReconnect,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusDot extends StatefulWidget {
  const _StatusDot({required this.color, required this.pulsing});

  final Color color;
  final bool pulsing;

  @override
  State<_StatusDot> createState() => _StatusDotState();
}

class _StatusDotState extends State<_StatusDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant _StatusDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pulsing != widget.pulsing) _sync();
  }

  void _sync() {
    if (widget.pulsing && !ReducedMotion.of(context)) {
      // Bounded so a stuck state never keeps the GPU busy forever.
      if (!_c.isAnimating) _c.repeat(reverse: true, count: 40);
    } else {
      _c
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        return SizedBox.square(
          dimension: 14,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 10 + 4 * t,
                height: 10 + 4 * t,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color.withValues(alpha: 0.25 * (1 - t) + 0.1),
                ),
              ),
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color,
                  boxShadow: [
                    BoxShadow(
                      color: widget.color.withValues(alpha: 0.6),
                      blurRadius: 6,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
