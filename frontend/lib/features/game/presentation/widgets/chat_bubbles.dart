import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/audio_haptics/reduced_motion.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/game_visuals/game_visuals.dart';
import '../../../../shared/widgets/widgets.dart';

/// One bubble: a localized quick-chat line or an emote.
@immutable
class ChatBubbleData {
  const ChatBubbleData({
    required this.seat,
    required this.serial,
    this.text,
    this.emoteId,
  });

  final int seat;

  /// Increments per message so repeated identical messages re-animate.
  final int serial;
  final String? text;
  final String? emoteId;
}

/// Holds the latest bubble per seat and expires it after [lifetime].
class ChatBubbleHub extends ValueNotifier<Map<int, ChatBubbleData>> {
  ChatBubbleHub({this.lifetime = const Duration(milliseconds: 2800)})
    : super(const {});

  final Duration lifetime;
  final Map<int, Timer> _timers = {};
  int _serial = 0;
  bool _disposed = false;

  void show(int seat, {String? text, String? emoteId}) {
    if (_disposed || (text == null && emoteId == null)) return;
    _timers[seat]?.cancel();
    value = {
      ...value,
      seat: ChatBubbleData(
        seat: seat,
        serial: ++_serial,
        text: text,
        emoteId: emoteId,
      ),
    };
    _timers[seat] = Timer(lifetime, () => _expire(seat));
  }

  void _expire(int seat) {
    if (_disposed) return;
    _timers.remove(seat);
    value = {...value}..remove(seat);
  }

  void clear() {
    for (final t in _timers.values) {
      t.cancel();
    }
    _timers.clear();
    if (!_disposed) value = const {};
  }

  @override
  void dispose() {
    _disposed = true;
    for (final t in _timers.values) {
      t.cancel();
    }
    _timers.clear();
    super.dispose();
  }
}

/// Draws the bubbles above everything, anchored to each seat's panel via
/// [links] (a `CompositedTransformTarget` around the panel). Panels in the
/// top row get bubbles below them; the others above.
class ChatBubbleLayer extends StatelessWidget {
  const ChatBubbleLayer({
    super.key,
    required this.hub,
    required this.links,
    required this.topSeats,
    required this.seatColors,
  });

  final ChatBubbleHub hub;
  final Map<int, LayerLink> links;
  final Set<int> topSeats;
  final Map<int, SeatColor> seatColors;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ValueListenableBuilder<Map<int, ChatBubbleData>>(
        valueListenable: hub,
        builder: (context, bubbles, _) {
          return Stack(
            children: [
              for (final b in bubbles.values)
                if (links[b.seat] != null)
                  CompositedTransformFollower(
                    key: ValueKey('bubble-${b.seat}'),
                    link: links[b.seat]!,
                    showWhenUnlinked: false,
                    targetAnchor: topSeats.contains(b.seat)
                        ? Alignment.bottomCenter
                        : Alignment.topCenter,
                    followerAnchor: topSeats.contains(b.seat)
                        ? Alignment.topCenter
                        : Alignment.bottomCenter,
                    offset: Offset(0, topSeats.contains(b.seat) ? 4 : -4),
                    child: _Bubble(
                      key: ValueKey(b.serial),
                      data: b,
                      pointsUp: topSeats.contains(b.seat),
                      color: seatColors[b.seat],
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }
}

class _Bubble extends StatefulWidget {
  const _Bubble({
    super.key,
    required this.data,
    required this.pointsUp,
    this.color,
  });

  final ChatBubbleData data;
  final bool pointsUp;
  final SeatColor? color;

  @override
  State<_Bubble> createState() => _BubbleState();
}

class _BubbleState extends State<_Bubble> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (ReducedMotion.of(context)) {
      _c.value = 1;
    } else if (_c.value == 0 && !_c.isAnimating) {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final palette = GamePalette.of(context);
    final accent = widget.color == null ? c.brand : palette.seat(widget.color!);
    final d = widget.data;
    final content = d.emoteId != null
        ? EmoteIcon(emoteId: d.emoteId!, size: 40)
        : Text(
            d.text ?? '',
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: context.textTheme.labelLarge?.copyWith(
              color: c.textPrimary,
              fontSize: 14,
            ),
          );
    return ScaleTransition(
      scale: CurvedAnimation(parent: _c, curve: Curves.easeOutBack),
      alignment: widget.pointsUp ? Alignment.topCenter : Alignment.bottomCenter,
      child: FadeTransition(
        opacity: _c,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 168),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: d.emoteId != null ? 8 : 12,
              vertical: d.emoteId != null ? 6 : 8,
            ),
            decoration: BoxDecoration(
              color: c.surfaceRaised,
              borderRadius: AppRadii.lgAll,
              border: Border.all(color: accent, width: 2),
              boxShadow: c.shadow(AppElevation.medium),
            ),
            child: content,
          ),
        ),
      ),
    );
  }
}
