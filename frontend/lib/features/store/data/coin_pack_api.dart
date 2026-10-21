import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/coin_pack_models.dart';

/// Coin pack REST endpoints (docs/rest-api.md → Coin packs).
class CoinPackApi {
  CoinPackApi(this._api);

  final ApiClient _api;

  /// `GET /store/coin-packs` (product ids for this app's platform).
  Future<CoinPackCatalog> list() async =>
      CoinPackCatalog.fromJson(await _api.get('/store/coin-packs'));

  /// `POST /store/purchases`: the server verifies the purchase with the
  /// store and grants the pack exactly once (a repeat answers the original
  /// grant with `replayed: true`). Throws [ApiException]
  /// (`iap_unavailable`, `purchase_invalid`, `purchase_pending`, …).
  ///
  /// Android sends the Play purchase token; iOS the StoreKit 2 transaction
  /// id and its signed JWS.
  Future<CoinPurchaseGrant> submit({
    required String platform,
    required String productId,
    String? purchaseToken,
    String? transactionId,
    String? signedTransaction,
  }) async => CoinPurchaseGrant.fromJson(
    await _api.post(
      '/store/purchases',
      body: {
        'platform': platform,
        'productId': productId,
        'purchaseToken': ?purchaseToken,
        'transactionId': ?transactionId,
        'signedTransaction': ?signedTransaction,
      },
    ),
  );
}

final coinPackApiProvider = Provider<CoinPackApi>(
  (ref) => CoinPackApi(ref.watch(apiClientProvider)),
);
