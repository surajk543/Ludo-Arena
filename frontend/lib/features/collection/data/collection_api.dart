import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/protocol/json_read.dart';
import '../domain/collection_models.dart';

/// Collection Room REST endpoints.
class CollectionApi {
  CollectionApi(this._api);

  final ApiClient _api;

  /// `GET /collection`. Throws [ApiException].
  Future<CollectionData> fetch() async =>
      CollectionData.fromJson(await _api.get('/collection'));

  /// `PUT /collection/loadout`; a null [itemId] resets the slot to its
  /// starter item. Throws [ApiException] (`item_locked`, …).
  Future<Loadout> equip(String slot, String? itemId) async {
    final json = await _api.put(
      '/collection/loadout',
      body: {'slot': slot, 'itemId': itemId},
    );
    return Loadout.fromJson(readMap(json['loadout']));
  }

  /// `POST /collection/items/{itemId}/purchase` with [idempotencyKey].
  /// Throws [ApiException] (`insufficient_funds`, `already_owned`,
  /// `item_locked`, `not_found`).
  Future<(CollectionItem, Wallet)> purchase(
    String itemId, {
    required String idempotencyKey,
  }) async {
    final json = await _api.post(
      '/collection/items/${Uri.encodeComponent(itemId)}/purchase',
      idempotencyKey: idempotencyKey,
    );
    return (
      CollectionItem.fromJson(readMap(json['item'])),
      Wallet.fromJson(readMap(json['wallet'])),
    );
  }
}

final collectionApiProvider = Provider<CollectionApi>(
  (ref) => CollectionApi(ref.watch(apiClientProvider)),
);
