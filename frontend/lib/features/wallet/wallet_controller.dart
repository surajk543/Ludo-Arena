import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/protocol/protocol.dart';
import '../../core/realtime/realtime_providers.dart';

/// Server-confirmed balances. Coins and diamonds are virtual and
/// non-redeemable; the client never computes them.
@immutable
class WalletState {
  const WalletState({
    this.wallet,
    this.lastCoinsDelta = 0,
    this.lastDiamondsDelta = 0,
    this.lastReason,
    this.revision = 0,
  });

  /// `null` until the first server value arrives.
  final Wallet? wallet;

  /// Delta of the most recent `wallet.updated` (0 for REST refreshes).
  final int lastCoinsDelta;
  final int lastDiamondsDelta;

  /// `entry_fee` | `payout` | `mission` | `purchase` | `level` | `refund`
  /// (or null). Unknown future reasons only update the balances.
  final String? lastReason;

  /// Increments on every server update (lets widgets animate per update).
  final int revision;

  int get coins => wallet?.coins ?? 0;
  int get diamonds => wallet?.diamonds ?? 0;
  bool get isLoaded => wallet != null;
}

class WalletController extends Notifier<WalletState> {
  @override
  WalletState build() {
    ref.listen<AsyncValue<WalletUpdatedEvent>>(walletUpdatesProvider, (
      _,
      next,
    ) {
      final e = next.value;
      if (e != null) applyRealtime(e);
    });
    return const WalletState();
  }

  /// Sets balances from an authoritative REST payload (auth, `/me`,
  /// `/wallet`, purchase/claim responses).
  void setFromServer(Wallet wallet) {
    if (state.wallet == wallet) return;
    state = WalletState(wallet: wallet, revision: state.revision + 1);
  }

  /// Applies a server-pushed `wallet.updated`.
  void applyRealtime(WalletUpdatedEvent e) {
    state = WalletState(
      wallet: Wallet(coins: e.coins, diamonds: e.diamonds),
      lastCoinsDelta: e.deltaCoins,
      lastDiamondsDelta: e.deltaDiamonds,
      lastReason: e.reason,
      revision: state.revision + 1,
    );
  }

  /// `GET /wallet`. Throws [ApiException].
  Future<void> refresh() async {
    final json = await ref.read(apiClientProvider).get('/wallet');
    setFromServer(Wallet.fromJson(json));
  }

  void clear() => state = WalletState(revision: state.revision + 1);
}

final walletControllerProvider =
    NotifierProvider<WalletController, WalletState>(WalletController.new);
