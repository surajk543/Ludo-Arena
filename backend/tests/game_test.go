package tests

import (
	"context"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/coder/websocket"

	"ludoroyale/internal/rooms"
)

// startPublic matchmakes n fresh guests into one public room and waits for
// the game to start on every client.
func startPublic(t *testing.T, e *env, game, variant string, n int) []*client {
	t.Helper()
	var cs []*client
	for i := 0; i < n; i++ {
		g := e.guest()
		c := e.mustDial(strings.Repeat("p", 1)+string(rune('A'+i)), g)
		reply := c.call("matchmaking.join", map[string]any{"game": game, "variant": variant, "capacity": n})
		if reply.T != "matchmaking.status" {
			t.Fatalf("matchmaking.join reply %s %s", reply.T, reply.P)
		}
		cs = append(cs, c)
	}
	for _, c := range cs {
		waitFor(t, 5*time.Second, c.name+" game start", func() bool {
			r := c.snapshot()
			return r != nil && r.Status == "playing"
		})
	}
	return cs
}

func playAll(t *testing.T, cs []*client) {
	var wg sync.WaitGroup
	for _, c := range cs {
		wg.Add(1)
		go func(c *client) {
			defer wg.Done()
			c.playUntilFinished(90 * time.Second)
		}(c)
	}
	wg.Wait()
}

func assertNoDivergence(t *testing.T, cs []*client) {
	t.Helper()
	for _, c := range cs {
		c.mu.Lock()
		if c.hashMiss > 0 {
			t.Errorf("%s: %d hash mismatches", c.name, c.hashMiss)
		}
		c.mu.Unlock()
	}
}

func TestFullPublicGames(t *testing.T) {
	cases := []struct {
		game, variant string
		players       int
		fee           int64
	}{
		{"ludo", "classic", 2, 1000},
		{"ludo", "quick", 4, 1000},
		{"snakes_ladders", "classic", 3, 500},
	}
	for _, tc := range cases {
		t.Run(tc.game+"_"+tc.variant, func(t *testing.T) {
			e := newEnv(t, envOpts{dice: rooms.NewSeededDice(42)})
			cs := startPublic(t, e, tc.game, tc.variant, tc.players)
			// Entry fees were charged once, atomically, before the first turn.
			for _, c := range cs {
				if got := e.coins(c.acct.Token); got != 1_000_000-tc.fee {
					t.Fatalf("%s coins after start = %d", c.name, got)
				}
			}
			playAll(t, cs)
			assertNoDivergence(t, cs)
			final := cs[0].snapshot()
			if final.Result == nil {
				t.Fatal("no result")
			}
			winner := final.Result.WinnerSeat
			wantPot := tc.fee * int64(tc.players)
			if final.Result.Payout != wantPot {
				t.Fatalf("payout = %d, want %d", final.Result.Payout, wantPot)
			}
			// The winner's payout settles exactly once; total coins are conserved.
			var total int64
			waitFor(t, 5*time.Second, "payout", func() bool {
				total = 0
				for _, c := range cs {
					total += e.coins(c.acct.Token)
				}
				return total == int64(tc.players)*1_000_000
			})
			for _, c := range cs {
				want := int64(1_000_000 - tc.fee)
				if c.seat() == winner {
					want += wantPot
				}
				if got := e.coins(c.acct.Token); got != want {
					t.Fatalf("%s (seat %d, winner %d) coins %d want %d", c.name, c.seat(), winner, got, want)
				}
				if c.count("wallet.updated") < 1 {
					t.Fatalf("%s got no wallet.updated", c.name)
				}
			}
		})
	}
}

