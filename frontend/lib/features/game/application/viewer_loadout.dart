import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../authentication/application/session_controller.dart';

/// The viewer's equipped board cosmetics. Boards are a personal view (the
/// room snapshot carries only dice/token/frame/trail/victory per player).
typedef ViewerBoardThemes = ({String? ludo, String? snakes});

final viewerBoardThemesProvider = Provider<ViewerBoardThemes>((ref) {
  final loadout = ref.watch(
    sessionControllerProvider.select((s) => s.user?.loadout),
  );
  return (ludo: loadout?.ludoBoard, snakes: loadout?.snakesBoard);
});
