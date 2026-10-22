/// Ludo Arena game-board rendering library (shared visuals).
///
/// Pure presentation: every widget renders and animates server-confirmed
/// state handed to it. Board widgets live in
/// `features/ludo/presentation/board/board.dart` and
/// `features/snakes_ladders/presentation/board/board.dart`.
library;

export 'board_cell.dart';
export 'boards_l10n.dart';
export 'cosmetics/cosmetic_previews.dart';
export 'cosmetics/cosmetic_visuals.dart';
export 'dice/dice_controller.dart';
export 'dice/dice_skins.dart';
export 'dice/dice_view.dart';
export 'effects/level_up_burst.dart';
export 'effects/victory_overlay.dart';
export 'game_palette.dart';
export 'motion/board_motion.dart'
    show
        BoardEffect,
        BoardEffectKind,
        RepaintSignal,
        TokenMotionState,
        TrailHistory;
export 'seat_color.dart';
export 'tokens/token_renderer.dart';
export 'trails/trail_renderer.dart';
