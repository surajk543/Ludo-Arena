import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/analytics/analytics_providers.dart';
import '../../../core/network/api_client.dart';
import '../../game/application/owned_emotes.dart';
import '../../progression/application/meta_support.dart';
import '../../wallet/wallet_controller.dart';
import '../data/store_api.dart';
import '../domain/store_models.dart';
import 'store_controller.dart';

/// Analytics `item_kind` of Store emotes (an emote like the catalogue ones).
const String kStoreEmoteItemKind = 'emote';

/// A shelf of Store emotes, loaded page by page.
@immutable
class EmoteShelfState {
  const EmoteShelfState({
    this.items = const [],
    this.nextCursor,
    this.total = 0,
    this.loading = true,
    this.loadingMore = false,
    this.error,
    this.moreError,
  });

  /// Every loaded item, in shelf order.
  final List<ShopEmote> items;

  /// Cursor of the next page; null after the last one.
  final String? nextCursor;
  final int total;

  /// The first page is loading and nothing is shown yet.
  final bool loading;
  final bool loadingMore;

  /// The first page failed (error with Retry).
  final Object? error;

  /// The next page failed (inline Retry at the end of the grid).
  final Object? moreError;

  bool get hasMore => nextCursor != null;
  bool get isEmpty => !loading && error == null && items.isEmpty;

  /// Loaded without an error: [total] is known.
  bool get loaded => !loading && error == null;

  ShopEmote? byId(String id) {
    for (final e in items) {
      if (e.id == id) return e;
    }
    return null;
  }

  EmoteShelfState copyWith({
    List<ShopEmote>? items,
    Object? nextCursor = _unset,
    int? total,
    bool? loading,
    bool? loadingMore,
    Object? error = _unset,
    Object? moreError = _unset,
  }) => EmoteShelfState(
    items: items ?? this.items,
    nextCursor: identical(nextCursor, _unset)
        ? this.nextCursor
        : nextCursor as String?,
    total: total ?? this.total,
    loading: loading ?? this.loading,
    loadingMore: loadingMore ?? this.loadingMore,
    error: identical(error, _unset) ? this.error : error,
    moreError: identical(moreError, _unset) ? this.moreError : moreError,
  );
}

const Object _unset = Object();

/// A Store emote shelf: paginated (`GET /store/emotes`) and purchases with an
/// Idempotency-Key (a retry of the same intent reuses the key).
///
/// The Shop's shelf ([excludeOwned]) lists only emotes not owned yet: a
/// bought emote leaves it and joins the owned shelf (Collection) and the
/// in-match picker, which are reloaded.
class EmoteShelfController extends Notifier<EmoteShelfState> {
  EmoteShelfController({
    this.filter = EmoteFilter.all,
    this.excludeOwned = false,
  });

  final EmoteFilter filter;

  /// Leave out owned emotes (`excludeOwned=true`; the Shop).
  final bool excludeOwned;

  /// Bumped on every new first-page load; stale responses are dropped.
  int _generation = 0;
  final Set<String> _inFlight = {};
  final Map<String, String> _purchaseKeys = {};

  StoreApi get _api => ref.read(storeApiProvider);
  AnalyticsService get _analytics => ref.read(analyticsServiceProvider);

  @override
  EmoteShelfState build() {
    final gen = ++_generation;
    unawaited(_loadFirst(gen));
    return const EmoteShelfState();
  }

  /// Reloads the first page (pull to refresh, Retry). Items stay on screen
  /// until the new page arrives. Throws [ApiException] when there were
  /// items to keep showing.
  Future<void> refresh() async {
    final gen = ++_generation;
    if (state.items.isEmpty) state = const EmoteShelfState();
    final hadItems = state.items.isNotEmpty;
    final error = await _loadFirst(gen);
    if (error != null && hadItems) throw error;
  }

  /// Returns the failure (also stored in the state when nothing is shown).
  Future<ApiException?> _loadFirst(int gen) async {
    try {
      final page = await _api.listEmotes(
        filter: filter,
        excludeOwned: excludeOwned,
      );
      if (!ref.mounted || gen != _generation) return null;
      state = EmoteShelfState(
        items: page.items,
        nextCursor: page.nextCursor,
        total: page.total,
        loading: false,
      );
      return null;
    } catch (error) {
      final e = _asApiException(error);
      if (!ref.mounted || gen != _generation) return e;
      if (state.items.isEmpty) {
        state = state.copyWith(loading: false, error: e);
      }
      return e;
    }
  }

