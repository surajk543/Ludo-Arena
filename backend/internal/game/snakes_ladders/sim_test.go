package snakesladders

import (
	"fmt"
	"math/rand/v2"
	"slices"
	"testing"
)

// maxSimActions bounds one simulated game (Roll and Forfeit calls).
const maxSimActions = 20000

type simOutcome struct {
	winner  int
	actions int
	final   string
}

// TestSimulation plays thousands of complete games with a seeded dice source,
// checking the engine invariants after every action. It shows that every game
// terminates with exactly one winner and that all seats win at comparable
// rates (the engine takes no part in dice rolls).
func TestSimulation(t *testing.T) {
	games := 2000
	if testing.Short() {
		games = 200
	}
	for n := 2; n <= 4; n++ {
		t.Run(fmt.Sprintf("%dp", n), func(t *testing.T) {
			t.Parallel()
			rng := rand.New(rand.NewPCG(uint64(n)*104729, 42))
			wins := make([]int, n)
			longest := 0
			for g := range games {
				out := playSnakes(t, rng, n, g%10 == 9)
				if t.Failed() {
					return
				}
				wins[out.winner]++
				longest = max(longest, out.actions)
			}
			t.Logf("wins per seat %v, longest game %d actions", wins, longest)
			for seat, w := range wins {
				if w < games/(2*n) {
					t.Errorf("seat %d won %d of %d games; expected roughly %d", seat, w, games, games/n)
				}
			}
		})
	}
}

func TestSimulationDeterministic(t *testing.T) {
	for seed := range uint64(5) {
		a := playSnakes(t, rand.New(rand.NewPCG(seed, 9)), 4, true)
		b := playSnakes(t, rand.New(rand.NewPCG(seed, 9)), 4, true)
		if a != b {
			t.Fatalf("seed %d: replay diverged: %+v vs %+v", seed, a, b)
		}
	}
}

func playSnakes(t *testing.T, rng *rand.Rand, n int, forfeits bool) simOutcome {
	t.Helper()
	s, err := New(n)
	if err != nil {
		t.Fatal(err)
	}
	for actions := 0; ; actions++ {
		if s.Phase == PhaseFinished {
			checkFinished(t, s, n)
			return simOutcome{winner: s.Winner, actions: actions, final: s.CanonicalString()}
		}
		if actions >= maxSimActions {
			t.Fatalf("game did not finish within %d actions: %s", maxSimActions, s.CanonicalString())
		}
		seat := s.Turn
		before := s.Clone()
		if forfeits && rng.IntN(150) == 0 {
			victim := rng.IntN(n)
			finished := s.Forfeit(victim)
			switch {
			case before.Forfeited[victim]:
				if finished || s.TurnSeq != before.TurnSeq {
					t.Fatal("repeated forfeit changed the game")
				}
			case finished:
				if before.ActiveCount() != 2 || s.TurnSeq != before.TurnSeq+1 {
					t.Fatalf("forfeit finish %+v", s)
				}
			case victim == seat:
				if s.Turn == seat || s.TurnSeq != before.TurnSeq+1 {
					t.Fatalf("forfeit on turn did not pass the turn %+v", s)
				}
			default:
				if s.Turn != seat || s.TurnSeq != before.TurnSeq {
					t.Fatalf("forfeit off turn changed the turn %+v", s)
				}
			}
			if !slices.Equal(s.Positions, before.Positions) {
				t.Fatal("forfeit moved tokens")
			}
		} else {
			value := rng.IntN(6) + 1
			res, err := s.Roll(seat, value)
			if err != nil {
				t.Fatalf("Roll(%d,%d): %v", seat, value, err)
			}
			from := before.Positions[seat]
			landing := from + value
			switch {
			case landing > FinalSquare:
				if res.Moved || res.To != from || res.Landing != from || res.Transition != nil {
					t.Fatalf("overshoot %+v", res)
				}
			default:
				to, kind := Transition(landing)
				if !res.Moved || res.Landing != landing || res.To != to || (kind == "") != (res.Transition == nil) {
					t.Fatalf("move %+v, want landing %d to %d", res, landing, to)
				}
			}
			for p := range n {
				if p != seat && s.Positions[p] != before.Positions[p] {
					t.Fatal("roll moved another player's token")
				}
			}
			if s.Positions[seat] != res.To || res.Won != (res.To == FinalSquare) || res.TurnPassed == res.Won ||
				s.TurnSeq != before.TurnSeq+1 || res.TurnSeq != s.TurnSeq || res.Turn != s.Turn || res.Phase != s.Phase {
				t.Fatalf("roll bookkeeping %+v", res)
			}
			if res.TurnPassed && s.Turn == seat {
				t.Fatal("turn did not pass")
			}
		}
		checkInvariants(t, s, n)
	}
}

func checkInvariants(t *testing.T, s *State, n int) {
	t.Helper()
	if len(s.Positions) != n || len(s.Forfeited) != n {
		t.Fatal("player count changed")
	}
	at100 := 0
	for seat, p := range s.Positions {
		if p < 0 || p > FinalSquare {
			t.Fatalf("seat %d at %d", seat, p)
		}
		if _, kind := Transition(p); kind != "" {
			t.Fatalf("seat %d rests on transition square %d", seat, p)
		}
		if p == FinalSquare {
			at100++
		}
	}
	if s.Turn < 0 || s.Turn >= n || s.Forfeited[s.Turn] {
		t.Fatalf("turn %d invalid", s.Turn)
	}
	switch s.Phase {
	case PhaseAwaitingRoll:
		if at100 != 0 || s.Dice != 0 || s.Winner != -1 {
			t.Fatalf("bad awaiting_roll state %+v", s)
		}
	case PhaseFinished:
		if at100 > 1 {
			t.Fatalf("%d players at 100", at100)
		}
	default:
		t.Fatalf("phase %q", s.Phase)
	}
}

func checkFinished(t *testing.T, s *State, n int) {
	t.Helper()
	w := s.Winner
	if w < 0 || w >= n || s.Forfeited[w] || s.Turn != w {
		t.Fatalf("bad winner %d", w)
	}
	if s.Positions[w] != FinalSquare && s.ActiveCount() != 1 {
		t.Fatalf("winner %d neither at 100 nor last player standing", w)
	}
	if len(s.Placements) != n || s.Placements[0] != w {
		t.Fatalf("placements %v", s.Placements)
	}
	for i, seat := range slices.Sorted(slices.Values(s.Placements)) {
		if seat != i {
			t.Fatalf("placements %v is not a permutation", s.Placements)
		}
	}
	active := s.ActiveCount()
	for i, seat := range s.Placements {
		if s.Forfeited[seat] != (i >= active) {
			t.Fatalf("placements %v: forfeited players must come last", s.Placements)
		}
	}
}
