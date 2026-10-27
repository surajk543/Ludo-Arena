// Package opsstats serves operator statistics about people (never bots) to
// the Telegram ops bot through the operator API (docs/rest-api.md →
// Operator API): who is online and what they are doing, and minutes played
// per game in a rolling window. Everything lives in Redis (no PostgreSQL
// table); see backend/docs/redis-keys.md.
//
//   - online:humans (zset, member = account id, score = unix ms when the
//     current connection registered) is written by the WebSocket gateway for
//     human connections only, together with presence:{userId}. A member
//     whose presence key is missing (an instance crashed before removing it)
//     is stale: readers drop it from the report and remove it.
//   - ptg:{game}:{YYYYMMDDHH} (zset, member = account id, score = ms) and
//     ptg:tot:{YYYYMMDDHH} (hash, game → ms) hold the play of each UTC hour.
//     They are fed by the room engine with exactly the intervals it credits
//     to daily playtime (rooms/playtime.go: active play of people), split at
//     hour boundaries, one pipeline per credit, TTL PlayTTL on every write.
package opsstats

import (
	"context"
	"log/slog"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/redis/go-redis/v9"

	"ludoarena/internal/profile"
	"ludoarena/internal/rooms"
)

// OnlineKey is the zset of online people (see the package comment).
const OnlineKey = "online:humans"

// PlayTTL is the lifetime of an hour's play keys after their last write: a
// 24 h window plus its partial oldest hour, with a margin.
const PlayTTL = 26 * time.Hour

// Games lists the games, in report order.
var Games = []string{rooms.GameLudo, rooms.GameSnakes}

func validGame(g string) bool { return g == rooms.GameLudo || g == rooms.GameSnakes }

// HourKey formats the UTC hour of t as YYYYMMDDHH.
func HourKey(t time.Time) string { return t.UTC().Format("2006010215") }

// PlayKey is the zset of one game's play per account in one UTC hour.
func PlayKey(game string, hour time.Time) string { return "ptg:" + game + ":" + HourKey(hour) }

// TotalKey is the hash of each game's total play in one UTC hour.
func TotalKey(hour time.Time) string { return "ptg:tot:" + HourKey(hour) }

// forgetHours is how many UTC hours back (the current one included) an
// account's play members can still exist: PlayTTL after the last write,
// which can come a little after its hour (a stretch is credited when it
// ends or at a checkpoint).
const forgetHours = 28

// AccountKeys returns, for account deletion, the keys holding userID as a
// member at time now: OnlineKey and every game's PlayKey that may still
// exist. ptg:tot:* hold aggregates without account ids and are kept.
func AccountKeys(now time.Time) []string {
	keys := []string{OnlineKey}
	hour := now.UTC().Truncate(time.Hour)
	for h := 0; h < forgetHours; h++ {
		for _, g := range Games {
			keys = append(keys, PlayKey(g, hour.Add(-time.Duration(h)*time.Hour)))
		}
	}
	return keys
}

// Options configure the Service.
type Options struct {
	// AdminKeySHA256 is sha256(X-Admin-Key); empty disables the operator
	// routes (404).
	AdminKeySHA256 []byte
	Now            func() time.Time // default time.Now
}

// Service records play per game and serves the operator reports.
type Service struct {
	rdb      *redis.Client
	pg       *pgxpool.Pool
	profiles *profile.Service
	log      *slog.Logger
	opts     Options
}

// New returns the Service. pg (account creation times) and profiles (names)
// may be nil in unit tests.
func New(rdb *redis.Client, pg *pgxpool.Pool, profiles *profile.Service, log *slog.Logger, opts Options) *Service {
	if opts.Now == nil {
		opts.Now = time.Now
	}
	return &Service{rdb: rdb, pg: pg, profiles: profiles, log: log, opts: opts}
}

// span is the part of an interval inside one UTC hour.
type span struct {
	hour time.Time
	ms   int64
}

// hourSpans splits [from, to) at UTC hour boundaries (empty parts dropped).
func hourSpans(from, to time.Time) []span {
	from, to = from.UTC(), to.UTC()
	var out []span
	for from.Before(to) {
		hour := from.Truncate(time.Hour)
		end := hour.Add(time.Hour)
		if end.After(to) {
			end = to
		}
		if ms := end.Sub(from).Milliseconds(); ms > 0 {
			out = append(out, span{hour: hour, ms: ms})
		}
		from = end
	}
	return out
}

// RecordPlay implements gameevents.PlayStats: [from, to) of userID's active
// play of game, added to each UTC hour it overlaps in one pipeline. Best
// effort: a failure is logged and the interval is not retried.
func (s *Service) RecordPlay(ctx context.Context, userID uuid.UUID, game string, from, to time.Time) {
	if s.rdb == nil || userID == uuid.Nil || !validGame(game) {
		return
	}
	spans := hourSpans(from, to)
	if len(spans) == 0 {
		return
	}
	ctx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()
	uid := userID.String()
	pipe := s.rdb.Pipeline()
	for _, sp := range spans {
		pk, tk := PlayKey(game, sp.hour), TotalKey(sp.hour)
		pipe.ZIncrBy(ctx, pk, float64(sp.ms), uid)
		pipe.Expire(ctx, pk, PlayTTL)
		pipe.HIncrBy(ctx, tk, game, sp.ms)
		pipe.Expire(ctx, tk, PlayTTL)
	}
	if _, err := pipe.Exec(ctx); err != nil {
		s.warn("ops playtime write failed", err)
	}
}
