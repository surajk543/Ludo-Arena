// Package wallet manages coin and diamond balances in PostgreSQL. Every
// balance change is a single atomic SQL statement or transaction; balances can
// never go negative (CHECK constraints plus conditional updates).
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

// Credit adds a non-negative amount.
func (s *Store) Credit(ctx context.Context, userID uuid.UUID, coins, diamonds int64) (Wallet, error) {
	if coins < 0 || diamonds < 0 {
		return Wallet{}, ErrInvalidAmount
	}
	return AdjustTx(ctx, s.pool, userID, coins, diamonds)
}

// ShortError lists users who could not pay in DebitAll.
type ShortError struct{ Users []uuid.UUID }

func (e *ShortError) Error() string {
	return fmt.Sprintf("%d user(s) have insufficient funds", len(e.Users))
}
func (e *ShortError) Unwrap() error { return ErrInsufficientFunds }

// DebitAll charges every user the same coin amount in ONE transaction: either
// all are charged or nobody is. Users are locked in id order to avoid
// deadlocks between concurrent games.
func (s *Store) DebitAll(ctx context.Context, users []uuid.UUID, coins int64) (map[uuid.UUID]Wallet, error) {
	if coins < 0 {
		return nil, ErrInvalidAmount
	}
	out := make(map[uuid.UUID]Wallet, len(users))
	if coins == 0 || len(users) == 0 {
		return out, nil
	}
	tx, err := s.pool.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		return nil, err
	}
	defer tx.Rollback(ctx) //nolint:errcheck

	rows, err := tx.Query(ctx, `
		SELECT user_id, coins FROM wallet.wallets
		 WHERE user_id = ANY($1) ORDER BY user_id FOR UPDATE`, users)
	if err != nil {
		return nil, err
	}
	have := map[uuid.UUID]int64{}
	for rows.Next() {
		var id uuid.UUID
		var c int64
		if err := rows.Scan(&id, &c); err != nil {
			rows.Close()
			return nil, err
		}
		have[id] = c
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return nil, err
	}
	var short []uuid.UUID
	for _, u := range users {
		if c, ok := have[u]; !ok || c < coins {
			short = append(short, u)
		}
	}
	if len(short) > 0 {
		return nil, &ShortError{Users: short}
	}
	for _, u := range users {
		w, err := AdjustTx(ctx, tx, u, -coins, 0)
		if err != nil {
			return nil, err
		}
		out[u] = w
	}
	if err := tx.Commit(ctx); err != nil {
		return nil, err
	}
	return out, nil
}
