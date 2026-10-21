package tests

import (
	"encoding/json"
	"fmt"
	"slices"
	"testing"
	"time"

	"ludoroyale/internal/config"
	"ludoroyale/internal/rooms"
)

// driveTurns plays for the active clients (one roll / move per turn and
// phase, like playUntilFinished) until done reports true.
func driveTurns(t *testing.T, timeout time.Duration, what string, active []*client, done func() bool) {
	t.Helper()
	acted := map[*client]string{}
	deadline := time.Now().Add(timeout)
	for !done() {
		if time.Now().After(deadline) {
			t.Fatalf("timed out waiting for %s", what)
		}
		for _, c := range active {
			r := c.snapshot()
			if r == nil || r.Status != "playing" {
				continue
			}
			seat := seatIn(r, c.acct.UID)
			if seat < 0 || r.Turn.Seat != seat {
				continue
			}
			key := fmt.Sprintf("%d/%s", r.Turn.TurnSeq, r.Turn.Phase)
			if acted[c] == key {
				continue
			}
			acted[c] = key
			switch r.Turn.Phase {
			case "awaiting_roll":
				c.send("game.roll_dice", map[string]any{"roomId": r.ID, "turnSeq": r.Turn.TurnSeq})
			case "awaiting_move":
				if len(r.Turn.Legal) > 0 {
					c.send("game.make_move", map[string]any{"roomId": r.ID, "turnSeq": r.Turn.TurnSeq,
						"token": r.Turn.Legal[len(r.Turn.Legal)-1]})
				}
			}
		}
		time.Sleep(10 * time.Millisecond)
	}
}

// roomDeltas counts versioned room deltas c received for roomID.
func (c *client) roomDeltas(roomID string) int {
	c.mu.Lock()
	defer c.mu.Unlock()
	n := 0
	for _, m := range c.all {
		var hdr struct {
			RoomID string `json:"roomId"`
			V      int64  `json:"v"`
		}
		if json.Unmarshal(m.P, &hdr) == nil && hdr.RoomID == roomID && hdr.V > 0 {
			n++
		}
	}
	return n
}

// A connected player who stops playing is removed after MAX_STRIKES (5 by
// default) consecutive missed turns: player.forfeited carries reason
// "timeouts" and the strikes, snapshots carry forfeitWhy, and once the app
// leaves (as it does after telling the player) no more room events reach it
// while the game goes on for the others.
func TestAFKPlayerRemovedAfterConsecutiveMissedTurns(t *testing.T) {
	e := newEnv(t, envOpts{dice: rooms.NewSeededDice(5), turnTimeout: 300 * time.Millisecond})
	if e.app.Cfg.Game.MaxStrikes != config.DefaultMaxStrikes || config.DefaultMaxStrikes != 5 {
		t.Fatalf("MAX_STRIKES = %d (default %d), want 5", e.app.Cfg.Game.MaxStrikes, config.DefaultMaxStrikes)
	}
	cs := startPublic(t, e, "ludo", "classic", 3)
	afk := cs[1]
	active := []*client{cs[0], cs[2]}
	roomID := afk.snapshot().ID
	seat := afk.seat()

	driveTurns(t, 60*time.Second, "the AFK player to be removed", active, func() bool {
		r := afk.snapshot()
		return r != nil && r.Players[seat].Forfeited
	})

	// Live delta: reason, strikes and the reducer's forfeitWhy.
	var forfeits []map[string]any
	var autoStrikes []int
	afk.mu.Lock()
	for _, m := range afk.all {
		switch m.T {
		case "player.forfeited":
			var p map[string]any
			_ = json.Unmarshal(m.P, &p)
			forfeits = append(forfeits, p)
		case "game.dice_result":
			var p struct {
				Seat, Strikes int
				Auto          bool
			}
			_ = json.Unmarshal(m.P, &p)
			if p.Seat == seat {
				if !p.Auto {
					t.Errorf("the AFK player never rolled, got an own roll")
				}
				autoStrikes = append(autoStrikes, p.Strikes)
			}
		}
	}
	afk.mu.Unlock()
	if len(forfeits) != 1 || forfeits[0]["reason"] != "timeouts" || forfeits[0]["strikes"] != float64(5) ||
		forfeits[0]["seat"] != float64(seat) {
		t.Fatalf("player.forfeited: %v", forfeits)
	}
	// The server played the first four missed turns (one strike each).
	if !slices.Equal(autoStrikes, []int{1, 2, 3, 4}) {
		t.Fatalf("auto-roll strikes %v, want [1 2 3 4]", autoStrikes)
	}
	if p := afk.snapshot().Players[seat]; p.ForfeitWhy != "timeouts" || p.Strikes != 5 {
		t.Fatalf("reduced seat %+v", p)
	}

	// Snapshot (resync after the app was in the background).
	var st struct {
		Room *roomState `json:"room"`
	}
	if reply := afk.call("game.request_sync", map[string]any{"roomId": roomID}); reply.T != "game.state" ||
		json.Unmarshal(reply.P, &st) != nil || st.Room == nil {
		t.Fatalf("request_sync reply %s %s", reply.T, reply.P)
	}
	if p := st.Room.Players[seat]; !p.Forfeited || p.ForfeitWhy != "timeouts" || p.Strikes != 5 || st.Room.Status != "playing" {
		t.Fatalf("snapshot seat %+v (status %s)", p, st.Room.Status)
	}
	for i, p := range st.Room.Players {
		if i != seat && (p.Forfeited || p.ForfeitWhy != "") {
			t.Fatalf("seat %d: %+v", i, p)
		}
	}

	// The app leaves: no more events for that room, and no active room.
	if reply := afk.call("room.leave", map[string]any{"roomId": roomID}); reply.T != "ack" {
		t.Fatalf("room.leave reply %s %s", reply.T, reply.P)
	}
	if reply := afk.call("game.request_sync", map[string]any{}); reply.T != "game.state" || string(reply.P) != `{"room":null}` {
		t.Fatalf("active room after leaving: %s %s", reply.T, reply.P)
	}
	before := afk.roomDeltas(roomID)
	seq := cs[0].snapshot().Turn.TurnSeq
	driveTurns(t, 30*time.Second, "the game to go on", active, func() bool {
		r := cs[0].snapshot()
		return r.Status != "playing" || r.Turn.TurnSeq >= seq+6
	})
	if after := afk.roomDeltas(roomID); after != before {
		t.Fatalf("the removed player still receives room events after leaving (%d → %d)", before, after)
	}
	if reply := cs[0].call("game.request_sync", map[string]any{"roomId": roomID}); reply.T == "game.state" {
		_ = json.Unmarshal(reply.P, &st)
		if p := st.Room.Players[seat]; !p.Forfeited || p.ForfeitWhy != "left" {
			t.Fatalf("others see the removed seat as %+v", p)
		}
	}
	assertNoDivergence(t, cs)
}
