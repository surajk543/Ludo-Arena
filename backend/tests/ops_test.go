package tests

import (
	"context"
	"encoding/json"
	"errors"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/redis/go-redis/v9"

	"ludoarena/internal/opsstats"
	"ludoarena/internal/rooms"
)

// Operator statistics for the ops bot (docs/rest-api.md → Operator API):
// GET /admin/ops/online and GET /admin/ops/playtime. People only.

type opsUser struct {
	UID         string  `json:"uid"`
	UserID      string  `json:"userId"`
	Name        string  `json:"name"`
	CreatedAt   *string `json:"createdAt"`
	OnlineSince string  `json:"onlineSince"`
	Activity    string  `json:"activity"`
	Game        *string `json:"game"`
	Mode        *string `json:"mode"`
}

type opsOnline struct {
	At     string         `json:"at"`
	Total  int            `json:"total"`
	Counts map[string]int `json:"counts"`
	Users  []opsUser      `json:"users"`
}

type opsPlayer struct {
	UID       string  `json:"uid"`
	UserID    string  `json:"userId"`
	Name      string  `json:"name"`
	CreatedAt *string `json:"createdAt"`
	Seconds   int64   `json:"seconds"`
}

type opsGame struct {
	Game    string `json:"game"`
	Seconds int64  `json:"seconds"`
	Players int64  `json:"players"`
	Hourly  []struct {
		Hour    string `json:"hour"`
		Seconds int64  `json:"seconds"`
	} `json:"hourly"`
	Top []opsPlayer `json:"top"`
}

type opsPlaytime struct {
	From  string    `json:"from"`
	To    string    `json:"to"`
	Hours int       `json:"hours"`
	Games []opsGame `json:"games"`
}

// opsGet calls an operator route with the admin key and decodes the 200
// response into out.
func (e *env) opsGet(t *testing.T, path string, out any) resp {
	t.Helper()
	r := e.do("GET", path, "", nil, "X-Admin-Key", adminKey)
	if r.Status != 200 {
		t.Fatalf("GET %s: %d %s", path, r.Status, r.Raw)
	}
	if err := json.Unmarshal(r.Raw, out); err != nil {
		t.Fatalf("GET %s: %v %s", path, err, r.Raw)
	}
	return r
}

func (e *env) opsOnline(t *testing.T) opsOnline {
	t.Helper()
	var o opsOnline
	e.opsGet(t, "/api/v1/admin/ops/online", &o)
	return o
}

func (e *env) opsPlaytime(t *testing.T, query string) opsPlaytime {
	t.Helper()
	var p opsPlaytime
	e.opsGet(t, "/api/v1/admin/ops/playtime"+query, &p)
	if len(p.Games) != 2 || p.Games[0].Game != "ludo" || p.Games[1].Game != "snakes_ladders" {
		t.Fatalf("playtime games: %+v", p.Games)
	}
	return p
}

// opsMember reports whether userID is in the online set and in any game's
// hourly play that can still exist.
func (e *env) opsMember(t *testing.T, userID string) (online, played bool) {
	t.Helper()
	ctx := context.Background()
	for i, k := range opsstats.AccountKeys(time.Now()) {
		err := e.rdb.ZScore(ctx, k, userID).Err()
		if err != nil && !errors.Is(err, redis.Nil) {
			t.Fatal(err)
		}
		if i == 0 {
			online = err == nil
		} else if err == nil {
			played = true
		}
	}
	return online, played
}

func str(p *string) string {
	if p == nil {
		return ""
	}
	return *p
}

func TestOpsAPIDisabledWithoutAdminKey(t *testing.T) {
	t.Setenv("ADMIN_API_KEY_SHA256", "")
	e := newEnv(t, envOpts{})
	for _, path := range []string{"/api/v1/admin/ops/online", "/api/v1/admin/ops/playtime"} {
		if r := e.do("GET", path, "", nil, "X-Admin-Key", adminKey); r.Status != 404 || errCode(r) != "not_found" {
			t.Fatalf("GET %s without ADMIN_API_KEY_SHA256: %d %s", path, r.Status, r.Raw)
		}
	}
}

