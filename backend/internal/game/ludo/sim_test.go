package ludo

import (
	"fmt"
	"math/rand/v2"
	"slices"
	"testing"
)

// maxSimActions bounds one simulated game (Roll, Move and Forfeit calls).
const maxSimActions = 20000

type simOutcome struct {
	winner    int
	actions   int
	byForfeit bool
	final     string
}

// TestSimulation plays thousands of complete games with a seeded dice source
// and random legal choices, checking the engine invariants after every action.
// It shows that every game terminates and has exactly one winner, and that
// all seats win at comparable rates (the engine takes no part in dice rolls).
func TestSimulation(t *testing.T) {
	games := 2000
	if testing.Short() {
		games = 200
	}
	for _, v := range []Variant{Classic, Quick} {
		for n := 2; n <= 4; n++ {
			t.Run(fmt.Sprintf("%s/%dp", v, n), func(t *testing.T) {
				t.Parallel()
				rng := rand.New(rand.NewPCG(uint64(n)*7919, uint64(len(v))))
				wins := make([]int, n)
				longest, forfeitWins := 0, 0
				for g := range games {
					out := playLudo(t, rng, n, v, g%10 == 9)
					if t.Failed() {
						return
					}
					wins[out.winner]++
					longest = max(longest, out.actions)
					if out.byForfeit {
						forfeitWins++
					}
				}
				t.Logf("wins per seat %v, longest game %d actions, %d games ended by forfeit", wins, longest, forfeitWins)
				for seat, w := range wins {
					if w < games/(2*n) {
						t.Errorf("seat %d won %d of %d games; expected roughly %d", seat, w, games, games/n)
					}
				}
			})
		}
	}
}

func TestSimulationDeterministic(t *testing.T) {
	for seed := range uint64(5) {
		a := playLudo(t, rand.New(rand.NewPCG(seed, 1)), 4, Classic, true)
		b := playLudo(t, rand.New(rand.NewPCG(seed, 1)), 4, Classic, true)
		if a != b {
			t.Fatalf("seed %d: replay diverged: %+v vs %+v", seed, a, b)
		}
	}
}

// playLudo plays one game to the end. With forfeits, players occasionally
// leave mid-game. Moves are random legal tokens or the auto-move choice.
func playLudo(t *testing.T, rng *rand.Rand, n int, v Variant, forfeits bool) simOutcome {
	t.Helper()
	s, err := New(n, v)
	if err != nil {
		t.Fatal(err)
	}
	for actions := 0; ; actions++ {
		if s.Phase == PhaseFinished {
			checkFinished(t, s, n)
			return simOutcome{winner: s.Winner, actions: actions, byForfeit: !s.allHome(s.Winner), final: s.CanonicalString()}
		}
		if actions >= maxSimActions {
			t.Fatalf("game did not finish within %d actions: %s", maxSimActions, s.CanonicalString())
		}
		seat := s.Turn
		before := s.Clone()

		switch {
		case forfeits && rng.IntN(400) == 0:
			victim := rng.IntN(n)
			finished := s.Forfeit(victim)
			switch {
			case before.Players[victim].Forfeited:
				if finished || s.TurnSeq != before.TurnSeq {
					t.Fatalf("repeated forfeit changed the game")
				}
			case finished:
				if s.Phase != PhaseFinished || before.ActiveCount() != 2 || s.TurnSeq != before.TurnSeq+1 {
					t.Fatalf("forfeit finish: %+v", s)
				}
			case victim == seat:
				if s.Turn == seat || s.TurnSeq != before.TurnSeq+1 || s.Phase != PhaseAwaitingRoll {
					t.Fatalf("forfeit on turn did not pass the turn: %+v", s)
				}
			default:
				if s.Turn != seat || s.Phase != before.Phase || s.TurnSeq != before.TurnSeq {
					t.Fatalf("forfeit off turn changed the turn: %+v", s)
				}
			}

		case s.Phase == PhaseAwaitingRoll:
			value := rng.IntN(6) + 1
			res, err := s.Roll(seat, value)
			if err != nil {
				t.Fatalf("Roll(%d,%d): %v", seat, value, err)
			}
			checkRoll(t, before, s, res, value)

		case s.Phase == PhaseAwaitingMove:
			var token int
			if rng.IntN(4) == 0 {
				token, _ = s.AutoMoveToken()
			} else {
				token = s.Legal[rng.IntN(len(s.Legal))]
			}
			res, err := s.Move(seat, token)
			if err != nil {
				t.Fatalf("Move(%d,%d): %v", seat, token, err)
			}
			checkMove(t, before, s, res)

		default:
			t.Fatalf("unexpected phase %q", s.Phase)
		}
		checkInvariants(t, s, n)
	}
}

