import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/analytics/analytics_providers.dart';
import '../../../core/network/api_client.dart';
import '../../../core/protocol/protocol.dart';
import '../../../core/realtime/realtime_providers.dart';
import '../../../core/storage/preferences_store.dart';
import '../../authentication/application/session_controller.dart';
import '../../progression/application/meta_support.dart';
import '../../wallet/wallet_controller.dart';
import '../data/collection_api.dart';
import '../domain/collection_models.dart';

/// Result of an equip / purchase action.
@immutable
sealed class CollectionOutcome {
  const CollectionOutcome();
}

final class CollectionSucceeded extends CollectionOutcome {
  const CollectionSucceeded();
}

/// The same action is already in flight (double tap).
final class CollectionIgnored extends CollectionOutcome {
  const CollectionIgnored();
}

final class CollectionFailed extends CollectionOutcome {
  const CollectionFailed(this.error);
  final ApiException error;
  String get code => error.code;
}

/// The Collection Room: catalog with ownership (`GET /collection`), equip
/// (`PUT /collection/loadout`) and fixed-price purchases (exactly once via
/// Idempotency-Key; retries of the same intent reuse the key).
class CollectionController extends AsyncNotifier<CollectionData> {
  final Set<String> _inFlight = {};
  final Map<String, String> _purchaseKeys = {};

  CollectionApi get _api => ref.read(collectionApiProvider);
  AnalyticsService get _analytics => ref.read(analyticsServiceProvider);

  @override
  Future<CollectionData> build() async {
    // Items unlocked elsewhere (level-ups, claims) appear without a manual
    // refresh.
    ref.listen<AsyncValue<ProgressionUpdatedEvent>>(
      progressionUpdatesProvider,
      (_, next) {
        final e = next.value;
        if (e != null && e.unlocked.isNotEmpty) {
          unawaited(refresh().catchError((Object _) {}));
        }
      },
    );
    return _api.fetch();
  }

  Future<void> refresh() async {
    try {
      final data = await _api.fetch();
      if (ref.mounted) state = AsyncData(data);
    } catch (e, s) {
      if (ref.mounted && !state.hasValue) state = AsyncError(e, s);
      rethrow;
    }
  }

  bool isBusy(String itemId) => _inFlight.contains(itemId);

  @visibleForTesting
  String? pendingPurchaseKey(String itemId) => _purchaseKeys[itemId];

  /// Equips an owned [item] into its slot.
  Future<CollectionOutcome> equip(CollectionItem item) =>
      _equip(item.kind, item.id, busyKey: item.id);

  /// Resets [slot] to its starter item.
  Future<CollectionOutcome> equipDefault(String slot) =>
      _equip(slot, null, busyKey: 'slot:$slot');

  Future<CollectionOutcome> _equip(
    String slot,
    String? itemId, {
    required String busyKey,
  }) async {
    if (!_inFlight.add(busyKey)) return const CollectionIgnored();
    try {
      final loadout = await _api.equip(slot, itemId);
      if (!ref.mounted) return const CollectionSucceeded();
      final data = state.value;
      if (data != null) state = AsyncData(data.withLoadout(loadout));
      ref.read(sessionControllerProvider.notifier).applyLoadout(loadout);
      _analytics.cosmeticEquipped(slot);
      return const CollectionSucceeded();
    } on ApiException catch (e) {
      if (ref.mounted && !isTransientFailure(e)) {
        unawaited(refresh().catchError((Object _) {}));
      }
      return CollectionFailed(e);
    } finally {
      _inFlight.remove(busyKey);
    }
  }

  /// Buys [item] for its fixed price. Cosmetic only; never random.
  Future<CollectionOutcome> purchase(CollectionItem item) async {
    if (!_inFlight.add(item.id)) return const CollectionIgnored();
    final key = _purchaseKeys[item.id] ??= ref.read(
      idempotencyKeyFactoryProvider,
    )();
    try {
      final (bought, wallet) = await _api.purchase(
        item.id,
        idempotencyKey: key,
      );
      _purchaseKeys.remove(item.id);
      if (!ref.mounted) return const CollectionSucceeded();
      ref.read(walletControllerProvider.notifier).setFromServer(wallet);
      final data = state.value;
      if (data != null) {
        state = AsyncData(data.replaceItem(bought.copyWith(owned: true)));
      }
      // No progression push follows a purchase, so it is reported here.
      _analytics.cosmeticUnlocked(bought.kind, bought.rarity);
      return const CollectionSucceeded();
    } on ApiException catch (e) {
      final transient = isTransientFailure(e);
      if (!transient) _purchaseKeys.remove(item.id);
      if (ref.mounted && !transient) {
        unawaited(refresh().catchError((Object _) {}));
        if (e.code == 'insufficient_funds') {
          unawaited(
            ref
                .read(walletControllerProvider.notifier)
                .refresh()
                .catchError((Object _) {}),
          );
        }
      }
      return CollectionFailed(e);
    } finally {
      _inFlight.remove(item.id);
    }
  }
}

/// Remembers which owned items the user has seen, for the "New" badge
/// (local only; never sent anywhere).
class CollectionSeenStore {
  CollectionSeenStore(this._prefs);

  static const _key = 'meta.collection.seen_owned';

  final PreferencesStore? _prefs;

  /// Owned items not seen yet. The first visit records everything owned, so
  /// starter items are never "new".
  Set<String> unseenOwned(CollectionData data) {
    final prefs = _prefs;
    if (prefs == null) return const {};
    final owned = {
      for (final i in data.items)
        if (i.owned) i.id,
    };
    final raw = prefs.getString(_key);
    if (raw == null) {
      unawaited(prefs.setString(_key, jsonEncode(owned.toList())));
      return const {};
    }
    return owned.difference(_decode(raw));
  }

  /// Marks [ids] as seen.
  void markSeen(Iterable<String> ids) {
    final prefs = _prefs;
    if (prefs == null) return;
    final seen = _decode(prefs.getString(_key))..addAll(ids);
    unawaited(prefs.setString(_key, jsonEncode(seen.toList())));
  }

  static Set<String> _decode(String? raw) {
    if (raw == null) return <String>{};
    try {
      return (jsonDecode(raw) as List).whereType<String>().toSet();
    } catch (_) {
      return <String>{};
    }
  }
}

final collectionSeenStoreProvider = Provider<CollectionSeenStore>((ref) {
  try {
    return CollectionSeenStore(ref.watch(preferencesStoreProvider));
  } catch (_) {
    return CollectionSeenStore(null);
  }
});

final collectionProvider =
    AsyncNotifierProvider<CollectionController, CollectionData>(
      CollectionController.new,
      isAutoDispose: true,
      retry: noRetry,
    );
