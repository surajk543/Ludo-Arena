package snakesladders

import (
	"encoding/json"
	"errors"
	"maps"
	"reflect"
	"slices"
	"testing"

	"ludoarena/internal/game"
)

func mustNew(t *testing.T, n int) *State {
	t.Helper()
	s, err := New(n)
	if err != nil {
		t.Fatalf("New(%d): %v", n, err)
	}
	return s
}

func mustRoll(t *testing.T, s *State, player, value int) RollResult {
	t.Helper()
	res, err := s.Roll(player, value)
	if err != nil {
		t.Fatalf("Roll(%d, %d): %v", player, value, err)
	}
	return res
}

func TestBoardMaps(t *testing.T) {
	wantSnakes := map[int]int{16: 6, 47: 26, 49: 11, 56: 53, 62: 19, 64: 60, 87: 24, 93: 73, 95: 75, 98: 78}
	wantLadders := map[int]int{1: 38, 4: 14, 9: 31, 21: 42, 28: 84, 36: 44, 51: 67, 71: 91, 80: 100}
	if !maps.Equal(Snakes, wantSnakes) {
		t.Fatalf("Snakes = %v", Snakes)
	}
	if !maps.Equal(Ladders, wantLadders) {
		t.Fatalf("Ladders = %v", Ladders)
	}
	for head, tail := range Snakes {
		if !(tail >= 1 && tail < head && head < FinalSquare) {
			t.Errorf("snake %d→%d is not a downward move inside the board", head, tail)
		}
		if _, ok := Ladders[head]; ok {
			t.Errorf("square %d is both a snake head and a ladder bottom", head)
		}
	}
	for bottom, top := range Ladders {
		if !(bottom >= 1 && top > bottom && top <= FinalSquare) {
			t.Errorf("ladder %d→%d is not an upward move inside the board", bottom, top)
		}
	}
	// Only one transition per move: no destination starts another transition.
	for _, m := range []map[int]int{Snakes, Ladders} {
		for _, dest := range m {
			if _, kind := Transition(dest); kind != "" {
				t.Errorf("destination %d starts another %s", dest, kind)
			}
		}
	}
}

func TestTransition(t *testing.T) {
	for sq := 0; sq <= FinalSquare+1; sq++ {
		to, kind := Transition(sq)
		switch {
		case Snakes[sq] != 0:
			if kind != KindSnake || to != Snakes[sq] {
				t.Errorf("Transition(%d) = %d,%q", sq, to, kind)
			}
		case Ladders[sq] != 0:
			if kind != KindLadder || to != Ladders[sq] {
				t.Errorf("Transition(%d) = %d,%q", sq, to, kind)
			}
		default:
			if kind != "" || to != sq {
				t.Errorf("Transition(%d) = %d,%q, want no transition", sq, to, kind)
			}
		}
	}
}

func TestNew(t *testing.T) {
	for n := 2; n <= 4; n++ {
		s := mustNew(t, n)
		if !slices.Equal(s.Positions, make([]int, n)) || !slices.Equal(s.Forfeited, make([]bool, n)) ||
			s.Turn != 0 || s.Phase != PhaseAwaitingRoll || s.Dice != 0 || s.Winner != -1 || s.TurnSeq != 0 ||
			len(s.Placements) != 0 || s.ActiveCount() != n || s.TurnPlayer() != 0 {
			t.Errorf("New(%d) = %+v", n, s)
		}
	}
	for _, n := range []int{-1, 0, 1, 5} {
		if _, err := New(n); !errors.Is(err, ErrBadPlayerCount) {
			t.Errorf("New(%d) err = %v", n, err)
		}
	}
}

func TestRollMoves(t *testing.T) {
	cases := []struct {
		name        string
		from, dice  int
		landing, to int
		kind        string
		moved, won  bool
	}{
		{"enter onto plain square", 0, 2, 2, 2, "", true, false},
		{"enter onto ladder 1", 0, 1, 1, 38, KindLadder, true, false},
		{"enter onto ladder 4", 0, 4, 4, 14, KindLadder, true, false},
		{"plain move", 23, 3, 26, 26, "", true, false},
		{"snake 16", 14, 2, 16, 6, KindSnake, true, false},
		{"snake 98", 92, 6, 98, 78, KindSnake, true, false},
		{"ladder 28", 25, 3, 28, 84, KindLadder, true, false},
		{"six gives no extra turn", 30, 6, 36, 44, KindLadder, true, false},
		{"exact 100", 94, 6, 100, 100, "", true, true},
		{"exact 100 with a 1", 99, 1, 100, 100, "", true, true},
		{"ladder 80 to 100 wins", 76, 4, 80, 100, KindLadder, true, true},
		{"overshoot by one", 97, 4, 97, 97, "", false, false},
		{"overshoot at 99", 99, 2, 99, 99, "", false, false},
		{"overshoot with a six", 96, 6, 96, 96, "", false, false},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			s := mustNew(t, 3)
			s.Positions[0] = tc.from
			res := mustRoll(t, s, 0, tc.dice)
			if res.Player != 0 || res.Value != tc.dice || res.From != tc.from || res.Landing != tc.landing || res.To != tc.to ||
				res.Moved != tc.moved || res.Won != tc.won || s.Positions[0] != tc.to {
				t.Fatalf("res = %+v, position %d", res, s.Positions[0])
			}
			if tc.kind == "" {
				if res.Transition != nil {
					t.Fatalf("unexpected transition %+v", res.Transition)
				}
			} else if res.Transition == nil || *res.Transition != (Jump{Kind: tc.kind, From: tc.landing, To: tc.to}) {
				t.Fatalf("transition = %+v", res.Transition)
			}
			if s.TurnSeq != 1 || res.TurnSeq != 1 {
				t.Fatalf("TurnSeq = %d, want 1", s.TurnSeq)
			}
			if tc.won {
				if s.Phase != PhaseFinished || s.Winner != 0 || s.Turn != 0 || res.TurnPassed || s.Dice != tc.dice ||
					res.Phase != PhaseFinished || !slices.Equal(s.Placements, []int{0, 1, 2}) {
					t.Fatalf("win state %+v", s)
				}
				return
			}
			if !res.TurnPassed || s.Turn != 1 || res.Turn != 1 || s.Phase != PhaseAwaitingRoll || s.Dice != 0 || s.Winner != -1 {
				t.Fatalf("turn did not pass: %+v", s)
			}
		})
	}
}

