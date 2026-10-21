package connection

import (
	"encoding/json"
	"testing"
)

// player.forfeited carries the reason and the seat's consecutive missed
// turns; the reducer keeps both (not part of the state hash).
func TestPlayerForfeitedReasonAndStrikes(t *testing.T) {
	cases := []struct {
		name        string
		payload     map[string]any
		wantWhy     string
		wantStrikes int
	}{
		{"timeouts", map[string]any{"roomId": "r1", "v": 11, "seat": 1, "reason": "timeouts", "strikes": 5}, "timeouts", 5},
		{"left with strikes", map[string]any{"roomId": "r1", "v": 11, "seat": 1, "reason": "left", "strikes": 2}, "left", 2},
		// An older server sends no strikes.
		{"no strikes field", map[string]any{"roomId": "r1", "v": 11, "seat": 1, "reason": "left"}, "left", 0},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			var s RoomState
			r := baseRoom()
			r.Players[1].Strikes = 4
			s.ApplySnapshot(r)
			exp := baseRoom()
			exp.Board.Tokens[1] = []int{-1, -1, -1, -1}
			c.payload["h"] = *h32(exp)
			if out, err := s.ApplyDelta(TPlayerForfeited, delta(t, c.payload)); out != Applied || err != nil {
				t.Fatalf("forfeit: %v %v", out, err)
			}
			p := s.Room().Player(1)
			if !p.Forfeited || p.ForfeitWhy != c.wantWhy || p.Strikes != c.wantStrikes {
				t.Fatalf("seat 1 = %+v", p)
			}
			if other := s.Room().Player(0); other.Forfeited || other.ForfeitWhy != "" {
				t.Fatalf("seat 0 = %+v", other)
			}
		})
	}
}

func TestSnapshotForfeitWhy(t *testing.T) {
	raw := `{"id":"r1","v":3,"game":"ludo","status":"playing","capacity":2,
		"players":[{"seat":0,"uid":"a","color":"red","connected":true,"bot":true,"forfeited":false,"strikes":0},
		           {"seat":1,"uid":"b","color":"yellow","connected":true,"bot":false,"forfeited":true,"forfeitWhy":"timeouts","strikes":5}],
		"turn":{"seat":0,"phase":"awaiting_roll","turnSeq":9,"deadline":1,"dice":0,"legal":[],"sixStreak":0},
		"board":{"tokens":[[-1,-1,-1,-1],[-1,-1,-1,-1]]}}`
	var r Room
	if err := json.Unmarshal([]byte(raw), &r); err != nil {
		t.Fatal(err)
	}
	if p := r.Player(1); !p.Forfeited || p.ForfeitWhy != "timeouts" || p.Strikes != 5 {
		t.Fatalf("seat 1 = %+v", p)
	}
	if p := r.Player(0); p.ForfeitWhy != "" {
		t.Fatalf("seat 0 = %+v", p)
	}
	// forfeitWhy is not part of the state hash.
	h, ok := StateHash(&r)
	r.Players[1].ForfeitWhy = ""
	if h2, _ := StateHash(&r); !ok || h != h2 {
		t.Fatal("forfeitWhy changed the state hash")
	}
}
