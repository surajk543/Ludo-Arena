// Package profile derives public player ids and serves display profiles.
//
// A display profile is a public id, a display name and an avatar. The Redis
// hash profile:{userId} caches it for every reader (friends, leaderboards,
// invites, room seats). Where the name comes from, highest precedence first:
//
//  1. A name the player chose (PATCH /api/v1/me, ChangeName). It is
//     authoritative in PostgreSQL (progression.player_progress.display_name,
//     migration 005) and written to the cache in the same request. Sign-ins
//     never overwrite it: Save re-reads it from PostgreSQL on every sign-in
//     and provider link, and Get / GetMany rebuild a lost cache entry from it.
//  2. Otherwise the provider's name, refreshed on every provider sign-in or
//     link (non-authoritative presentation data, cache only).
//  3. Otherwise the cached name, or a generated "Player XXXX".
//
// Chosen names follow ValidateName (names.go) and are limited to
// NameChangesPerDay successful changes per account per rolling 24 h
// (Redis namechg:{userId}). Rooms copy the name into the seat when a player
// joins, so rooms that are already open or playing keep the name the player
// joined with; rooms joined afterwards show the new one.
package profile

import (
	"context"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base32"
	"encoding/hex"
	"errors"
	"fmt"
	"strconv"
	"strings"
	"time"
	"unicode"
	"unicode/utf8"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/redis/go-redis/v9"
)

// Profile is what other players may see.
type Profile struct {
	UID    string `json:"uid"`
	Name   string `json:"name"`
	Avatar int    `json:"avatar"`
}

// DefaultNameChangesPerDay is the default NAME_CHANGES_PER_DAY.
const DefaultNameChangesPerDay = 3

// NameChangeWindow is the rolling window of the name-change limit.
const NameChangeWindow = 24 * time.Hour

// Options configure player-chosen display names (WithPostgres).
type Options struct {
	// NameChangesPerDay is the number of successful name changes allowed per
	// account per rolling 24 h (default DefaultNameChangesPerDay).
	NameChangesPerDay int
	// Now is the clock of the name-change limit (default time.Now).
	Now func() time.Time
}

// LimitError is returned by ChangeName when the account used up its name
// changes for the rolling window.
type LimitError struct {
	Limit      int           // changes allowed per window
	RetryAfter time.Duration // until the oldest change leaves the window
}

func (e *LimitError) Error() string {
	return fmt.Sprintf("display name changed %d times in 24 h; retry in %s", e.Limit, e.RetryAfter)
}

// ErrNoStore is returned by ChangeName when PostgreSQL is not configured.
var ErrNoStore = errors.New("profile: chosen display names need PostgreSQL")

// Service manages public ids and display profiles.
type Service struct {
	rdb           *redis.Client
	key           []byte
	pg            *pgxpool.Pool // nil: no chosen names (provider/generated only)
	changesPerDay int
	now           func() time.Time
}

// New returns a Service. key is the HMAC secret for public ids. Without
// WithPostgres it serves provider and generated names only.
func New(rdb *redis.Client, key []byte) *Service {
	return &Service{rdb: rdb, key: key, changesPerDay: DefaultNameChangesPerDay, now: time.Now}
}

// WithPostgres enables player-chosen display names stored in
// progression.player_progress.display_name. A nil pool leaves them disabled.
func (s *Service) WithPostgres(pool *pgxpool.Pool, opts Options) *Service {
	s.pg = pool
	if opts.NameChangesPerDay > 0 {
		s.changesPerDay = opts.NameChangesPerDay
	}
	if opts.Now != nil {
		s.now = opts.Now
	}
	return s
}

// NameChangesPerDay returns the configured name-change limit.
func (s *Service) NameChangesPerDay() int { return s.changesPerDay }

var b32 = base32.NewEncoding("abcdefghijkmnpqrstuvwxyz23456789").WithPadding(base32.NoPadding)

