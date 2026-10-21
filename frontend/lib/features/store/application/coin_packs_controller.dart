import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../authentication/application/session_controller.dart';
import '../data/coin_pack_api.dart';
import '../domain/coin_pack_models.dart';
import '../iap/iap_store.dart';

/// The Shop's coin packs: the server catalogue (amounts, fallback prices,
/// the account token) plus the store's localized products when the store
/// knows them.
@immutable
class CoinPacksState {
  const CoinPacksState({
    this.catalog,
    this.loading = true,
    this.error,
    this.products = const {},
    this.storeAvailable,
  });

  final CoinPackCatalog? catalog;

  /// The catalogue is loading and nothing is shown yet.
  final bool loading;

  /// The catalogue failed (full error with Retry).
  final ApiException? error;

  /// Store products by product id (missing: not configured in the store
  /// yet, or the store is unavailable — the card shows the fallback price).
  final Map<String, ProductDetails> products;

  /// Null until the store answered.
  final bool? storeAvailable;

  List<CoinPack> get packs => catalog?.packs ?? const [];

  ProductDetails? productFor(CoinPack pack) => products[pack.productId];

  CoinPacksState copyWith({
    CoinPackCatalog? catalog,
    bool? loading,
    ApiException? error,
    bool clearError = false,
    Map<String, ProductDetails>? products,
    bool? storeAvailable,
  }) => CoinPacksState(
    catalog: catalog ?? this.catalog,
    loading: loading ?? this.loading,
    error: clearError ? null : (error ?? this.error),
    products: products ?? this.products,
    storeAvailable: storeAvailable ?? this.storeAvailable,
  );
}

/// Loads `GET /store/coin-packs` for the signed-in account (reloaded when
/// the account changes: the account token is per account), then asks the
/// store for the localized products.
class CoinPacksController extends Notifier<CoinPacksState> {
  int _generation = 0;

  @override
  CoinPacksState build() {
    final userId = ref.watch(
      sessionControllerProvider.select((s) => s.user?.id),
    );
    final gen = ++_generation;
    if (userId == null) return const CoinPacksState(loading: false);
    unawaited(Future<void>.microtask(() => _load(gen)));
    return const CoinPacksState();
  }

  /// Pull to refresh / Retry. Throws [ApiException] when packs were already
  /// shown (they stay on screen).
  Future<void> refresh() async {
    final gen = ++_generation;
    final had = state.catalog != null;
    if (!had) state = const CoinPacksState();
    final error = await _load(gen);
    if (error != null && had) throw error;
  }

  Future<ApiException?> _load(int gen) async {
    try {
      final catalog = await ref.read(coinPackApiProvider).list();
      if (!ref.mounted || gen != _generation) return null;
      state = state.copyWith(
        catalog: catalog,
        loading: false,
        clearError: true,
      );
      await _loadProducts(catalog, gen);
      return null;
    } catch (error) {
      final e = error is ApiException
          ? error
          : const ApiException(code: ClientErrorCodes.badResponse, status: 0);
      if (!ref.mounted || gen != _generation) return e;
      if (state.catalog == null) {
        state = state.copyWith(loading: false, error: e);
      }
      return e;
    }
  }

  Future<void> _loadProducts(CoinPackCatalog catalog, int gen) async {
    final store = ref.read(iapStoreProvider);
    var available = false;
    var list = const <ProductDetails>[];
    try {
      available = await store.isAvailable();
      if (available) list = await store.queryProducts(catalog.productIds);
    } catch (e) {
      // Not configured in the store yet, offline, … : fallback prices.
      if (kDebugMode) debugPrint('iap: product query failed ($e)');
    }
    if (!ref.mounted || gen != _generation) return;
    state = state.copyWith(
      storeAvailable: available,
      products: {for (final p in list) p.id: p},
    );
  }
}

final coinPacksProvider = NotifierProvider<CoinPacksController, CoinPacksState>(
  CoinPacksController.new,
);
