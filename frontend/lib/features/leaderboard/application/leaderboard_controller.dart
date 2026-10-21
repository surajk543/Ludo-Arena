import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../progression/application/meta_support.dart';
import '../data/leaderboard_api.dart';
import '../domain/leaderboard_models.dart';

/// Weekly friends leaderboard.
class LeaderboardController extends AsyncNotifier<FriendsLeaderboard> {
  @override
  Future<FriendsLeaderboard> build() =>
      ref.read(leaderboardApiProvider).friends();

  Future<void> refresh() async {
    try {
      final lb = await ref.read(leaderboardApiProvider).friends();
      if (ref.mounted) state = AsyncData(lb);
    } catch (e, s) {
      if (ref.mounted && !state.hasValue) state = AsyncError(e, s);
      rethrow;
    }
  }
}

final friendsLeaderboardProvider =
    AsyncNotifierProvider<LeaderboardController, FriendsLeaderboard>(
      LeaderboardController.new,
      isAutoDispose: true,
      retry: noRetry,
    );
