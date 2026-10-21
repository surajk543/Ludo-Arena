import '../../../features/ludo/presentation/board/ludo_board_theme.dart';
import '../../../features/snakes_ladders/presentation/board/snakes_board_theme.dart';
import '../dice/dice_skins.dart';
import '../effects/victory_overlay.dart';
import '../tokens/token_renderer.dart';
import '../trails/trail_renderer.dart';

/// Cosmetic slots that have a visual renderer in this library.
///
/// Frames, titles, badges and emotes are rendered by the app shell, not
/// here.
enum CosmeticVisualKind { dice, token, ludoBoard, snakesBoard, trail, victory }

/// Maps catalog ids (`docs/cosmetics-catalog.md`) to the renderers of the
/// board library. Unknown ids of a known kind resolve to that kind's
/// starter look.
abstract final class CosmeticVisuals {
  /// All ids per kind, in catalog order (starter first).
  static const Map<CosmeticVisualKind, List<String>> ids = {
    CosmeticVisualKind.dice: DiceSkins.all,
    CosmeticVisualKind.token: TokenSkins.all,
    CosmeticVisualKind.ludoBoard: LudoBoardThemes.all,
    CosmeticVisualKind.snakesBoard: SnakesBoardThemes.all,
    CosmeticVisualKind.trail: TrailStyles.all,
    CosmeticVisualKind.victory: VictoryStyles.all,
  };

  /// Starter (default loadout) id per kind.
  static const Map<CosmeticVisualKind, String> starters = {
    CosmeticVisualKind.dice: DiceSkins.classic,
    CosmeticVisualKind.token: TokenSkins.classic,
    CosmeticVisualKind.ludoBoard: LudoBoardThemes.classic,
    CosmeticVisualKind.snakesBoard: SnakesBoardThemes.classic,
    CosmeticVisualKind.trail: TrailStyles.none,
    CosmeticVisualKind.victory: VictoryStyles.confetti,
  };

  /// The kind of [id] inferred from its prefix, or null when this library
  /// does not render it (frames, titles, badges, emotes, garbage).
  static CosmeticVisualKind? kindOf(String? id) {
    if (id == null) return null;
    if (id.startsWith('dice_')) return CosmeticVisualKind.dice;
    if (id.startsWith('token_')) return CosmeticVisualKind.token;
    if (id.startsWith('ludo_board_')) return CosmeticVisualKind.ludoBoard;
    if (id.startsWith('snakes_board_')) return CosmeticVisualKind.snakesBoard;
    if (id.startsWith('trail_')) return CosmeticVisualKind.trail;
    if (id.startsWith('victory_')) return CosmeticVisualKind.victory;
    return null;
  }

  /// Whether [id] is a catalog id with a dedicated renderer.
  static bool isKnown(String? id) {
    final kind = kindOf(id);
    return kind != null && ids[kind]!.contains(id);
  }

  /// Whether a preview can be drawn for [id] (known, or an unknown id of a
  /// renderable kind that falls back to the starter).
  static bool canPreview(String? id) => kindOf(id) != null;

  /// [id] if known for [kind], else the starter of [kind].
  static String resolve(CosmeticVisualKind kind, String? id) =>
      ids[kind]!.contains(id) ? id! : starters[kind]!;

  static String dice(String? id) => DiceSkins.resolve(id);
  static String token(String? id) => TokenSkins.resolve(id);
  static String ludoBoard(String? id) => LudoBoardThemes.resolve(id);
  static String snakesBoard(String? id) => SnakesBoardThemes.resolve(id);
  static String trail(String? id) => TrailStyles.resolve(id);
  static String victory(String? id) => VictoryStyles.resolve(id);
}
