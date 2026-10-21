import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/analytics/analytics_providers.dart';
import '../../../core/network/api_client.dart';
import '../../authentication/application/session_controller.dart';
import '../../progression/application/meta_support.dart';
import '../../wallet/wallet_controller.dart';
import '../data/store_api.dart';
import '../domain/store_models.dart';

/// Analytics `item_kind` of Store profile pictures.
const String kProfilePictureItemKind = 'profile_picture';

/// The Store shelf of one filter, loaded page by page.
@immutable
class StoreState {
  const StoreState({
    this.filter = StoreFilter.all,
    this.items = const [],
    this.nextCursor,
    this.total = 0,
    this.equippedId,
    this.loading = true,
    this.loadingMore = false,
    this.error,
    this.moreError,
  });

  final StoreFilter filter;

  /// Every loaded item, in shelf order.
  final List<ProfilePicture> items;

  /// Cursor of the next page; null after the last one.
  final String? nextCursor;
  final int total;

  /// Applied picture id (null: the built-in avatar).
  final String? equippedId;

  /// The first page of [filter] is loading and nothing is shown yet.
  final bool loading;
  final bool loadingMore;

  /// The first page failed (full-screen error with Retry).
  final Object? error;

  /// The next page failed (inline Retry at the end of the grid).
  final Object? moreError;

  bool get hasMore => nextCursor != null;
  bool get isEmpty => !loading && error == null && items.isEmpty;

  ProfilePicture? byId(String id) {
    for (final p in items) {
      if (p.id == id) return p;
    }
    return null;
  }

  StoreState copyWith({
    List<ProfilePicture>? items,
    Object? nextCursor = _unset,
    int? total,
    Object? equippedId = _unset,
    bool? loading,
    bool? loadingMore,
    Object? error = _unset,
    Object? moreError = _unset,
  }) => StoreState(
    filter: filter,
    items: items ?? this.items,
    nextCursor: identical(nextCursor, _unset)
        ? this.nextCursor
        : nextCursor as String?,
    total: total ?? this.total,
    equippedId: identical(equippedId, _unset)
        ? this.equippedId
        : equippedId as String?,
    loading: loading ?? this.loading,
    loadingMore: loadingMore ?? this.loadingMore,
    error: identical(error, _unset) ? this.error : error,
    moreError: identical(moreError, _unset) ? this.moreError : moreError,
  );
}

const Object _unset = Object();

/// Result of a purchase / apply.
@immutable
sealed class StoreOutcome {
  const StoreOutcome();
}

final class StoreSucceeded extends StoreOutcome {
  const StoreSucceeded();
}

/// The same action is already in flight (double tap).
final class StoreIgnored extends StoreOutcome {
  const StoreIgnored();
}

final class StoreFailed extends StoreOutcome {
  const StoreFailed(this.error);
  final ApiException error;
  String get code => error.code;
}

/// The Store: paginated shelf per filter, purchases with an Idempotency-Key
/// (a retry of the same intent reuses the key) and applying a picture
/// (`PUT /me/profile-picture`), which updates the signed-in user at once.
class StoreController extends Notifier<StoreState> {
  StoreController([this.initialFilter = StoreFilter.all]);

  /// Shelf loaded first (the Profile picker starts on [StoreFilter.owned]).
  final StoreFilter initialFilter;

  /// Bumped on every new first-page load; stale responses are dropped.
  int _generation = 0;
  final Set<String> _inFlight = {};
  final Map<String, String> _purchaseKeys = {};

  StoreApi get _api => ref.read(storeApiProvider);
  AnalyticsService get _analytics => ref.read(analyticsServiceProvider);

  @override
  StoreState build() {
    _generation++;
    unawaited(_loadFirst(initialFilter, _generation));
    return StoreState(filter: initialFilter);
  }

  /// Switches the shelf to [filter] (first page).
  void setFilter(StoreFilter filter) {
    if (filter == state.filter && state.error == null) return;
    final gen = ++_generation;
    state = StoreState(filter: filter, equippedId: state.equippedId);
    unawaited(_loadFirst(filter, gen));
  }

