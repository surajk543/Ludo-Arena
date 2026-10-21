import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/protocol/protocol.dart';
import '../../../core/realtime/realtime_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/widgets/widgets.dart';
import '../../ludo/presentation/screens/ludo_game_screen.dart';
import '../../snakes_ladders/presentation/screens/snakes_game_screen.dart';
import 'play_nav.dart';

/// `/game/:roomId` — picks the Ludo or Snakes & Ladders match screen for
/// the active room. When the room is not held yet (cold start / deep link),
/// it asks the server for a snapshot and waits briefly.
class GameRouteScreen extends ConsumerStatefulWidget {
  const GameRouteScreen({super.key, required this.roomId});

  final String roomId;

  @override
  ConsumerState<GameRouteScreen> createState() => _GameRouteScreenState();
}

class _GameRouteScreenState extends ConsumerState<GameRouteScreen> {
  String? _game;
  bool _timedOut = false;
  bool _redirecting = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    final room = ref.read(activeRoomControllerProvider).room;
    if (room?.id != widget.roomId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref
            .read(activeRoomControllerProvider.notifier)
            .requestSync(roomId: widget.roomId);
      });
      _timer = Timer(const Duration(seconds: 12), () {
        if (mounted && _game == null) setState(() => _timedOut = true);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final live = ref.watch(activeRoomControllerProvider);
    final room = live.room;
    // Latch the game once the room is known: the match screen owns every
    // later transition (rematch, leave, room closed).
    if (_game == null && room != null && room.id == widget.roomId) {
      _game = room.game;
      _timer?.cancel();
    }
    final game = _game;
    if (game != null) {
      return game == GameIds.snakesLadders
          ? SnakesGameScreen(roomId: widget.roomId)
          : LudoGameScreen(roomId: widget.roomId);
    }

    // The user is in a different live room: go there.
    if (room != null &&
        room.id != widget.roomId &&
        (room.isPlaying || room.isLobby) &&
        !_redirecting) {
      _redirecting = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) PlayNav.toRoom(context, room);
      });
    }

    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: LayeredBackground(
        child: SafeArea(
          child: _timedOut
              ? EmptyState(
                  title: l10n.playMatchUnavailable,
                  action: PremiumButton(
                    label: l10n.playBackHome,
                    icon: Icons.home_rounded,
                    expand: false,
                    size: PremiumButtonSize.medium,
                    onPressed: () => PlayNav.home(context),
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: LoadingState(message: l10n.playLoadingMatch),
                ),
        ),
      ),
    );
  }
}
