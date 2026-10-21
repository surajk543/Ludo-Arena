import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

export 'package:in_app_purchase/in_app_purchase.dart'
    show
        IAPError,
        ProductDetails,
        PurchaseDetails,
        PurchaseStatus,
        PurchaseVerificationData;

/// The platform store (Google Play Billing / StoreKit 2) behind a small
/// seam, so the purchase flow is testable with a fake.
///
/// The app never decides what a purchase is worth: it forwards the store's
/// proof to `POST /store/purchases` and only consumes (Android) or finishes
/// (iOS) the purchase after the server granted it.
abstract interface class IapStore {
  /// Every purchase update (new, restored, re-delivered at startup).
  Stream<List<PurchaseDetails>> get purchaseStream;

  /// Whether the store can be used on this device right now.
  Future<bool> isAvailable();

  /// Store products for [productIds]; unknown ids are left out.
  Future<List<ProductDetails>> queryProducts(Set<String> productIds);

  /// Starts the store's purchase sheet for a consumable. [accountToken]
  /// binds the purchase to the account (Google obfuscatedAccountId / Apple
  /// appAccountToken). Never auto-consumed: see [finish].
  Future<bool> buyConsumable(ProductDetails product, {String? accountToken});

  /// After the server granted [purchase]: consume it (Android, so the pack
  /// can be bought again) or finish the transaction (iOS).
  Future<void> finish(PurchaseDetails purchase);

  /// Clears a purchase that will never be granted (cancelled / failed) from
  /// the store queue when the store asks for it.
  Future<void> dismiss(PurchaseDetails purchase);

  /// Android: re-delivers unconsumed purchases (status `restored`). No-op on
  /// iOS, where StoreKit 2 re-delivers unfinished transactions by itself.
  Future<void> redeliverPending();
}

/// A store that is never available (tests, desktop, web).
class UnavailableIapStore implements IapStore {
  const UnavailableIapStore();

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => const Stream.empty();

  @override
  Future<bool> isAvailable() async => false;

  @override
  Future<List<ProductDetails>> queryProducts(Set<String> productIds) async =>
      const [];

  @override
  Future<bool> buyConsumable(
    ProductDetails product, {
    String? accountToken,
  }) async => false;

  @override
  Future<void> finish(PurchaseDetails purchase) async {}

  @override
  Future<void> dismiss(PurchaseDetails purchase) async {}

  @override
  Future<void> redeliverPending() async {}
}

/// The `in_app_purchase` plugin.
class PluginIapStore implements IapStore {
  PluginIapStore({required this.android});

  /// Google Play (true) or the App Store (false).
  final bool android;

  InAppPurchase get _iap => InAppPurchase.instance;

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => _iap.purchaseStream;

  @override
  Future<bool> isAvailable() async {
    try {
      return await _iap.isAvailable();
    } catch (e) {
      if (kDebugMode) debugPrint('iap: isAvailable failed ($e)');
      return false;
    }
  }

  @override
  Future<List<ProductDetails>> queryProducts(Set<String> productIds) async {
    if (productIds.isEmpty) return const [];
    final res = await _iap.queryProductDetails(productIds);
    return res.productDetails;
  }

  @override
  Future<bool> buyConsumable(ProductDetails product, {String? accountToken}) =>
      _iap.buyConsumable(
        purchaseParam: PurchaseParam(
          productDetails: product,
          applicationUserName: accountToken,
        ),
        // Consumed only after the server granted the pack (finish).
        autoConsume: false,
      );

  @override
  Future<void> finish(PurchaseDetails purchase) async {
    if (android) {
      await _iap
          .getPlatformAddition<InAppPurchaseAndroidPlatformAddition>()
          .consumePurchase(purchase);
    } else if (purchase.pendingCompletePurchase) {
      await _iap.completePurchase(purchase);
    }
  }

  @override
  Future<void> dismiss(PurchaseDetails purchase) async {
    // Android has nothing to clear for a cancelled or failed purchase.
    if (!android && purchase.pendingCompletePurchase) {
      await _iap.completePurchase(purchase);
    }
  }

  @override
  Future<void> redeliverPending() async {
    if (android) await _iap.restorePurchases();
  }
}

/// The device's store: the plugin on Android and iOS, otherwise
/// [UnavailableIapStore] (widget tests run on the host and never touch the
/// platform channels).
final iapStoreProvider = Provider<IapStore>((ref) {
  if (kIsWeb) return const UnavailableIapStore();
  if (Platform.isAndroid) return PluginIapStore(android: true);
  if (Platform.isIOS) return PluginIapStore(android: false);
  return const UnavailableIapStore();
});
