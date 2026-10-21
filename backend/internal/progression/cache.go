package progression

// Hot-path caches (docs/architecture.md → PostgreSQL on the hot path;
// backend/docs/redis-keys.md). PostgreSQL stays the source of truth: every
// Redis error falls back to it, so a cache outage never fails a join or an
// emote.
//
// Seat summary — seat:{userId}, string (JSON), TTL SeatCacheTTL. What a room
// seat shows of an account: its level, the loadout slots that differ from
// the starter loadout (the title is the loadout's title slot) and the
// equipped profile picture id. Matchmaking,
// private joins and practice starts read it instead of PostgreSQL. Every
// committed change to level or loadout deletes it (InvalidateSeat): level-ups
// in RecordMatch and Claim, Equip and ApplyPicture. A miss takes a fill lease
// (seat:{userId}:lease) atomically with the read, reads PostgreSQL and stores
// the entry only while the lease is still its own; InvalidateSeat deletes the
// entry and the lease, so a fill that read PostgreSQL before a concurrent
// commit can never store the old value.
//
// Owned emotes — emotes:{userId}, set, TTL EmoteCacheTTL. The account's
// non-starter emotes, read on every chat.emote. Inventory rows are never
// deleted, so a member is always a correct "owned" answer; a missing member is
// confirmed in PostgreSQL (and added), so a fill racing a grant can never deny
// an owned emote. Grants (purchase, mission/event rewards, level milestones)
// add to an existing set (write-through). Starter emotes need no lookup.

import (
	"context"
	"encoding/json"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/redis/go-redis/v9"

	"ludoroyale/internal/metrics"
	"ludoroyale/internal/playerinfo"
)

// Cache TTLs. Correctness rests on invalidation (seat) and on the set being
// append-only with negatives confirmed in PostgreSQL (emotes); the TTL only
// bounds how long a failed invalidation can leave a seat stale. One hour
// outlasts a game (a classic Ludo game can take 20+ minutes), so the join
// after a game is usually a hit.
const (
	SeatCacheTTL  = time.Hour
	EmoteCacheTTL = time.Hour
	seatLeaseTTL  = 5 * time.Second // ≥ the 5 s statement timeout of the fill query
)

// SeatKey is the Redis key of an account's cached seat summary.
func SeatKey(userID uuid.UUID) string { return "seat:" + userID.String() }

func seatLeaseKey(userID uuid.UUID) string { return "seat:" + userID.String() + ":lease" }

// EmotesKey is the Redis set of an account's owned non-starter emotes.
func EmotesKey(userID uuid.UUID) string { return "emotes:" + userID.String() }

var _ playerinfo.SeatProvider = (*Service)(nil)

// seatEntry is the cached JSON: level, non-starter loadout slots and the
// equipped profile picture id (resolved against the in-memory picture
// catalogue when read).
type seatEntry struct {
	Level   int               `json:"l"`
	Loadout map[string]string `json:"lo,omitempty"`
	Picture string            `json:"p,omitempty"`
}

// seatGet returns the cached entry, or takes the fill lease (1) or reports
// that another caller holds it (0).
var seatGet = redis.NewScript(`
local v = redis.call('GET', KEYS[1])
if v then return v end
if redis.call('SET', KEYS[2], ARGV[1], 'NX', 'PX', ARGV[2]) then return 1 end
return 0`)

// seatFill stores the entry only if the caller still holds the lease (no
// invalidation happened since its PostgreSQL read began).
var seatFill = redis.NewScript(`
if redis.call('GET', KEYS[2]) ~= ARGV[1] then return 0 end
redis.call('SET', KEYS[1], ARGV[2], 'PX', ARGV[3])
redis.call('DEL', KEYS[2])
return 1`)