func checkRoll(t *testing.T, before, s *State, res RollResult, value int) {
	t.Helper()
	seat := before.Turn
	if s.TurnSeq != before.TurnSeq+1 || res.TurnSeq != s.TurnSeq || res.Turn != s.Turn || res.Phase != s.Phase {
		t.Fatalf("roll bookkeeping: %+v state seq %d", res, s.TurnSeq)
	}
	wantStreak := 0
	if value == 6 {
		wantStreak = before.SixStreak + 1
	}
	if res.SixStreak != wantStreak || res.Voided != (wantStreak == 3) {
		t.Fatalf("six streak: before %d value %d → %+v", before.SixStreak, value, res)
	}
	for i := range s.Players {
		if !slices.Equal(s.Players[i].Tokens, before.Players[i].Tokens) {
			t.Fatalf("roll moved tokens")
		}
	}
	// Brute-force legal set: one entry per distinct movable progress value.
	want := []int{}
	if !res.Voided {
		var seen []int
		for i, p := range before.Players[seat].Tokens {
			movable := (p == Base && before.Variant.CanEnter(value)) || (p >= 0 && p < Home && p+value <= Home)
			if movable && !slices.Contains(seen, p) {
				seen = append(seen, p)
				want = append(want, i)
			}
		}
	}
	if !slices.Equal(res.Legal, want) {
		t.Fatalf("legal = %v, want %v (tokens %v, dice %d)", res.Legal, want, before.Players[seat].Tokens, value)
	}
	if len(want) == 0 {
		if !res.TurnPassed || s.Turn == seat || s.Phase != PhaseAwaitingRoll {
			t.Fatalf("roll without move must pass: %+v", res)
		}
	} else if res.TurnPassed || s.Turn != seat || s.Phase != PhaseAwaitingMove || s.Dice != value {
		t.Fatalf("roll with moves: %+v", res)
	}
}

func checkMove(t *testing.T, before, s *State, res MoveResult) {
	t.Helper()
	seat, dice := before.Turn, before.Dice
	from := before.Players[seat].Tokens[res.Token]
	wantTo := from + dice
	if from == Base {
		wantTo = 0
	}
	if res.From != from || res.To != wantTo || s.Players[seat].Tokens[res.Token] != wantTo {
		t.Fatalf("move %d→%d with dice %d, want →%d", res.From, res.To, dice, wantTo)
	}
	abs := TrackIndex(s.Players[seat].Color, wantTo)
	captured := map[Capture]bool{}
	for _, c := range res.Captures {
		captured[c] = true
		o := before.Players[c.Player]
		if c.Player == seat || o.Forfeited || abs < 0 || IsSafe(abs) || TrackIndex(o.Color, o.Tokens[c.Token]) != abs {
			t.Fatalf("invalid capture %+v at %d", c, abs)
		}
		if s.Players[c.Player].Tokens[c.Token] != Base {
			t.Fatalf("captured token not in base")
		}
	}
	for p := range s.Players {
		for tok, prog := range s.Players[p].Tokens {
			if (p == seat && tok == res.Token) || captured[Capture{p, tok}] {
				continue
			}
			if prog != before.Players[p].Tokens[tok] {
				t.Fatalf("uninvolved token %d/%d changed", p, tok)
			}
			if p != seat && abs >= 0 && !IsSafe(abs) && TrackIndex(s.Players[p].Color, prog) == abs {
				t.Fatalf("opponent token %d/%d survived on square %d", p, tok, abs)
			}
		}
	}
	wantExtra := !res.Won && (dice == 6 || len(res.Captures) > 0 || wantTo == Home)
	if res.ExtraTurn != wantExtra || res.ReachedHome != (wantTo == Home) || res.Won != s.allHome(seat) {
		t.Fatalf("move flags %+v", res)
	}
	if s.TurnSeq != before.TurnSeq+1 || res.TurnSeq != s.TurnSeq || res.Turn != s.Turn || res.Phase != s.Phase {
		t.Fatalf("move bookkeeping %+v", res)
	}
	switch {
	case res.Won:
		if s.Phase != PhaseFinished || s.Winner != seat {
			t.Fatalf("win not recorded")
		}
	case wantExtra:
		if s.Turn != seat || s.Phase != PhaseAwaitingRoll {
			t.Fatalf("extra turn not granted")
		}
	default:
		if !res.TurnPassed || s.Turn == seat {
			t.Fatalf("turn did not pass")
		}
	}
}

