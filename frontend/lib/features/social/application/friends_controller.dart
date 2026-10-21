import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/protocol/protocol.dart';
import '../../../core/realtime/realtime_providers.dart';
import '../../leaderboard/application/leaderboard_controller.dart';
import '../../progression/application/meta_support.dart';
import '../data/social_api.dart';
import '../domain/social_models.dart';

/// Result of a friends action.
@immutable
sealed class FriendActionOutcome {
  const FriendActionOutcome();
}

final class FriendActionSucceeded extends FriendActionOutcome {
  const FriendActionSucceeded([this.friend]);

  /// The server's view of the other player (null for removals).
  final Friend? friend;
}

final class FriendActionIgnored extends FriendActionOutcome {
  const FriendActionIgnored();
}

final class FriendActionFailed extends FriendActionOutcome {
  const FriendActionFailed(this.error);
  final ApiException error;
}

/// Friends, incoming and outgoing requests (`GET /friends`) and the actions
/// on them. A `social.friend_request` push refreshes the lists.
class FriendsController extends AsyncNotifier<FriendsLists> {
  final Set<String> _inFlight = {};

  SocialApi get _api => ref.read(socialApiProvider);

  @override
  Future<FriendsLists> build() {
    ref.listen<AsyncValue<ServerEvent>>(socialEventsProvider, (_, next) {
      if (next.value is FriendRequestEvent) {
        unawaited(refresh().catchError((Object _) {}));
      }
    });
    return _api.friends();
  }

  Future<void> refresh() async {
    try {
      final lists = await _api.friends();
      if (ref.mounted) state = AsyncData(lists);
    } catch (e, s) {
      if (ref.mounted && !state.hasValue) state = AsyncError(e, s);
      rethrow;
    }
  }

  bool isBusy(String uid) => _inFlight.contains(uid);

  /// Sends a request to an already normalized [friendCode].
  Future<FriendActionOutcome> sendRequest(String friendCode) =>
      _run('code:$friendCode', () => _api.request(friendCode), upsert: true);

  /// Accepts an incoming request.
  Future<FriendActionOutcome> accept(String uid) =>
      _run(uid, () => _api.accept(uid), upsert: true);

  /// Declines an incoming request, cancels an outgoing one, or removes a
  /// friend (one endpoint).
  Future<FriendActionOutcome> remove(String uid) => _run(uid, () async {
    await _api.remove(uid);
    return null;
  }, removeUid: uid);

  Future<FriendActionOutcome> _run(
    String busyKey,
    Future<Friend?> Function() call, {
    bool upsert = false,
    String? removeUid,
  }) async {
    if (!_inFlight.add(busyKey)) return const FriendActionIgnored();
    try {
      final friend = await call();
      if (ref.mounted) {
        final lists = state.value ?? const FriendsLists();
        if (removeUid != null) state = AsyncData(lists.remove(removeUid));
        if (upsert && friend != null) state = AsyncData(lists.upsert(friend));
        // Friendships change the weekly friends leaderboard.
        ref.invalidate(friendsLeaderboardProvider);
      }
      return FriendActionSucceeded(friend);
    } on ApiException catch (e) {
      if (ref.mounted && !isTransientFailure(e)) {
        unawaited(refresh().catchError((Object _) {}));
      }
      return FriendActionFailed(e);
    } finally {
      _inFlight.remove(busyKey);
    }
  }
}

final friendsProvider = AsyncNotifierProvider<FriendsController, FriendsLists>(
  FriendsController.new,
  isAutoDispose: true,
  retry: noRetry,
);

/// Recent human opponents (`GET /social/recent`).
class RecentPlayersController extends AsyncNotifier<List<Friend>> {
  @override
  Future<List<Friend>> build() => ref.read(socialApiProvider).recent();

  Future<void> refresh() async {
    try {
      final list = await ref.read(socialApiProvider).recent();
      if (ref.mounted) state = AsyncData(list);
    } catch (e, s) {
      if (ref.mounted && !state.hasValue) state = AsyncError(e, s);
      rethrow;
    }
  }

  /// Reflects a server-confirmed relationship change locally.
  void applyStatus(String uid, FriendStatus status) {
    final list = state.value;
    if (list == null) return;
    state = AsyncData(
      List.unmodifiable([
        for (final p in list) p.uid == uid ? p.copyWith(status: status) : p,
      ]),
    );
  }
}

final recentPlayersProvider =
    AsyncNotifierProvider<RecentPlayersController, List<Friend>>(
      RecentPlayersController.new,
      isAutoDispose: true,
      retry: noRetry,
    );
