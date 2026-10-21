import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/protocol/json_read.dart';
import '../domain/store_models.dart';

/// Profile-picture REST endpoints (`/store/…`, shown as the Shop).
class StoreApi {
  StoreApi(this._api);

  final ApiClient _api;

  /// `GET /store/profile-pictures`. [excludeOwned] leaves out the pictures
  /// the player owns (the Shop; not with [StoreFilter.owned]). Throws
  /// [ApiException] (`bad_request` for a stale cursor).
  Future<StorePage> list({
    StoreFilter filter = StoreFilter.all,
    bool excludeOwned = false,
    String? cursor,
    int limit = kStorePageSize,
  }) async => StorePage.fromJson(
    await _api.get(
      '/store/profile-pictures',
      query: {
        'filter': filter.wire,
        if (excludeOwned) 'excludeOwned': 'true',
        'limit': '$limit',
        'cursor': ?cursor,
      },
    ),
  );

  /// `POST /store/profile-pictures/{id}/purchase` with [idempotencyKey].
  /// Throws [ApiException] (`insufficient_funds`, `already_owned`,
  /// `not_found`).
  Future<(ProfilePicture, Wallet)> purchase(
    String id, {
    required String idempotencyKey,
  }) async {
    final json = await _api.post(
      '/store/profile-pictures/${Uri.encodeComponent(id)}/purchase',
      idempotencyKey: idempotencyKey,
    );
    return (
      ProfilePicture.fromJson(readMap(json['item'])),
      Wallet.fromJson(readMap(json['wallet'])),
    );
  }

  /// `PUT /me/profile-picture`; a null [id] goes back to the built-in
  /// avatar. Returns the applied picture (null for the built-in avatar).
  /// Throws [ApiException] (`item_locked` when not owned, `not_found`).
  Future<ProfilePicture?> apply(String? id) async {
    final json = await _api.put('/me/profile-picture', body: {'id': id});
    final equipped = readMapOrNull(json['equipped']);
    return equipped == null ? null : ProfilePicture.fromJson(equipped);
  }
}

final storeApiProvider = Provider<StoreApi>(
  (ref) => StoreApi(ref.watch(apiClientProvider)),
);
