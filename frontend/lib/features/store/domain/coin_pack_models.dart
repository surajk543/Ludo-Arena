import 'package:flutter/foundation.dart';

import '../../../core/network/api_models.dart';
import '../../../core/protocol/json_read.dart';

/// Highlight of a coin pack card (`badge` of `GET /store/coin-packs`).
enum CoinPackBadge {
  none,
  popular,
  bestValue;

  static CoinPackBadge parse(Object? raw) => switch (raw) {
    'popular' => popular,
    'best_value' => bestValue,
    _ => none,
  };
}

/// Fallback display price of a pack (major currency units), shown while the
/// store's localized price is unknown (store unavailable, product not
/// configured yet, or still loading).
@immutable
class CoinPackPrice {
  const CoinPackPrice({required this.currency, required this.amount});

  factory CoinPackPrice.fromJson(Map<String, dynamic> j) => CoinPackPrice(
    currency: readString(j['currency'], 'INR').toUpperCase(),
    amount: readInt(j['amount']),
  );

  /// ISO 4217 code, e.g. `INR`.
  final String currency;

  /// Whole major units (₹199 → 199).
  final int amount;
}

/// A coin pack sold for real money through Google Play / the App Store.
/// The amounts are display only: the server grants them from its own
/// configuration after verifying the purchase with the store.
@immutable
class CoinPack {
  const CoinPack({
    required this.id,
    required this.productId,
    required this.label,
    required this.coins,
    required this.diamonds,
    required this.fallbackPrice,
    this.badge = CoinPackBadge.none,
    this.sortOrder = 0,
  });

  factory CoinPack.fromJson(Map<String, dynamic> j) {
    final id = readString(j['id']);
    return CoinPack(
      id: id,
      productId: readString(j['productId'], id),
      label: readString(j['label']),
      coins: readInt(j['coins']),
      diamonds: readInt(j['diamonds']),
      fallbackPrice: CoinPackPrice.fromJson(readMap(j['fallbackPrice'])),
      badge: CoinPackBadge.parse(j['badge']),
      sortOrder: readInt(j['sortOrder']),
    );
  }

  /// Stable pack id (`coins_starter`).
  final String id;

  /// Store product id for this platform.
  final String productId;

  /// English label from the server (the app shows its own translation for
  /// known ids, see `CoinPackTexts`).
  final String label;
  final int coins;
  final int diamonds;
  final CoinPackPrice fallbackPrice;
  final CoinPackBadge badge;
  final int sortOrder;

  bool get highlighted => badge != CoinPackBadge.none;

  /// Analytics `pack` value: the label as a slug (`great_value`), never an
  /// id or a store product id.
  String get analyticsSlug {
    final known = switch (id) {
      'coins_starter' => 'starter',
      'coins_popular' => 'popular',
      'coins_great_value' => 'great_value',
      'coins_best_value' => 'best_value',
      _ => null,
    };
    if (known != null) return known;
    return label
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
  }
}

/// `GET /store/coin-packs`.
@immutable
class CoinPackCatalog {
  const CoinPackCatalog({
    required this.packs,
    this.purchasesAvailable = false,
    this.accountToken,
  });

  factory CoinPackCatalog.fromJson(Map<String, dynamic> j) {
    final packs = [
      for (final p in readList(j['packs']))
        if (p is Map) CoinPack.fromJson(p.cast<String, dynamic>()),
    ]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return CoinPackCatalog(
      packs: List.unmodifiable(packs),
      purchasesAvailable: readBool(j['purchasesAvailable']),
      accountToken: readStringOrNull(j['accountToken']),
    );
  }

  /// In display order.
  final List<CoinPack> packs;

  /// The server can verify purchases for this platform. When false the
  /// packs are still listed; Buy explains they are not available yet.
  final bool purchasesAvailable;

  /// Passed to the store as `applicationUserName` (Google
  /// obfuscatedAccountId / Apple appAccountToken). The server only grants a
  /// purchase that carries the caller's token. Never logged or sent to
  /// analytics.
  final String? accountToken;

  CoinPack? byProductId(String productId) {
    for (final p in packs) {
      if (p.productId == productId) return p;
    }
    return null;
  }

  Set<String> get productIds => {for (final p in packs) p.productId};
}

/// `POST /store/purchases` → 200.
@immutable
class CoinPurchaseGrant {
  const CoinPurchaseGrant({
    required this.wallet,
    required this.coins,
    required this.diamonds,
    required this.pack,
    this.replayed = false,
  });

  factory CoinPurchaseGrant.fromJson(Map<String, dynamic> j) {
    final granted = readMap(j['granted']);
    final pack = readMapOrNull(j['pack']);
    return CoinPurchaseGrant(
      wallet: Wallet.fromJson(readMap(j['wallet'])),
      coins: readInt(granted['coins']),
      diamonds: readInt(granted['diamonds']),
      pack: pack == null ? null : CoinPack.fromJson(pack),
      replayed: readBool(j['replayed']),
    );
  }

  /// Balance after the grant (authoritative).
  final Wallet wallet;

  /// What this purchase granted (also when [replayed]).
  final int coins;
  final int diamonds;
  final CoinPack? pack;

  /// The purchase had already been granted earlier: nothing new was added.
  final bool replayed;
}

/// Store product ids that are coin packs even before the catalogue loaded
/// (purchases re-delivered at startup).
bool isCoinPackProductId(String productId) => productId.startsWith('coins_');