// SeatSummary implements playerinfo.SeatProvider: the account's level, title
// and loadout for a room seat, from Redis when cached (XP is not cached and is
// always 0; LevelXP/NextLevelXP describe the level). A miss reads PostgreSQL
// through Summary (which also creates a missing progression row).
func (s *Service) SeatSummary(ctx context.Context, userID uuid.UUID) (playerinfo.Summary, error) {
	if s.rdb == nil {
		return s.seatFromPG(ctx, userID)
	}
	keys := []string{SeatKey(userID), seatLeaseKey(userID)}
	token := uuid.NewString()
	res, err := seatGet.Run(ctx, s.rdb, keys, token, seatLeaseTTL.Milliseconds()).Result()
	if err != nil {
		metrics.CacheLookups.WithLabelValues("seat", "error").Inc()
		s.log.Warn("seat cache unavailable; reading PostgreSQL", "error", err.Error())
		return s.seatFromPG(ctx, userID)
	}
	if raw, ok := res.(string); ok {
		var e seatEntry
		if json.Unmarshal([]byte(raw), &e) == nil && e.Level >= 1 {
			metrics.CacheLookups.WithLabelValues("seat", "hit").Inc()
			return s.seatView(e), nil
		}
		s.InvalidateSeat(ctx, userID) // unreadable entry: drop it, refill next time
	}
	metrics.CacheLookups.WithLabelValues("seat", "miss").Inc()
	sum, err := s.Summary(ctx, userID)
	if err != nil {
		return playerinfo.Summary{}, err
	}
	e := seatEntryOf(sum)
	if lease, _ := res.(int64); lease == 1 {
		raw, _ := json.Marshal(e)
		if err := seatFill.Run(ctx, s.rdb, keys, token, raw, SeatCacheTTL.Milliseconds()).Err(); err != nil {
			metrics.CacheWriteErrors.WithLabelValues("seat", "fill").Inc()
		}
	}
	return s.seatView(e), nil
}

// seatFromPG reads the seat summary from PostgreSQL only.
func (s *Service) seatFromPG(ctx context.Context, userID uuid.UUID) (playerinfo.Summary, error) {
	sum, err := s.Summary(ctx, userID)
	if err != nil {
		return playerinfo.Summary{}, err
	}
	return s.seatView(seatEntryOf(sum)), nil
}

// InvalidateSeat drops the cached seat summary and any fill lease. Call it
// after every committed change to an account's level or loadout. A failed
// delete leaves the entry stale until SeatCacheTTL (logged and counted).
func (s *Service) InvalidateSeat(ctx context.Context, userID uuid.UUID) {
	if s.rdb == nil {
		return
	}
	if err := s.rdb.Del(context.WithoutCancel(ctx), SeatKey(userID), seatLeaseKey(userID)).Err(); err != nil {
		metrics.CacheWriteErrors.WithLabelValues("seat", "invalidate").Inc()
		s.log.Warn("seat cache invalidation failed; entry may be stale until its TTL", "error", err.Error())
	}
}

func seatEntryOf(sum playerinfo.Summary) seatEntry {
	e := seatEntry{Level: sum.Level}
	if e.Level < 1 {
		e.Level = 1
	}
	if sum.Picture != nil {
		e.Picture = sum.Picture.ID
	}
	starter := playerinfo.StarterLoadout()
	for slot, item := range sum.Loadout {
		if item != "" && item != starter[slot] {
			if e.Loadout == nil {
				e.Loadout = map[string]string{}
			}
			e.Loadout[slot] = item
		}
	}
	return e
}

// seatView expands an entry; items no longer in the catalog (or in the wrong
// slot) fall back to the starter item, exactly like loadouts().
func (s *Service) seatView(e seatEntry) playerinfo.Summary {
	lo := playerinfo.StarterLoadout()
	for slot, item := range e.Loadout {
		if it := s.catalog.Get(item); it != nil && it.Kind == slot {
			if _, ok := lo[slot]; ok {
				lo[slot] = item
			}
		}
	}
	return playerinfo.Summary{Level: e.Level, LevelXP: LevelStartXP(e.Level), NextLevelXP: XPToNext(e.Level),
		Title: lo["title"], Loadout: lo, Picture: s.pictureRef(e.Picture)}
}

// emoteCheck: -1 = no cached set, 1 = member, 0 = set without the member.
var emoteCheck = redis.NewScript(`
if redis.call('EXISTS', KEYS[1]) == 0 then return -1 end
return redis.call('SISMEMBER', KEYS[1], ARGV[1])`)

