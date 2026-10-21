package tests

import (
	"os"
	"sync/atomic"
	"testing"
	"time"

	"ludoroyale/botplay/internal/config"
	"ludoroyale/botplay/tests/fakebackend"
)

// watchPeak samples the service population until stop is closed.
func watchPeak(h *harness, stop <-chan struct{}) *atomic.Int64 {
	var peak atomic.Int64
	go func() {
		for {
			select {
			case <-stop:
				return
			default:
			}
			if n := int64(h.svc.Count()); n > peak.Load() {
				peak.Store(n)
			}
			time.Sleep(2 * time.Millisecond)
		}
	}()
	return &peak
}

// Assignments beyond max_concurrent_bots / target are rejected, never served.
func TestConcurrencyLimitRejectsExcessAssignments(t *testing.T) {
	t.Parallel()
	f := newFake(t, fakebackend.Options{TurnTimeout: 10 * time.Second})
	h := newHarness(t, f, func(c *config.Config) {
		c.Bots.MaxConcurrentBots = 2
		c.Bots.TargetActiveBots = 2
	})
	stop := make(chan struct{})
	defer close(stop)
	peak := watchPeak(h, stop)
	h.start()
	f.StartPractice(fakebackend.RoomSetup{Game: "ludo", Bots: 3})
	waitFor(t, 10*time.Second, "rejection", func() bool {
		return h.metricValue("assignments_rejected_total", map[string]string{"reason": "at_capacity"}) == 1
	})
	waitFor(t, 5*time.Second, "two bots", func() bool { return h.svc.Count() == 2 })
	time.Sleep(200 * time.Millisecond)
	if peak.Load() > 2 {
		t.Fatalf("peak population %d exceeds max_concurrent_bots 2", peak.Load())
	}
	if len(f.SessionBodies()) != 2 {
		t.Fatalf("sessions created: %d", len(f.SessionBodies()))
	}
}

// per_game_max limits bots per game independently.
func TestPerGameMax(t *testing.T) {
	t.Parallel()
	f := newFake(t, fakebackend.Options{TurnTimeout: 10 * time.Second})
	h := newHarness(t, f, func(c *config.Config) { c.Bots.PerGameMax = map[string]int{config.GameLudo: 1} })
	h.start()
	f.StartPractice(fakebackend.RoomSetup{Game: "ludo", Bots: 2})
	f.StartPractice(fakebackend.RoomSetup{Game: "snakes_ladders", Bots: 2})
	waitFor(t, 10*time.Second, "game cap rejection", func() bool {
		return h.metricValue("assignments_rejected_total", map[string]string{"reason": "game_at_capacity"}) == 1
	})
	waitFor(t, 5*time.Second, "3 bots", func() bool { return h.svc.Count() == 3 })
	by := h.svc.CountsByGame()
	if by[config.GameLudo] != 1 || by[config.GameSnakes] != 2 {
		t.Fatalf("per game: %v", by)
	}
	if h.metricValue("bots_active", map[string]string{"game": "ludo"}) != 1 {
		t.Fatal("bots_active gauge")
	}
}

// Disabling bots stops new assignments; running games finish; re-enabling
// serves again. A disabled game is not served.
func TestEnableDisableAtRuntime(t *testing.T) {
	t.Parallel()
	f := newFake(t, fakebackend.Options{})
	h := newHarness(t, f, nil)
	h.start()
	room1 := f.StartPractice(fakebackend.RoomSetup{Game: "ludo", Bots: 1, StartTokens: [][]int{{20, 30, 40, 50}, {20, 30, 40, 50}}})
	waitFor(t, 10*time.Second, "bot playing", func() bool {
		r, _ := f.Room(room1)
		return r.Status == "playing"
	})
	if err := h.reload(func(c *config.Config) { c.Bots.Enabled = false }); err != nil {
		t.Fatal(err)
	}
	room2 := f.StartPractice(fakebackend.RoomSetup{Game: "ludo", Bots: 1})
	waitFor(t, 60*time.Second, "running game finished while disabled", roomFinished(f, room1))
	waitFor(t, 10*time.Second, "bot exited", func() bool { return h.svc.Count() == 0 })
	time.Sleep(1500 * time.Millisecond) // longer than the assignment long-poll
	if r, _ := f.Room(room2); len(r.Players) != 1 {
		t.Fatalf("disabled service served a new assignment: %+v", r.Players)
	}
	if h.metricValue("bots_target", nil) != 0 {
		t.Fatal("bots_target should be 0 when disabled")
	}
	// Re-enable, but with snakes disabled.
	if err := h.reload(func(c *config.Config) {
		c.Bots.Enabled = true
		c.Bots.Games = map[string]bool{config.GameSnakes: false}
	}); err != nil {
		t.Fatal(err)
	}
	f.StartPractice(fakebackend.RoomSetup{Game: "snakes_ladders", Bots: 1})
	room3 := f.StartPractice(fakebackend.RoomSetup{Game: "ludo", Bots: 1, StartTokens: nearHome(2)})
	waitFor(t, 30*time.Second, "game after re-enable", roomFinished(f, room3))
	waitFor(t, 5*time.Second, "game_disabled rejection", func() bool {
		return h.metricValue("assignments_rejected_total", map[string]string{"reason": "game_disabled"}) >= 1
	})
}