// PublicID returns the stable pseudonymous id shown to other players
// ("u_" + 12 chars). It does not reveal the account id.
func (s *Service) PublicID(userID uuid.UUID) string {
	m := hmac.New(sha256.New, s.key)
	m.Write(userID[:])
	return "u_" + b32.EncodeToString(m.Sum(nil))[:12]
}

// Avatar returns the default avatar index (0..11) for an account.
func (s *Service) Avatar(userID uuid.UUID) int { return int(userID[15]) % 12 }

// GuestName is the generated name for accounts without a provider name.
func (s *Service) GuestName(userID uuid.UUID) string {
	return "Player " + strings.ToUpper(s.PublicID(userID)[2:6])
}

// SanitizeName trims, removes control characters and limits the length of
// provider and bot names. Empty results return "". Player-chosen names use
// the stricter ValidateName instead.
func SanitizeName(name string) string {
	name = strings.TrimSpace(name)
	var b strings.Builder
	for _, r := range name {
		if unicode.IsControl(r) || r == utf8.RuneError {
			continue
		}
		b.WriteRune(r)
	}
	out := strings.Join(strings.Fields(b.String()), " ")
	if r := []rune(out); len(r) > 20 {
		out = strings.TrimSpace(string(r[:20]))
	}
	return out
}

func profileKey(userID uuid.UUID) string { return "profile:" + userID.String() }

// NameChangesKey is the ZSET of an account's successful name changes in the
// rolling window (member = change id, score = unix ms).
func NameChangesKey(userID uuid.UUID) string { return "namechg:" + userID.String() }

// Save refreshes the display profile at sign-in (and on provider linking)
// and stores the public-id → account mapping. A name the player chose always
// wins over name (the provider's name). Otherwise a non-empty name replaces
// the cached one; an empty name keeps the cached name or uses a generated one.
func (s *Service) Save(ctx context.Context, userID uuid.UUID, name string) (Profile, error) {
	chosen, err := s.chosenName(ctx, userID)
	if err != nil {
		return Profile{}, err
	}
	if chosen != "" {
		return s.cache(ctx, userID, chosen)
	}
	name = SanitizeName(name)
	if name == "" {
		existing, err := s.rdb.HGet(ctx, profileKey(userID), "name").Result()
		if err == nil && existing != "" {
			name = existing
		} else {
			name = s.GuestName(userID)
		}
	}
	return s.cache(ctx, userID, name)
}

// cache writes the display profile and the public-id mapping to Redis.
func (s *Service) cache(ctx context.Context, userID uuid.UUID, name string) (Profile, error) {
	p := Profile{UID: s.PublicID(userID), Name: name, Avatar: s.Avatar(userID)}
	pipe := s.rdb.TxPipeline()
	pipe.HSet(ctx, profileKey(userID), "name", p.Name, "avatar", p.Avatar)
	pipe.Set(ctx, "pubid:"+p.UID, userID.String(), 0)
	_, err := pipe.Exec(ctx)
	return p, err
}

// chosenName returns the player-chosen name from PostgreSQL ("" if none, if
// the account has no progression row yet, or without PostgreSQL).
func (s *Service) chosenName(ctx context.Context, userID uuid.UUID) (string, error) {
	if s.pg == nil {
		return "", nil
	}
	var name *string
	err := s.pg.QueryRow(ctx, `SELECT display_name FROM progression.player_progress WHERE user_id = $1`,
		userID).Scan(&name)
	if errors.Is(err, pgx.ErrNoRows) {
		return "", nil
	}
	if err != nil {
		return "", err
	}
	if name == nil {
		return "", nil
	}
	return *name, nil
}

// Get returns the cached profile. A missing cache entry is rebuilt from
// PostgreSQL (see GetMany); otherwise defaults are generated.
func (s *Service) Get(ctx context.Context, userID uuid.UUID) Profile {
	return s.GetMany(ctx, []uuid.UUID{userID})[userID]
}