  /// Reloads the first page of the current filter (pull to refresh, Retry).
  /// Items stay on screen until the new page arrives. Throws
  /// [ApiException] when there were items to keep showing.
  Future<void> refresh() async {
    final gen = ++_generation;
    final filter = state.filter;
    if (state.items.isEmpty) {
      state = StoreState(filter: filter, equippedId: state.equippedId);
    }
    final hadItems = state.items.isNotEmpty;
    final error = await _loadFirst(filter, gen);
    if (error != null && hadItems) throw error;
  }

  /// Returns the failure (also stored in the state when nothing is shown).
  Future<ApiException?> _loadFirst(StoreFilter filter, int gen) async {
    try {
      final page = await _api.list(filter: filter);
      if (!ref.mounted || gen != _generation) return null;
      state = StoreState(
        filter: filter,
        items: page.items,
        nextCursor: page.nextCursor,
        total: page.total,
        equippedId: page.equipped,
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
      final page = await _api.list(filter: s.filter, cursor: cursor);
      if (!ref.mounted || gen != _generation) return;
      final known = {for (final p in state.items) p.id};
      state = state.copyWith(
        items: List.unmodifiable([
          ...state.items,
          ...page.items.where((p) => !known.contains(p.id)),
        ]),
        nextCursor: page.nextCursor,
        total: page.total,
        equippedId: page.equipped,
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

  /// Buys [picture] for its fixed diamond price.
  Future<StoreOutcome> purchase(ProfilePicture picture) async {
    if (!_inFlight.add(picture.id)) return const StoreIgnored();
    final key = _purchaseKeys[picture.id] ??= ref.read(
      idempotencyKeyFactoryProvider,
    )();
    try {
      final (bought, wallet) = await _api.purchase(
        picture.id,
        idempotencyKey: key,
      );
      _purchaseKeys.remove(picture.id);
      if (!ref.mounted) return const StoreSucceeded();
      ref.read(walletControllerProvider.notifier).setFromServer(wallet);
      _replace(
        (bought.id.isEmpty ? picture : bought).copyWith(
          owned: true,
          equipped: state.equippedId == picture.id,
        ),
      );
      // Server-confirmed; no id in the parameters.
      _analytics.cosmeticUnlocked(kProfilePictureItemKind, '');
      return const StoreSucceeded();
    } on ApiException catch (e) {
      final transient = isTransientFailure(e);
      if (!transient) _purchaseKeys.remove(picture.id);
      if (ref.mounted) {
        if (e.code == 'already_owned') {
          // The server says it is ours: show it as owned.
          _replace(picture.copyWith(owned: true));
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
      _inFlight.remove(picture.id);
    }
  }

  /// Applies [picture] (owned), or the built-in avatar when null.
  Future<StoreOutcome> apply(ProfilePicture? picture) async {
    final busyKey = picture?.id ?? ':builtin';
    if (!_inFlight.add(busyKey)) return const StoreIgnored();
    try {
      final equipped = await _api.apply(picture?.id);
      if (!ref.mounted) return const StoreSucceeded();
      final id = equipped?.id;
      state = state.copyWith(
        equippedId: id,
        items: List.unmodifiable([
          for (final p in state.items)
            p.equipped == (p.id == id) ? p : p.copyWith(equipped: p.id == id),
        ]),
      );
      final session = ref.read(sessionControllerProvider.notifier);
      final user = ref.read(sessionControllerProvider).user;
      if (user != null) {
        session.updateUser(user.copyWith(picture: equipped?.picture));
      }
      _analytics.cosmeticEquipped(kProfilePictureItemKind);
      return const StoreSucceeded();
    } on ApiException catch (e) {
      if (ref.mounted && e.code == 'item_locked' && picture != null) {
        _replace(picture.copyWith(owned: false, equipped: false));
      }
      return StoreFailed(e);
    } finally {
      _inFlight.remove(busyKey);
    }
  }

  void _replace(ProfilePicture item) {
    state = state.copyWith(
      items: List.unmodifiable([
        for (final p in state.items) p.id == item.id ? item : p,
      ]),
    );
  }
}

final storeProvider = NotifierProvider<StoreController, StoreState>(
  StoreController.new,
  isAutoDispose: true,
);

/// The pictures the player owns (`filter=owned`), page by page, for the
/// Profile picture picker. Applying through it updates the session user
/// like the Store does.
final ownedPicturesProvider = NotifierProvider<StoreController, StoreState>(
  () => StoreController(StoreFilter.owned),
  isAutoDispose: true,
);