func TestOpsOnlineAndPlaytime(t *testing.T) {
	t.Setenv("ADMIN_API_KEY_SHA256", adminHash())
	e := newEnv(t, envOpts{dice: rooms.NewSeededDice(21)})
	ctx := context.Background()

	// The key is required; the parameters are checked.
	for _, path := range []string{"/api/v1/admin/ops/online", "/api/v1/admin/ops/playtime"} {
		for _, key := range []string{"", "wrong-key"} {
			var hdr []string
			if key != "" {
				hdr = []string{"X-Admin-Key", key}
			}
			if r := e.do("GET", path, "", nil, hdr...); r.Status != 401 || errCode(r) != "unauthorized" {
				t.Fatalf("GET %s with key %q: %d %s", path, key, r.Status, r.Raw)
			}
		}
	}
	for _, q := range []string{"online?limit=0", "online?limit=501", "online?limit=x", "playtime?hours=0",
		"playtime?hours=25", "playtime?limit=0", "playtime?limit=501", "playtime?hours=1.5"} {
		if r := e.do("GET", "/api/v1/admin/ops/"+q, "", nil, "X-Admin-Key", adminKey); r.Status != 400 || errCode(r) != "bad_request" {
			t.Fatalf("GET /admin/ops/%s: %d %s", q, r.Status, r.Raw)
		}
	}
	var empty opsOnline
	if r := e.opsGet(t, "/api/v1/admin/ops/online?limit=500", &empty); empty.Total != 0 ||
		!strings.Contains(string(r.Raw), `"users":[]`) {
		t.Fatalf("nobody online: %s", r.Raw)
	}

	// A person connected and doing nothing is in the lobby.
	idle := e.guest()
	ic := e.mustDial("idle", idle)
	o := e.opsOnline(t)
	if o.Total != 1 || o.Counts["lobby"] != 1 || len(o.Users) != 1 {
		t.Fatalf("one idle person: %+v", o)
	}
	if u := o.Users[0]; u.UID != idle.UID || u.UserID != idle.UserID || u.Activity != "lobby" || u.Game != nil ||
		u.Mode != nil || u.CreatedAt == nil || u.Name == "" || u.OnlineSince == "" {
		t.Fatalf("idle person: %+v", u)
	}
	if _, err := time.Parse(time.RFC3339, o.At); err != nil || !strings.HasSuffix(o.At, "Z") {
		t.Fatalf("at = %q", o.At)
	}

	// A practice game against two bots: the person plays Ludo, the bots are
	// never listed (nor in the online set).
	pl := e.guest()
	pc := e.mustDial("practice", pl)
	if m := pc.call("practice.start", map[string]any{"game": "ludo", "variant": "quick", "bots": 2}); m.T != "room.updated" {
		t.Fatalf("practice.start: %s %s", m.T, m.P)
	}
	bots := e.spawnBots(t, e.botController(t), 2)
	waitFor(t, 10*time.Second, "practice game start", func() bool {
		s := pc.snapshot()
		return s != nil && s.Status == "playing"
	})
	// A person waiting in a Snakes & Ladders lobby.
	wt := e.guest()
	wc := e.mustDial("waiting", wt)
	if m := wc.call("matchmaking.join", map[string]any{"game": "snakes_ladders", "capacity": 4}); m.T != "matchmaking.status" {
		t.Fatalf("matchmaking.join: %s %s", m.T, m.P)
	}
	waitFor(t, 3*time.Second, "snakes lobby", func() bool { return wc.snapshot() != nil })

	o = e.opsOnline(t)
	if o.Total != 3 || o.Counts["ludo"] != 1 || o.Counts["snakes_ladders"] != 0 || o.Counts["waiting"] != 1 ||
		o.Counts["lobby"] != 1 || len(o.Users) != 3 {
		t.Fatalf("online: %+v", o)
	}
	for i, w := range []struct {
		acct            account
		act, game, mode string
	}{
		{pl, "ludo", "ludo", "practice"}, {wt, "waiting", "snakes_ladders", "public"}, {idle, "lobby", "", ""},
	} {
		u := o.Users[i]
		if u.UID != w.acct.UID || u.UserID != w.acct.UserID || u.Activity != w.act || str(u.Game) != w.game || str(u.Mode) != w.mode {
			t.Fatalf("users[%d] = %+v, want %s %s %s %s", i, u, w.acct.UID, w.act, w.game, w.mode)
		}
	}
	for _, b := range bots {
		for _, u := range o.Users {
			if u.UID == b.acct.UID {
				t.Fatalf("bot %s listed online", b.acct.UID)
			}
		}
	}
	if n := e.rdb.ZCard(ctx, opsstats.OnlineKey).Val(); n != 3 {
		t.Fatalf("online set has %d members with 3 people and 2 bots connected", n)
	}
	var cut opsOnline
	if e.opsGet(t, "/api/v1/admin/ops/online?limit=1", &cut); cut.Total != 3 || len(cut.Users) != 1 || cut.Users[0].UID != pl.UID {
		t.Fatalf("limit=1: %+v", cut)
	}

	// Play is credited when the app goes to the background; it shows in the
	// Ludo playtime of the last hour, attributed to the person only.
	time.Sleep(1500 * time.Millisecond)
	if m := pc.call("app.focus", map[string]any{"foreground": false}); m.T != "ack" {
		t.Fatalf("app.focus: %s %s", m.T, m.P)
	}
	var p opsPlaytime
	waitFor(t, 5*time.Second, "ludo playtime", func() bool {
		p = e.opsPlaytime(t, "?hours=1&limit=10")
		return p.Games[0].Players == 1
	})
	ludo, snakes := p.Games[0], p.Games[1]
	if p.Hours != 1 || ludo.Seconds < 1 || ludo.Seconds > 10 || len(ludo.Top) != 1 || ludo.Top[0].UID != pl.UID ||
		ludo.Top[0].UserID != pl.UserID || ludo.Top[0].Seconds != ludo.Seconds || ludo.Top[0].CreatedAt == nil {
		t.Fatalf("ludo playtime: %+v", ludo)
	}
	if snakes.Seconds != 0 || snakes.Players != 0 || snakes.Top == nil || len(snakes.Top) != 0 {
		t.Fatalf("snakes playtime: %+v", snakes)
	}
	from, err1 := time.Parse(time.RFC3339, p.From)
	to, err2 := time.Parse(time.RFC3339, p.To)
	if err1 != nil || err2 != nil || to.Sub(from) != time.Hour {
		t.Fatalf("window %s – %s", p.From, p.To)
	}
	for _, g := range p.Games {
		n := len(g.Hourly)
		if n < 1 || n > 2 {
			t.Fatalf("%s hourly: %+v", g.Game, g.Hourly)
		}
		if last, err := time.Parse(time.RFC3339, g.Hourly[n-1].Hour); err != nil || !last.Equal(to.Add(-time.Second).Truncate(time.Hour)) {
			t.Fatalf("%s hourly: %+v (to %s)", g.Game, g.Hourly, p.To)
		}
	}
	// Rounding (and play straddling an hour) may differ by a second.
	near := func(a, b int64) bool { return a-b <= 1 && b-a <= 1 }
	var sum int64
	for _, h := range ludo.Hourly {
		sum += h.Seconds
	}
	if !near(sum, ludo.Seconds) {
		t.Fatalf("hourly %+v does not add up to %d s", ludo.Hourly, ludo.Seconds)
	}
	if d := e.opsPlaytime(t, ""); d.Hours != 24 || !near(d.Games[0].Seconds, ludo.Seconds) || len(d.Games[0].Hourly) < 24 {
		t.Fatalf("default window: %+v", d)
	}

	// A member left behind by a crashed instance (no presence key) is not
	// listed and is removed.
	ghost := e.guest()
	e.rdb.ZAdd(ctx, opsstats.OnlineKey, redis.Z{Score: float64(time.Now().UnixMilli()), Member: ghost.UserID})
	if o := e.opsOnline(t); o.Total != 3 {
		t.Fatalf("stale member listed: %+v", o)
	}
	if err := e.rdb.ZScore(ctx, opsstats.OnlineKey, ghost.UserID).Err(); !errors.Is(err, redis.Nil) {
		t.Fatalf("stale member kept: %v", err)
	}

	// Disconnecting leaves the online set at once.
	ic.close()
	waitFor(t, 3*time.Second, "idle person offline", func() bool {
		o := e.opsOnline(t)
		return o.Total == 2 && !slices.ContainsFunc(o.Users, func(u opsUser) bool { return u.UID == idle.UID })
	})
	if online, _ := e.opsMember(t, idle.UserID); online {
		t.Fatal("disconnected person still in the online set")
	}

	// Deleting the account removes it from both reports (the hourly totals
	// are aggregates without account ids and stay).
	if online, played := e.opsMember(t, pl.UserID); !online || !played {
		t.Fatalf("before deletion: online %v, played %v", online, played)
	}
	if r := e.deleteAccount(pl.Token, confirmDelete); r.Status != 204 {
		t.Fatalf("delete: %d %s", r.Status, r.Raw)
	}
	if online, played := e.opsMember(t, pl.UserID); online || played {
		t.Fatalf("after deletion: online %v, played %v", online, played)
	}
	o = e.opsOnline(t)
	if o.Total != 1 || o.Users[0].UID != wt.UID {
		t.Fatalf("online after deletion: %+v", o)
	}
	p = e.opsPlaytime(t, "?hours=1")
	if p.Games[0].Players != 0 || len(p.Games[0].Top) != 0 || !near(p.Games[0].Seconds, ludo.Seconds) {
		t.Fatalf("ludo playtime after deletion: %+v", p.Games[0])
	}
}

// PostgreSQL pool gauges (per instance), read from the pool at scrape time.
// Tests build an App per test in one process: the gauges follow the newest.
func TestPostgresPoolMetrics(t *testing.T) {
	e := newEnv(t, envOpts{})
	conn, err := e.app.PG.Acquire(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	m := e.scrape(t)
	conn.Release()
	maxConns := m["postgres_pool_max_connections"]
	acquired, idle := m[`postgres_pool_connections{state="acquired"}`], m[`postgres_pool_connections{state="idle"}`]
	constructing, ok := m[`postgres_pool_connections{state="constructing"}`]
	if maxConns != float64(e.app.PG.Config().MaxConns) || acquired < 1 || !ok || acquired+idle+constructing > maxConns {
		t.Fatalf("pool gauges: max %v acquired %v idle %v constructing %v (ok %v)", maxConns, acquired, idle, constructing, ok)
	}
}
