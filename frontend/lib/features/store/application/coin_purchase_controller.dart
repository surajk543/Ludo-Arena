import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/analytics/analytics_providers.dart';
import '../../../core/config/app_info.dart';
import '../../../core/network/api_client.dart';
import '../../authentication/application/session_controller.dart';
import '../../wallet/wallet_controller.dart';
import '../data/coin_pack_api.dart';
import '../domain/coin_pack_models.dart';
import '../iap/iap_store.dart';
import 'coin_packs_controller.dart';

/// What [CoinPurchaseController.buy] did right away. The outcome of the
/// purchase itself arrives later as a [CoinPurchaseNotice].
enum CoinBuyResult {
  /// The store's purchase sheet was opened.
  started,

  /// The store or the product is not available (yet): "This pack isn't
  /// available yet".
  unavailable,

  /// A purchase of this pack is already being opened or delivered.
  busy,

  /// The store refused to open the purchase.
  failed,
}

/// Kinds of [CoinPurchaseNotice].
enum CoinNoticeKind {
  /// The server granted the pack.
  granted,

  /// The payment is pending (e.g. a slow payment method).
  pending,

  /// The server or the store refused the purchase ([CoinPurchaseNotice.code]
  /// is the server error code, null for a store failure).
  failed,

  /// The server could not be reached: the purchase stays with the store and
  /// is delivered on a later attempt (next app start at the latest).
  delayed,
}

/// Something to tell the player about a purchase (shown once by a
/// `CoinPurchaseHost`).
@immutable
class CoinPurchaseNotice {
  const CoinPurchaseNotice(
    this.kind, {
    this.code,
    this.pack,
    this.coins = 0,
    this.diamonds = 0,
  });

  final CoinNoticeKind kind;
  final String? code;
  final CoinPack? pack;
  final int coins;
  final int diamonds;
}

@immutable
class CoinPurchaseState {
  const CoinPurchaseState({this.busy = const {}, this.notices = const []});

  /// Product ids whose purchase is being opened or delivered.
  final Set<String> busy;

  /// Undelivered notices, oldest first.
  final List<CoinPurchaseNotice> notices;

  bool isBusy(String productId) => busy.contains(productId);

  CoinPurchaseState copyWith({
    Set<String>? busy,
    List<CoinPurchaseNotice>? notices,
  }) => CoinPurchaseState(
    busy: busy ?? this.busy,
    notices: notices ?? this.notices,
  );
}

/// Retry policy of `POST /store/purchases` (network errors and 5xx).
@immutable
class CoinDeliveryRetry {
  const CoinDeliveryRetry({
    this.attempts = 4,
    this.baseDelay = const Duration(seconds: 1),
    this.sleep = _sleep,
  });

  /// Total attempts per delivery.
  final int attempts;

  /// Doubled after every failed attempt (1 s, 2 s, 4 s).
  final Duration baseDelay;
  final Future<void> Function(Duration) sleep;

  static Future<void> _sleep(Duration d) => Future<void>.delayed(d);
}

final coinDeliveryRetryProvider = Provider<CoinDeliveryRetry>(
  (ref) => const CoinDeliveryRetry(),
);

/// Coin pack purchases, from the store sheet to the server grant.
///
/// Created at app start (`app.dart`) so it listens to the store's purchase
/// stream before anything else: purchases that were paid but never
/// delivered (app killed, server unreachable, …) are re-delivered by the
/// store when the app starts (StoreKit 2 by itself; Google Play through
/// [IapStore.redeliverPending] after sign-in) and are delivered here.
///
/// A purchase is consumed (Android) or finished (iOS) only after
/// `POST /store/purchases` answered 200. On any refusal it stays with the
/// store, so it is offered again on the next start. Purchases that arrive
/// while signed out wait for the sign-in. The server grants a purchase
/// exactly once (a repeat answers `replayed: true`), so delivering twice is
/// harmless; this controller still de-duplicates by purchase.
class CoinPurchaseController extends Notifier<CoinPurchaseState> {
  StreamSubscription<List<PurchaseDetails>>? _sub;

  /// Purchases waiting for a signed-in account, by purchase key.
  final Map<String, PurchaseDetails> _waiting = {};

  /// Purchase keys being delivered right now.
  final Set<String> _inFlight = {};

  /// Purchase keys the server granted during this run.
  final Set<String> _granted = {};

  /// Purchase keys already celebrated / failure notices already shown.
  final Set<String> _celebrated = {};
  final Set<String> _reported = {};

  /// Product ids bought from the Shop during this run (a live purchase is
  /// celebrated even when its first delivery's answer was lost).
  final Set<String> _live = {};

  /// Account the Android re-delivery last ran for.
  String? _redeliveredFor;

  IapStore get _store => ref.read(iapStoreProvider);

