package tests

import (
	"bufio"
	"context"
	"encoding/json"
	"fmt"
	"net/http/httptest"
	"os"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/google/uuid"

	"ludoarena/internal/rooms"
)

// scrape reads the app's Prometheus endpoint and returns every sample keyed
// by its exposition text, e.g. `players_in_game{actor="human"}`.
func (e *env) scrape(t *testing.T) map[string]float64 {
	t.Helper()
	rec := httptest.NewRecorder()
	e.app.MetricsHandler().ServeHTTP(rec, httptest.NewRequest("GET", "/metrics", nil))
	if rec.Code != 200 {
		t.Fatalf("metrics: %d", rec.Code)
	}
	out := map[string]float64{}
	sc := bufio.NewScanner(rec.Body)
	for sc.Scan() {
		line := sc.Text()
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		i := strings.LastIndexByte(line, ' ')
		v, err := strconv.ParseFloat(line[i+1:], 64)
		if err == nil {
			out[line[:i]] = v
		}
	}
	return out
}

type liveWant struct {
	playH, playB, lobbyH, lobbyB int
	rooms                        map[string]int // "{game}:{mode}" → playing rooms
}

func (e *env) assertLive(t *testing.T, what string, w liveWant) rooms.GameStats {
	t.Helper()
	st, err := e.app.Rooms.CountGameStats(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	got := liveWant{st.Playing.Human, st.Playing.Bot, st.Lobby.Human, st.Lobby.Bot, st.Rooms}
	if got.playH != w.playH || got.playB != w.playB || got.lobbyH != w.lobbyH || got.lobbyB != w.lobbyB {
		t.Fatalf("%s: playing %d humans / %d bots, lobby %d / %d; want %d / %d, %d / %d", what,
			got.playH, got.playB, got.lobbyH, got.lobbyB, w.playH, w.playB, w.lobbyH, w.lobbyB)
	}
	for _, g := range []string{rooms.GameLudo, rooms.GameSnakes} {
		for _, m := range []string{rooms.ModePublic, rooms.ModePrivate, rooms.ModePractice} {
			if st.RoomsInGame(g, m) != w.rooms[g+":"+m] {
				t.Fatalf("%s: rooms in game %v, want %v", what, st.Rooms, w.rooms)
			}
		}
	}
	return st
}

// assertGauges refreshes the gauges through the production path (lease +
// cache) and checks the scraped exposition.
func (e *env) assertGauges(t *testing.T, w liveWant) {
	t.Helper()
	before := time.Now()
	if _, err := e.app.Rooms.RefreshGameStats(context.Background()); err != nil {
		t.Fatal(err)
	}
	m := e.scrape(t)
	want := map[string]float64{
		`players_in_game{actor="human"}`:  float64(w.playH),
		`players_in_game{actor="bot"}`:    float64(w.playB),
		`players_in_lobby{actor="human"}`: float64(w.lobbyH),
		`players_in_lobby{actor="bot"}`:   float64(w.lobbyB),
	}
	for _, g := range []string{"ludo", "snakes_ladders"} {
		for _, md := range []string{"public", "private", "practice"} {
			want[fmt.Sprintf(`rooms_in_game{game=%q,mode=%q}`, g, md)] = float64(w.rooms[g+":"+md])
		}
	}
	for k, v := range want {
		if got, ok := m[k]; !ok || got != v {
			t.Fatalf("gauge %s = %v (present %t), want %v", k, got, ok, v)
		}
	}
	ts := m["game_stats_refreshed_timestamp_seconds"]
	if ts < float64(before.Unix())-1 || ts > float64(time.Now().Unix())+1 {
		t.Fatalf("game_stats_refreshed_timestamp_seconds = %v, want ~%d", ts, before.Unix())
	}
}

func (e *env) indexed(t *testing.T, roomID string) bool {
	t.Helper()
	ok, err := e.rdb.HExists(context.Background(), "idx:rooms:live", roomID).Result()
	if err != nil {
		t.Fatal(err)
	}
	return ok
}

// TestLiveGameGauges drives real games (humans, practice bots, public-fill
// bots, load-test bots) and checks the cluster-wide gauges at each step.
func TestLiveGameGauges(t *testing.T) {
	// One background refresh right after start, then the test drives refreshes.
	t.Setenv("GAME_STATS_INTERVAL", "1h")
	e := newEnv(t, envOpts{dice: rooms.NewSeededDice(5), turnTimeout: 5 * time.Minute, fill: 5 * time.Minute})
	ctx := context.Background()
	waitFor(t, 5*time.Second, "background game-stats refresh", func() bool {
		return e.rdb.Exists(ctx, "stats:game").Val() == 1
	})
	ctl := e.botController(t)

	// Playing: public Snakes & Ladders with three humans.
	snakes := startPublic(t, e, "snakes_ladders", "classic", 3)
	snakesID := snakes[0].snapshot().ID

	// Playing: practice Ludo, one human and two bots.
	ph := e.mustDial("practice", e.guest())
	if m := ph.call("practice.start", map[string]any{"game": "ludo", "variant": "quick", "bots": 2}); m.T != "ack" {
		t.Fatalf("practice.start: %s %s", m.T, m.P)
	}
	pbots := e.spawnBots(t, ctl, 2)
	waitFor(t, 10*time.Second, "practice game start", func() bool {
		s := ph.snapshot()
		return s != nil && s.Status == "playing"
	})
	practiceID := ph.snapshot().ID

	// Playing: public Ludo between two load-test bots.
	var lt []*client
	for i := 0; i < 2; i++ {
		s := e.do("POST", "/api/v1/bot/sessions", ctl, map[string]any{"mode": "loadtest", "name": "Load"})
		if s.Status != 200 {
			t.Fatalf("loadtest session: %d %s", s.Status, s.Raw)
		}
		acct := account{Token: s.Body["accessToken"].(string), UID: s.Body["uid"].(string)}
		c, _, err := e.dial("lt"+acct.UID, acct, map[string]string{"X-App-Platform": "bot"})
		if err != nil {
			t.Fatal(err)
		}
		if m := c.call("matchmaking.join", map[string]any{"game": "ludo", "capacity": 2}); m.T != "matchmaking.status" {
			t.Fatalf("loadtest matchmaking: %s %s", m.T, m.P)
		}
		lt = append(lt, c)
	}
	waitFor(t, 5*time.Second, "loadtest game", func() bool {
		s := lt[0].snapshot()
		return s != nil && s.Status == "playing"
	})
	loadtestID := lt[0].snapshot().ID

	// Lobby: public Ludo (capacity 4) with one human and one public-fill bot.
	lh := e.mustDial("lobby", e.guest())
	lh.call("matchmaking.join", map[string]any{"game": "ludo", "variant": "classic", "capacity": 4})
	waitFor(t, 3*time.Second, "public lobby", func() bool { return lh.snapshot() != nil })
	lobbyID := lh.snapshot().ID
	if r := e.do("POST", "/api/v1/bot/lobbies/"+lobbyID+"/fill", ctl, map[string]any{"count": 1}); r.Status != 200 {
		t.Fatalf("fill: %d %s", r.Status, r.Raw)
	}
	e.spawnBots(t, ctl, 1)
	waitFor(t, 5*time.Second, "bot seated in lobby", func() bool { return len(lh.snapshot().Players) == 2 })

	// Lobby: private Snakes & Ladders room with its host.
	host := e.mustDial("host", e.guest())
	if r := host.call("room.create", map[string]any{"game": "snakes_ladders", "capacity": 2}); r.T != "ack" {
		t.Fatalf("create: %s %s", r.T, r.P)
	}
	waitFor(t, 3*time.Second, "private lobby", func() bool { return host.snapshot() != nil })
	privateID := host.snapshot().ID

	all := liveWant{playH: 4, playB: 4, lobbyH: 2, lobbyB: 1,
		rooms: map[string]int{"snakes_ladders:public": 1, "ludo:practice": 1, "ludo:public": 1}}
	e.assertLive(t, "all rooms", all)
	e.assertGauges(t, all)

	// A player who leaves a running game is forfeited and no longer counted.
	if m := snakes[0].call("room.leave", map[string]any{"roomId": snakesID}); m.T != "ack" {
		t.Fatalf("leave: %s %s", m.T, m.P)
	}
	if m := ph.call("room.leave", map[string]any{"roomId": practiceID}); m.T != "ack" {
		t.Fatalf("practice leave: %s %s", m.T, m.P)
	}
	waitFor(t, 3*time.Second, "forfeits", func() bool {
		s := snakes[1].snapshot()
		p := pbots[0].snapshot()
		return s.Status == "playing" && s.Players[seatIn(s, snakes[0].acct.UID)].Forfeited &&
			p.Status == "playing" && p.Players[seatIn(p, ph.acct.UID)].Forfeited
	})
	afterForfeit := all
	afterForfeit.playH = 2
	e.assertLive(t, "after forfeits", afterForfeit)
	e.assertGauges(t, afterForfeit)

	// Self-healing 1: a room key that disappears (TTL expiry) drops its index
	// entry at the next recount.
	if !e.indexed(t, privateID) {
		t.Fatal("private lobby not indexed")
	}
	e.rdb.Del(ctx, "room:"+privateID)
	afterExpiry := afterForfeit
	afterExpiry.lobbyH = 1
	if st := e.assertLive(t, "after expiry", afterExpiry); st.Pruned != 1 {
		t.Fatalf("pruned %d, want 1", st.Pruned)
	}
	if e.indexed(t, privateID) {
		t.Fatal("expired room still indexed")
	}

	// Self-healing 2: a commit that did not update the index (an instance
	// without it, e.g. during a rolling deploy) is detected by the rev
	// mismatch; the room itself is read and its stale entry dropped.
	vals := e.rdb.HMGet(ctx, "room:"+loadtestID, "rev", "s").Val()
	var state map[string]any
	if err := json.Unmarshal([]byte(vals[1].(string)), &state); err != nil {
		t.Fatal(err)
	}
	state["status"] = "finished"
	raw, _ := json.Marshal(state)
	rev, _ := strconv.Atoi(vals[0].(string))
	e.rdb.HSet(ctx, "room:"+loadtestID, "rev", rev+1, "s", string(raw))
	afterStale := afterExpiry
	afterStale.playB = 2
	afterStale.rooms = map[string]int{"snakes_ladders:public": 1, "ludo:practice": 1}
	e.assertLive(t, "after stale entry", afterStale)
	if e.indexed(t, loadtestID) {
		t.Fatal("stale entry of a finished room still indexed")
	}

	// Games end: the practice bots play to completion, the second Snakes
	// player leaves (the third wins by forfeit), the lobby human leaves.
	var wg sync.WaitGroup
	for _, c := range pbots {
		wg.Add(1)
		go func(c *client) { defer wg.Done(); c.playUntilFinished(60 * time.Second) }(c)
	}
	wg.Wait()
	if m := snakes[1].call("room.leave", map[string]any{"roomId": snakesID}); m.T != "ack" {
		t.Fatalf("leave: %s %s", m.T, m.P)
	}
	waitFor(t, 3*time.Second, "snakes finished", func() bool { return snakes[2].snapshot().Status == "finished" })
	if m := lh.call("room.leave", map[string]any{"roomId": lobbyID}); m.T != "ack" {
		t.Fatalf("lobby leave: %s %s", m.T, m.P)
	}
	waitFor(t, 3*time.Second, "lobby closed", func() bool { return !e.indexed(t, lobbyID) })
	zero := liveWant{}
	e.assertLive(t, "all finished", zero)
	e.assertGauges(t, zero)
	if n := e.rdb.HLen(ctx, "idx:rooms:live").Val(); n != 0 {
		t.Fatalf("index still holds %d rooms", n)
	}

	// Multi-instance: while another instance holds the lease, this one
	// publishes the leader's cached recount instead of counting itself.
	cached := rooms.GameStats{At: 1_800_000_000_000, Playing: rooms.ActorCounts{Human: 7, Bot: 5},
		Lobby: rooms.ActorCounts{Human: 1}, Rooms: map[string]int{"ludo:public": 3, "snakes_ladders:private": 1}, Lobbies: 1}
	cachedRaw, _ := json.Marshal(cached)
	e.rdb.Set(ctx, "stats:game:lease", "other-instance", time.Minute)
	e.rdb.Set(ctx, "stats:game", cachedRaw, time.Minute)
	if _, err := e.app.Rooms.RefreshGameStats(ctx); err != nil {
		t.Fatal(err)
	}
	m := e.scrape(t)
	for k, v := range map[string]float64{
		`players_in_game{actor="human"}`: 7, `players_in_game{actor="bot"}`: 5, `players_in_lobby{actor="human"}`: 1,
		`rooms_in_game{game="ludo",mode="public"}`: 3, `rooms_in_game{game="snakes_ladders",mode="private"}`: 1,
		`game_stats_refreshed_timestamp_seconds`: 1_800_000_000,
	} {
		if m[k] != v {
			t.Fatalf("follower gauge %s = %v, want %v", k, m[k], v)
		}
	}
	// When the lease is free again this instance takes it and recounts.
	e.rdb.Del(ctx, "stats:game:lease")
	e.assertGauges(t, zero)
	if owner := e.rdb.Get(ctx, "stats:game:lease").Val(); owner == "" || owner == "other-instance" {
		t.Fatalf("lease owner %q", owner)
	}
}

// TestLiveGameStatsAtScale seeds many live rooms through the real matchmaking
// path (load-test bots), checks exact counts across several HSCAN pages and
// validation batches, prunes expired rooms, and logs the recount cost.
// GAME_STATS_ROOMS overrides the room count (default 1200).
func TestLiveGameStatsAtScale(t *testing.T) {
	t.Setenv("GAME_STATS_INTERVAL", "1h")
	e := newEnv(t, envOpts{dice: rooms.NewSeededDice(9), turnTimeout: 10 * time.Minute, fill: 10 * time.Minute})
	ctx := context.Background()
	nRooms := 1200
	if v, err := strconv.Atoi(os.Getenv("GAME_STATS_ROOMS")); err == nil && v > 0 {
		nRooms = v
	}
	bots := 2 * nRooms
	start := time.Now()
	var next atomic.Int64
	var failed atomic.Int64
	var wg sync.WaitGroup
	for w := 0; w < 16; w++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for next.Add(1) <= int64(bots) {
				c := rooms.Caller{UserID: uuid.NewString(), Bot: true, LoadTest: true}
				if _, err := e.app.Rooms.MatchmakingJoin(ctx, c, "ludo", "classic", 2); err != nil {
					failed.Add(1)
				}
			}
		}()
	}
	wg.Wait()
	if failed.Load() > 0 {
		t.Fatalf("%d joins failed", failed.Load())
	}
	t.Logf("seeded %d load-test bots in %v", bots, time.Since(start))

	check := func(what string) rooms.GameStats {
		t0 := time.Now()
		st, err := e.app.Rooms.CountGameStats(ctx)
		if err != nil {
			t.Fatal(err)
		}
		t.Logf("%s: recount of %d live rooms took %v", what, st.RoomsInGame("ludo", "public")+st.Lobbies, time.Since(t0))
		// Concurrent matchmaking may leave a few one-bot lobbies; every bot
		// is counted exactly once either way.
		if st.Playing.Human != 0 || st.Lobby.Human != 0 ||
			st.Playing.Bot != 2*st.RoomsInGame("ludo", "public") || st.Lobby.Bot != st.Lobbies {
			t.Fatalf("%s: inconsistent counts %+v", what, st)
		}
		return st
	}
	st := check("cold")
	if st.Playing.Bot+st.Lobby.Bot != bots {
		t.Fatalf("counted %d bots, want %d", st.Playing.Bot+st.Lobby.Bot, bots)
	}
	check("warm")

	// Expire a slice of rooms: their entries are pruned and they stop counting.
	ids := e.rdb.HKeys(ctx, "idx:rooms:live").Val()
	expired := len(ids) / 10
	for _, id := range ids[:expired] {
		e.rdb.Del(ctx, "room:"+id)
	}
	after := check("after expiring 10%")
	if after.Pruned != expired || int(e.rdb.HLen(ctx, "idx:rooms:live").Val()) != len(ids)-expired {
		t.Fatalf("pruned %d (index %d), want %d of %d", after.Pruned, e.rdb.HLen(ctx, "idx:rooms:live").Val(), expired, len(ids))
	}
	if after.RoomsInGame("ludo", "public")+after.Lobbies != len(ids)-expired {
		t.Fatalf("live rooms %d, want %d", after.RoomsInGame("ludo", "public")+after.Lobbies, len(ids)-expired)
	}
}
