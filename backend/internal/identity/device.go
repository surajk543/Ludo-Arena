package identity

// Device binding: restores an account after an app update or reinstall.
//
// The app sends a platform-scoped device id (Android: Settings.Secure.ANDROID_ID,
// per app-signing key; iOS: a random UUID kept in the keychain). The binding
// is stored as provider Device with subject
//
//	hex(HMAC-SHA256(deviceKey, platform + ":" + lower(deviceId)))
//	deviceKey = HMAC-SHA256(PUBLIC_ID_KEY, "ludo-royale/device-id/v1")
//
// so the raw device id is never stored (or logged), and the same id on
// another platform is a different binding. The table keys give one account
// per device (PRIMARY KEY (provider, subject)) and one device per account
// (UNIQUE (user_id, provider)).
//
// Only guests are bound: a binding is the device guest's restore credential
// (with its guest secret) until the account is deleted or linked to Google,
// Facebook or Apple — Link removes both, BindDevice refuses linked accounts,
// and a binding left on a linked account by older code never resolves (it is
// released for the device's next guest).

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"errors"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
)

// Device id rules.
const (
	DeviceIDMinLen = 16
	DeviceIDMaxLen = 64

	deviceKeyLabel = "ludo-royale/device-id/v1"
	// bindLockClass namespaces the per-account advisory lock that serializes
	// BindDevice and Link calls of one account (two-key form: never overlaps
	// the single-key migration lock).
	bindLockClass = 0x64657669 // "devi"
	// knownBadAndroidID is the ANDROID_ID many Android 2.2 devices shared.
	knownBadAndroidID = "9774d56d682e549c"
)

// Errors.
var (
	// ErrInvalidDevice: the device id or platform is not acceptable.
	ErrInvalidDevice = errors.New("invalid device id or platform")
	// ErrNotGuest: the account is linked to Google, Facebook or Apple; only
	// guests are bound to a device.
	ErrNotGuest = errors.New("account is linked: only guests are bound to a device")
)

// lockAccountBinds takes the transaction-scoped lock that serializes the
// account's BindDevice and Link calls.
func lockAccountBinds(ctx context.Context, tx pgx.Tx, userID uuid.UUID) error {
	_, err := tx.Exec(ctx, `SELECT pg_advisory_xact_lock($1, hashtext($2))`,
		int32(bindLockClass), userID.String())
	return err
}

// DeviceKey derives the device-binding HMAC key from the server secret
// (PUBLIC_ID_KEY) with domain separation, so the secret's other uses (public
// player ids) never share a key with device subjects.
func DeviceKey(secret []byte) []byte {
	m := hmac.New(sha256.New, secret)
	m.Write([]byte(deviceKeyLabel))
	return m.Sum(nil)
}

// ValidDeviceID reports whether id is an acceptable device id: 16–64
// characters of [A-Za-z0-9-], not the known-bad Android id and not a single
// repeated character (e.g. all zeros, ignoring hyphens).
func ValidDeviceID(id string) bool {
	if len(id) < DeviceIDMinLen || len(id) > DeviceIDMaxLen {
		return false
	}
	var first byte
	n, same := 0, true
	for i := 0; i < len(id); i++ {
		c := id[i]
		switch {
		case c == '-':
			continue
		case c >= 'A' && c <= 'Z':
			c += 'a' - 'A'
		case c >= 'a' && c <= 'z', c >= '0' && c <= '9':
		default:
			return false
		}
		if n == 0 {
			first = c
		} else if c != first {
			same = false
		}
		n++
	}
	if n == 0 || same {
		return false
	}
	return lower(id) != knownBadAndroidID
}

// DeviceSubject validates platform ("android" or "ios") and the device id and
// returns the subject stored for the Device binding. Device ids are hex or
// UUID strings, so they are compared case-insensitively.
func DeviceSubject(key []byte, platform, deviceID string) (string, error) {
	if len(key) == 0 {
		return "", errors.New("identity: device key not configured")
	}
	if platform != "android" && platform != "ios" {
		return "", ErrInvalidDevice
	}
	if !ValidDeviceID(deviceID) {
		return "", ErrInvalidDevice
	}
	m := hmac.New(sha256.New, key)
	m.Write([]byte(platform + ":" + lower(deviceID)))
	return hex.EncodeToString(m.Sum(nil)), nil
}