  static ApiException _asApiException(Object error) => error is ApiException
      ? error
      : const ApiException(code: ClientErrorCodes.badResponse, status: 0);

  /// Loads the next page (no-op while loading, at the end, or after a
  /// failure until [retry]).
  Future<void> loadMore({bool retry = false}) async {
    final s = state;
    final cursor = s.nextCursor;
    if (s.loading || s.loadingMore || cursor == null) return;
    if (s.moreError != null && !retry) return;
    final gen = _generation;
    state = s.copyWith(loadingMore: true, moreError: null);
    try {
      final page = await _api.listEmotes(
        filter: filter,
        excludeOwned: excludeOwned,
        cursor: cursor,
      );
      if (!ref.mounted || gen != _generation) return;
      final known = {for (final e in state.items) e.id};
      state = state.copyWith(
        items: List.unmodifiable([
          ...state.items,
          ...page.items.where((e) => !known.contains(e.id)),
        ]),
        nextCursor: page.nextCursor,
        total: page.total,
        loadingMore: false,
      );
    } catch (e) {
      if (!ref.mounted || gen != _generation) return;
      state = state.copyWith(loadingMore: false, moreError: _asApiException(e));
    }
  }

  bool isBusy(String id) => _inFlight.contains(id);

  @visibleForTesting
  String? pendingPurchaseKey(String id) => _purchaseKeys[id];

  /// Buys [emote] for its fixed diamond price.
  Future<StoreOutcome> purchase(ShopEmote emote) async {
    if (!_inFlight.add(emote.id)) return const StoreIgnored();
    final key = _purchaseKeys[emote.id] ??= ref.read(
      idempotencyKeyFactoryProvider,
    )();
    try {
      final (bought, wallet) = await _api.purchaseEmote(
        emote.id,
        idempotencyKey: key,
      );
      _purchaseKeys.remove(emote.id);
      if (!ref.mounted) return const StoreSucceeded();
      ref.read(walletControllerProvider.notifier).setFromServer(wallet);
      _owned((bought.id.isEmpty ? emote : bought).copyWith(owned: true));
      // Server-confirmed; no id in the parameters.
      _analytics.cosmeticUnlocked(kStoreEmoteItemKind, '');
      return const StoreSucceeded();
    } on ApiException catch (e) {
      final transient = isTransientFailure(e);
      if (!transient) _purchaseKeys.remove(emote.id);
      if (ref.mounted) {
        if (e.code == 'already_owned') {
          // The server says it is ours: show it as owned.
          _owned(emote.copyWith(owned: true));
        } else if (e.code == 'insufficient_funds') {
          unawaited(
            ref
                .read(walletControllerProvider.notifier)
                .refresh()
                .catchError((Object _) {}),
          );
        }
      }
      return StoreFailed(e);
    } finally {
      _inFlight.remove(emote.id);
    }
  }

  /// [item] is now owned: it leaves the Shop's shelf, or shows as owned on
  /// any other shelf. The owned shelf and the in-match picker reload.
  void _owned(ShopEmote item) {
    if (excludeOwned) {
      final left = [
        for (final e in state.items)
          if (e.id != item.id) e,
      ];
      final removed = state.items.length - left.length;
      state = state.copyWith(
        items: List.unmodifiable(left),
        total: (state.total - removed).clamp(0, state.total),
      );
      ref.invalidate(ownedStoreEmotesProvider);
    } else {
      state = state.copyWith(
        items: List.unmodifiable([
          for (final e in state.items) e.id == item.id ? item : e,
        ]),
      );
    }
    ref.invalidate(ownedEmotesProvider);
  }
}

/// An emote shelf provider ([shopEmotesProvider]: the Shop,
/// [ownedStoreEmotesProvider]: the Collection).
typedef EmoteShelfProvider =
    NotifierProvider<EmoteShelfController, EmoteShelfState>;

/// The Shop's emote shelf: Store emotes not owned yet (`excludeOwned=true`).
final EmoteShelfProvider shopEmotesProvider =
    NotifierProvider<EmoteShelfController, EmoteShelfState>(
      () => EmoteShelfController(excludeOwned: true),
      isAutoDispose: true,
    );

/// The Store emotes the player owns (`filter=owned`), page by page, for the
/// Collection's Emotes tab.
final EmoteShelfProvider ownedStoreEmotesProvider =
    NotifierProvider<EmoteShelfController, EmoteShelfState>(
      () => EmoteShelfController(filter: EmoteFilter.owned),
      isAutoDispose: true,
    );
