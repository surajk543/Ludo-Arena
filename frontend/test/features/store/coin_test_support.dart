import 'dart:async';

import 'package:ludo_royale/features/store/iap/iap_store.dart';

import '../../helpers/fake_backend.dart';
import '../../helpers/harness.dart';

/// The account token `GET /store/coin-packs` hands out in tests.
const String kTestAccountToken = '7f1c2a9e-4b3d-4c8e-9f10-2a3b4c5d6e7f';

Map<String, dynamic> coinPackJson(
  String id,
  String label,
  int coins,
  int diamonds,
  int rupees, {
  String? badge,
  int sortOrder = 0,
}) => {
  'id': id,
  'productId': id,
  'label': label,
  'coins': coins,
  'diamonds': diamonds,
  'fallbackPrice': {'currency': 'INR', 'amount': rupees},
  'badge': badge,
  'sortOrder': sortOrder,
};

/// The four packs of `backend/config/coin_packs.json` (listed out of order:
/// the app sorts by `sortOrder`).
List<Map<String, dynamic>> coinPacks() => [
  coinPackJson(
    'coins_best_value',
    'Best Value',
    35000000,
    250,
    999,
    badge: 'best_value',
    sortOrder: 4,
  ),
  coinPackJson('coins_starter', 'Starter', 5000000, 5, 199, sortOrder: 1),
  coinPackJson(
    'coins_popular',
    'Popular',
    8000000,
    8,
    299,
    badge: 'popular',
    sortOrder: 2,
  ),
  coinPackJson(
    'coins_great_value',
    'Great Value',
    15000000,
    100,
    499,
    sortOrder: 3,
  ),
];

Map<String, dynamic> coinCatalogJson({
  bool available = true,
  List<Map<String, dynamic>>? packs,
}) => {
  'packs': packs ?? coinPacks(),
  'purchasesAvailable': available,
  'accountToken': kTestAccountToken,
};

/// Routes `GET /store/coin-packs`.
void routeCoinPacks(TestEnv env, {bool available = true}) => env.backend.json(
  'GET',
  '/store/coin-packs',
  coinCatalogJson(available: available),
);

/// `POST /store/purchases` 200 body.
Map<String, dynamic> grantJson(
  String packId, {
  int coins = 5000000,
  int diamonds = 5,
  int walletCoins = 6000000,
  int walletDiamonds = 55,
  bool replayed = false,
}) => {
  'wallet': {'coins': walletCoins, 'diamonds': walletDiamonds},
  'granted': {'coins': coins, 'diamonds': diamonds},
  'pack': coinPacks().firstWhere((p) => p['id'] == packId),
  'replayed': replayed,
};

/// A store product as Google Play would describe it.
ProductDetails storeProduct(
  String id, {
  required String price,
  required double rawPrice,
  String currency = 'INR',
}) => ProductDetails(
  id: id,
  title: id,
  description: id,
  price: price,
  rawPrice: rawPrice,
  currencyCode: currency,
);

/// A purchase update from the store.
PurchaseDetails storePurchase(
  String productId, {
  PurchaseStatus status = PurchaseStatus.purchased,
  String token = 'play-token-1',
  String? transactionId,
}) => PurchaseDetails(
  purchaseID: transactionId ?? 'GPA.0000-$token',
  productID: productId,
  verificationData: PurchaseVerificationData(
    localVerificationData: '{}',
    serverVerificationData: token,
    source: 'test',
  ),
  transactionDate: '1761022800000',
  status: status,
)..pendingCompletePurchase = status != PurchaseStatus.pending;

/// A scriptable [IapStore]: products, availability, the purchase stream,
/// and every call the app made.
class FakeIapStore implements IapStore {
  FakeIapStore({this.available = true, Map<String, ProductDetails>? products})
    : products = products ?? {};

  final StreamController<List<PurchaseDetails>> updates =
      StreamController<List<PurchaseDetails>>.broadcast();

  bool available;
  final Map<String, ProductDetails> products;

  /// What [buyConsumable] answers (false: the store refused to open).
  bool openSheet = true;

  /// When set, [buyConsumable] immediately reports this status for the
  /// product (as the store would after the sheet closed).
  PurchaseStatus? autoResult;
  int _tokens = 0;

  final List<(String productId, String? accountToken)> buys = [];
  final List<PurchaseDetails> finished = [];
  final List<PurchaseDetails> dismissed = [];
  int redeliveries = 0;

  /// Purchases re-delivered by [redeliverPending] (Android restore).
  final List<PurchaseDetails> unconsumed = [];

  void emit(List<PurchaseDetails> purchases) => updates.add(purchases);

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => updates.stream;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<List<ProductDetails>> queryProducts(Set<String> productIds) async => [
    for (final id in productIds)
      if (products[id] != null) products[id]!,
  ];

  @override
  Future<bool> buyConsumable(
    ProductDetails product, {
    String? accountToken,
  }) async {
    buys.add((product.id, accountToken));
    if (!openSheet) return false;
    final result = autoResult;
    if (result != null) {
      final p = storePurchase(
        product.id,
        status: result,
        token: 'play-token-${++_tokens}',
      );
      scheduleMicrotask(() => emit([p]));
    }
    return true;
  }

  @override
  Future<void> finish(PurchaseDetails purchase) async {
    finished.add(purchase);
    unconsumed.removeWhere(
      (p) =>
          p.verificationData.serverVerificationData ==
          purchase.verificationData.serverVerificationData,
    );
  }

  @override
  Future<void> dismiss(PurchaseDetails purchase) async =>
      dismissed.add(purchase);

  @override
  Future<void> redeliverPending() async {
    redeliveries++;
    if (unconsumed.isNotEmpty) {
      emit([
        for (final p in unconsumed)
          storePurchase(
            p.productID,
            status: PurchaseStatus.restored,
            token: p.verificationData.serverVerificationData,
          ),
      ]);
    }
  }

  Future<void> close() => updates.close();
}

/// Error helper re-exported for the coin tests.
FakeResponse coinError(int status, String code) =>
    FakeResponse.error(status, code);
