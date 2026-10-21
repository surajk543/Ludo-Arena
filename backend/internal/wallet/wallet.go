// Package wallet manages coin and diamond balances in PostgreSQL. Every
// balance change is a single atomic SQL statement or transaction; balances can
// never go negative (CHECK constraints plus conditional updates).
//
// Bot wallets (bots.go): a row with is_bot = TRUE holds the play coins of one
// bot persona. It is not an account. Bots pay entry fees and receive payouts
// through the same transactions, lock order and idempotency keys as people
// (ChargeEntry, Credit), and their balances follow BotRules.
package wallet

import (
	"context"
	"errors"
	"fmt"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// Errors.
var (
	ErrNotFound          = errors.New("wallet not found")
	ErrInsufficientFunds = errors.New("insufficient funds")
	ErrInvalidAmount     = errors.New("invalid amount")
)

// Wallet is an authoritative balance snapshot.
type Wallet struct {
	Coins    int64 `json:"coins"`
	Diamonds int64 `json:"diamonds"`
}

// Store accesses wallet.wallets.
type Store struct{ pool *pgxpool.Pool }

// NewStore returns a Store.
func NewStore(pool *pgxpool.Pool) *Store { return &Store{pool: pool} }

// ProvisionTx creates the wallet with the welcome grant inside tx. The primary
// key makes a second provisioning for the same user impossible.
func ProvisionTx(ctx context.Context, tx pgx.Tx, userID uuid.UUID, coins, diamonds int64) error {
	_, err := tx.Exec(ctx,
		`INSERT INTO wallet.wallets (user_id, coins, diamonds) VALUES ($1, $2, $3)`,
		userID, coins, diamonds)
	return err
}

// Get returns the current balance.
func (s *Store) Get(ctx context.Context, userID uuid.UUID) (Wallet, error) {
	return GetTx(ctx, s.pool, userID)
}

type rowQuerier interface {
	QueryRow(ctx context.Context, sql string, args ...any) pgx.Row
}

// GetTx reads a balance with any querier (pool or tx).
func GetTx(ctx context.Context, q rowQuerier, userID uuid.UUID) (Wallet, error) {
	var w Wallet
	err := q.QueryRow(ctx, `SELECT coins, diamonds FROM wallet.wallets WHERE user_id = $1`, userID).
		Scan(&w.Coins, &w.Diamonds)
	if errors.Is(err, pgx.ErrNoRows) {
		return Wallet{}, ErrNotFound
	}
	return w, err
}

// AdjustTx adds (positive) or removes (negative) coins/diamonds atomically
// inside q. A debit that would make a balance negative changes nothing and
// returns ErrInsufficientFunds.
func AdjustTx(ctx context.Context, q rowQuerier, userID uuid.UUID, coins, diamonds int64) (Wallet, error) {
	var w Wallet
	err := q.QueryRow(ctx, `
		UPDATE wallet.wallets
		   SET coins = coins + $2, diamonds = diamonds + $3
		 WHERE user_id = $1 AND coins + $2 >= 0 AND diamonds + $3 >= 0
		RETURNING coins, diamonds`, userID, coins, diamonds).Scan(&w.Coins, &w.Diamonds)
	if errors.Is(err, pgx.ErrNoRows) {
		if _, gerr := GetTx(ctx, q, userID); errors.Is(gerr, ErrNotFound) {
			return Wallet{}, ErrNotFound
		}
		return Wallet{}, ErrInsufficientFunds
	}
	return w, err
}

// Credit adds a non-negative amount (a person's or a bot's wallet).
func (s *Store) Credit(ctx context.Context, userID uuid.UUID, coins, diamonds int64) (Wallet, error) {
	if coins < 0 || diamonds < 0 {
		return Wallet{}, ErrInvalidAmount
	}
	return AdjustTx(ctx, s.pool, userID, coins, diamonds)
}

// ShortError lists people who could not pay in ChargeEntry / DebitAll.
type ShortError struct{ Users []uuid.UUID }

func (e *ShortError) Error() string {
	return fmt.Sprintf("%d user(s) have insufficient funds", len(e.Users))
}
func (e *ShortError) Unwrap() error { return ErrInsufficientFunds }

// DebitAll charges every user (people only) the same coin amount in ONE
// transaction: either all are charged or nobody is.
func (s *Store) DebitAll(ctx context.Context, users []uuid.UUID, coins int64) (map[uuid.UUID]Wallet, error) {
	return s.ChargeEntry(ctx, users, nil, coins, BotRules{})
}

// ChargeEntry charges every seat of a starting game the same entry fee in ONE
// transaction: either every person and every bot is charged or nobody is.
// All rows are locked in id order (people and bots together) to avoid
// deadlocks between concurrent games. Bot wallets are created first when
// missing (EnsureBots) and, inside the transaction, get the before-match
// rules (reset above ResetAbove, recharge below RechargeBelow or the fee)
// before paying, so a bot can always pay. People who cannot pay make the
// whole charge fail with *ShortError; nothing changes then.
func (s *Store) ChargeEntry(ctx context.Context, people, bots []uuid.UUID, fee int64, rules BotRules) (map[uuid.UUID]Wallet, error) {
	if fee < 0 {
		return nil, ErrInvalidAmount
	}
	out := make(map[uuid.UUID]Wallet, len(people)+len(bots))
	if fee == 0 || len(people)+len(bots) == 0 {
		return out, nil
	}
	if len(bots) > 0 {
		if _, err := s.EnsureBots(ctx, bots, rules.Start); err != nil {
			return nil, err
		}
	}
	all := make([]uuid.UUID, 0, len(people)+len(bots))
	all = append(append(all, people...), bots...)

	tx, err := s.pool.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		return nil, err
	}
	defer tx.Rollback(ctx) //nolint:errcheck

	have, err := lockRows(ctx, tx, all, false)
	if err != nil {
		return nil, err
	}
	var short []uuid.UUID
	for _, u := range people {
		if r, ok := have[u]; !ok || r.bot || r.coins < fee {
			short = append(short, u)
		}
	}
	if len(short) > 0 {
		return nil, &ShortError{Users: short}
	}
	var adjs []BotAdjustment
	for _, b := range bots {
		r, ok := have[b]
		if !ok || !r.bot {
			return nil, fmt.Errorf("bot wallet: %w", ErrNotFound)
		}
		to, adj := rules.BeforeMatch(r.coins, fee)
		if adj.changed() {
			if err := setBotCoins(ctx, tx, b, to); err != nil {
				return nil, err
			}
			adjs = append(adjs, adj)
		}
	}
	for _, u := range all {
		w, err := AdjustTx(ctx, tx, u, -fee, 0)
		if err != nil {
			return nil, err
		}
		out[u] = w
	}
	if err := tx.Commit(ctx); err != nil {
		return nil, err
	}
	record(adjs)
	return out, nil
}

// lockedRow is a wallet row locked FOR UPDATE.
type lockedRow struct {
	coins int64
	bot   bool
}

// lockRows locks the wallets of ids in id order (only bot wallets when
// botsOnly) and returns them by id.
func lockRows(ctx context.Context, tx pgx.Tx, ids []uuid.UUID, botsOnly bool) (map[uuid.UUID]lockedRow, error) {
	q := `SELECT user_id, coins, is_bot FROM wallet.wallets WHERE user_id = ANY($1) ORDER BY user_id FOR UPDATE`
	if botsOnly {
		q = `SELECT user_id, coins, is_bot FROM wallet.wallets WHERE user_id = ANY($1) AND is_bot ORDER BY user_id FOR UPDATE`
	}
	rows, err := tx.Query(ctx, q, ids)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	have := make(map[uuid.UUID]lockedRow, len(ids))
	for rows.Next() {
		var id uuid.UUID
		var r lockedRow
		if err := rows.Scan(&id, &r.coins, &r.bot); err != nil {
			return nil, err
		}
		have[id] = r
	}
	return have, rows.Err()
}