  @override
  CoinPurchaseState build() {
    final store = ref.watch(iapStoreProvider);
    _sub = store.purchaseStream.listen(
      _onUpdates,
      onError: (Object e) {
        if (kDebugMode) debugPrint('iap: purchase stream error ($e)');
      },
    );
    ref.onDispose(() => _sub?.cancel());
    ref.listen<String?>(sessionControllerProvider.select((s) => s.user?.id), (
      _,
      userId,
    ) {
      if (userId != null) _onSignedIn(userId);
    });
    final userId = ref.read(sessionControllerProvider).user?.id;
    if (userId != null) {
      scheduleMicrotask(() {
        if (ref.mounted) _onSignedIn(userId);
      });
    }
    return const CoinPurchaseState();
  }

  /// Opens the store's purchase sheet for [pack]. The result of the payment
  /// arrives on the purchase stream.
  Future<CoinBuyResult> buy(CoinPack pack) async {
    final productId = pack.productId;
    if (state.isBusy(productId)) return CoinBuyResult.busy;
    final packs = ref.read(coinPacksProvider);
    final catalog = packs.catalog;
    final product = packs.products[productId];
    if (catalog == null || !catalog.purchasesAvailable || product == null) {
      return CoinBuyResult.unavailable;
    }
    _setBusy(productId, true);
    try {
      if (!await _store.isAvailable()) {
        _setBusy(productId, false);
        return CoinBuyResult.unavailable;
      }
      _live.add(productId);
      final opened = await _store.buyConsumable(
        product,
        accountToken: catalog.accountToken,
      );
      if (!opened) {
        _live.remove(productId);
        _setBusy(productId, false);
        // Google Play refuses a second purchase while an earlier one of the
        // same pack is still unconsumed: deliver that one now.
        unawaited(_redeliver());
        return CoinBuyResult.failed;
      }
      // The sheet is the store's: the button is free again until the
      // purchase comes back for delivery.
      _setBusy(productId, false);
      return CoinBuyResult.started;
    } catch (e) {
      if (kDebugMode) debugPrint('iap: buy failed ($e)');
      _live.remove(productId);
      _setBusy(productId, false);
      return CoinBuyResult.failed;
    }
  }

  /// The oldest undelivered notice, removed from the queue.
  CoinPurchaseNotice? takeNotice() {
    final list = state.notices;
    if (list.isEmpty) return null;
    state = state.copyWith(notices: List.unmodifiable(list.skip(1)));
    return list.first;
  }

  // ------------------------------------------------------------- delivery

  void _onSignedIn(String userId) {
    final waiting = _waiting.values.toList();
    _waiting.clear();
    for (final p in waiting) {
      unawaited(_deliver(p));
    }
    if (_redeliveredFor != userId) {
      _redeliveredFor = userId;
      unawaited(_redeliver());
    }
  }

  Future<void> _redeliver() async {
    try {
      await _store.redeliverPending();
    } catch (e) {
      if (kDebugMode) debugPrint('iap: re-delivery failed ($e)');
    }
  }

  void _onUpdates(List<PurchaseDetails> updates) {
    for (final p in updates) {
      if (!_isCoinPack(p.productID)) continue;
      switch (p.status) {
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          unawaited(_deliver(p));
        case PurchaseStatus.pending:
          _setBusy(p.productID, false);
          if (_reported.add('pending|${_key(p) ?? p.productID}')) {
            _notify(const CoinPurchaseNotice(CoinNoticeKind.pending));
          }
        case PurchaseStatus.canceled:
          _live.remove(p.productID);
          _setBusy(p.productID, false);
          unawaited(_dismiss(p));
        case PurchaseStatus.error:
          _live.remove(p.productID);
          _setBusy(p.productID, false);
          _notify(const CoinPurchaseNotice(CoinNoticeKind.failed));
          unawaited(_dismiss(p));
      }
    }
  }

  /// Coin packs are the only store products the app sells. Before the
  /// catalogue is loaded (a purchase re-delivered at launch) any product is
  /// delivered: the server refuses one it does not sell.
  bool _isCoinPack(String productId) {
    final catalog = ref.read(coinPacksProvider).catalog;
    return isCoinPackProductId(productId) ||
        catalog == null ||
        catalog.byProductId(productId) != null;
  }

  /// Purchase identity: the Play purchase token, or the StoreKit
  /// transaction id.
  String? _key(PurchaseDetails p) {
    final token = p.verificationData.serverVerificationData;
    if (_platform == 'ios') {
      final id = p.purchaseID;
      if (id != null && id.isNotEmpty) return id;
    }
    return token.isEmpty ? null : token;
  }

  String get _platform => ref.read(appInfoProvider).platform;

  bool get _signedIn => ref.read(sessionControllerProvider).user != null;

