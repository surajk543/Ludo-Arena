package rooms

import (
	"context"
	"encoding/json"
	"errors"
	mrand "math/rand/v2"
	"strconv"
	"strings"
	"time"

	"github.com/redis/go-redis/v9"

	"ludoroyale/internal/metrics"
)

// Cluster-wide live-game counts (players_in_game, rooms_in_game,
// players_in_lobby; see docs/architecture.md → Observability).
//
// Index: every room commit (commitScript) atomically writes the room's entry
// in the hash idx:rooms:live — "{rev}|{status}|{game}|{mode}|{humans}|{bots}"
// while the room is in the lobby or playing — and removes it when the room
// finishes or closes. So the index never disagrees with committed room state;
// the only way an entry outlives its room is TTL expiry of room:{id}, which
// the recount detects and prunes. An entry whose rev differs from the room's
// current rev was not written by a commit of this code (e.g. by an older
// instance during a rolling deploy); the recount then reads the room itself.
//
// Recount: one instance at a time (Redis lease stats:game:lease, renewed by
// the holder each interval) scans the index in bounded batches, verifies
// each batch atomically against the room hashes (validateLiveScript), sets
// the gauges and caches the result in stats:game. The other instances expose
// that cached result, so every instance reports the same cluster value
// (aggregate with max) and Redis does the work once per interval.
const (
	statsCacheKey = "stats:game"
	statsLeaseKey = "stats:game:lease"
	statsBatch    = 256 // index entries per HSCAN page and per validation script call (~0.5 ms of Redis time)
)

// ActorCounts splits seats by actor (human accounts vs bots, load-test bots
// included).
type ActorCounts struct {
	Human int `json:"human"`
	Bot   int `json:"bot"`
}

// GameStats is one cluster-wide recount of live rooms.
type GameStats struct {
	At      int64          `json:"at"`      // unix ms when the recount finished
	Playing ActorCounts    `json:"playing"` // non-forfeited seats in rooms that are playing
	Lobby   ActorCounts    `json:"lobby"`   // seats in rooms waiting to start
	Rooms   map[string]int `json:"rooms"`   // rooms playing by "{game}:{mode}"
	Lobbies int            `json:"lobbies"` // rooms in the lobby
	Pruned  int            `json:"pruned"`  // index entries dropped (room key gone)
}

// RoomsInGame returns the number of playing rooms of game and mode.
func (st GameStats) RoomsInGame(game, mode string) int { return st.Rooms[game+":"+mode] }

// liveEntry returns the index update for a committed room: "set" with its
// summary while it is in the lobby or playing, "del" once it is finished or
// closed. Forfeited players (left or timed out) are not counted.
func liveEntry(r *Room) (op, summary string) {
	if r.Status != StatusLobby && r.Status != StatusPlaying {
		return "del", ""
	}
	humans, bots := 0, 0
	for _, p := range r.Players {
		switch {
		case p.Forfeited:
		case p.Bot:
			bots++
		default:
			humans++
		}
	}
	return "set", r.Status + "|" + r.Game + "|" + r.Mode + "|" + strconv.Itoa(humans) + "|" + strconv.Itoa(bots)
}

// add counts one room summary ("{status}|{game}|{mode}|{humans}|{bots}").
// It reports false for a malformed summary or a status that is not live.
func (st *GameStats) add(summary string) bool {
	f := strings.Split(summary, "|")
	if len(f) != 5 {
		return false
	}
	humans, err1 := strconv.Atoi(f[3])
	bots, err2 := strconv.Atoi(f[4])
	if err1 != nil || err2 != nil || humans < 0 || bots < 0 {
		return false
	}
	switch f[0] {
	case StatusPlaying:
		st.Playing.Human += humans
		st.Playing.Bot += bots
		if st.Rooms == nil {
			st.Rooms = map[string]int{}
		}
		st.Rooms[f[1]+":"+f[2]]++
	case StatusLobby:
		st.Lobby.Human += humans
		st.Lobby.Bot += bots
		st.Lobbies++
	default:
		return false
	}
	return true
}