func checkInvariants(t *testing.T, s *State, n int) {
	t.Helper()
	if len(s.Players) != n {
		t.Fatalf("player count changed")
	}
	squares := map[int]Color{}
	homeCount := 0
	for seat, p := range s.Players {
		if len(p.Tokens) != s.Variant.TokensPerPlayer() {
			t.Fatalf("seat %d has %d tokens", seat, len(p.Tokens))
		}
		allHome := true
		for _, prog := range p.Tokens {
			if prog < Base || prog > Home {
				t.Fatalf("seat %d token progress %d out of range", seat, prog)
			}
			if p.Forfeited && prog != Base {
				t.Fatalf("forfeited seat %d has a token on the board", seat)
			}
			allHome = allHome && prog == Home
			if abs := TrackIndex(p.Color, prog); abs >= 0 && !IsSafe(abs) {
				if other, ok := squares[abs]; ok && other != p.Color {
					t.Fatalf("square %d holds %s and %s tokens", abs, other, p.Color)
				}
				squares[abs] = p.Color
			}
		}
		if allHome {
			homeCount++
		}
	}
	if s.Turn < 0 || s.Turn >= n || s.Players[s.Turn].Forfeited {
		t.Fatalf("turn %d invalid", s.Turn)
	}
	switch s.Phase {
	case PhaseAwaitingRoll:
		if len(s.Legal) != 0 || s.Dice != 0 || s.SixStreak > 2 || s.Winner != -1 || homeCount != 0 {
			t.Fatalf("bad awaiting_roll state %+v", s)
		}
	case PhaseAwaitingMove:
		if len(s.Legal) == 0 || s.Dice < 1 || s.Dice > 6 || s.SixStreak > 2 || s.Winner != -1 || homeCount != 0 {
			t.Fatalf("bad awaiting_move state %+v", s)
		}
	case PhaseFinished:
		if homeCount > 1 {
			t.Fatalf("%d players finished all tokens", homeCount)
		}
	default:
		t.Fatalf("phase %q", s.Phase)
	}
}

func checkFinished(t *testing.T, s *State, n int) {
	t.Helper()
	w := s.Winner
	if w < 0 || w >= n || s.Players[w].Forfeited || s.Turn != w {
		t.Fatalf("bad winner %d (turn %d)", w, s.Turn)
	}
	if !s.allHome(w) && s.ActiveCount() != 1 {
		t.Fatalf("winner %d neither finished nor last player standing", w)
	}
	if len(s.Placements) != n || s.Placements[0] != w {
		t.Fatalf("placements %v", s.Placements)
	}
	sorted := slices.Sorted(slices.Values(s.Placements))
	for i, seat := range sorted {
		if seat != i {
			t.Fatalf("placements %v is not a permutation of seats", s.Placements)
		}
	}
	active := s.ActiveCount()
	for i, seat := range s.Placements {
		if s.Players[seat].Forfeited != (i >= active) {
			t.Fatalf("placements %v: forfeited players must come last", s.Placements)
		}
	}
	if len(s.Legal) != 0 {
		t.Fatalf("legal moves after finish")
	}
}