// emoteAdd adds members to an existing set only, so a write never creates a
// partial set or a set without a TTL.
var emoteAdd = redis.NewScript(`
if redis.call('EXISTS', KEYS[1]) == 0 then return 0 end
redis.call('SADD', KEYS[1], unpack(ARGV))
return 1`)

// ownsEmote answers Owns for a non-starter emote from the cached set.
func (s *Service) ownsEmote(ctx context.Context, userID uuid.UUID, itemID string) (bool, error) {
	if s.rdb == nil {
		return s.ownsStored(ctx, userID, itemID)
	}
	key := EmotesKey(userID)
	n, err := emoteCheck.Run(ctx, s.rdb, []string{key}, itemID).Int()
	switch {
	case err != nil:
		metrics.CacheLookups.WithLabelValues("emotes", "error").Inc()
		s.log.Warn("emote cache unavailable; reading PostgreSQL", "error", err.Error())
		return s.ownsStored(ctx, userID, itemID)
	case n == 1:
		metrics.CacheLookups.WithLabelValues("emotes", "hit").Inc()
		return true, nil
	case n == 0:
		// Not in the set: confirm (a fill can race a grant), repair if owned.
		metrics.CacheLookups.WithLabelValues("emotes", "verify").Inc()
		ok, err := s.ownsStored(ctx, userID, itemID)
		if err == nil && ok {
			s.addEmotes(ctx, userID, []string{itemID})
		}
		return ok, err
	}
	metrics.CacheLookups.WithLabelValues("emotes", "miss").Inc()
	owned, err := s.ownedEmotes(ctx, userID)
	if err != nil {
		return false, err
	}
	if len(owned) > 0 {
		members := make([]any, len(owned))
		for i, id := range owned {
			members[i] = id
		}
		pipe := s.rdb.TxPipeline()
		pipe.SAdd(ctx, key, members...)
		pipe.PExpire(ctx, key, EmoteCacheTTL)
		if _, err := pipe.Exec(ctx); err != nil {
			metrics.CacheWriteErrors.WithLabelValues("emotes", "fill").Inc()
		}
	}
	for _, id := range owned {
		if id == itemID {
			return true, nil
		}
	}
	return false, nil
}

// ownsStored reads ownership of a non-starter item from PostgreSQL.
func (s *Service) ownsStored(ctx context.Context, userID uuid.UUID, itemID string) (bool, error) {
	var ok bool
	err := s.pool.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM progression.inventory WHERE user_id = $1 AND item_id = $2)`,
		userID, itemID).Scan(&ok)
	return ok, err
}

// ownedEmotes returns the account's non-starter emotes from PostgreSQL.
func (s *Service) ownedEmotes(ctx context.Context, userID uuid.UUID) ([]string, error) {
	var ids []string
	for _, it := range s.catalog.Items() {
		if it.Kind == KindEmote && !it.Starter() {
			ids = append(ids, it.ID)
		}
	}
	rows, err := s.pool.Query(ctx, `SELECT item_id FROM progression.inventory WHERE user_id = $1 AND item_id = ANY($2)`,
		userID, ids)
	if err != nil {
		return nil, err
	}
	return pgx.CollectRows(rows, pgx.RowTo[string])
}

// cacheGranted writes newly granted emotes through to an existing cached set.
// Call it after the granting transaction committed.
func (s *Service) cacheGranted(ctx context.Context, userID uuid.UUID, items []*Item) {
	var ids []string
	for _, it := range items {
		if it != nil && it.Kind == KindEmote && !it.Starter() {
			ids = append(ids, it.ID)
		}
	}
	if len(ids) > 0 {
		s.addEmotes(ctx, userID, ids)
	}
}

func (s *Service) addEmotes(ctx context.Context, userID uuid.UUID, ids []string) {
	if s.rdb == nil {
		return
	}
	args := make([]any, len(ids))
	for i, id := range ids {
		args[i] = id
	}
	if err := emoteAdd.Run(context.WithoutCancel(ctx), s.rdb, []string{EmotesKey(userID)}, args...).Err(); err != nil {
		// Harmless: a missing member is confirmed in PostgreSQL.
		metrics.CacheWriteErrors.WithLabelValues("emotes", "add").Inc()
	}
}
