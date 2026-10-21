import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/protocol/protocol.dart';
import '../../../core/realtime/realtime_providers.dart';

/// A server-confirmed level-up to celebrate.
@immutable
class LevelUpCelebration {
  const LevelUpCelebration({required this.level, this.unlocked = const []});

  /// The level reached.
  final int level;

  /// Item ids newly added to the collection (milestones and rewards).
  final List<String> unlocked;
}

@immutable
class LevelUpState {
  const LevelUpState({
    this.pending = const [],
    this.showing = false,
    this.highestCelebrated = 0,
  });

  /// Level-ups waiting to be shown (ascending by level).
  final List<LevelUpCelebration> pending;

  /// A celebration is on screen right now.
  final bool showing;

  /// Highest level already shown (or being shown); later duplicates of the
  /// same level (claim response + `progression.updated`) are ignored.
  final int highestCelebrated;

  bool get hasPending => pending.isNotEmpty;

  LevelUpState copyWith({
    List<LevelUpCelebration>? pending,
    bool? showing,
    int? highestCelebrated,
  }) => LevelUpState(
    pending: pending ?? this.pending,
    showing: showing ?? this.showing,
    highestCelebrated: highestCelebrated ?? this.highestCelebrated,
  );
}

/// Queues level-up celebrations from `progression.updated` pushes and claim
/// responses. Hosts ([LevelUpCelebrationHost]) take them with [takeNext]
/// only when the user is NOT in a match, so a level-up earned in a game is
/// celebrated after the match screen closes.
class LevelUpController extends Notifier<LevelUpState> {
  @override
  LevelUpState build() {
    ref.listen<AsyncValue<ProgressionUpdatedEvent>>(
      progressionUpdatesProvider,
      (_, next) {
        final e = next.value;
        if (e != null && e.levelUp) enqueue(e.level, e.unlocked);
      },
    );
    return const LevelUpState();
  }

  /// Adds a server-confirmed level-up. Same-level duplicates merge their
  /// unlocked items; levels already celebrated are ignored.
  void enqueue(int level, Iterable<String> unlocked) {
    if (level <= state.highestCelebrated) return;
    final items = unlocked.where((id) => id.isNotEmpty).toList();
    final list = [...state.pending];
    final i = list.indexWhere((c) => c.level == level);
    if (i >= 0) {
      list[i] = LevelUpCelebration(
        level: level,
        unlocked: {...list[i].unlocked, ...items}.toList(),
      );
    } else {
      list
        ..add(LevelUpCelebration(level: level, unlocked: items))
        ..sort((a, b) => a.level.compareTo(b.level));
    }
    state = state.copyWith(pending: List.unmodifiable(list));
  }

  /// Takes everything pending as ONE celebration (the highest level with
  /// all unlocked items), or null when nothing is pending or one is
  /// already showing. Call [markShown] when it closes.
  LevelUpCelebration? takeNext() {
    if (state.showing || state.pending.isEmpty) return null;
    final top = state.pending.last;
    final items = <String>{for (final c in state.pending) ...c.unlocked};
    state = LevelUpState(showing: true, highestCelebrated: top.level);
    return LevelUpCelebration(level: top.level, unlocked: items.toList());
  }

  void markShown() {
    if (state.showing) state = state.copyWith(showing: false);
  }
}

final levelUpControllerProvider =
    NotifierProvider<LevelUpController, LevelUpState>(LevelUpController.new);