func TestTurnOrder(t *testing.T) {
	s := mustNew(t, 4)
	for i, seat := range []int{0, 1, 2, 3, 0, 1} {
		res := mustRoll(t, s, seat, 6)
		if res.Turn != (seat+1)%4 || s.TurnSeq != i+1 {
			t.Fatalf("roll %d by %d: turn %d seq %d", i, seat, res.Turn, s.TurnSeq)
		}
	}
	s.Forfeit(3)
	for _, st := range []struct{ roller, next int }{{2, 0}, {0, 1}, {1, 2}} {
		if res := mustRoll(t, s, st.roller, 2); res.Turn != st.next {
			t.Fatalf("after %d: turn %d, want %d", st.roller, res.Turn, st.next)
		}
	}
}

func TestForfeit(t *testing.T) {
	t.Run("turn player", func(t *testing.T) {
		s := mustNew(t, 3)
		s.Positions = []int{40, 12, 7}
		if s.Forfeit(0) {
			t.Fatal("game must continue")
		}
		if s.Turn != 1 || s.TurnSeq != 1 || !s.Forfeited[0] || s.Positions[0] != 40 || s.ActiveCount() != 2 {
			t.Fatalf("%+v", s)
		}
		if _, err := s.Roll(0, 3); !errors.Is(err, ErrNotYourTurn) {
			t.Fatalf("forfeited roll err = %v", err)
		}
	})
	t.Run("player not on turn", func(t *testing.T) {
		s := mustNew(t, 3)
		if s.Forfeit(2) || s.Turn != 0 || s.TurnSeq != 0 {
			t.Fatalf("%+v", s)
		}
	})
	t.Run("last remaining player wins", func(t *testing.T) {
		for _, tc := range []struct{ forfeit, winner int }{{1, 0}, {0, 1}} {
			s := mustNew(t, 2)
			if !s.Forfeit(tc.forfeit) {
				t.Fatal("game must finish")
			}
			if s.Phase != PhaseFinished || s.Winner != tc.winner || s.Turn != tc.winner || s.TurnSeq != 1 ||
				!slices.Equal(s.Placements, []int{tc.winner, tc.forfeit}) {
				t.Fatalf("%+v", s)
			}
		}
	})
	t.Run("placements", func(t *testing.T) {
		s := mustNew(t, 4)
		s.Positions = []int{10, 50, 70, 90}
		s.Forfeit(3)
		s.Forfeit(1)
		if !s.Forfeit(0) || s.Winner != 2 || !slices.Equal(s.Placements, []int{2, 0, 1, 3}) {
			t.Fatalf("%+v", s)
		}
	})
	t.Run("no-ops", func(t *testing.T) {
		s := mustNew(t, 3)
		s.Forfeit(1)
		before := s.Clone()
		for _, seat := range []int{1, -1, 3} {
			if s.Forfeit(seat) {
				t.Fatalf("Forfeit(%d) reported finish", seat)
			}
		}
		if !reflect.DeepEqual(s, before) {
			t.Fatal("no-op forfeit changed the state")
		}
		s.Forfeit(2)
		fin := s.Clone()
		if s.Forfeit(0) || !reflect.DeepEqual(s, fin) {
			t.Fatal("forfeit after finish must be a no-op")
		}
	})
}

func TestPlacementsOnWin(t *testing.T) {
	s := mustNew(t, 4)
	s.Positions = []int{97, 50, 50, 99}
	s.Forfeit(3)
	mustRoll(t, s, 0, 3)
	if s.Winner != 0 || !slices.Equal(s.Placements, []int{0, 1, 2, 3}) {
		t.Fatalf("placements = %v", s.Placements)
	}
	s = mustNew(t, 3)
	s.Positions = []int{94, 20, 60}
	mustRoll(t, s, 0, 6)
	if !slices.Equal(s.Placements, []int{0, 2, 1}) {
		t.Fatalf("placements = %v", s.Placements)
	}
}

