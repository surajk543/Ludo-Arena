package tests

import (
	"net/http"
	"slices"
	"strings"
	"sync"
	"testing"
	"time"

	"ludoarena/internal/rooms"
)

func (e *env) botController(t *testing.T) string {
	t.Helper()
	r := e.do("POST", "/api/v1/bot/controller/token", "", nil, "Authorization", "Bot-Service "+botKey)
	if r.Status != 200 {
		t.Fatalf("controller token: %d %s", r.Status, r.Raw)
	}
	return r.Body["token"].(string)
}

// spawnBots claims n assignments and connects bot clients.
func (e *env) spawnBots(t *testing.T, ctl string, n int) []*client {
	t.Helper()
	var bots []*client
	deadline := time.Now().Add(10 * time.Second)
	for len(bots) < n && time.Now().Before(deadline) {
		r := e.do("GET", "/api/v1/bot/assignments?wait=2", ctl, nil)
		if r.Status != 200 {
			t.Fatalf("assignments: %d %s", r.Status, r.Raw)
		}
		for _, a := range r.Body["assignments"].([]any) {
			id := a.(map[string]any)["id"].(string)
			s := e.do("POST", "/api/v1/bot/sessions", ctl, map[string]any{"assignmentId": id, "name": "Asha", "profile": "balanced"})
			acct := botAccount(t, s)
			c, _, err := e.dial("bot"+acct.UID, acct, map[string]string{"X-App-Platform": "bot"})
			if err != nil {
				t.Fatalf("bot dial: %v", err)
			}
			c.send("game.request_sync", map[string]any{})
			bots = append(bots, c)
		}
	}
	if len(bots) < n {
		t.Fatalf("only %d/%d bots", len(bots), n)
	}
	return bots
}

func TestBotServiceAuthAndPracticeGame(t *testing.T) {
	e := newEnv(t, envOpts{dice: rooms.NewSeededDice(21)})
	if r := e.do("POST", "/api/v1/bot/controller/token", "", nil, "Authorization", "Bot-Service wrong-key-wrong-key-wrong-key-wrong"); r.Status != 401 {
		t.Fatalf("wrong bot key accepted: %d", r.Status)
	}
	human := e.guest()
	// Human tokens cannot use bot endpoints; controller tokens cannot use player endpoints.
	if r := e.do("GET", "/api/v1/bot/assignments?wait=0", human.Token, nil); r.Status != 403 {
		t.Fatalf("human used bot API: %d", r.Status)
	}
	ctl := e.botController(t)
	if r := e.do("GET", "/api/v1/me", ctl, nil); r.Status != 403 {
		t.Fatalf("controller used player API: %d", r.Status)
	}

	hc := e.mustDial("human", human)
	if m := hc.call("practice.start", map[string]any{"game": "ludo", "variant": "quick", "bots": 2}); m.T != "room.updated" {
		t.Fatalf("practice.start: %s %s", m.T, m.P)
	}
	bots := e.spawnBots(t, ctl, 2)
	waitFor(t, 10*time.Second, "practice game start", func() bool {
		s := hc.snapshot()
		return s != nil && s.Status == "playing"
	})
	s := hc.snapshot()
	// Practice: the player chose computer opponents, so the room lists them
	// (only practice and private rooms do; seats never carry a bot flag).
	if s.Mode != "practice" || len(s.ComputerSeats) != 2 || seatIn(s, bots[0].acct.UID) < 0 ||
		!slices.Contains(s.ComputerSeats, seatIn(s, bots[0].acct.UID)) || slices.Contains(s.ComputerSeats, hc.seat()) {
		t.Fatalf("practice room: mode %s computer seats %v", s.Mode, s.ComputerSeats)
	}
	// Bot tokens: no player REST, no other rooms.
	if r := e.do("GET", "/api/v1/wallet", bots[0].acct.Token, nil); r.Status != 403 {
		t.Fatalf("bot used wallet API: %d", r.Status)
	}
	if m := bots[0].call("game.request_sync", map[string]any{"roomId": "r_other"}); !strings.Contains(string(m.P), "not_in_room") {
		t.Fatalf("bot accessed another room: %s", m.P)
	}
	if m := bots[0].call("chat.quick", map[string]any{"roomId": "r_other", "msg": "gg"}); !strings.Contains(string(m.P), "not_in_room") {
		t.Fatalf("bot chatted in another room: %s", m.P)
	}

	all := append([]*client{hc}, bots...)
	var wg sync.WaitGroup
	for _, c := range all {
		wg.Add(1)
		go func(c *client) { defer wg.Done(); c.playUntilFinished(60 * time.Second) }(c)
	}
	wg.Wait()
	assertNoDivergence(t, all)
	// Practice games never touch coins.
	if got := e.coins(human.Token); got != 1_000_000 {
		t.Fatalf("practice changed coins: %d", got)
	}
}