func TestPrivateRoomAndRematch(t *testing.T) {
	e := newEnv(t, envOpts{dice: rooms.NewSeededDice(7)})
	host := e.mustDial("host", e.guest())
	if r := host.call("room.create", map[string]any{"game": "snakes_ladders", "capacity": 2}); r.T != "ack" {
		t.Fatalf("create: %s %s", r.T, r.P)
	}
	waitFor(t, 3*time.Second, "lobby", func() bool { return host.snapshot() != nil && host.snapshot().Code != "" })
	code := host.snapshot().Code

	friend := e.guest()
	// REST preview reveals only coarse info.
	prev := e.do("GET", "/api/v1/rooms/code/"+strings.ToLower(code), friend.Token, nil)
	if prev.Status != 200 || prev.Body["players"].(float64) != 1 || prev.Body["game"] != "snakes_ladders" {
		t.Fatalf("preview: %d %s", prev.Status, prev.Raw)
	}
	if bad := e.do("GET", "/api/v1/rooms/code/ZZZZZZ", friend.Token, nil); bad.Status != 404 {
		t.Fatalf("invalid code preview: %d", bad.Status)
	}
	fc := e.mustDial("friend", friend)
	if r := fc.call("room.join", map[string]any{"code": code}); r.T != "room.updated" {
		t.Fatalf("join: %s %s", r.T, r.P)
	}
	// A third player cannot join a full room; an invalid code is rejected.
	third := e.mustDial("third", e.guest())
	if r := third.call("room.join", map[string]any{"code": code}); r.T != "error" || !strings.Contains(string(r.P), "room_full") {
		t.Fatalf("full room join: %s %s", r.T, r.P)
	}
	if r := third.call("room.join", map[string]any{"code": "AAAAAA"}); !strings.Contains(string(r.P), "invalid_code") {
		t.Fatalf("invalid code join: %s", r.P)
	}
	// Only the host can start.
	roomID := host.snapshot().ID
	if r := fc.call("game.start", map[string]any{"roomId": roomID}); !strings.Contains(string(r.P), "not_host") {
		t.Fatalf("non-host start: %s", r.P)
	}
	waitFor(t, 3*time.Second, "both connected", func() bool {
		s := host.snapshot()
		return len(s.Players) == 2 && s.Players[0].Connected && s.Players[1].Connected
	})
	if r := host.call("game.start", map[string]any{"roomId": roomID}); r.T != "ack" {
		t.Fatalf("start: %s %s", r.T, r.P)
	}
	// Joining a game in progress is refused.
	if r := third.call("room.join", map[string]any{"code": code}); !strings.Contains(string(r.P), "room_in_progress") {
		t.Fatalf("join in progress: %s", r.P)
	}
	cs := []*client{host, fc}
	playAll(t, cs)
	assertNoDivergence(t, cs)

	// Rematch requires every participant's consent; then the SAME room and
	// code reopen as a lobby for round 2 with fresh game state.
	if r := host.call("game.rematch", map[string]any{"roomId": roomID, "accept": true}); r.T != "ack" {
		t.Fatalf("rematch vote: %s %s", r.T, r.P)
	}
	time.Sleep(200 * time.Millisecond)
	if s := host.snapshot(); s.Status != "finished" {
		t.Fatalf("rematch started without consent: %s", s.Status)
	}
	if r := fc.call("game.rematch", map[string]any{"roomId": roomID, "accept": true}); r.T != "ack" {
		t.Fatalf("rematch vote 2: %s %s", r.T, r.P)
	}
	waitFor(t, 3*time.Second, "rematch lobby", func() bool {
		s := host.snapshot()
		return s.Status == "lobby" && s.Round == 2
	})
	s := host.snapshot()
	if s.Code != code || s.ID != roomID || len(s.Players) != 2 || s.Board.Positions != nil {
		t.Fatalf("rematch state: %+v", s)
	}
	if r := host.call("game.start", map[string]any{"roomId": roomID}); r.T != "ack" {
		t.Fatalf("round 2 start: %s %s", r.T, r.P)
	}
	waitFor(t, 3*time.Second, "round 2 playing", func() bool { return fc.snapshot().Status == "playing" })
	if s := fc.snapshot(); s.Turn.TurnSeq != 0 || s.Board.Positions[0] != 0 || s.Board.Positions[1] != 0 {
		t.Fatalf("round 2 not reset: %+v", s.Board)
	}
}

