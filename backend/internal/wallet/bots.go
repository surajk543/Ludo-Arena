package wallet

// Bot wallets (owner-approved 2026-10-22; backend/docs/game-rules.md "Coins
// with bots").
//
// Bots play public and private matches for coins like people. Each bot
// persona has a wallet.wallets row with is_bot = TRUE (not an account: no
// identity, progression or friendship rows) keyed by the persona's stable id.
// It is created lazily with BotRules.Start coins and no diamonds the first
// time the persona is seated (EnsureBots), and its balance follows the
// owner's rules:
//
//   - before every entry fee (ChargeEntry, in the fee's transaction): above
//     ResetAbove it is reset to ResetTo; then, below RechargeBelow (or below
//     the fee, so a bot can always pay) it is recharged to RechargeTo (or to
//     the fee when that is larger);
//   - after every settlement (SettleBots, once the round's payout is made):
//     below RechargeBelow it is recharged to RechargeTo.
//
// Every applied rule is counted (bot_wallet_recharges_total,
// bot_wallet_resets_total) together with the coins it created or removed
// (bot_coins_minted_total, bot_coins_removed_total), so operators can watch
// how many coins the bots inject into the economy.

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"slices"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"

	"ludoarena/internal/metrics"
)

// Default bot coin rules (1 lakh = 100,000; 1 crore = 10,000,000).
const (
	DefaultBotStart         int64 = 10_000_000  // BOT_COINS_START: 1 crore
	DefaultBotRechargeBelow int64 = 100_000     // BOT_COINS_RECHARGE_BELOW: 1 lakh
	DefaultBotRechargeTo    int64 = 10_000_000  // BOT_COINS_RECHARGE_TO: 1 crore
	DefaultBotResetAbove    int64 = 100_000_000 // BOT_COINS_RESET_ABOVE: 10 crore
	DefaultBotResetTo       int64 = 10_000_000  // BOT_COINS_RESET_TO: 1 crore

	// MaxBotCoins bounds every rule value (and keeps pots far from int64
	// overflow).
	MaxBotCoins int64 = 1_000_000_000_000
)

// BotRules are the coin rules of bot wallets (BOT_COINS_*).
type BotRules struct {
	Start         int64 // coins of a new bot wallet
	RechargeBelow int64 // a balance below this is recharged...
	RechargeTo    int64 // ...to this
	ResetAbove    int64 // a balance above this is reset before the next match...
	ResetTo       int64 // ...to this
}

// DefaultBotRules returns the owner's defaults.
func DefaultBotRules() BotRules {
	return BotRules{Start: DefaultBotStart, RechargeBelow: DefaultBotRechargeBelow, RechargeTo: DefaultBotRechargeTo,
		ResetAbove: DefaultBotResetAbove, ResetTo: DefaultBotResetTo}
}

// Validate refuses rules that are out of range or contradict each other (a
// recharge that triggers a reset, a reset that triggers a recharge, a start
// outside the band).
func (r BotRules) Validate() error {
	var errs []error
	for _, v := range []struct {
		name string
		v    int64
	}{{"BOT_COINS_START", r.Start}, {"BOT_COINS_RECHARGE_BELOW", r.RechargeBelow}, {"BOT_COINS_RECHARGE_TO", r.RechargeTo},
		{"BOT_COINS_RESET_ABOVE", r.ResetAbove}, {"BOT_COINS_RESET_TO", r.ResetTo}} {
		if v.v < 1 || v.v > MaxBotCoins {
			errs = append(errs, fmt.Errorf("%s must be between 1 and %d", v.name, MaxBotCoins))
		}
	}
	if len(errs) > 0 {
		return errors.Join(errs...)
	}
	if r.RechargeTo <= r.RechargeBelow {
		errs = append(errs, errors.New("BOT_COINS_RECHARGE_TO must be greater than BOT_COINS_RECHARGE_BELOW"))
	}
	if r.RechargeTo > r.ResetAbove {
		errs = append(errs, errors.New("BOT_COINS_RECHARGE_TO must not exceed BOT_COINS_RESET_ABOVE"))
	}
	if r.ResetTo < r.RechargeBelow || r.ResetTo > r.ResetAbove {
		errs = append(errs, errors.New("BOT_COINS_RESET_TO must be between BOT_COINS_RECHARGE_BELOW and BOT_COINS_RESET_ABOVE"))
	}
	if r.Start < r.RechargeBelow || r.Start > r.ResetAbove {
		errs = append(errs, errors.New("BOT_COINS_START must be between BOT_COINS_RECHARGE_BELOW and BOT_COINS_RESET_ABOVE"))
	}
	return errors.Join(errs...)
}

// BotAdjustment is what the rules changed on one bot wallet.
type BotAdjustment struct {
	Reset     bool
	Removed   int64 // coins removed by the reset
	Recharged bool
	Minted    int64 // coins created by the recharge
}