// validateLiveScript checks index entries against their rooms in one atomic
// step. ARGV are room ids; for each it returns the summary when the entry
// matches the room's current rev, "" when the room is no longer indexed, "-"
// when the room key is gone (the entry is deleted: room ids are never
// reused), or "~{entry}" when the entry is stale (rev mismatch).
var validateLiveScript = redis.NewScript(`
local out = {}
for i, id in ipairs(ARGV) do
  local rev = redis.call('HGET', 'room:' .. id, 'rev')
  local v = redis.call('HGET', KEYS[1], id)
  if not rev then
    if v then redis.call('HDEL', KEYS[1], id); out[i] = '-' else out[i] = '' end
  elseif not v then
    out[i] = ''
  elseif string.sub(v, 1, #rev + 1) == rev .. '|' then
    out[i] = string.sub(v, #rev + 2)
  else
    out[i] = '~' .. v
  end
end
return out`)

// delIfScript removes a hash field only if it still holds the given value.
var delIfScript = redis.NewScript(`
if redis.call('HGET', KEYS[1], ARGV[1]) == ARGV[2] then return redis.call('HDEL', KEYS[1], ARGV[1]) end
return 0`)

// leaseScript takes or renews a lease held by ARGV[1] for ARGV[2] ms.
var leaseScript = redis.NewScript(`
local cur = redis.call('GET', KEYS[1])
if cur and cur ~= ARGV[1] then return 0 end
redis.call('SET', KEYS[1], ARGV[1], 'PX', ARGV[2])
return 1`)

// releaseScript deletes a lease only if ARGV[1] still holds it.
var releaseScript = redis.NewScript(`
if redis.call('GET', KEYS[1]) == ARGV[1] then return redis.call('DEL', KEYS[1]) end
return 0`)

// CountGameStats recounts every live room from the index (cluster-wide) and
// prunes entries whose room no longer exists. Cost is O(live rooms): one
// HSCAN page and one validation script per statsBatch rooms; room state is
// only read for stale entries.
func (s *Service) CountGameStats(ctx context.Context) (GameStats, error) {
	st := GameStats{Rooms: map[string]int{}}
	seen := map[string]struct{}{} // HSCAN may return a field more than once
	var cursor uint64
	for {
		kv, next, err := s.RDB.HScan(ctx, liveRoomsKey, cursor, "", statsBatch).Result()
		if err != nil {
			return GameStats{}, err
		}
		ids := make([]any, 0, len(kv)/2)
		for i := 0; i+1 < len(kv); i += 2 {
			if _, dup := seen[kv[i]]; !dup {
				seen[kv[i]] = struct{}{}
				ids = append(ids, kv[i])
			}
		}
		for len(ids) > 0 {
			n := min(len(ids), statsBatch)
			if err := s.countBatch(ctx, &st, ids[:n]); err != nil {
				return GameStats{}, err
			}
			ids = ids[n:]
		}
		cursor = next
		if cursor == 0 {
			break
		}
	}
	st.At = s.nowMs()
	return st, nil
}

func (s *Service) countBatch(ctx context.Context, st *GameStats, ids []any) error {
	res, err := validateLiveScript.Run(ctx, s.RDB, []string{liveRoomsKey}, ids...).StringSlice()
	if err != nil {
		return err
	}
	for i, v := range res {
		switch {
		case v == "":
		case v == "-":
			st.Pruned++
		case strings.HasPrefix(v, "~"):
			if err := s.countStale(ctx, st, ids[i].(string), v[1:]); err != nil {
				return err
			}
		default:
			if !st.add(v) {
				s.Log.Warn("malformed live-room index entry", "room", ids[i])
			}
		}
	}
	return nil
}

// countStale counts a room whose index entry does not match its current
// revision by reading the room itself, and drops the entry if the room is no
// longer live (unless a newer commit rewrote it meanwhile).
func (s *Service) countStale(ctx context.Context, st *GameStats, id, entry string) error {
	r, _, err := s.st.load(ctx, id)
	if errors.Is(err, errNoRoom) {
		return nil
	}
	if err != nil {
		return err
	}
	if op, summary := liveEntry(r); op == "set" {
		st.add(summary)
		return nil
	}
	return delIfScript.Run(ctx, s.RDB, []string{liveRoomsKey}, id, entry).Err()
}