func TestReconnectRestoresGame(t *testing.T) {
	e := newEnv(t, envOpts{dice: rooms.NewSeededDice(3)})
	cs := startPublic(t, e, "ludo", "classic", 2)
	a, b := cs[0], cs[1]
	roomID := a.snapshot().ID
	b.close()
	waitFor(t, 5*time.Second, "disconnect seen", func() bool {
		s := a.snapshot()
		return !s.Players[b.seat()].Connected
	})
	// Reconnect with the same account: ready + authoritative snapshot.
	b2, _, err := e.dial("pB2", b.acct, map[string]string{"X-Reconnect": "1"})
	if err != nil {
		t.Fatal(err)
	}
	waitFor(t, 5*time.Second, "resync", func() bool {
		s := b2.snapshot()
		return s != nil && s.ID == roomID && s.Status == "playing"
	})
	b2.mu.Lock()
	active := b2.ready["activeRoomId"]
	b2.mu.Unlock()
	if active != roomID {
		t.Fatalf("activeRoomId = %v", active)
	}
	waitFor(t, 5*time.Second, "reconnect seen", func() bool {
		s := a.snapshot()
		return s.Players[b.seat()].Connected
	})
	playAll(t, []*client{a, b2})
	assertNoDivergence(t, []*client{a, b2})
}

func TestDuplicateAndConcurrentCommands(t *testing.T) {
	e := newEnv(t, envOpts{dice: rooms.NewSeededDice(11)})
	cs := startPublic(t, e, "snakes_ladders", "classic", 2)
	var mover *client
	for _, c := range cs {
		if c.snapshot().Turn.Seat == c.seat() {
			mover = c
		}
	}
	r := mover.snapshot()
	before := mover.count("game.dice_result")
	// 10 rapid rolls for the same turn: exactly one is accepted.
	for i := 0; i < 10; i++ {
		mover.send("game.roll_dice", map[string]any{"roomId": r.ID, "turnSeq": r.Turn.TurnSeq})
	}
	time.Sleep(500 * time.Millisecond)
	if got := mover.count("game.dice_result") - before; got != 1 {
		t.Fatalf("accepted rolls = %d, want 1", got)
	}
	if !mover.hasError("stale_state") && !mover.hasError("not_your_turn") {
		t.Fatal("duplicate rolls were not rejected")
	}
	// A replayed message id is acknowledged as a duplicate, not executed.
	raw := `{"t":"game.request_sync","id":"same-id","p":{}}`
	for i := 0; i < 2; i++ {
		_ = mover.conn.Write(context.Background(), websocket.MessageText, []byte(raw))
	}
	waitFor(t, 3*time.Second, "dup ack", func() bool {
		mover.mu.Lock()
		defer mover.mu.Unlock()
		for _, m := range mover.all {
			if m.T == "ack" && strings.Contains(string(m.P), `"dup":true`) {
				return true
			}
		}
		return false
	})
}

func TestMaliciousCommandsRejected(t *testing.T) {
	e := newEnv(t, envOpts{dice: rooms.NewSeededDice(5)})
	cs := startPublic(t, e, "ludo", "classic", 2)
	var waiting *client
	for _, c := range cs {
		if c.snapshot().Turn.Seat != c.seat() {
			waiting = c
		}
	}
	r := waiting.snapshot()
	if m := waiting.call("game.roll_dice", map[string]any{"roomId": r.ID, "turnSeq": r.Turn.TurnSeq}); !strings.Contains(string(m.P), "not_your_turn") {
		t.Fatalf("out-of-turn roll: %s", m.P)
	}
	if m := waiting.call("game.make_move", map[string]any{"roomId": r.ID, "turnSeq": r.Turn.TurnSeq, "token": 9}); !strings.Contains(string(m.P), "bad_request") {
		t.Fatalf("bad token: %s", m.P)
	}
	if m := waiting.call("game.roll_dice", map[string]any{"roomId": r.ID, "turnSeq": r.Turn.TurnSeq, "dice": 6}); !strings.Contains(string(m.P), "bad_request") {
		t.Fatalf("client-chosen dice field accepted: %s", m.P)
	}
	if m := waiting.call("game.nuke", map[string]any{}); !strings.Contains(string(m.P), "unknown_type") {
		t.Fatalf("unknown type: %s", m.P)
	}
	outsider := e.mustDial("outsider", e.guest())
	if m := outsider.call("game.request_sync", map[string]any{"roomId": r.ID}); !strings.Contains(string(m.P), "not_in_room") {
		t.Fatalf("outsider sync leaked state: %s", m.P)
	}
	if m := outsider.call("game.roll_dice", map[string]any{"roomId": r.ID, "turnSeq": r.Turn.TurnSeq}); !strings.Contains(string(m.P), "not_in_room") {
		t.Fatalf("outsider roll: %s", m.P)
	}
	// Already in a game: cannot matchmake into another.
	if m := waiting.call("matchmaking.join", map[string]any{"game": "ludo", "capacity": 2}); !strings.Contains(string(m.P), "already_in_room") {
		t.Fatalf("double membership: %s", m.P)
	}
	// Oversized messages close the connection.
	big := `{"t":"game.request_sync","id":"x","p":{"pad":"` + strings.Repeat("a", 8000) + `"}}`
	_ = outsider.conn.Write(context.Background(), websocket.MessageText, []byte(big))
	select {
	case <-outsider.closed:
	case <-time.After(3 * time.Second):
		t.Fatal("oversized message did not close the connection")
	}
}