func TestInvalidInputs(t *testing.T) {
	finished := func(t *testing.T) *State {
		s := mustNew(t, 2)
		s.Positions[0] = 99
		mustRoll(t, s, 0, 1)
		return s
	}
	fresh := func(t *testing.T) *State { return mustNew(t, 2) }
	corrupt := func(t *testing.T) *State { s := mustNew(t, 2); s.Phase = "bogus"; return s }
	cases := []struct {
		name          string
		state         func(*testing.T) *State
		player, value int
		want          error
	}{
		{"wrong player", fresh, 1, 3, ErrNotYourTurn},
		{"negative seat", fresh, -1, 3, ErrNotYourTurn},
		{"seat out of range", fresh, 2, 3, ErrNotYourTurn},
		{"dice 0", fresh, 0, 0, ErrBadDice},
		{"dice 7", fresh, 0, 7, ErrBadDice},
		{"unknown phase", corrupt, 0, 3, ErrInvalidPhase},
		{"after game over", finished, 0, 3, ErrGameOver},
		{"other seat after game over", finished, 1, 3, ErrGameOver},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			s := tc.state(t)
			before := s.Clone()
			if _, err := s.Roll(tc.player, tc.value); !errors.Is(err, tc.want) {
				t.Fatalf("err = %v, want %v", err, tc.want)
			}
			if !reflect.DeepEqual(s, before) {
				t.Fatal("failed roll changed the state")
			}
		})
	}
}

func TestHash(t *testing.T) {
	vectors := []struct {
		s string
		h uint32
	}{
		{"L|7|1|-1,-1,5,56;0,-1,-1,-1", 2902942580},
		{"S|12|0|34,0,99", 1234224186},
		{"L|0|0|-1,-1,-1,-1;-1,-1,-1,-1", 638091788},
	}
	for _, v := range vectors {
		if got := game.FNV1a32(v.s); got != v.h {
			t.Errorf("FNV1a32(%q) = %d, want %d", v.s, got, v.h)
		}
	}
	s := &State{Positions: []int{34, 0, 99}, Forfeited: make([]bool, 3), TurnSeq: 12, Turn: 0, Phase: PhaseAwaitingRoll, Winner: -1}
	if got := s.CanonicalString(); got != "S|12|0|34,0,99" {
		t.Fatalf("CanonicalString = %q", got)
	}
	if s.Hash() != 1234224186 || s.HashAt(12, 0) != 1234224186 {
		t.Fatalf("Hash = %d", s.Hash())
	}
	if got := mustNew(t, 2).CanonicalString(); got != "S|0|0|0,0" {
		t.Fatalf("new CanonicalString = %q", got)
	}
	if got := s.CanonicalStringAt(13, 2); got != "S|13|2|34,0,99" {
		t.Fatalf("CanonicalStringAt = %q", got)
	}
}

func TestCloneAndJSON(t *testing.T) {
	s := mustNew(t, 4)
	mustRoll(t, s, 0, 4)
	s.Forfeit(2)
	c := s.Clone()
	if !reflect.DeepEqual(s, c) {
		t.Fatal("clone differs")
	}
	c.Positions[0] = 77
	c.Forfeited[1] = true
	c.ForfeitOrder[0] = 3
	c.Placements = append(c.Placements, 1)
	if s.Positions[0] != 14 || s.Forfeited[1] || s.ForfeitOrder[0] != 2 || len(s.Placements) != 0 {
		t.Fatalf("mutating the clone changed the original: %+v", s)
	}

	fin := mustNew(t, 2)
	fin.Positions[0] = 76
	mustRoll(t, fin, 0, 4)
	for _, st := range []*State{s, fin, mustNew(t, 3)} {
		data, err := json.Marshal(st)
		if err != nil {
			t.Fatal(err)
		}
		var back State
		if err := json.Unmarshal(data, &back); err != nil {
			t.Fatal(err)
		}
		if !reflect.DeepEqual(st, &back) || back.Hash() != st.Hash() {
			t.Fatalf("round trip mismatch: %s", data)
		}
		var keys map[string]json.RawMessage
		if err := json.Unmarshal(data, &keys); err != nil {
			t.Fatal(err)
		}
		for _, k := range []string{"positions", "forfeited", "turn", "phase", "dice", "winner", "turnSeq", "placements", "forfeitOrder"} {
			if _, ok := keys[k]; !ok {
				t.Errorf("missing JSON key %q in %s", k, data)
			}
		}
	}
	res, _ := json.Marshal(RollResult{Transition: &Jump{Kind: KindLadder, From: 80, To: 100}})
	var m map[string]any
	_ = json.Unmarshal(res, &m)
	if tr, ok := m["transition"].(map[string]any); !ok || tr["kind"] != "ladder" {
		t.Fatalf("RollResult JSON = %s", res)
	}
}