// GetMany returns profiles for several accounts in one Redis round trip,
// plus one PostgreSQL query when some cache entries are missing.
func (s *Service) GetMany(ctx context.Context, ids []uuid.UUID) map[uuid.UUID]Profile {
	out := make(map[uuid.UUID]Profile, len(ids))
	pipe := s.rdb.Pipeline()
	cmds := make([]*redis.SliceCmd, len(ids))
	for i, id := range ids {
		cmds[i] = pipe.HMGet(ctx, profileKey(id), "name", "avatar")
	}
	_, _ = pipe.Exec(ctx)
	var missing []uuid.UUID
	for i, id := range ids {
		p := Profile{UID: s.PublicID(id), Avatar: s.Avatar(id), Name: s.GuestName(id)}
		if vals, err := cmds[i].Result(); err == nil {
			if n, ok := vals[0].(string); ok && n != "" {
				p.Name = n
			} else {
				missing = append(missing, id)
			}
			if a, ok := vals[1].(string); ok {
				if v, err := strconv.Atoi(a); err == nil && v >= 0 && v < 12 {
					p.Avatar = v
				}
			}
		}
		out[id] = p
	}
	if len(missing) > 0 {
		s.rebuild(ctx, missing, out)
	}
	return out
}

// rebuild restores lost cache entries of accounts from PostgreSQL: the
// chosen name, or the generated name for accounts without one (what readers
// saw before; the next sign-in refreshes a provider name). Ids that are not
// accounts (bots, unknown ids) stay uncached. HSETNX never overwrites a name
// written concurrently (e.g. by ChangeName).
func (s *Service) rebuild(ctx context.Context, ids []uuid.UUID, out map[uuid.UUID]Profile) {
	if s.pg == nil {
		return
	}
	rows, err := s.pg.Query(ctx, `
		SELECT w.user_id, p.display_name
		FROM wallet.wallets w LEFT JOIN progression.player_progress p ON p.user_id = w.user_id
		WHERE w.user_id = ANY($1)`, ids)
	if err != nil {
		return
	}
	defer rows.Close()
	pipe := s.rdb.Pipeline()
	for rows.Next() {
		var id uuid.UUID
		var name *string
		if rows.Scan(&id, &name) != nil {
			return
		}
		p, ok := out[id]
		if !ok {
			continue
		}
		if name != nil {
			p.Name = *name
			out[id] = p
		}
		pipe.HSetNX(ctx, profileKey(id), "name", p.Name)
		pipe.HSetNX(ctx, profileKey(id), "avatar", p.Avatar)
		pipe.Set(ctx, "pubid:"+p.UID, id.String(), 0)
	}
	if rows.Err() == nil && pipe.Len() > 0 {
		_, _ = pipe.Exec(ctx)
	}
}

// Resolve maps a public id back to an account id (cache; durable callers
// should fall back to the progression store).
func (s *Service) Resolve(ctx context.Context, uid string) (uuid.UUID, error) {
	raw, err := s.rdb.Get(ctx, "pubid:"+uid).Result()
	if err != nil {
		return uuid.Nil, fmt.Errorf("unknown public id: %w", err)
	}
	return uuid.Parse(raw)
}

// ensureProgress creates the account's progression row if needed (the same
// statement as progression.Service: no conflict target, so both unique
// indexes arbitrate concurrent first inserts).
const ensureProgress = `
	INSERT INTO progression.player_progress (user_id, public_id) VALUES ($1, $2)
	ON CONFLICT DO NOTHING`