// lower lowercases ASCII letters (device ids are ASCII-only once validated).
func lower(s string) string {
	b := []byte(s)
	for i, c := range b {
		if c >= 'A' && c <= 'Z' {
			b[i] = c + 'a' - 'A'
		}
	}
	return string(b)
}

// FindOrCreateDeviceGuest returns the guest bound to the device or, if the
// device has no guest, creates a new guest account: wallet (welcome grant),
// guest identity and device binding in one transaction. Concurrent first
// calls for the same device create exactly one account. A binding that a
// linked account still holds (written before linking released it) is
// released first, so the device gets a new guest instead of that account.
func (s *Store) FindOrCreateDeviceGuest(ctx context.Context, deviceSubject, guestSubject string) (Account, error) {
	if _, err := s.pool.Exec(ctx, releaseStaleDeviceSQL, Device, deviceSubject); err != nil {
		return Account{}, err
	}
	return s.findOrCreate(ctx, ident{Device, deviceSubject}, ident{Guest, guestSubject})
}

// releaseStaleDeviceSQL deletes the device binding ($1 = Device, $2 =
// subject) if its account is linked: such a binding no longer restores
// anything (LookupGuest ignores it) and the device is free for a guest.
const releaseStaleDeviceSQL = `
	DELETE FROM identity.auth_identities d
	WHERE d.provider = $1 AND d.subject = $2 AND EXISTS (
		SELECT 1 FROM identity.auth_identities l
		WHERE l.user_id = d.user_id AND l.` + linkedProviderSQL + `)`

// errRetryBind: a concurrent bind by another account took the device.
var errRetryBind = errors.New("concurrent device bind")

// BindDevice binds the device to the guest account: a no-op if it already
// is, ErrNotGuest if the account is linked (only guests are bound),
// ErrConflict if the device belongs to another guest (it is never moved),
// and otherwise it replaces the account's previous device binding, if any
// (one device per account). Binds and links of one account are serialized
// by a transaction-scoped advisory lock; a race with another account for
// the same device is re-checked (and then reports ErrConflict).
func (s *Store) BindDevice(ctx context.Context, userID uuid.UUID, deviceSubject string) error {
	for attempt := 0; ; attempt++ {
		err := s.bindDeviceOnce(ctx, userID, deviceSubject)
		if !errors.Is(err, errRetryBind) || attempt == 2 {
			return err
		}
	}
}

func (s *Store) bindDeviceOnce(ctx context.Context, userID uuid.UUID, subject string) error {
	tx, err := s.pool.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx) //nolint:errcheck
	if err := lockAccountBinds(ctx, tx, userID); err != nil {
		return err
	}
	switch linked, err := isLinked(ctx, tx, userID); {
	case err != nil:
		return err
	case linked:
		return ErrNotGuest
	}
	if _, err := tx.Exec(ctx, releaseStaleDeviceSQL, Device, subject); err != nil {
		return err
	}
	var owner uuid.UUID
	err = tx.QueryRow(ctx,
		`SELECT user_id FROM identity.auth_identities WHERE provider = $1 AND subject = $2`,
		Device, subject).Scan(&owner)
	switch {
	case err == nil && owner == userID:
		return nil
	case err == nil:
		return ErrConflict
	case !errors.Is(err, pgx.ErrNoRows):
		return err
	}
	if _, err := tx.Exec(ctx,
		`DELETE FROM identity.auth_identities WHERE provider = $1 AND user_id = $2`, Device, userID); err != nil {
		return err
	}
	err = tx.QueryRow(ctx, `
		INSERT INTO identity.auth_identities (provider, subject, user_id) VALUES ($1, $2, $3)
		ON CONFLICT (provider, subject) DO NOTHING
		RETURNING user_id`, Device, subject, userID).Scan(&owner)
	var pgErr *pgconn.PgError
	switch {
	case errors.Is(err, pgx.ErrNoRows):
		// Bound concurrently (by this or another account): re-check.
		return errRetryBind
	case errors.As(err, &pgErr) && pgErr.Code == "23505" && pgErr.ConstraintName == "auth_identities_user_provider":
		// Defensive: binds of one account are serialized, so this needs a
		// writer outside BindDevice; re-check.
		return errRetryBind
	case err != nil:
		return err
	}
	return tx.Commit(ctx)
}
