package tests

import (
	"context"
	"encoding/json"
	"sync"
	"testing"
	"time"

	dto "github.com/prometheus/client_model/go"

	"ludoroyale/internal/metrics"
	"ludoroyale/internal/rooms"
)

func asyncCount(job, result string) float64 {
	var m dto.Metric
	if err := metrics.AsyncJobs.WithLabelValues(job, result).Write(&m); err != nil {
		panic(err)
	}
	return m.GetCounter().GetValue()
}

// blockAsync occupies every background worker so work enqueued meanwhile
// (the new-account bootstrap) stays queued until release is called.
func blockAsync(t *testing.T, e *env) (release func()) {
	t.Helper()
	n := e.app.Async.Workers()
	started, gate := make(chan struct{}, n), make(chan struct{})
	for i := 0; i < n; i++ {
		if !e.app.Async.Go("test_block", func(ctx context.Context) error {
			started <- struct{}{}
			select {
			case <-gate:
			case <-ctx.Done():
			}
			return nil
		}) {
			t.Fatal("blocking job dropped")
		}
	}
	for i := 0; i < n; i++ {
		select {
		case <-started:
		case <-time.After(5 * time.Second):
			t.Fatal("background workers did not start")
		}
	}
	var once sync.Once
	release = func() { once.Do(func() { close(gate) }) }
	t.Cleanup(release)
	return release
}

func (e *env) hasProgressRow(userID string) bool {
	e.t.Helper()
	var n int
	if err := e.app.PG.QueryRow(context.Background(),
		`SELECT count(*) FROM progression.player_progress WHERE user_id = $1`, userID).Scan(&n); err != nil {
		e.t.Fatal(err)
	}
	return n == 1
}

// TestNewAccountUsableBeforeBootstrap: the progression bootstrap runs off the
// sign-up request; a brand-new account can use every progression-backed
// feature before it ran (rows are created lazily), and the late bootstrap is
// a harmless no-op.
func TestNewAccountUsableBeforeBootstrap(t *testing.T) {
	qc := &queryCounter{}
	e := newEnv(t, envOpts{pgTracer: qc})
	release := blockAsync(t, e)
	ok0 := asyncCount("new_account", "ok")

	q0, p0 := qc.n.Load(), qc.prog.Load()
	signup := e.do("POST", "/api/v1/auth/guest", "", map[string]any{})
	if n := qc.prog.Load() - p0; n != 0 {
		t.Fatalf("sign-up issued %d progression statements on the request path, want 0", n)
	}
	t.Logf("sign-up request path: %d PostgreSQL statements", qc.n.Load()-q0)
	a := parseAuth(t, signup)
	if u := signup.Body["user"].(map[string]any); u["level"].(float64) != 1 || u["title"] != "title_rookie" {
		t.Fatalf("sign-up user %v", u)
	}
	if e.hasProgressRow(a.UserID) {
		t.Fatal("progression bootstrap ran on the sign-up request path")
	}

	me := e.do("GET", "/api/v1/me", a.Token, nil)
	if me.Status != 200 || me.Body["user"].(map[string]any)["level"].(float64) != 1 {
		t.Fatalf("GET /me before bootstrap: %d %s", me.Status, me.Raw)
	}
	for _, path := range []string{"/api/v1/progression", "/api/v1/missions", "/api/v1/collection"} {
		if r := e.do("GET", path, a.Token, nil); r.Status != 200 {
			t.Fatalf("GET %s before bootstrap: %d %s", path, r.Status, r.Raw)
		}
	}
	var ms struct {
		Daily struct {
			PeriodKey string `json:"periodKey"`
			Missions  []struct {
				ID string `json:"id"`
			} `json:"missions"`
		} `json:"daily"`
	}
	_ = json.Unmarshal(e.do("GET", "/api/v1/missions", a.Token, nil).Raw, &ms)
	claim := e.do("POST", "/api/v1/missions/"+ms.Daily.PeriodKey+"/"+ms.Daily.Missions[0].ID+"/claim", a.Token, nil)
	if claim.Status != 422 || claim.Body["error"].(map[string]any)["code"] != "not_completed" {
		t.Fatalf("claim before bootstrap: %d %s", claim.Status, claim.Raw)
	}

	// Another new account befriends it by public id (resolved without a row).
	b := e.guest()
	if r := e.do("POST", "/api/v1/friends/requests", b.Token, map[string]any{"friendCode": a.UID}); r.Status != 201 {
		t.Fatalf("friend request to a not-yet-bootstrapped account: %d %s", r.Status, r.Raw)
	}

	// Buy an emote, join matchmaking and use the emote at once.
	if r := e.do("POST", "/api/v1/collection/items/emote_crown/purchase", a.Token, nil); r.Status != 200 {
		t.Fatalf("purchase: %d %s", r.Status, r.Raw)
	}
	c := e.mustDial("a", a)
	if reply := c.call("matchmaking.join", map[string]any{"game": "ludo", "capacity": 4}); reply.T != "matchmaking.status" {
		t.Fatalf("matchmaking.join: %s %s", reply.T, reply.P)
	}
	waitFor(t, 3*time.Second, "lobby", func() bool { return c.snapshot() != nil })
	if reply := c.call("chat.emote", map[string]any{"roomId": c.snapshot().ID, "emote": "emote_crown"}); reply.T != "ack" {
		t.Fatalf("emote right after purchase: %s %s", reply.T, reply.P)
	}

	release()
	waitFor(t, 5*time.Second, "late bootstraps", func() bool { return asyncCount("new_account", "ok")-ok0 >= 2 })
	if !e.hasProgressRow(a.UserID) || !e.hasProgressRow(b.UserID) {
		t.Fatal("progression rows missing after bootstrap")
	}
}

