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

	"ludoarena/internal/wallet"
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
	welcome func() Welcome // read once per account creation (live config)
}

// NewStore returns a Store with a fixed welcome grant.
func NewStore(pool *pgxpool.Pool, welcome Welcome) *Store {
	return NewStoreWithGrant(pool, func() Welcome { return welcome })
}

// NewStoreWithGrant returns a Store whose welcome grant is looked up when each
// account is created, so a live config change applies to later accounts only.
func NewStoreWithGrant(pool *pgxpool.Pool, welcome func() Welcome) *Store {
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
	grant := s.welcome()
	created, err := s.createAccount(ctx, newID, append([]ident{key}, extra...), grant)
	if err != nil {
		return Account{}, err
	}
	if created {
		return Account{UserID: newID, Created: true,
			Wallet: wallet.Wallet{Coins: grant.Coins, Diamonds: grant.Diamonds}}, nil
	}
	// A concurrent request created the account first; use it.
	id, err := s.Lookup(ctx, key.provider, key.subject)
	if err != nil {
		return Account{}, err
	}
	w, err := wallet.GetTx(ctx, s.pool, id)
	return Account{UserID: id, Wallet: w}, err
}

// createAccount inserts the wallet (with the welcome grant) and every
// identity atomically. It returns false (and rolls back, discarding the
// wallet) when an identity already exists; the first identity is the one
// concurrent creators race on.
func (s *Store) createAccount(ctx context.Context, id uuid.UUID, idents []ident, grant Welcome) (bool, error) {
	tx, err := s.pool.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		return false, err
	}
	defer tx.Rollback(ctx) //nolint:errcheck
	if err := wallet.ProvisionTx(ctx, tx, id, grant.Coins, grant.Diamonds); err != nil {
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
//
// Linking Google, Facebook or Apple ends the account's life as a device
// guest: in the same transaction its guest secret and device binding are
// removed, so neither "Play as guest" nor a reinstall on that device
// resolves to it any more — it is reached by signing in with a linked
// provider (docs/authentication.md "Guest persistence"). The transaction
// holds the account's bind lock, so a concurrent BindDevice cannot re-bind
// it.
func (s *Store) Link(ctx context.Context, userID uuid.UUID, provider, subject string) error {
	if !ValidProvider(provider) {
		return fmt.Errorf("identity: %q cannot be linked", provider) // e.g. Device: use BindDevice
	}
	tx, err := s.pool.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx) //nolint:errcheck
	if err := lockAccountBinds(ctx, tx, userID); err != nil {
		return err
	}
	var owner uuid.UUID
	err = tx.QueryRow(ctx, `
		INSERT INTO identity.auth_identities (provider, subject, user_id) VALUES ($1, $2, $3)
		ON CONFLICT (provider, subject) DO NOTHING
		RETURNING user_id`, provider, subject, userID).Scan(&owner)
	var pgErr *pgconn.PgError
	switch {
	case err == nil:
	case errors.As(err, &pgErr) && pgErr.Code == "23505" && pgErr.ConstraintName == "auth_identities_user_provider":
		return ErrProviderTaken
	case !errors.Is(err, pgx.ErrNoRows):
		return err
	default:
		// The identity exists: idempotent for this account, else a conflict.
		err = tx.QueryRow(ctx,
			`SELECT user_id FROM identity.auth_identities WHERE provider = $1 AND subject = $2`,
			provider, subject).Scan(&owner)
		if errors.Is(err, pgx.ErrNoRows) {
			return ErrNotFound
		}
		if err != nil {
			return err
		}
		if owner != userID {
			return ErrConflict
		}
	}
	if provider != Guest {
		if _, err := tx.Exec(ctx,
			`DELETE FROM identity.auth_identities WHERE user_id = $1 AND provider IN ($2, $3)`,
			userID, Guest, Device); err != nil {
			return err
		}
	}
	return tx.Commit(ctx)
}

// linkedProviderSQL matches the providers that make an account "linked"
// (no longer a guest): the user-facing sign-in providers.
const linkedProviderSQL = `provider IN ('google', 'facebook', 'apple')`

// querier is the read side shared by the pool and transactions.
type querier interface {
	QueryRow(ctx context.Context, sql string, args ...any) pgx.Row
}

// isLinked reports whether the account has a Google, Facebook or Apple
// identity (it is then no longer a guest).
func isLinked(ctx context.Context, q querier, userID uuid.UUID) (bool, error) {
	var linked bool
	err := q.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM identity.auth_identities
		WHERE user_id = $1 AND `+linkedProviderSQL+`)`, userID).Scan(&linked)
	return linked, err
}

// LookupGuest resolves a guest credential — provider Guest (the hash of a
// guest secret) or Device (a device binding) — to its account. ErrNotFound
// when there is none, and also when that account has been linked since: a
// guest credential never signs in to a linked account. (Linking removes
// both credentials; this also covers rows written before it did.)
func (s *Store) LookupGuest(ctx context.Context, provider, subject string) (uuid.UUID, error) {
	var id uuid.UUID
	var linked bool
	err := s.pool.QueryRow(ctx, `
		SELECT i.user_id, EXISTS (SELECT 1 FROM identity.auth_identities l
			WHERE l.user_id = i.user_id AND l.`+linkedProviderSQL+`)
		FROM identity.auth_identities i WHERE i.provider = $1 AND i.subject = $2`,
		provider, subject).Scan(&id, &linked)
	if errors.Is(err, pgx.ErrNoRows) || (err == nil && linked) {
		return uuid.Nil, ErrNotFound
	}
	return id, err
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
	var ok bool
	err := s.pool.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM wallet.wallets WHERE user_id = $1 AND NOT is_bot)`,
		userID).Scan(&ok)
	return ok, err
}