// ChangeName validates raw (ValidateName) and makes it the account's chosen
// display name: PostgreSQL (authoritative) and the Redis cache, inside one
// transaction that holds the account's progression row lock, so concurrent
// changes of one account are serialized.
//
// Choosing the current chosen name again is a no-op (it only re-syncs the
// cache). Choosing the name currently shown (provider or generated) pins it
// as the chosen name. Neither counts toward the limit; changed reports
// whether the change counted. Errors: *NameError, *LimitError, ErrNoStore or
// infrastructure errors.
func (s *Service) ChangeName(ctx context.Context, userID uuid.UUID, raw string) (p Profile, changed bool, err error) {
	if s.pg == nil {
		return Profile{}, false, ErrNoStore
	}
	name, err := ValidateName(raw)
	if err != nil {
		return Profile{}, false, err
	}
	tx, err := s.pg.Begin(ctx)
	if err != nil {
		return Profile{}, false, err
	}
	defer tx.Rollback(context.WithoutCancel(ctx)) //nolint:errcheck // no-op after Commit
	if _, err := tx.Exec(ctx, ensureProgress, userID, s.PublicID(userID)); err != nil {
		return Profile{}, false, err
	}
	var current *string
	if err := tx.QueryRow(ctx, `SELECT display_name FROM progression.player_progress WHERE user_id = $1 FOR UPDATE`,
		userID).Scan(&current); err != nil {
		return Profile{}, false, err
	}
	if current != nil && *current == name {
		p, err := s.cache(ctx, userID, name)
		return p, false, err
	}
	previous := s.Get(ctx, userID).Name
	counted := current != nil || previous != name
	var slot string
	if counted {
		if slot, err = s.reserveChange(ctx, userID); err != nil {
			return Profile{}, false, err
		}
	}
	release := func() {
		if slot != "" {
			_ = s.rdb.ZRem(context.WithoutCancel(ctx), NameChangesKey(userID), slot).Err()
		}
	}
	if _, err := tx.Exec(ctx, `UPDATE progression.player_progress SET display_name = $2 WHERE user_id = $1`,
		userID, name); err != nil {
		release()
		return Profile{}, false, err
	}
	if p, err = s.cache(ctx, userID, name); err != nil {
		release()
		return Profile{}, false, err
	}
	if err := tx.Commit(ctx); err != nil {
		release()
		_, _ = s.cache(context.WithoutCancel(ctx), userID, previous) // best effort: undo the cache write
		return Profile{}, false, err
	}
	return p, counted, nil
}

// reserveScript atomically drops changes older than the window and, while
// the account is under the limit, records a new one. It returns {1, 0} when
// recorded and {0, oldestMs} when the limit is reached.
var reserveScript = redis.NewScript(`
redis.call('ZREMRANGEBYSCORE', KEYS[1], '-inf', tonumber(ARGV[1]) - tonumber(ARGV[2]))
if redis.call('ZCARD', KEYS[1]) >= tonumber(ARGV[3]) then
  local oldest = redis.call('ZRANGE', KEYS[1], 0, 0, 'WITHSCORES')
  return {0, tonumber(oldest[2])}
end
redis.call('ZADD', KEYS[1], ARGV[1], ARGV[4])
redis.call('PEXPIRE', KEYS[1], ARGV[2])
return {1, 0}`)

// reserveChange records one name change in the rolling window and returns
// its member (to release it if the change fails), or a *LimitError.
func (s *Service) reserveChange(ctx context.Context, userID uuid.UUID) (string, error) {
	var nonce [8]byte
	_, _ = rand.Read(nonce[:])
	now := s.now().UnixMilli()
	member := strconv.FormatInt(now, 10) + ":" + hex.EncodeToString(nonce[:])
	window := NameChangeWindow.Milliseconds()
	res, err := reserveScript.Run(ctx, s.rdb, []string{NameChangesKey(userID)},
		now, window, s.changesPerDay, member).Int64Slice()
	if err != nil {
		return "", err
	}
	if len(res) != 2 {
		return "", fmt.Errorf("profile: unexpected name-change reply %v", res)
	}
	if res[0] == 1 {
		return member, nil
	}
	retry := time.Duration(res[1]+window-now) * time.Millisecond
	if retry < time.Second {
		retry = time.Second
	}
	return "", &LimitError{Limit: s.changesPerDay, RetryAfter: retry}
}