// TestShutdownDrainsPendingBootstrap: bootstraps still queued when the app
// shuts down are run by the bounded drain before Wait returns.
func TestShutdownDrainsPendingBootstrap(t *testing.T) {
	e := newEnv(t, envOpts{})
	release := blockAsync(t, e)
	var ids []string
	for i := 0; i < 3; i++ {
		ids = append(ids, e.guest().UserID)
	}
	ok0 := asyncCount("new_account", "ok")
	e.cancel() // shutdown begins with 3 bootstraps queued behind busy workers
	release()
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := e.app.Wait(ctx); err != nil {
		t.Fatalf("background work did not drain: %v", err)
	}
	if got := asyncCount("new_account", "ok") - ok0; got != 3 {
		t.Fatalf("drained %v of 3 bootstraps", got)
	}
	for _, id := range ids {
		if !e.hasProgressRow(id) {
			t.Fatalf("bootstrap for %s lost at shutdown", id)
		}
	}
	if e.app.Async.Go("new_account", func(context.Context) error { return nil }) {
		t.Fatal("job accepted after shutdown")
	}
}

// TestSeatAndEmoteCachesE2E: production wiring; a warm matchmaking join
// issues only the wallet pre-check, a warm owned emote no PostgreSQL query,
// and the next join reflects an equip immediately.
func TestSeatAndEmoteCachesE2E(t *testing.T) {
	t.Setenv("RATE_LIMIT_DISABLED", "true") // back-to-back emotes (chat: 1 per 3 s)
	qc := &queryCounter{}
	e := newEnv(t, envOpts{pgTracer: qc})
	ctx := context.Background()
	a := e.guest()
	caller := rooms.Caller{UserID: a.UserID}
	for _, item := range []string{"token_crown", "emote_crown"} {
		if r := e.do("POST", "/api/v1/collection/items/"+item+"/purchase", a.Token, nil); r.Status != 200 {
			t.Fatalf("purchase %s: %d %s", item, r.Status, r.Raw)
		}
	}
	join := func() (*rooms.Room, sample) {
		t.Helper()
		var room *rooms.Room
		s, err := timed(qc, func() (err error) {
			room, err = e.app.Rooms.MatchmakingJoin(ctx, caller, "ludo", "classic", 4)
			return err
		})
		if err != nil {
			t.Fatal(err)
		}
		return room, s
	}
	leave := func() {
		t.Helper()
		if err := e.app.Rooms.MatchmakingCancel(ctx, caller); err != nil {
			t.Fatal(err)
		}
	}
	seatOf := func(r *rooms.Room) rooms.Player {
		for _, p := range r.Players {
			if p.UserID == a.UserID {
				return p
			}
		}
		t.Fatal("not seated")
		return rooms.Player{}
	}

	room, _ := join() // fills the seat cache
	if p := seatOf(room); p.Level != 1 || p.Cosmetics["token"] != "token_classic" {
		t.Fatalf("seat %+v", p)
	}
	if err := e.app.Rooms.QuickChat(ctx, caller, room.ID, "", "emote_crown"); err != nil {
		t.Fatal(err) // fills the emote set
	}
	leave()

	room, s := join()
	if s.q != 1 {
		t.Fatalf("warm join issued %d PostgreSQL statements, want 1 (wallet pre-check)", s.q)
	}
	s, err := timed(qc, func() error { return e.app.Rooms.QuickChat(ctx, caller, room.ID, "", "emote_crown") })
	if err != nil || s.q != 0 {
		t.Fatalf("warm owned emote: %d statements, err %v", s.q, err)
	}
	leave()

	// Equip over REST; the very next join shows it.
	if r := e.do("PUT", "/api/v1/collection/loadout", a.Token, map[string]any{"slot": "token", "itemId": "token_crown"}); r.Status != 200 {
		t.Fatalf("equip: %d %s", r.Status, r.Raw)
	}
	room, _ = join()
	if p := seatOf(room); p.Cosmetics["token"] != "token_crown" {
		t.Fatalf("seat after equip: %+v", p.Cosmetics)
	}
	leave()

	// A non-owned emote is still rejected.
	b := e.guest()
	bc := rooms.Caller{UserID: b.UserID}
	broom, err := e.app.Rooms.MatchmakingJoin(ctx, bc, "ludo", "classic", 2)
	if err != nil {
		t.Fatal(err)
	}
	if err := e.app.Rooms.QuickChat(ctx, bc, broom.ID, "", "emote_crown"); err == nil {
		t.Fatal("non-owned emote accepted")
	}
}
