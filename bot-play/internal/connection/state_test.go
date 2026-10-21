package connection

import (
	"encoding/json"
	"testing"
)

func TestHashVectors(t *testing.T) {
	vectors := map[string]uint32{
		"L|7|1|-1,-1,5,56;0,-1,-1,-1":   2902942580,
		"S|12|0|34,0,99":                1234224186,
		"L|0|0|-1,-1,-1,-1;-1,-1,-1,-1": 638091788,
	}
	for s, want := range vectors {
		if got := FNV1a(s); got != want {
			t.Errorf("FNV1a(%q) = %d, want %d", s, got, want)
		}
	}
	r := &Room{Game: "ludo", Turn: Turn{TurnSeq: 7, Seat: 1}, Board: Board{Tokens: [][]int{{-1, -1, 5, 56}, {0, -1, -1, -1}}}}
	if h, ok := StateHash(r); !ok || h != 2902942580 {
		t.Fatalf("ludo room hash %d", h)
	}
	r = &Room{Game: "snakes_ladders", Turn: Turn{TurnSeq: 12, Seat: 0}, Board: Board{Positions: []int{34, 0, 99}}}
	if h, ok := StateHash(r); !ok || h != 1234224186 {
		t.Fatalf("snakes room hash %d", h)
	}
}

// Seats carry "picture" (an object or null); bot-play parses it and the
// state hash ignores it.
func TestSnapshotWithSeatPictures(t *testing.T) {
	raw := `{"id":"r1","v":3,"game":"ludo","variant":"classic","mode":"public","status":"playing","capacity":2,
		"players":[
		 {"seat":0,"uid":"u_a","name":"A","avatar":1,"level":3,"title":"title_rookie","cosmetics":{},
		  "picture":{"id":"pp_wolf","format":"image","path":"profile_pictures/image/wolf.png"},
		  "color":"red","connected":true,"forfeited":false,"strikes":0},
		 {"seat":1,"uid":"b_1","name":"B","avatar":2,"level":1,"title":"title_rookie","cosmetics":{},
		  "picture":null,"color":"yellow","connected":true,"forfeited":false,"strikes":0}],
		"turn":{"seat":1,"phase":"awaiting_roll","turnSeq":7,"deadline":1,"dice":0,"legal":[],"sixStreak":0},
		"board":{"tokens":[[-1,-1,5,56],[0,-1,-1,-1]]},"h":2902942580}`
	var r Room
	if err := json.Unmarshal([]byte(raw), &r); err != nil {
		t.Fatal(err)
	}
	if p := r.Players[0].Picture; p == nil || p.ID != "pp_wolf" || p.Format != "image" || p.Path != "profile_pictures/image/wolf.png" {
		t.Fatalf("seat 0 picture %+v", p)
	}
	if r.Players[1].Picture != nil {
		t.Fatalf("seat 1 picture %+v", r.Players[1].Picture)
	}
	if match, ok := VerifySnapshotHash(&r); !ok || !match {
		t.Fatalf("hash with pictures: match=%v ok=%v", match, ok)
	}
}

func h32(r *Room) *uint32 { h, _ := StateHash(r); return &h }

func baseRoom() *Room {
	r := &Room{ID: "r1", V: 10, Game: "ludo", Status: StatusPlaying, Capacity: 2,
		Players: []Player{{Seat: 0, UID: "a", Color: "red"}, {Seat: 1, UID: "b", Color: "yellow"}},
		Turn:    Turn{Seat: 0, Phase: PhaseAwaitingRoll, TurnSeq: 3, Legal: []int{}},
		Board:   Board{Tokens: [][]int{{-1, -1, -1, -1}, {-1, -1, -1, -1}}}}
	r.H = h32(r)
	return r
}

func delta(t *testing.T, v any) json.RawMessage {
	b, err := json.Marshal(v)
	if err != nil {
		t.Fatal(err)
	}
	return b
}