func (a BotAdjustment) changed() bool { return a.Reset || a.Recharged }

// BeforeMatch returns the balance a bot holding coins has before paying fee
// for its next match: above ResetAbove it is reset to ResetTo, then below
// max(RechargeBelow, fee) it is recharged to max(RechargeTo, fee).
func (r BotRules) BeforeMatch(coins, fee int64) (int64, BotAdjustment) {
	var a BotAdjustment
	if coins > r.ResetAbove {
		a.Reset, a.Removed = true, coins-r.ResetTo
		coins = r.ResetTo
	}
	if coins < max(r.RechargeBelow, fee) {
		to := max(r.RechargeTo, fee)
		a.Recharged, a.Minted = true, to-coins
		coins = to
	}
	return coins, a
}

// AfterSettlement returns the balance after a settlement: below
// RechargeBelow it is recharged to RechargeTo.
func (r BotRules) AfterSettlement(coins int64) (int64, BotAdjustment) {
	var a BotAdjustment
	if coins < r.RechargeBelow {
		a.Recharged, a.Minted = true, r.RechargeTo-coins
		coins = r.RechargeTo
	}
	return coins, a
}

// sortedUnique returns ids sorted (PostgreSQL's uuid order) without
// duplicates or nil ids.
func sortedUnique(ids []uuid.UUID) []uuid.UUID {
	out := make([]uuid.UUID, 0, len(ids))
	for _, id := range ids {
		if id != uuid.Nil {
			out = append(out, id)
		}
	}
	slices.SortFunc(out, func(a, b uuid.UUID) int { return bytes.Compare(a[:], b[:]) })
	return slices.Compact(out)
}

// EnsureBots creates the missing wallets of bots ids (is_bot = TRUE, start
// coins, no diamonds) and returns how many it created. Existing rows are left
// alone (ON CONFLICT DO NOTHING), so it is safe to call on every seating.
// Rows are inserted in id order, the lock order of every wallet transaction.
func (s *Store) EnsureBots(ctx context.Context, ids []uuid.UUID, start int64) (int, error) {
	ids = sortedUnique(ids)
	if len(ids) == 0 {
		return 0, nil
	}
	if start < 1 || start > MaxBotCoins {
		return 0, ErrInvalidAmount
	}
	tag, err := s.pool.Exec(ctx, `
		INSERT INTO wallet.wallets (user_id, coins, diamonds, is_bot)
		SELECT id, $2, 0, TRUE FROM unnest($1::uuid[]) AS t(id) ORDER BY id
		ON CONFLICT (user_id) DO NOTHING`, ids, start)
	if err != nil {
		return 0, err
	}
	n := int(tag.RowsAffected())
	if n > 0 {
		metrics.BotCoinsMinted.WithLabelValues("start").Add(float64(start) * float64(n))
	}
	return n, nil
}

// SettleBots applies the after-settlement rule to the wallets of bots (one
// transaction, rows locked in id order): a balance below RechargeBelow is
// recharged to RechargeTo. Ids without a bot wallet are skipped. Applying it
// again changes nothing, so retries are safe.
func (s *Store) SettleBots(ctx context.Context, bots []uuid.UUID, rules BotRules) error {
	bots = sortedUnique(bots)
	if len(bots) == 0 {
		return nil
	}
	tx, err := s.pool.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx) //nolint:errcheck
	have, err := lockRows(ctx, tx, bots, true)
	if err != nil {
		return err
	}
	var adjs []BotAdjustment
	for _, b := range bots {
		r, ok := have[b]
		if !ok {
			continue
		}
		to, adj := rules.AfterSettlement(r.coins)
		if adj.changed() {
			if err := setBotCoins(ctx, tx, b, to); err != nil {
				return err
			}
			adjs = append(adjs, adj)
		}
	}
	if err := tx.Commit(ctx); err != nil {
		return err
	}
	record(adjs)
	return nil
}

// setBotCoins sets a locked bot wallet's balance.
func setBotCoins(ctx context.Context, tx pgx.Tx, id uuid.UUID, coins int64) error {
	tag, err := tx.Exec(ctx, `UPDATE wallet.wallets SET coins = $2 WHERE user_id = $1 AND is_bot`, id, coins)
	if err == nil && tag.RowsAffected() != 1 {
		err = fmt.Errorf("bot wallet: %w", ErrNotFound)
	}
	return err
}

// record counts committed rule applications.
func record(adjs []BotAdjustment) {
	for _, a := range adjs {
		if a.Reset {
			metrics.BotWalletResets.Inc()
			metrics.BotCoinsRemoved.WithLabelValues("reset").Add(float64(a.Removed))
		}
		if a.Recharged {
			metrics.BotWalletRecharges.Inc()
			metrics.BotCoinsMinted.WithLabelValues("recharge").Add(float64(a.Minted))
		}
	}
}
