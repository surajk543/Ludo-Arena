import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/leaderboard_models.dart';

/// `GET /leaderboards/friends` (you + accepted friends, weekly XP).
class LeaderboardApi {
  LeaderboardApi(this._api);

  final ApiClient _api;

  /// Throws [ApiException].
  Future<FriendsLeaderboard> friends() async =>
      FriendsLeaderboard.fromJson(await _api.get('/leaderboards/friends'));
}

final leaderboardApiProvider = Provider<LeaderboardApi>(
  (ref) => LeaderboardApi(ref.watch(apiClientProvider)),
);
