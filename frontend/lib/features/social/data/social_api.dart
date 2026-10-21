import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/protocol/json_read.dart';
import '../domain/social_models.dart';

/// Friends and recent-opponent REST endpoints.
class SocialApi {
  SocialApi(this._api);

  final ApiClient _api;

  /// `GET /friends`. Throws [ApiException].
  Future<FriendsLists> friends() async =>
      FriendsLists.fromJson(await _api.get('/friends'));

  /// `POST /friends/requests`. Auto-accepts when they already requested me
  /// (`status: friend`). Throws [ApiException] (`not_found`,
  /// `already_friends`, `cannot_friend_self`, `friend_limit`).
  Future<Friend> request(String friendCode) async {
    final json = await _api.post(
      '/friends/requests',
      body: {'friendCode': friendCode},
    );
    return Friend.fromJson(readMap(json['friend']));
  }

  /// `POST /friends/requests/{uid}/accept`.
  Future<Friend> accept(String uid) async {
    final json = await _api.post(
      '/friends/requests/${Uri.encodeComponent(uid)}/accept',
    );
    return Friend.fromJson(readMap(json['friend']));
  }

  /// `DELETE /friends/{uid}`: removes a friend, declines an incoming or
  /// cancels an outgoing request.
  Future<void> remove(String uid) =>
      _api.delete('/friends/${Uri.encodeComponent(uid)}');

  /// `GET /social/recent`: last 20 human opponents (14 days), newest first.
  Future<List<Friend>> recent() async =>
      Friend.listFrom((await _api.get('/social/recent'))['players']);
}

final socialApiProvider = Provider<SocialApi>(
  (ref) => SocialApi(ref.watch(apiClientProvider)),
);