// publishGameStats sets the live-game gauges. Every known label combination
// is written so a count that drops to zero is reported as 0.
func publishGameStats(st GameStats) {
	metrics.PlayersInGame.WithLabelValues("human").Set(float64(st.Playing.Human))
	metrics.PlayersInGame.WithLabelValues("bot").Set(float64(st.Playing.Bot))
	metrics.PlayersInLobby.WithLabelValues("human").Set(float64(st.Lobby.Human))
	metrics.PlayersInLobby.WithLabelValues("bot").Set(float64(st.Lobby.Bot))
	for _, game := range []string{GameLudo, GameSnakes} {
		for _, mode := range []string{ModePublic, ModePrivate, ModePractice} {
			metrics.RoomsInGame.WithLabelValues(game, mode).Set(float64(st.RoomsInGame(game, mode)))
		}
	}
	metrics.GameStatsRefreshed.Set(float64(st.At) / 1000)
}

var errStatsPending = errors.New("game stats: no cached recount yet")

func (s *Service) statsInterval() time.Duration {
	if s.StatsInterval > 0 {
		return s.StatsInterval
	}
	return 15 * time.Second
}

// RefreshGameStats updates the live-game gauges once. The lease holder (or
// whoever takes the free lease) recounts and caches the result; every other
// instance publishes the cached result of the holder.
func (s *Service) RefreshGameStats(ctx context.Context) (GameStats, error) {
	interval := s.statsInterval()
	// The lease outlives the holder's next (jittered) tick, so a healthy
	// holder keeps it; after a crash another instance takes over within
	// about two intervals.
	leader, err := leaseScript.Run(ctx, s.RDB, []string{statsLeaseKey}, s.instance,
		(2 * interval).Milliseconds()).Int()
	if err != nil {
		return GameStats{}, err
	}
	if leader == 1 {
		st, err := s.CountGameStats(ctx)
		if err != nil {
			s.releaseStatsLease(ctx) // let another instance try
			return GameStats{}, err
		}
		raw, _ := json.Marshal(st)
		if err := s.RDB.Set(ctx, statsCacheKey, raw, 4*interval).Err(); err != nil {
			s.Log.Warn("game stats cache write failed", "error", err.Error())
		}
		publishGameStats(st)
		return st, nil
	}
	raw, err := s.RDB.Get(ctx, statsCacheKey).Bytes()
	if errors.Is(err, redis.Nil) {
		return GameStats{}, errStatsPending
	}
	if err != nil {
		return GameStats{}, err
	}
	var st GameStats
	if err := json.Unmarshal(raw, &st); err != nil {
		return GameStats{}, err
	}
	publishGameStats(st)
	return st, nil
}

func (s *Service) releaseStatsLease(ctx context.Context) {
	_ = releaseScript.Run(ctx, s.RDB, []string{statsLeaseKey}, s.instance).Err()
}

// RunGameStats refreshes the live-game gauges every StatsInterval (±10 %
// jitter) until ctx is cancelled, then releases the recount lease so another
// instance takes over at once.
func (s *Service) RunGameStats(ctx context.Context) {
	interval := s.statsInterval()
	t := time.NewTimer(time.Duration(mrand.Int64N(int64(time.Second)))) // first refresh soon after start
	defer t.Stop()
	defer func() {
		rctx, cancel := context.WithTimeout(context.WithoutCancel(ctx), 2*time.Second)
		defer cancel()
		s.releaseStatsLease(rctx)
	}()
	for {
		select {
		case <-ctx.Done():
			return
		case <-t.C:
		}
		if _, err := s.RefreshGameStats(ctx); err != nil && ctx.Err() == nil && !errors.Is(err, errStatsPending) {
			s.Log.Warn("game stats refresh failed", "error", err.Error())
		}
		t.Reset(interval*9/10 + time.Duration(mrand.Int64N(int64(interval/5)+1)))
	}
}
