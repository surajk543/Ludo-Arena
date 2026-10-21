// Package identity maps verified provider identities to internal accounts.
//
// Storage: identity.auth_identities (approved design, separate schema from
// wallet.wallets). An account exists exactly when its wallet row exists; the
// first identity and the wallet (with the welcome grant) are created in one
// transaction, so concurrent first logins can never award the bonus twice.
package identity

import (
	"context"
	"errors"
	"fmt"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"

	"ludoroyale/internal/wallet"
)

// Providers.
const (
	Guest    = "guest"
	Google   = "google"
	Facebook = "facebook"
	Apple    = "apple"
	// Device is the internal device binding used to restore an account after
	// an app update or reinstall (see device.go). It is not a sign-in
	// provider: it is never listed by Providers, never makes an account
	// "linked" and cannot be linked through /account/link.
	Device = "device"
)

// ValidProvider reports whether p is a known sign-in provider (the internal
// Device binding is not one).
func ValidProvider(p string) bool {
	switch p {
	case Guest, Google, Facebook, Apple:
		return true
	}
	return false
}

// Errors.
var (
	// ErrConflict: the provider identity belongs to a different account.
	ErrConflict = errors.New("identity belongs to another account")
	// ErrProviderTaken: the account already has a different identity of this provider.
	ErrProviderTaken = errors.New("account already linked to another identity of this provider")
	// ErrNotFound: no account for the identity.
	ErrNotFound = errors.New("identity not found")
)

// Welcome is the one-time grant for new accounts.
type Welcome struct {
	Coins    int64
	Diamonds int64
}

// Account is the resolved internal account.
type Account struct {
	UserID  uuid.UUID
	Created bool
	Wallet  wallet.Wallet
}

// Store accesses identity.auth_identities.
type Store struct {
	pool    *pgxpool.Pool
	welcome Welcome
}

// NewStore returns a Store.
func NewStore(pool *pgxpool.Pool, welcome Welcome) *Store {
	return &Store{pool: pool, welcome: welcome}
}

// Lookup returns the account owning (provider, subject).
func (s *Store) Lookup(ctx context.Context, provider, subject string) (uuid.UUID, error) {
	var id uuid.UUID
	err := s.pool.QueryRow(ctx,
		`SELECT user_id FROM identity.auth_identities WHERE provider = $1 AND subject = $2`,
		provider, subject).Scan(&id)
	if errors.Is(err, pgx.ErrNoRows) {
		return uuid.Nil, ErrNotFound
	}
	return id, err
}

// FindOrCreate resolves a verified identity, creating a new account (wallet
// with the welcome grant + identity row) only when none exists.
func (s *Store) FindOrCreate(ctx context.Context, provider, subject string) (Account, error) {
	return s.findOrCreate(ctx, ident{provider, subject})
}

// ident is a (provider, subject) pair.
type ident struct{ provider, subject string }

// findOrCreate resolves key, or creates a new account owning key and the
// extra identities. Concurrent first calls for the same key serialize on its
// primary key: exactly one creates the account, the others resolve to it.
func (s *Store) findOrCreate(ctx context.Context, key ident, extra ...ident) (Account, error) {
	if id, err := s.Lookup(ctx, key.provider, key.subject); err == nil {
		w, err := wallet.GetTx(ctx, s.pool, id)
		return Account{UserID: id, Wallet: w}, err
	} else if !errors.Is(err, ErrNotFound) {
		return Account{}, err
	}

	newID := uuid.New()
	created, err := s.createAccount(ctx, newID, append([]ident{key}, extra...))
	if err != nil {
		return Account{}, err
	}
	if created {
		return Account{UserID: newID, Created: true,
			Wallet: wallet.Wallet{Coins: s.welcome.Coins, Diamonds: s.welcome.Diamonds}}, nil
	}
	// A concurrent request created the account first; use it.
	id, err := s.Lookup(ctx, key.provider, key.subject)
	if err != nil {
		return Account{}, err
	}
	w, err := wallet.GetTx(ctx, s.pool, id)
	return Account{UserID: id, Wallet: w}, err
}

// createAccount inserts the wallet and every identity atomically. It returns
// false (and rolls back, discarding the wallet) when an identity already
// exists; the first identity is the one concurrent creators race on.
func (s *Store) createAccount(ctx context.Context, id uuid.UUID, idents []ident) (bool, error) {
	tx, err := s.pool.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		return false, err
	}
	defer tx.Rollback(ctx) //nolint:errcheck
	if err := wallet.ProvisionTx(ctx, tx, id, s.welcome.Coins, s.welcome.Diamonds); err != nil {
		return false, err
	}
	for _, in := range idents {
		var owner uuid.UUID
		err = tx.QueryRow(ctx, `
			INSERT INTO identity.auth_identities (provider, subject, user_id) VALUES ($1, $2, $3)
			ON CONFLICT (provider, subject) DO NOTHING
			RETURNING user_id`, in.provider, in.subject, id).Scan(&owner)
		if errors.Is(err, pgx.ErrNoRows) {
			return false, nil
		}
		if err != nil {
			return false, err
		}
	}
	return true, tx.Commit(ctx)
}

// Link attaches (provider, subject) to an existing account. It never merges
// accounts or moves currency. Linking the same identity twice is idempotent.
func (s *Store) Link(ctx context.Context, userID uuid.UUID, provider, subject string) error {
	if !ValidProvider(provider) {
		return fmt.Errorf("identity: %q cannot be linked", provider) // e.g. Device: use BindDevice
	}
	var owner uuid.UUID
	err := s.pool.QueryRow(ctx, `
		INSERT INTO identity.auth_identities (provider, subject, user_id) VALUES ($1, $2, $3)
		ON CONFLICT (provider, subject) DO NOTHING
		RETURNING user_id`, provider, subject, userID).Scan(&owner)
	if err == nil {
		return nil
	}
	var pgErr *pgconn.PgError
	if errors.As(err, &pgErr) && pgErr.Code == "23505" && pgErr.ConstraintName == "auth_identities_user_provider" {
		return ErrProviderTaken
	}
	if !errors.Is(err, pgx.ErrNoRows) {
		return err
	}
	existing, err := s.Lookup(ctx, provider, subject)
	if err != nil {
		return err
	}
	if existing != userID {
		return ErrConflict
	}
	return nil
}

// Providers lists the sign-in providers linked to an account, sorted. The
// internal Device binding is never included.
func (s *Store) Providers(ctx context.Context, userID uuid.UUID) ([]string, error) {
	rows, err := s.pool.Query(ctx, `
		SELECT provider FROM identity.auth_identities
		WHERE user_id = $1 AND provider <> $2 ORDER BY provider`, userID, Device)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []string
	for rows.Next() {
		var p string
		if err := rows.Scan(&p); err != nil {
			return nil, err
		}
		out = append(out, p)
	}
	return out, rows.Err()
}

// Wallet returns the account's authoritative balance.
func (s *Store) Wallet(ctx context.Context, userID uuid.UUID) (wallet.Wallet, error) {
	return wallet.GetTx(ctx, s.pool, userID)
}

// Exists reports whether the account exists (its wallet row is present).
func (s *Store) Exists(ctx context.Context, userID uuid.UUID) (bool, error) {
	_, err := wallet.GetTx(ctx, s.pool, userID)
	if errors.Is(err, wallet.ErrNotFound) {
		return false, nil
	}
	return err == nil, err
}