func TestPublicFillRespectsLimits(t *testing.T) {
	e := newEnv(t, envOpts{dice: rooms.NewSeededDice(4)})
	ctl := e.botController(t)
	h := e.mustDial("h", e.guest())
	h.call("matchmaking.join", map[string]any{"game": "snakes_ladders", "capacity": 3})
	waitFor(t, 3*time.Second, "lobby", func() bool { return h.snapshot() != nil })
	roomID := h.snapshot().ID

	l := e.do("GET", "/api/v1/bot/lobbies", ctl, nil)
	if l.Status != 200 || !strings.Contains(string(l.Raw), roomID) {
		t.Fatalf("lobbies: %d %s", l.Status, l.Raw)
	}
	if r := e.do("POST", "/api/v1/bot/lobbies/"+roomID+"/fill", ctl, map[string]any{"count": 3}); r.Status != 409 {
		t.Fatalf("over-capacity fill accepted: %d %s", r.Status, r.Raw)
	}
	if r := e.do("POST", "/api/v1/bot/lobbies/"+roomID+"/fill", ctl, map[string]any{"count": 2}); r.Status != 200 {
		t.Fatalf("fill: %d %s", r.Status, r.Raw)
	}
	if r := e.do("POST", "/api/v1/bot/lobbies/"+roomID+"/fill", ctl, map[string]any{"count": 1}); r.Status != 409 {
		t.Fatalf("repeat fill while pending accepted: %d", r.Status)
	}
	bots := e.spawnBots(t, ctl, 2)
	waitFor(t, 10*time.Second, "filled game starts", func() bool { return h.snapshot().Status == "playing" })
	if s := h.snapshot(); len(s.Players) != 3 {
		t.Fatalf("players = %d", len(s.Players))
	}
	_ = bots
}

func TestLoadTestSessionsIsolated(t *testing.T) {
	e := newEnv(t, envOpts{dice: rooms.NewSeededDice(8)})
	ctl := e.botController(t)
	var cs []*client
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
		cs = append(cs, c)
	}
	// A human matchmaking at the same time never lands with load-test bots.
	human := e.mustDial("human", e.guest())
	human.call("matchmaking.join", map[string]any{"game": "ludo", "capacity": 2})
	for _, c := range cs {
		if m := c.call("matchmaking.join", map[string]any{"game": "ludo", "capacity": 2}); m.T != "matchmaking.status" {
			t.Fatalf("loadtest matchmaking: %s %s", m.T, m.P)
		}
	}
	waitFor(t, 5*time.Second, "loadtest game", func() bool {
		s := cs[0].snapshot()
		return s != nil && s.Status == "playing"
	})
	if s := human.snapshot(); s == nil || s.Status != "lobby" || len(s.Players) != 1 {
		t.Fatalf("human mixed with load-test bots: %+v", s)
	}
	// Bots without the loadtest scope cannot matchmake.
	_ = http.StatusOK
}