func TestReconciliationRules(t *testing.T) {
	var s RoomState
	if out, _ := s.ApplyDelta(TTurnChanged, delta(t, map[string]any{"roomId": "r1", "v": 1})); out != NoState {
		t.Fatalf("delta before snapshot: %v", out)
	}
	if s.ApplySnapshot(baseRoom()) != Replaced || s.V() != 10 {
		t.Fatal("snapshot not applied")
	}
	// Expected state after a roll of 6 with 2 legal moves.
	exp := baseRoom()
	exp.Turn.TurnSeq, exp.Turn.Phase, exp.Turn.Dice = 4, PhaseAwaitingMove, 6
	dice := map[string]any{"roomId": "r1", "v": 11, "h": *h32(exp), "seat": 0, "value": 6, "turnSeq": 4,
		"phase": PhaseAwaitingMove, "deadline": 1, "legal": []int{0}, "sixStreak": 1, "strikes": 0}
	if out, err := s.ApplyDelta(TDiceResult, delta(t, dice)); out != Applied || err != nil {
		t.Fatalf("v+1 must apply: %v %v", out, err)
	}
	if s.Room().Turn.Dice != 6 || s.Room().Turn.Phase != PhaseAwaitingMove || s.V() != 11 {
		t.Fatalf("dice not applied: %+v", s.Room().Turn)
	}
	// Duplicate and old events are ignored.
	if out, _ := s.ApplyDelta(TDiceResult, delta(t, dice)); out != Duplicate {
		t.Fatalf("duplicate: %v", out)
	}
	// Other rooms are ignored.
	if out, _ := s.ApplyDelta(TTurnChanged, delta(t, map[string]any{"roomId": "r2", "v": 12})); out != OtherRoom {
		t.Fatalf("other room: %v", out)
	}
	// Gap: v jumps by 2.
	if out, _ := s.ApplyDelta(TTurnChanged, delta(t, map[string]any{"roomId": "r1", "v": 13, "seat": 1, "turnSeq": 5})); out != Gap {
		t.Fatalf("gap: %v", out)
	}
	if s.V() != 11 {
		t.Fatal("gap must not change state")
	}
	// Move with capture: hash after the move.
	s.Room().Board.Tokens[1][2] = 7
	exp2 := *s.Room()
	exp2.Board = Board{Tokens: [][]int{{0, -1, -1, -1}, {-1, -1, -1, -1}}}
	move := map[string]any{"roomId": "r1", "v": 12, "h": *h32(&exp2), "seat": 0, "token": 0, "from": -1, "to": 0,
		"captures": []map[string]int{{"seat": 1, "token": 2}}}
	if out, _ := s.ApplyDelta(TMoveApplied, delta(t, move)); out != Applied {
		t.Fatalf("move: %v", out)
	}
	if s.Room().Board.Tokens[1][2] != -1 || s.Room().Board.Tokens[0][0] != 0 || len(s.Room().Turn.Legal) != 0 {
		t.Fatalf("move/capture not applied: %+v", s.Room().Board)
	}
	// Hash mismatch is detected (state still applied).
	tc := map[string]any{"roomId": "r1", "v": 13, "h": 12345, "seat": 1, "turnSeq": 5, "phase": PhaseAwaitingRoll}
	if out, _ := s.ApplyDelta(TTurnChanged, delta(t, tc)); out != HashMismatch {
		t.Fatalf("hash mismatch: %v", out)
	}
	if s.Room().Turn.Seat != 1 || s.Room().Turn.Dice != 0 {
		t.Fatal("turn_changed not applied")
	}
	// Older snapshot is ignored; newer replaces.
	old := baseRoom()
	old.V = 5
	if s.ApplySnapshot(old) != Duplicate {
		t.Fatal("older snapshot must be ignored")
	}
	nr := baseRoom()
	nr.V = 20
	if s.ApplySnapshot(nr) != Replaced || s.V() != 20 {
		t.Fatal("newer snapshot must replace")
	}
	// Forfeit resets the seat's tokens.
	s.Room().Board.Tokens[1] = []int{5, 6, 7, 8}
	if out, _ := s.ApplyDelta(TPlayerForfeited, delta(t, map[string]any{"roomId": "r1", "v": 21, "seat": 1, "reason": "left"})); out != Applied {
		t.Fatalf("forfeit: %v", out)
	}
	if s.Room().Board.Tokens[1][3] != -1 || !s.Room().Player(1).Forfeited {
		t.Fatal("forfeit not applied")
	}
	if out, _ := s.ApplyDelta(TGameFinished, delta(t, map[string]any{"roomId": "r1", "v": 22, "result": map[string]any{"winnerSeat": 0}})); out != Applied ||
		s.Room().Status != StatusFinished || s.Room().Result.WinnerSeat != 0 {
		t.Fatalf("finished: %v", out)
	}
	if match, ok := VerifySnapshotHash(baseRoom()); !ok || !match {
		t.Fatal("snapshot hash verify")
	}
}

func TestSnakesDeltas(t *testing.T) {
	var s RoomState
	r := &Room{ID: "s", V: 1, Game: "snakes_ladders", Status: StatusPlaying, Players: []Player{{Seat: 0}, {Seat: 1}},
		Turn: Turn{Seat: 0, Phase: PhaseAwaitingRoll, TurnSeq: 1}, Board: Board{Positions: []int{0, 0}}}
	s.ApplySnapshot(r)
	exp := &Room{Game: "snakes_ladders", Turn: Turn{Seat: 0, TurnSeq: 1}, Board: Board{Positions: []int{38, 0}}}
	mv := map[string]any{"roomId": "s", "v": 2, "h": *h32(exp), "seat": 0, "token": 0, "from": 0, "to": 38, "landing": 1,
		"transition": map[string]any{"kind": "ladder", "from": 1, "to": 38}}
	if out, _ := s.ApplyDelta(TMoveApplied, delta(t, mv)); out != Applied || s.Room().Board.Positions[0] != 38 {
		t.Fatalf("snakes move: %v %+v", out, s.Room().Board)
	}
}