  Future<void> _deliver(PurchaseDetails p) async {
    final key = _key(p);
    if (key == null) return;
    if (_granted.contains(key)) {
      // Delivered already; the store offers it again because consuming /
      // finishing failed.
      await _finish(p);
      return;
    }
    if (!_signedIn) {
      _waiting[key] = p;
      return;
    }
    if (!_inFlight.add(key)) return;
    _setBusy(p.productID, true);
    try {
      final grant = await _submit(p);
      _granted.add(key);
      await _finish(p);
      if (!ref.mounted) return;
      ref.read(walletControllerProvider.notifier).setFromServer(grant.wallet);
      final packs = ref.read(coinPacksProvider);
      final pack = packs.catalog?.byProductId(p.productID) ?? grant.pack;
      if (!grant.replayed && pack != null) {
        final product = packs.products[p.productID];
        ref
            .read(analyticsServiceProvider)
            .coinPackPurchased(
              pack: pack.analyticsSlug,
              value: product?.rawPrice ?? pack.fallbackPrice.amount.toDouble(),
              currency:
                  product?.currencyCode.toUpperCase() ??
                  pack.fallbackPrice.currency,
            );
      }
      final live = _live.remove(p.productID);
      if ((!grant.replayed || live) && _celebrated.add(key)) {
        _notify(
          CoinPurchaseNotice(
            CoinNoticeKind.granted,
            pack: pack,
            coins: grant.coins,
            diamonds: grant.diamonds,
          ),
        );
      }
    } on ApiException catch (e) {
      // Not granted: the purchase stays with the store (never consumed or
      // finished) and is delivered again on a later start.
      if (!ref.mounted) return;
      _live.remove(p.productID);
      final transient = _isTransient(e);
      if (_reported.add('$key|${transient ? 'delayed' : e.code}')) {
        _notify(
          transient
              ? CoinPurchaseNotice(CoinNoticeKind.delayed, code: e.code)
              : CoinPurchaseNotice(CoinNoticeKind.failed, code: e.code),
        );
      }
    } finally {
      _inFlight.remove(key);
      if (ref.mounted) _setBusy(p.productID, false);
    }
  }

  /// `POST /store/purchases`, retrying network errors and 5xx with backoff.
  Future<CoinPurchaseGrant> _submit(PurchaseDetails p) async {
    final api = ref.read(coinPackApiProvider);
    final retry = ref.read(coinDeliveryRetryProvider);
    final ios = _platform == 'ios';
    final proof = p.verificationData.serverVerificationData;
    var delay = retry.baseDelay;
    for (var attempt = 1; ; attempt++) {
      try {
        return await api.submit(
          platform: ios ? 'ios' : 'android',
          productId: p.productID,
          purchaseToken: ios ? null : proof,
          transactionId: ios ? p.purchaseID : null,
          signedTransaction: ios ? proof : null,
        );
      } on ApiException catch (e) {
        if (!_isTransient(e) || attempt >= retry.attempts || !ref.mounted) {
          rethrow;
        }
        await retry.sleep(delay);
        delay *= 2;
      } catch (_) {
        if (attempt >= retry.attempts || !ref.mounted) {
          throw const ApiException(
            code: ClientErrorCodes.badResponse,
            status: 0,
          );
        }
        await retry.sleep(delay);
        delay *= 2;
      }
    }
  }

  /// Worth retrying as is: the server was not reached or failed. A refusal
  /// (4xx, `iap_unavailable`, maintenance) is not.
  static bool _isTransient(ApiException e) =>
      e.isNetwork ||
      e.code == ClientErrorCodes.badResponse ||
      e.code == 'rate_limited' ||
      (e.status >= 500 && e.code != 'iap_unavailable' && !e.isPolicyBlock);

  Future<void> _finish(PurchaseDetails p) async {
    try {
      await _store.finish(p);
    } catch (e) {
      // The server already granted it (and consumes Play purchases itself);
      // a repeat delivery is answered as a replay.
      if (kDebugMode) debugPrint('iap: finish failed ($e)');
    }
  }

  Future<void> _dismiss(PurchaseDetails p) async {
    try {
      await _store.dismiss(p);
    } catch (e) {
      if (kDebugMode) debugPrint('iap: dismiss failed ($e)');
    }
  }

  void _setBusy(String productId, bool busy) {
    if (!ref.mounted || state.isBusy(productId) == busy) return;
    state = state.copyWith(
      busy: Set.unmodifiable(
        busy ? {...state.busy, productId} : state.busy.difference({productId}),
      ),
    );
  }

  void _notify(CoinPurchaseNotice notice) {
    if (!ref.mounted) return;
    state = state.copyWith(
      notices: List.unmodifiable([...state.notices, notice]),
    );
  }
}

final coinPurchaseControllerProvider =
    NotifierProvider<CoinPurchaseController, CoinPurchaseState>(
      CoinPurchaseController.new,
    );