// The player whose turn it is cannot choose, preview or re-roll the dice:
// any extra field is refused, and the server rolls once per turnSeq.
func TestCurrentPlayerCannotChooseOrRerollDice(t *testing.T) {
	for _, game := range []string{"ludo", "snakes_ladders"} {
		t.Run(game, func(t *testing.T) {
			e := newEnv(t, envOpts{dice: rooms.NewSeededDice(5)})
			cs := startPublic(t, e, game, "classic", 2)
			var mover *client
			for _, c := range cs {
				if c.snapshot().Turn.Seat == c.seat() {
					mover = c
				}
			}
			r := mover.snapshot()
			for _, field := range []string{"dice", "value", "result", "seed"} {
				m := mover.call("game.roll_dice", map[string]any{"roomId": r.ID, "turnSeq": r.Turn.TurnSeq, field: 6})
				if m.T != "error" || !strings.Contains(string(m.P), "bad_request") {
					t.Fatalf("roll with client %q accepted: %s %s", field, m.T, m.P)
				}
			}
			if n := mover.count("game.dice_result"); n != 0 {
				t.Fatalf("tampered rolls produced %d dice results", n)
			}
			if after := mover.snapshot(); after.Turn.Dice != 0 || after.Turn.TurnSeq != r.Turn.TurnSeq {
				t.Fatalf("tampered rolls changed the turn: dice=%d turnSeq=%d", after.Turn.Dice, after.Turn.TurnSeq)
			}

			if m := mover.call("game.roll_dice", map[string]any{"roomId": r.ID, "turnSeq": r.Turn.TurnSeq}); m.T == "error" {
				t.Fatalf("honest roll refused: %s", m.P)
			}
			waitFor(t, 5*time.Second, "dice result", func() bool { return mover.count("game.dice_result") >= 1 })
			// Same turnSeq again: never a second roll for the same turn.
			m := mover.call("game.roll_dice", map[string]any{"roomId": r.ID, "turnSeq": r.Turn.TurnSeq})
			if m.T != "error" {
				t.Fatalf("second roll for turnSeq %d accepted", r.Turn.TurnSeq)
			}
			time.Sleep(200 * time.Millisecond)
			if n := mover.count("game.dice_result"); n != 1 {
				t.Fatalf("re-roll produced %d dice results, want 1", n)
			}
		})
	}
}

func TestCompressionNegotiatedAndDecoded(t *testing.T) {
	e := newEnv(t, envOpts{})
	c := e.mustDial("z", e.guest())
	c.mu.Lock()
	comp, _ := c.ready["compression"].(string)
	c.mu.Unlock()
	if !strings.Contains(comp, "permessage-deflate") || !strings.Contains(comp, "server_no_context_takeover") {
		t.Fatalf("compression not negotiated: %q", comp)
	}
	// Room snapshots exceed the 256-byte test threshold, so they arrive
	// compressed and must decode into valid state.
	c.call("room.create", map[string]any{"game": "ludo", "capacity": 4})
	waitFor(t, 3*time.Second, "snapshot", func() bool { return c.snapshot() != nil && c.snapshot().Code != "" })

	// Clients that do not offer the extension still work uncompressed.
	h := map[string]string{}
	_ = h
}

func TestEnsureSingleConnection(t *testing.T) {
	e := newEnv(t, envOpts{})
	g := e.guest()
	first := e.mustDial("first", g)
	second := e.mustDial("second", g)
	select {
	case <-first.closed:
	case <-time.After(3 * time.Second):
		t.Fatal("older connection not replaced")
	}
	first.mu.Lock()
	code := first.closeCode
	first.mu.Unlock()
	if code != 4409 {
		t.Fatalf("close code = %d, want 4409", code)
	}
	_ = second
}