// An invalid reload is rejected and the last valid config stays active.
func TestReloadInvalidConfigKeepsLastValid(t *testing.T) {
	t.Parallel()
	f := newFake(t, fakebackend.Options{})
	h := newHarness(t, f, nil)
	h.start()
	gen := h.store.Load().Generation
	if err := os.WriteFile(h.cfgPath, []byte("bots: {max_bots_per_room: 9}\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := h.watcher.Reload("test"); err == nil {
		t.Fatal("invalid config accepted")
	}
	if h.store.Load().Generation != gen || h.store.Config().Connection.BackendHTTPURL != f.HTTPURL() {
		t.Fatal("active config changed after invalid reload")
	}
	if h.metricValue("config_reload_failures_total", nil) != 1 || h.metricValue("config_reloads_total", map[string]string{"result": "failure"}) != 1 {
		t.Fatal("reload failure not counted")
	}
	// The service keeps working on the last valid config.
	room := f.StartPractice(fakebackend.RoomSetup{Game: "ludo", Bots: 1, StartTokens: nearHome(2)})
	waitFor(t, 30*time.Second, "game finished", roomFinished(f, room))
	// A valid reload (profile change) applies.
	if err := h.reload(func(c *config.Config) { c.Bots.Behavior.DefaultProfile = "advanced" }); err != nil {
		t.Fatal(err)
	}
	if h.store.Config().Bots.Behavior.DefaultProfile != "advanced" || h.metricValue("config_reloads_total", map[string]string{"result": "success"}) != 1 {
		t.Fatal("valid reload not applied")
	}
}

// Public fill: requests at most min(free seats, max_bots_per_room - bots),
// never re-requests while bots are pending or within the cooldown, and serves
// the resulting assignments. Runs against both fill response shapes: the
// backend implementation ({"requested": n} + long-poll delivery, with
// publicFillEnabled in the lobby list) and the documented one (assignments
// inline, 403 when disabled).
func TestPublicFillRespectsCapacity(t *testing.T) {
	t.Parallel()
	for _, mode := range []string{"implementation", "documented"} {
		t.Run(mode, func(t *testing.T) {
			t.Parallel()
			documented := mode == "documented"
			f := newFake(t, fakebackend.Options{PublicFillEnabled: true, TurnTimeout: 10 * time.Second,
				FillReturnsAssignments: documented, OmitPublicFillFlag: documented})
			testPublicFill(t, f, documented)
		})
	}
}

func testPublicFill(t *testing.T, f *fakebackend.Server, documented bool) {
	h := newHarness(t, f, func(c *config.Config) {
		c.Bots.Modes = []string{config.ModePublicFill}
		c.Bots.MaxBotsPerRoom = 2
		pm := &c.Bots.PublicMatchmaking
		pm.Enabled = true
		pm.PerGame = map[string]bool{config.GameLudo: true, config.GameSnakes: false}
		pm.PollIntervalMS = 100
		pm.FillAfterSeconds = 5
		pm.MaximumWaitSeconds = 60
		pm.RefillCooldownSeconds = 1
	})
	roomA := f.AddLobby(fakebackend.LobbySetup{Game: "ludo", Capacity: 4, Humans: 1, Waited: 10 * time.Second})
	roomEarly := f.AddLobby(fakebackend.LobbySetup{Game: "ludo", Capacity: 4, Humans: 1, Waited: time.Second})
	roomSnakes := f.AddLobby(fakebackend.LobbySetup{Game: "snakes_ladders", Capacity: 2, Humans: 1, Waited: 10 * time.Second})
	roomFull := f.AddLobby(fakebackend.LobbySetup{Game: "ludo", Capacity: 2, Humans: 1, Waited: 10 * time.Second})
	h.start()
	waitFor(t, 10*time.Second, "bots seated in lobby A", func() bool {
		r, _ := f.Room(roomA)
		return len(r.Players) == 3
	})
	waitFor(t, 10*time.Second, "2-seat lobby filled and started", func() bool {
		r, _ := f.Room(roomFull)
		return r.Status == "playing" || r.Finished
	})
	time.Sleep(2500 * time.Millisecond) // several poll intervals + cooldowns
	perRoom := map[string][]int{}
	for _, fr := range f.Fills() {
		perRoom[fr.RoomID] = append(perRoom[fr.RoomID], fr.Count)
	}
	if got := perRoom[roomA]; len(got) != 1 || got[0] != 2 {
		t.Fatalf("lobby A fills = %v, want exactly one request for 2 (max_bots_per_room)", got)
	}
	if got := perRoom[roomFull]; len(got) != 1 || got[0] != 1 {
		t.Fatalf("2-seat lobby fills = %v, want one request for 1 (free seats)", got)
	}
	if len(perRoom[roomEarly]) != 0 || len(perRoom[roomSnakes]) != 0 {
		t.Fatalf("filled a lobby that is too early or disabled: %v", perRoom)
	}
	for _, fr := range f.Fills() {
		if fr.Status != 200 {
			t.Fatalf("a fill request was refused by the backend (over capacity or pending): %+v", fr)
		}
	}
	if r, _ := f.Room(roomA); r.Status != "lobby" {
		t.Fatal("lobby A should still wait for a human (3/4)")
	}
	if h.metricValue("room_joins_total", map[string]string{"kind": "public_fill"}) != 3 {
		t.Fatal("public fill joins")
	}
	// The backend disables public fill.
	f.SetPublicFill(false)
	f.AddLobby(fakebackend.LobbySetup{Game: "ludo", Capacity: 4, Humans: 2, Waited: 10 * time.Second})
	if documented {
		// No flag in the lobby list: the fill is refused with 403 and paused.
		waitFor(t, 5*time.Second, "forbidden fill", func() bool {
			return h.metricValue("public_fill_requests_total", map[string]string{"result": "forbidden"}) == 1
		})
	} else {
		time.Sleep(500 * time.Millisecond)
	}
	n := len(f.Fills())
	time.Sleep(700 * time.Millisecond)
	if len(f.Fills()) != n {
		t.Fatal("fill requests continued while the backend has public fill disabled")
	}
	if !documented && h.metricValue("public_fill_requests_total", map[string]string{"result": "forbidden"}) != 0 {
		t.Fatal("publicFillEnabled=false should prevent fill requests entirely")
	}
}

// SIGTERM with policy finish_games: no new work, the running game is
// finished, sessions are revoked, Run returns.
func TestGracefulShutdownFinishesGames(t *testing.T) {
	t.Parallel()
	f := newFake(t, fakebackend.Options{})
	h := newHarness(t, f, nil)
	h.start()
	room := f.StartPractice(fakebackend.RoomSetup{Game: "ludo", Bots: 1, StartTokens: [][]int{{30, 40, 45, 50}, {30, 40, 45, 50}}})
	waitFor(t, 10*time.Second, "playing", func() bool {
		r, _ := f.Room(room)
		return r.Status == "playing"
	})
	if err := h.stop(30 * time.Second); err != nil {
		t.Fatalf("run error: %v", err)
	}
	r, _ := f.Room(room)
	if !r.Finished || r.Players[1].Forfeited || r.Players[0].Forfeited {
		t.Fatalf("game should have finished normally: %+v", r)
	}
	if len(f.Revoked()) != 1 {
		t.Fatal("session not revoked")
	}
}

// Policy leave_now: bots leave immediately (forfeit) and sessions are revoked.
func TestGracefulShutdownLeaveNow(t *testing.T) {
	t.Parallel()
	f := newFake(t, fakebackend.Options{TurnTimeout: 10 * time.Second})
	h := newHarness(t, f, func(c *config.Config) { c.Bots.Shutdown.Policy = config.PolicyLeaveNow })
	h.start()
	room := f.StartPractice(fakebackend.RoomSetup{Game: "ludo", Bots: 1})
	waitFor(t, 10*time.Second, "playing", func() bool {
		r, _ := f.Room(room)
		return r.Status == "playing"
	})
	start := time.Now()
	if err := h.stop(10 * time.Second); err != nil {
		t.Fatal(err)
	}
	if time.Since(start) > 5*time.Second {
		t.Fatal("leave_now took too long")
	}
	r, _ := f.Room(room)
	if !r.Finished || r.Winner != 0 {
		t.Fatalf("bot should have forfeited, human wins: %+v", r)
	}
	if len(f.Revoked()) != 1 {
		t.Fatal("session not revoked")
	}
}
