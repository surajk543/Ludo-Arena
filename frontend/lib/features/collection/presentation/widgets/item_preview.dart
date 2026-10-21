import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/audio_haptics/reduced_motion.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/game_visuals/game_visuals.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../../authentication/application/session_controller.dart';
import '../../../progression/domain/progression_models.dart';

/// Visual preview of ANY catalog item in a [size] box: the board library
/// renders dice/tokens/boards/trails/victory effects; frames, titles,
/// badges and emotes use the shared app widgets. Animation is only used
/// when [animate] and motion is not reduced. Decorative (no semantics):
/// the surrounding card/sheet labels the item.
class CosmeticItemPreview extends ConsumerWidget {
  const CosmeticItemPreview({
    super.key,
    required this.id,
    this.kind,
    this.size = 72,
    this.animate = false,
    this.dimmed = false,
  });

  final String id;

  /// Defaults to the kind inferred from the id prefix.
  final String? kind;
  final double size;
  final bool animate;

  /// Desaturated look for locked items.
  final bool dimmed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final k = kind ?? kindOfItemId(id);
    final anim = animate && !context.reduceMotion;
    final avatar = ref.watch(
      sessionControllerProvider.select((s) => s.user?.avatar ?? 0),
    );
    Widget art = switch (k) {
      'frame' => PlayerAvatar(avatarIndex: avatar, frameId: id, size: size),
      'title' when size < 48 => Icon(
        Icons.military_tech_rounded,
        size: size * 0.72,
        color: cosmeticRarity(id).color(context.colors),
      ),
      'title' => SizedBox(
        width: size,
        height: size * 0.5,
        child: FittedBox(
          fit: size >= 48 ? BoxFit.contain : BoxFit.scaleDown,
          child: TitleChip(titleId: id),
        ),
      ),
      'badge' => BadgeIcon(badgeId: id, size: size * 0.9),
      'emote' => EmoteIcon(emoteId: id, size: size * 0.86),
      'ludo_board' || 'snakes_board' => ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.08),
        child: BoardThemePreview(id, size: size * 0.92, showTokens: anim),
      ),
      // The dice renderer draws at 70 % of its size; fill the box instead.
      'dice' => DiceSkinPreview(id, size: size * 0.78, animate: anim),
      'token' || 'trail' || 'victory' => CosmeticPreview(
        id,
        size: size,
        animate: anim,
        color: SeatColor.blue,
      ),
      _ => Icon(
        Icons.auto_awesome_rounded,
        size: size * 0.5,
        color: context.colors.gold,
      ),
    };
    if (dimmed) {
      // Locked: softly muted (45 % saturation) but still showing what the
      // item looks like.
      art = Opacity(
        opacity: 0.8,
        child: ColorFiltered(
          colorFilter: const ColorFilter.matrix([
            0.5669, 0.3934, 0.0397, 0, 0, //
            0.1169, 0.8434, 0.0397, 0, 0, //
            0.1169, 0.3934, 0.4897, 0, 0, //
            0, 0, 0, 1, 0,
          ]),
          child: art,
        ),
      );
    }
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: Center(child: art),
      ),
    );
  }
}
