package tests

import (
	"net/http"
	"os"
	"strings"
	"testing"
	"time"

	"ludoroyale/internal/rooms"
)

func TestVersionGateAndMaintenanceEnforcement(t *testing.T) {
	e := newEnv(t, envOpts{dice: rooms.NewSeededDice(1)})
	g := e.guest()

	cfg := e.do("GET", "/api/v1/app/config?platform=android&version=1.0.0&build=1&environment=development", "", nil)
	if cfg.Status != 200 || cfg.Body["mode"] != "normal" || cfg.Body["entryFees"] == nil {
		t.Fatalf("app config: %d %s", cfg.Status, cfg.Raw)
	}
	if r := e.do("GET", "/api/v1/app/config?platform=android&version=1.0.0&build=1&environment=production", "", nil); r.Status != 400 {
		t.Fatalf("environment mismatch accepted: %d", r.Status)
	}
	if r := e.do("GET", "/api/v1/me", g.Token, nil, "X-App-Version", "banana"); r.Status != 400 {
		t.Fatalf("invalid version accepted: %d", r.Status)
	}

	// Raise the minimum: old clients get 426 on REST and on the WebSocket
	// handshake, and live connections are closed with 4426.
	live := e.mustDial("live", g)
	writeFile(t, e.policy, policyJSON("1.2.0", 1, "1.3.0", 1, false))
	if err := e.app.Policy.Reload(); err != nil {
		t.Fatal(err)
	}
	r := e.do("GET", "/api/v1/me", g.Token, nil)
	if r.Status != 426 || r.Body["error"].(map[string]any)["code"] != "update_required" {
		t.Fatalf("old client REST: %d %s", r.Status, r.Raw)
	}
	if !strings.Contains(string(r.Raw), `"minimumSupportedVersion":"1.2.0"`) {
		t.Fatalf("426 must carry the policy: %s", r.Raw)
	}
	if r := e.do("POST", "/api/v1/auth/guest", "", map[string]any{}); r.Status != 426 {
		t.Fatalf("auth with old client: %d", r.Status)
	}
	if _, res, err := e.dial("old", g, nil); err == nil || res == nil || res.StatusCode != http.StatusUpgradeRequired {
		t.Fatalf("old client WS handshake not rejected with 426: %v %v", err, res)
	}
	select {
	case <-live.closed:
	case <-time.After(15 * time.Second):
		t.Fatal("live connection of an unsupported version was not closed")
	}
	live.mu.Lock()
	code := live.closeCode
	live.mu.Unlock()
	if code != 4426 {
		t.Fatalf("close code %d, want 4426", code)
	}
	// A supported (newer) client is allowed; optional update is not blocking.
	if r := e.do("GET", "/api/v1/me", g.Token, nil, "X-App-Version", "1.2.5"); r.Status != 200 {
		t.Fatalf("supported client blocked: %d %s", r.Status, r.Raw)
	}
	cfg = e.do("GET", "/api/v1/app/config?platform=android&version=1.2.5&build=1", "", nil)
	if cfg.Body["mode"] != "optional_update" {
		t.Fatalf("mode = %v", cfg.Body["mode"])
	}

	// Emergency maintenance via the flag file blocks REST, handshakes and
	// game actions; removing it restores service without a new build.
	writeFile(t, e.policy, policyJSON("1.0.0", 1, "1.0.0", 1, false))
	_ = e.app.Policy.Reload()
	p1 := e.mustDial("m1", g)
	writeFile(t, e.flag, "Upgrading servers\n")
	_ = e.app.Policy.Reload()
	if r := e.do("GET", "/api/v1/wallet", g.Token, nil); r.Status != 503 || r.Body["error"].(map[string]any)["code"] != "maintenance" {
		t.Fatalf("maintenance REST: %d %s", r.Status, r.Raw)
	}
	if m := p1.call("matchmaking.join", map[string]any{"game": "ludo", "capacity": 2}); !strings.Contains(string(m.P), "maintenance") {
		t.Fatalf("matchmaking during maintenance: %s", m.P)
	}
	select {
	case <-p1.closed:
	case <-time.After(5 * time.Second):
		t.Fatal("connection not closed for maintenance")
	}
	if _, res, err := e.dial("m2", g, nil); err == nil || res == nil || res.StatusCode != http.StatusServiceUnavailable {
		t.Fatalf("handshake during maintenance: %v %v", err, res)
	}
	cfg = e.do("GET", "/api/v1/app/config?platform=ios&version=1.0.0&build=1", "", nil)
	if cfg.Status != 200 || cfg.Body["mode"] != "maintenance" ||
		cfg.Body["maintenance"].(map[string]any)["message"] != "Upgrading servers" {
		t.Fatalf("config during maintenance: %s", cfg.Raw)
	}
	_ = os.Remove(e.flag)
	_ = e.app.Policy.Reload()
	if r := e.do("GET", "/api/v1/wallet", g.Token, nil); r.Status != 200 {
		t.Fatalf("service not restored: %d", r.Status)
	}
}

func TestMaintenancePausesRunningGame(t *testing.T) {
	e := newEnv(t, envOpts{dice: rooms.NewSeededDice(2), turnTimeout: 600 * time.Millisecond})
	cs := startPublic(t, e, "snakes_ladders", "classic", 2)
	roomID := cs[0].snapshot().ID
	writeFile(t, e.flag, "")
	_ = e.app.Policy.Reload()
	time.Sleep(2500 * time.Millisecond) // several turn deadlines pass
	// No auto-moves happened during maintenance and nobody was forfeited.
	v, err := e.app.Rooms.Snapshot(t.Context(), cs[0].acct.UserID, roomID)
	if err != nil {
		t.Fatal(err)
	}
	if v.Status != "playing" || v.Turn.TurnSeq != 0 || v.Players[0].Strikes != 0 || v.Players[1].Strikes != 0 {
		t.Fatalf("game advanced during maintenance: status=%s seq=%d strikes=%d/%d",
			v.Status, v.Turn.TurnSeq, v.Players[0].Strikes, v.Players[1].Strikes)
	}
	_ = os.Remove(e.flag)
	_ = e.app.Policy.Reload()
	// After maintenance, timers resume (auto-play of absent players).
	waitFor(t, 20*time.Second, "game resumes", func() bool {
		v, err := e.app.Rooms.Snapshot(t.Context(), cs[0].acct.UserID, roomID)
		return err == nil && v.Turn.TurnSeq > 0
	})
}

func TestTurnTimeoutsForfeitAbsentPlayer(t *testing.T) {
	e := newEnv(t, envOpts{dice: rooms.NewSeededDice(9), turnTimeout: 300 * time.Millisecond})
	cs := startPublic(t, e, "ludo", "classic", 2)
	a, b := cs[0], cs[1]
	b.close()
	// a keeps playing; b times out MAX_STRIKES (5) times and is forfeited -> a wins.
	a.playUntilFinished(60 * time.Second)
	s := a.snapshot()
	if s.Result == nil || s.Result.WinnerSeat != a.seat() {
		t.Fatalf("result %+v (a seat %d)", s.Result, a.seat())
	}
	if !s.Players[1-a.seat()].Forfeited {
		t.Fatal("absent player not forfeited")
	}
	assertNoDivergence(t, []*client{a})
}
