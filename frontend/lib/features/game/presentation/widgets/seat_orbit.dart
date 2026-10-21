import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/audio_haptics/reduced_motion.dart';
import '../../../../core/protocol/protocol.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../shared/widgets/widgets.dart';
import '../play_text.dart';

/// "Seats filling" visual for matchmaking and practice: [capacity] seats on
/// a ring around a pulsing center. Seats fill with the real players from
/// the server snapshot (avatar + frame + BOT badge) as they arrive.
class SeatOrbit extends StatefulWidget {
  const SeatOrbit({
    super.key,
    required this.capacity,
    required this.players,
    this.selfUid,
    this.center,
    this.searching = true,
  });

  final int capacity;
  final List<RoomPlayer> players;
  final String? selfUid;

  /// Widget in the middle (countdown, icon).
  final Widget? center;

  /// Animate the radar pulse.
  final bool searching;

  @override
  State<SeatOrbit> createState() => _SeatOrbitState();
}

class _SeatOrbitState extends State<SeatOrbit>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant SeatOrbit oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.searching != widget.searching) _sync();
  }

  void _sync() {
    if (widget.searching && !ReducedMotion.of(context)) {
      // Bounded repeat: never keeps the GPU busy forever.
      if (!_pulse.isAnimating) _pulse.repeat(count: 60);
    } else {
      _pulse
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final reduce = ReducedMotion.of(context);
    final players = [...widget.players]..sort((a, b) => a.seat - b.seat);
    final n = widget.capacity.clamp(2, 4);

    return LayoutBuilder(
      builder: (context, constraints) {
        final side = math.min(
          math.min(constraints.maxWidth, constraints.maxHeight),
          340.0,
        );
        final seatSize = (side * 0.22).clamp(48.0, 72.0);
        final radius = side / 2 - seatSize / 2 - 26;
        final centerSize = side * 0.3;

        return Center(
          child: SizedBox.square(
            dimension: side,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: _OrbitPainter(
                        pulse: _pulse,
                        ring: c.brand,
                        track: c.outline.withValues(alpha: 0.5),
                        radius: radius,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: (side - centerSize) / 2,
                  top: (side - centerSize) / 2,
                  width: centerSize,
                  height: centerSize,
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: c.brandGradient,
                      boxShadow: c.shadow(AppElevation.medium),
                    ),
                    alignment: Alignment.center,
                    child: widget.center,
                  ),
                ),
                for (var i = 0; i < n; i++)
                  _seat(
                    context,
                    index: i,
                    count: n,
                    side: side,
                    radius: radius,
                    seatSize: seatSize,
                    player: i < players.length ? players[i] : null,
                    reduce: reduce,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _seat(
    BuildContext context, {
    required int index,
    required int count,
    required double side,
    required double radius,
    required double seatSize,
    required RoomPlayer? player,
    required bool reduce,
  }) {
    final angle = -math.pi / 2 + index * 2 * math.pi / count;
    final cx = side / 2 + radius * math.cos(angle);
    final cy = side / 2 + radius * math.sin(angle);
    final l10n = AppLocalizations.of(context);
    final c = context.colors;
    final labelWidth = seatSize + 28;
    const labelHeight = 26.0;
    // Seats in the upper half carry their label above, so it never covers
    // the center.
    final labelAbove = math.sin(angle) < -0.5;

    final Widget content;
    if (player == null) {
      content = Padding(
        key: ValueKey('empty-$index'),
        padding: EdgeInsets.only(
          top: labelAbove ? labelHeight : 0,
          bottom: labelAbove ? 0 : labelHeight,
        ),
        child: Center(child: _EmptySeat(size: seatSize)),
      );
    } else {
      final label = SizedBox(
        width: labelWidth,
        height: labelHeight,
        child: Center(
          child: Text(
            player.uid == widget.selfUid
                ? l10n.commonYou
                : PlayText.playerName(l10n, player),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: context.textTheme.labelMedium?.copyWith(
              color: c.textPrimary,
            ),
          ),
        ),
      );
      final avatar = PlayerAvatar(
        avatarIndex: player.avatar,
        frameId: player.cosmetics.frame,
        size: seatSize,
        isBot: player.bot,
        seatColor: SeatColor.tryFromName(player.color),
        semanticLabel: PlayText.playerName(l10n, player),
      );
      content = Column(
        key: ValueKey('p-${player.uid}'),
        mainAxisSize: MainAxisSize.min,
        children: labelAbove ? [label, avatar] : [avatar, label],
      );
    }

    return Positioned(
      left: cx - labelWidth / 2,
      top: cy - seatSize / 2 - (labelAbove ? labelHeight : 0),
      width: labelWidth,
      height: seatSize + labelHeight,
      child: AnimatedSwitcher(
        duration: reduce ? Duration.zero : AppDurations.slow,
        switchInCurve: Curves.easeOutBack,
        transitionBuilder: (child, animation) =>
            ScaleTransition(scale: animation, child: child),
        child: content,
      ),
    );
  }
}

class _EmptySeat extends StatelessWidget {
  const _EmptySeat({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = AppLocalizations.of(context);
    return Semantics(
      label: l10n.playSeatOpen,
      excludeSemantics: true,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: c.surface.withValues(alpha: c.isDark ? 0.4 : 0.7),
          border: Border.all(color: c.outline, width: 2),
        ),
        child: Icon(
          Icons.person_search_rounded,
          color: c.textMuted,
          size: size * 0.44,
        ),
      ),
    );
  }
}

class _OrbitPainter extends CustomPainter {
  _OrbitPainter({
    required this.pulse,
    required this.ring,
    required this.track,
    required this.radius,
  }) : super(repaint: pulse);

  final Animation<double> pulse;
  final Color ring;
  final Color track;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = track,
    );
    final t = pulse.value;
    if (t <= 0) return;
    for (final phase in [0.0, 0.5]) {
      final u = (t + phase) % 1.0;
      canvas.drawCircle(
        center,
        radius * (0.35 + 0.75 * u),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3 * (1 - u) + 0.5
          ..color = ring.withValues(alpha: 0.35 * (1 - u)),
      );
    }
  }

  @override
  bool shouldRepaint(_OrbitPainter old) =>
      old.ring != ring || old.track != track || old.radius != radius;
}
