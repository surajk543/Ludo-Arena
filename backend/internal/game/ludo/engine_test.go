package ludo

import (
	"errors"
	"reflect"
	"slices"
	"testing"
)

func mustNew(t *testing.T, n int, v Variant) *State {
	t.Helper()
	s, err := New(n, v)
	if err != nil {
		t.Fatalf("New(%d, %q): %v", n, v, err)
	}
	return s
}

// setup builds a state with the given tokens per seat (nil keeps the seat in
// base), seat 0 on turn.
func setup(t *testing.T, v Variant, tokens ...[]int) *State {
	t.Helper()
	s := mustNew(t, len(tokens), v)
	for seat, toks := range tokens {
		if toks != nil {
			if len(toks) != v.TokensPerPlayer() {
				t.Fatalf("seat %d: %d tokens, want %d", seat, len(toks), v.TokensPerPlayer())
			}
			s.Players[seat].Tokens = slices.Clone(toks)
		}
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

func mustMove(t *testing.T, s *State, player, token int) MoveResult {
	t.Helper()
	res, err := s.Move(player, token)
	if err != nil {
		t.Fatalf("Move(%d, %d): %v", player, token, err)
	}
	return res
}

// progressAt returns the progress at which color c stands on absolute square abs.
func progressAt(c Color, abs int) int { return (abs - StartIndex(c) + TrackLength) % TrackLength }

func TestNew(t *testing.T) {
	for _, v := range []Variant{Classic, Quick} {
		for n := 2; n <= 4; n++ {
			s := mustNew(t, n, v)
			colors, _ := ColorsFor(n)
			if len(s.Players) != n {
				t.Fatalf("%s/%d: %d players", v, n, len(s.Players))
			}
			for seat, p := range s.Players {
				if p.Color != colors[seat] || p.Forfeited {
					t.Errorf("%s/%d seat %d: %+v", v, n, seat, p)
				}
				if len(p.Tokens) != v.TokensPerPlayer() {
					t.Errorf("%s/%d seat %d: %d tokens", v, n, seat, len(p.Tokens))
				}
				for _, tok := range p.Tokens {
					if tok != Base {
						t.Errorf("%s/%d seat %d: token %d not in base", v, n, seat, tok)
					}
				}
			}
			if s.Variant != v || s.Turn != 0 || s.Phase != PhaseAwaitingRoll || s.Dice != 0 || s.SixStreak != 0 ||
				s.Winner != -1 || s.TurnSeq != 0 || len(s.Legal) != 0 || len(s.Placements) != 0 || s.ActiveCount() != n ||
				s.TurnPlayer() != 0 {
				t.Errorf("%s/%d: bad initial state %+v", v, n, s)
			}
		}
	}
	for _, n := range []int{-1, 0, 1, 5} {
		if _, err := New(n, Classic); !errors.Is(err, ErrBadPlayerCount) {
			t.Errorf("New(%d) err = %v, want ErrBadPlayerCount", n, err)
		}
	}
	for _, v := range []Variant{"", "turbo", "Classic"} {
		if _, err := New(2, v); !errors.Is(err, ErrBadVariant) {
			t.Errorf("New(2, %q) err = %v, want ErrBadVariant", v, err)
		}
	}
}

func TestEnterFromBase(t *testing.T) {
	cases := []struct {
		v         Variant
		dice      int
		canEnter  bool
		extraTurn bool
	}{
		{Classic, 1, false, false},
		{Classic, 2, false, false},
		{Classic, 3, false, false},
		{Classic, 4, false, false},
		{Classic, 5, false, false},
		{Classic, 6, true, true},
		{Quick, 1, true, false},
		{Quick, 2, false, false},
		{Quick, 3, false, false},
		{Quick, 4, false, false},
		{Quick, 5, false, false},
		{Quick, 6, true, true},
	}
	for _, tc := range cases {
		s := mustNew(t, 2, tc.v)
		res := mustRoll(t, s, 0, tc.dice)
		if !tc.canEnter {
			if !res.TurnPassed || res.Voided || len(res.Legal) != 0 || s.Turn != 1 || res.Turn != 1 ||
				s.Phase != PhaseAwaitingRoll || s.TurnSeq != 1 || s.Dice != 0 {
				t.Errorf("%s dice %d: want pass, got res %+v state turn=%d phase=%s", tc.v, tc.dice, res, s.Turn, s.Phase)
			}
			continue
		}
		if res.TurnPassed || !slices.Equal(res.Legal, []int{0}) || s.Phase != PhaseAwaitingMove || res.Phase != PhaseAwaitingMove ||
			s.Turn != 0 || s.TurnSeq != 1 || s.Dice != tc.dice {
			t.Fatalf("%s dice %d: want legal [0], got %+v", tc.v, tc.dice, res)
		}
		mv := mustMove(t, s, 0, 0)
		if mv.From != Base || mv.To != 0 || s.Players[0].Tokens[0] != 0 || len(mv.Captures) != 0 {
			t.Errorf("%s dice %d: bad entry %+v", tc.v, tc.dice, mv)
		}
		if mv.ExtraTurn != tc.extraTurn || mv.TurnPassed == tc.extraTurn {
			t.Errorf("%s dice %d: extraTurn=%v turnPassed=%v, want extra %v", tc.v, tc.dice, mv.ExtraTurn, mv.TurnPassed, tc.extraTurn)
		}
		wantTurn := 1
		if tc.extraTurn {
			wantTurn = 0
		}
		if s.Turn != wantTurn || mv.Turn != wantTurn || s.Phase != PhaseAwaitingRoll || s.TurnSeq != 2 || s.Dice != 0 {
			t.Errorf("%s dice %d: after move turn=%d phase=%s seq=%d", tc.v, tc.dice, s.Turn, s.Phase, s.TurnSeq)
		}
	}
}

func TestForwardMovesAndExactHome(t *testing.T) {
	cases := []struct {
		from, dice int
		legal      bool
		to         int
	}{
		{0, 3, true, 3},
		{10, 5, true, 15},
		{47, 3, true, 50},
		{48, 5, true, 53},
		{50, 1, true, 51},
		{50, 6, true, 56},
		{52, 4, true, 56},
		{52, 5, false, 0},
		{55, 1, true, 56},
		{55, 2, false, 0},
		{51, 6, false, 0},
		{56, 1, false, 0},
		{56, 6, false, 0},
	}
	for _, tc := range cases {
		s := setup(t, Classic, []int{tc.from, -1, -1, -1}, nil)
		res := mustRoll(t, s, 0, tc.dice)
		if got := slices.Contains(res.Legal, 0); got != tc.legal {
			t.Errorf("from %d dice %d: token legal = %v, want %v (legal %v)", tc.from, tc.dice, got, tc.legal, res.Legal)
			continue
		}
		if !tc.legal {
			continue
		}
		mv := mustMove(t, s, 0, 0)
		if mv.From != tc.from || mv.To != tc.to || s.Players[0].Tokens[0] != tc.to {
			t.Errorf("from %d dice %d: moved %d→%d, want →%d", tc.from, tc.dice, mv.From, mv.To, tc.to)
		}
		if mv.ReachedHome != (tc.to == Home) {
			t.Errorf("from %d dice %d: ReachedHome = %v", tc.from, tc.dice, mv.ReachedHome)
		}
		if tc.to == Home && (!mv.ExtraTurn || s.Turn != 0) {
			t.Errorf("from %d dice %d: reaching home must grant an extra turn", tc.from, tc.dice)
		}
	}
}

func TestCaptures(t *testing.T) {
	cases := []struct {
		name      string
		tokens    [][]int
		forfeited []int
		dice      int
		token     int
		wantTo    int
		captures  []Capture
		after     [][]int
	}{
		{
			name:     "plain square",
			tokens:   [][]int{{4, -1, -1, -1}, {progressAt(Green, 6), -1, -1, -1}, nil, nil},
			dice:     2,
			wantTo:   6,
			captures: []Capture{{1, 0}},
			after:    [][]int{{6, -1, -1, -1}, {-1, -1, -1, -1}, {-1, -1, -1, -1}, {-1, -1, -1, -1}},
		},
		{
			name:   "star square 8 is safe",
			tokens: [][]int{{5, -1, -1, -1}, {progressAt(Green, 8), -1, -1, -1}, nil, nil},
			dice:   3,
			wantTo: 8,
			after:  [][]int{{8, -1, -1, -1}, {47, -1, -1, -1}, {-1, -1, -1, -1}, {-1, -1, -1, -1}},
		},
		{
			name:   "star square 21 is safe",
			tokens: [][]int{{17, -1, -1, -1}, nil, {progressAt(Yellow, 21), -1, -1, -1}, nil},
			dice:   4,
			wantTo: 21,
			after:  [][]int{{21, -1, -1, -1}, {-1, -1, -1, -1}, {47, -1, -1, -1}, {-1, -1, -1, -1}},
		},
		{
			name:   "another color's start square is safe",
			tokens: [][]int{{10, -1, -1, -1}, {0, -1, -1, -1}, nil, nil},
			dice:   3,
			wantTo: 13,
			after:  [][]int{{13, -1, -1, -1}, {0, -1, -1, -1}, {-1, -1, -1, -1}, {-1, -1, -1, -1}},
		},
		{
			name:   "entering own start square never captures",
			tokens: [][]int{{-1, -1, -1, -1}, nil, nil, {progressAt(Blue, 0), -1, -1, -1}},
			dice:   6,
			wantTo: 0,
			after:  [][]int{{0, -1, -1, -1}, {-1, -1, -1, -1}, {-1, -1, -1, -1}, {13, -1, -1, -1}},
		},
		{
			// A naive (start+progress)%52 for green progress 53 gives square 14.
			name:   "home column tokens are never captured",
			tokens: [][]int{{12, -1, -1, -1}, {53, -1, -1, -1}, nil, nil},
			dice:   2,
			wantTo: 14,
			after:  [][]int{{14, -1, -1, -1}, {53, -1, -1, -1}, {-1, -1, -1, -1}, {-1, -1, -1, -1}},
		},
		{
			// Red progress 53 would naively map to square 1, where yellow stands.
			name:   "moving into own home column captures nothing",
			tokens: [][]int{{49, -1, -1, -1}, nil, {progressAt(Yellow, 1), -1, -1, -1}, nil},
			dice:   4,
			wantTo: 53,
			after:  [][]int{{53, -1, -1, -1}, {-1, -1, -1, -1}, {27, -1, -1, -1}, {-1, -1, -1, -1}},
		},
		{
			name: "multi-token capture across colors, own token untouched",
			tokens: [][]int{
				{4, 6, -1, -1},
				{progressAt(Green, 6), progressAt(Green, 6), 20, -1},
				{progressAt(Yellow, 6), -1, -1, -1},
				nil,
			},
			dice:     2,
			wantTo:   6,
			captures: []Capture{{1, 0}, {1, 1}, {2, 0}},
			after:    [][]int{{6, 6, -1, -1}, {-1, -1, 20, -1}, {-1, -1, -1, -1}, {-1, -1, -1, -1}},
		},
		{
			name:      "forfeited tokens are ignored",
			tokens:    [][]int{{4, -1, -1, -1}, {progressAt(Green, 6), -1, -1, -1}, nil, nil},
			forfeited: []int{1},
			dice:      2,
			wantTo:    6,
			after:     [][]int{{6, -1, -1, -1}, {45, -1, -1, -1}, {-1, -1, -1, -1}, {-1, -1, -1, -1}},
		},
		{
			name:     "capture on a 6 still gives exactly one extra roll",
			tokens:   [][]int{{4, -1, -1, -1}, {progressAt(Green, 10), -1, -1, -1}, nil, nil},
			dice:     6,
			token:    0,
			wantTo:   10,
			captures: []Capture{{1, 0}},
			after:    [][]int{{10, -1, -1, -1}, {-1, -1, -1, -1}, {-1, -1, -1, -1}, {-1, -1, -1, -1}},
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			s := setup(t, Classic, tc.tokens...)
			for _, seat := range tc.forfeited {
				s.Players[seat].Forfeited = true // keep tokens to prove they are ignored
			}
			res := mustRoll(t, s, 0, tc.dice)
			if !slices.Contains(res.Legal, tc.token) {
				t.Fatalf("token %d not legal: %v", tc.token, res.Legal)
			}
			seq := s.TurnSeq
			mv := mustMove(t, s, 0, tc.token)
			if mv.To != tc.wantTo {
				t.Fatalf("to = %d, want %d", mv.To, tc.wantTo)
			}
			want := tc.captures
			if want == nil {
				want = []Capture{}
			}
			if !reflect.DeepEqual(mv.Captures, want) {
				t.Fatalf("captures = %v, want %v", mv.Captures, want)
			}
			for seat, toks := range tc.after {
				if !slices.Equal(s.Players[seat].Tokens, toks) {
					t.Errorf("seat %d tokens = %v, want %v", seat, s.Players[seat].Tokens, toks)
				}
			}
			wantExtra := tc.dice == 6 || len(want) > 0
			if mv.ExtraTurn != wantExtra || (s.Turn == 0) != wantExtra || s.TurnSeq != seq+1 {
				t.Errorf("extra=%v turn=%d seq=%d→%d, want extra %v", mv.ExtraTurn, s.Turn, seq, s.TurnSeq, wantExtra)
			}
		})
	}
}

func TestNoBlocking(t *testing.T) {
	// Two green tokens stacked on square 4 and one on square 3 do not block red.
	s := setup(t, Classic,
		[]int{2, 7, -1, -1},
		[]int{progressAt(Green, 3), progressAt(Green, 4), progressAt(Green, 4), -1},
	)
	res := mustRoll(t, s, 0, 5)
	if !slices.Equal(res.Legal, []int{0, 1}) {
		t.Fatalf("legal = %v, want [0 1]", res.Legal)
	}
	mv := mustMove(t, s, 0, 0)
	if mv.To != 7 || len(mv.Captures) != 0 {
		t.Fatalf("move = %+v", mv)
	}
	if !slices.Equal(s.Players[0].Tokens, []int{7, 7, -1, -1}) {
		t.Fatalf("red tokens = %v; own tokens may share a square", s.Players[0].Tokens)
	}
	if !slices.Equal(s.Players[1].Tokens, []int{42, 43, 43, -1}) {
		t.Fatalf("passed-over green tokens changed: %v", s.Players[1].Tokens)
	}
}

func TestExtraTurnRules(t *testing.T) {
	cases := []struct {
		name   string
		v      Variant
		tokens [][]int
		dice   int
		token  int
		extra  bool
		won    bool
	}{
		{"six with move", Classic, [][]int{{10, -1, -1, -1}, nil}, 6, 0, true, false},
		{"capture without six", Classic, [][]int{{10, -1, -1, -1}, {progressAt(Yellow, 12), -1, -1, -1}}, 2, 0, true, false},
		{"reached home without six", Classic, [][]int{{52, -1, -1, -1}, nil}, 4, 0, true, false},
		{"six and home", Classic, [][]int{{50, -1, -1, -1}, nil}, 6, 0, true, false},
		{"six, capture", Classic, [][]int{{3, -1, -1, -1}, {progressAt(Yellow, 9), -1, -1, -1}}, 6, 0, true, false},
		{"plain move", Classic, [][]int{{10, -1, -1, -1}, nil}, 3, 0, false, false},
		{"quick enter on one", Quick, [][]int{{-1, -1}, nil}, 1, 0, false, false},
		{"quick enter on six", Quick, [][]int{{-1, -1}, nil}, 6, 0, true, false},
		{"winning move ends the game, no extra turn", Quick, [][]int{{56, 53}, nil}, 3, 1, false, true},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			s := setup(t, tc.v, tc.tokens...)
			mustRoll(t, s, 0, tc.dice)
			seq := s.TurnSeq
			mv := mustMove(t, s, 0, tc.token)
			if mv.ExtraTurn != tc.extra || mv.Won != tc.won {
				t.Fatalf("extra=%v won=%v, want %v %v (%+v)", mv.ExtraTurn, mv.Won, tc.extra, tc.won, mv)
			}
			if s.TurnSeq != seq+1 {
				t.Fatalf("TurnSeq %d→%d, want +1 (one extra roll at most)", seq, s.TurnSeq)
			}
			switch {
			case tc.won:
				if s.Phase != PhaseFinished || s.Turn != 0 || mv.TurnPassed {
					t.Fatalf("won: phase=%s turn=%d", s.Phase, s.Turn)
				}
			case tc.extra:
				if s.Phase != PhaseAwaitingRoll || s.Turn != 0 || s.Dice != 0 || len(s.Legal) != 0 || mv.TurnPassed {
					t.Fatalf("extra: phase=%s turn=%d dice=%d", s.Phase, s.Turn, s.Dice)
				}
				// The extra roll is a single roll: a plain follow-up move passes the turn.
				s.Players[0].Tokens = slices.Repeat([]int{20}, tc.v.TokensPerPlayer())
				s.Players[0].Tokens[0] = 30
				s.Players[1].Tokens = slices.Repeat([]int{-1}, tc.v.TokensPerPlayer())
				r := mustRoll(t, s, 0, 2)
				mustMove(t, s, 0, r.Legal[0])
				if s.Turn != 1 {
					t.Fatalf("second plain move did not pass the turn (turn %d)", s.Turn)
				}
			default:
				if s.Phase != PhaseAwaitingRoll || s.Turn != 1 || !mv.TurnPassed {
					t.Fatalf("plain: phase=%s turn=%d", s.Phase, s.Turn)
				}
			}
		})
	}
}

func TestThreeSixes(t *testing.T) {
	t.Run("third six is void", func(t *testing.T) {
		s := setup(t, Classic, []int{-1, -1, -1, -1}, []int{30, -1, -1, -1})
		mustRoll(t, s, 0, 6)
		mustMove(t, s, 0, 0) // enter, streak 1
		r := mustRoll(t, s, 0, 6)
		if r.SixStreak != 2 || r.Voided {
			t.Fatalf("second six: %+v", r)
		}
		mustMove(t, s, 0, 0) // 0 → 6, streak 2
		before := slices.Clone(s.Players[0].Tokens)
		seq := s.TurnSeq
		r = mustRoll(t, s, 0, 6)
		if !r.Voided || !r.TurnPassed || r.SixStreak != 3 || len(r.Legal) != 0 || r.Turn != 1 || r.Phase != PhaseAwaitingRoll {
			t.Fatalf("third six: %+v", r)
		}
		if s.Turn != 1 || s.SixStreak != 0 || s.Dice != 0 || s.TurnSeq != seq+1 || !slices.Equal(s.Players[0].Tokens, before) {
			t.Fatalf("after void: turn=%d streak=%d dice=%d seq=%d tokens=%v", s.Turn, s.SixStreak, s.Dice, s.TurnSeq, s.Players[0].Tokens)
		}
	})
	t.Run("non-six resets the streak", func(t *testing.T) {
		s := setup(t, Classic, []int{50, 45, -1, -1}, nil)
		mustRoll(t, s, 0, 6)
		mustMove(t, s, 0, 0) // home, streak 1
		mustRoll(t, s, 0, 6)
		mustMove(t, s, 0, 1) // 45 → 51, streak 2
		r := mustRoll(t, s, 0, 5)
		if r.SixStreak != 0 {
			t.Fatalf("streak after a 5 = %d", r.SixStreak)
		}
		mustMove(t, s, 0, 1) // 51 → 56, extra turn by reaching home
		r = mustRoll(t, s, 0, 6)
		mustMove(t, s, 0, r.Legal[0])
		r = mustRoll(t, s, 0, 6)
		if r.Voided || r.SixStreak != 2 {
			t.Fatalf("6,6,5,6,6 must not be void: %+v", r)
		}
	})
	t.Run("streak resets when the turn passes", func(t *testing.T) {
		s := setup(t, Classic, []int{10, -1, -1, -1}, nil)
		mustRoll(t, s, 0, 6)
		mustMove(t, s, 0, 1) // enter, streak 1
		mustRoll(t, s, 0, 6)
		mustMove(t, s, 0, 0) // streak 2
		mustRoll(t, s, 0, 2)
		mustMove(t, s, 0, 0) // plain → pass
		mustRoll(t, s, 1, 3) // no legal move → pass back
		if s.Turn != 0 || s.SixStreak != 0 {
			t.Fatalf("turn=%d streak=%d", s.Turn, s.SixStreak)
		}
		r := mustRoll(t, s, 0, 6)
		if r.Voided || r.SixStreak != 1 {
			t.Fatalf("first six of a new turn: %+v", r)
		}
	})
}

func TestNoLegalMovePassesTurn(t *testing.T) {
	cases := []struct {
		name   string
		v      Variant
		tokens []int
		dice   int
	}{
		{"all in base, no six", Classic, []int{-1, -1, -1, -1}, 4},
		{"six overshoots everything", Classic, []int{56, 56, 56, 52}, 6},
		{"six overshoots, quick", Quick, []int{53, 54}, 6},
		{"only finished tokens", Classic, []int{56, 56, 56, 56}, 3},
		{"quick base, no 1 or 6", Quick, []int{-1, -1}, 5},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			other := slices.Repeat([]int{-1}, tc.v.TokensPerPlayer())
			s := setup(t, tc.v, tc.tokens, other, other)
			r := mustRoll(t, s, 0, tc.dice)
			if !r.TurnPassed || r.Voided || len(r.Legal) != 0 || r.Turn != 1 || r.TurnSeq != 1 || r.Value != tc.dice {
				t.Fatalf("roll = %+v", r)
			}
			if s.Turn != 1 || s.Phase != PhaseAwaitingRoll || s.SixStreak != 0 || s.Dice != 0 || s.TurnSeq != 1 {
				t.Fatalf("state turn=%d phase=%s streak=%d dice=%d seq=%d", s.Turn, s.Phase, s.SixStreak, s.Dice, s.TurnSeq)
			}
		})
	}
}

func TestLegalMovesDedupe(t *testing.T) {
	cases := []struct {
		v      Variant
		tokens []int
		dice   int
		legal  []int
	}{
		{Classic, []int{-1, -1, 10, 10}, 6, []int{0, 2}},
		{Classic, []int{5, 5, 5, 5}, 1, []int{0}},
		{Classic, []int{56, 56, 3, -1}, 2, []int{2}},
		{Classic, []int{-1, 20, -1, 20}, 6, []int{0, 1}},
		{Classic, []int{52, 52, 51, -1}, 5, []int{2}},
		{Classic, []int{30, 31, 30, 31}, 4, []int{0, 1}},
		{Quick, []int{-1, -1}, 1, []int{0}},
		{Quick, []int{7, 7}, 3, []int{0}},
	}
	for _, tc := range cases {
		s := setup(t, tc.v, tc.tokens, nil)
		r := mustRoll(t, s, 0, tc.dice)
		if !slices.Equal(r.Legal, tc.legal) || !slices.Equal(s.Legal, tc.legal) {
			t.Errorf("%v dice %d: legal = %v, want %v", tc.tokens, tc.dice, r.Legal, tc.legal)
		}
	}

	// Unlisted duplicates are rejected even though the move would be identical.
	s := setup(t, Classic, []int{-1, -1, 10, 10}, nil)
	mustRoll(t, s, 0, 6)
	for _, tok := range []int{1, 3} {
		if _, err := s.Move(0, tok); !errors.Is(err, ErrIllegalMove) {
			t.Errorf("Move(0, %d) err = %v, want ErrIllegalMove", tok, err)
		}
	}
}

func TestAutoMoveToken(t *testing.T) {
	cases := []struct {
		tokens []int
		dice   int
		want   int
	}{
		{[]int{-1, -1, 10, 30}, 6, 3},
		{[]int{-1, 4, 4, 2}, 6, 1},
		{[]int{52, -1, -1, -1}, 6, 1},
		{[]int{50, 51, -1, -1}, 5, 1},
		{[]int{20, 20, 3, 56}, 2, 0},
		{[]int{-1, -1, -1, -1}, 6, 0},
	}
	for _, tc := range cases {
		s := setup(t, Classic, tc.tokens, nil)
		if tok, ok := s.AutoMoveToken(); ok || tok != -1 {
			t.Fatalf("AutoMoveToken before roll = %d, %v", tok, ok)
		}
		mustRoll(t, s, 0, tc.dice)
		tok, ok := s.AutoMoveToken()
		if !ok || tok != tc.want {
			t.Errorf("%v dice %d: auto = %d,%v, want %d", tc.tokens, tc.dice, tok, ok, tc.want)
		}
		if !slices.Contains(s.Legal, tok) {
			t.Errorf("auto token %d not in legal %v", tok, s.Legal)
		}
	}
}

func TestForfeit(t *testing.T) {
	t.Run("turn player during awaiting_move", func(t *testing.T) {
		s := setup(t, Classic, []int{-1, -1, 10, -1}, []int{5, -1, -1, -1}, []int{7, -1, -1, -1})
		mustRoll(t, s, 0, 6)
		if s.Phase != PhaseAwaitingMove || s.TurnSeq != 1 {
			t.Fatalf("setup: phase=%s", s.Phase)
		}
		if s.Forfeit(0) {
			t.Fatal("game must continue")
		}
		if s.Turn != 1 || s.Phase != PhaseAwaitingRoll || s.TurnSeq != 2 || s.Dice != 0 || len(s.Legal) != 0 || s.SixStreak != 0 {
			t.Fatalf("after forfeit: %+v", s)
		}
		if !s.Players[0].Forfeited || !slices.Equal(s.Players[0].Tokens, []int{-1, -1, -1, -1}) || s.ActiveCount() != 2 {
			t.Fatalf("seat 0 = %+v", s.Players[0])
		}
		if _, err := s.Roll(0, 3); !errors.Is(err, ErrNotYourTurn) {
			t.Fatalf("forfeited player roll err = %v", err)
		}
	})
	t.Run("other player keeps turn and phase", func(t *testing.T) {
		s := setup(t, Classic, []int{-1, -1, 10, -1}, []int{5, -1, -1, -1}, []int{7, -1, -1, -1})
		mustRoll(t, s, 0, 6)
		if s.Forfeit(2) {
			t.Fatal("game must continue")
		}
		if s.Turn != 0 || s.Phase != PhaseAwaitingMove || s.TurnSeq != 1 || !slices.Equal(s.Legal, []int{0, 2}) || s.Dice != 6 {
			t.Fatalf("after forfeit: %+v", s)
		}
		if !slices.Equal(s.Players[2].Tokens, []int{-1, -1, -1, -1}) {
			t.Fatalf("tokens not removed: %v", s.Players[2].Tokens)
		}
	})
	t.Run("last remaining player wins", func(t *testing.T) {
		for _, tc := range []struct{ forfeit, winner int }{{1, 0}, {0, 1}} {
			s := setup(t, Classic, []int{3, -1, -1, -1}, []int{9, 56, -1, -1})
			if !s.Forfeit(tc.forfeit) {
				t.Fatalf("forfeit %d: game must finish", tc.forfeit)
			}
			if s.Phase != PhaseFinished || s.Winner != tc.winner || s.Turn != tc.winner || s.TurnSeq != 1 ||
				!slices.Equal(s.Placements, []int{tc.winner, tc.forfeit}) {
				t.Fatalf("forfeit %d: %+v", tc.forfeit, s)
			}
			if _, err := s.Roll(tc.winner, 3); !errors.Is(err, ErrGameOver) {
				t.Fatalf("roll after finish err = %v", err)
			}
		}
	})
	t.Run("winner mid-move keeps turn", func(t *testing.T) {
		s := setup(t, Classic, []int{-1, -1, 10, -1}, nil)
		mustRoll(t, s, 0, 6)
		if !s.Forfeit(1) {
			t.Fatal("game must finish")
		}
		if s.Phase != PhaseFinished || s.Winner != 0 || s.Turn != 0 || s.TurnSeq != 2 || len(s.Legal) != 0 {
			t.Fatalf("%+v", s)
		}
		if _, err := s.Move(0, 0); !errors.Is(err, ErrGameOver) {
			t.Fatalf("move after finish err = %v", err)
		}
	})
	t.Run("placements order forfeits latest first", func(t *testing.T) {
		s := mustNew(t, 4, Classic)
		for _, seat := range []int{3, 1} {
			if s.Forfeit(seat) {
				t.Fatalf("forfeit %d finished early", seat)
			}
		}
		if !s.Forfeit(0) {
			t.Fatal("game must finish")
		}
		if s.Winner != 2 || s.Turn != 2 || !slices.Equal(s.Placements, []int{2, 0, 1, 3}) || !slices.Equal(s.ForfeitOrder, []int{3, 1, 0}) {
			t.Fatalf("winner=%d placements=%v order=%v", s.Winner, s.Placements, s.ForfeitOrder)
		}
	})
	t.Run("no-ops", func(t *testing.T) {
		s := mustNew(t, 3, Classic)
		s.Forfeit(1)
		before := s.Clone()
		for _, seat := range []int{1, -1, 3, 99} {
			if s.Forfeit(seat) {
				t.Fatalf("Forfeit(%d) reported finish", seat)
			}
		}
		if !reflect.DeepEqual(s, before) {
			t.Fatalf("no-op forfeits changed the state")
		}
		s.Forfeit(2)
		finished := s.Clone()
		if s.Forfeit(0) || !reflect.DeepEqual(s, finished) {
			t.Fatal("forfeit after game over must be a no-op returning false")
		}
	})
}

func TestTurnOrderSkipsForfeited(t *testing.T) {
	s := mustNew(t, 4, Classic)
	s.Forfeit(1)
	steps := []struct{ roller, next int }{{0, 2}, {2, 3}, {3, 0}}
	for _, st := range steps {
		if r := mustRoll(t, s, st.roller, 3); r.Turn != st.next {
			t.Fatalf("after seat %d: turn %d, want %d", st.roller, r.Turn, st.next)
		}
	}
	s.Forfeit(3)
	for _, st := range []struct{ roller, next int }{{0, 2}, {2, 0}} {
		if r := mustRoll(t, s, st.roller, 3); r.Turn != st.next {
			t.Fatalf("after seat %d: turn %d, want %d", st.roller, r.Turn, st.next)
		}
	}
	// Forfeiting the turn player passes the turn past forfeited seats.
	s2 := mustNew(t, 4, Classic)
	s2.Forfeit(1)
	s2.Forfeit(2)
	s2.Forfeit(0)
	if s2.Phase != PhaseFinished || s2.Winner != 3 {
		t.Fatalf("winner = %d phase=%s", s2.Winner, s2.Phase)
	}
	s3 := mustNew(t, 4, Classic)
	s3.Forfeit(1)
	s3.Forfeit(0)
	if s3.Turn != 2 || s3.TurnSeq != 1 {
		t.Fatalf("turn = %d seq=%d", s3.Turn, s3.TurnSeq)
	}
}

func TestWinAndPlacements(t *testing.T) {
	t.Run("classic", func(t *testing.T) {
		s := setup(t, Classic,
			[]int{56, 56, 56, 50},
			[]int{10, 20, -1, -1}, // score 32
			[]int{56, 3, -1, -1},  // score 61
			[]int{40, 40, 40, 40}, // forfeited
		)
		s.Forfeit(3)
		r := mustRoll(t, s, 0, 6)
		if !slices.Equal(r.Legal, []int{3}) {
			t.Fatalf("legal = %v", r.Legal)
		}
		seq := s.TurnSeq
		mv := mustMove(t, s, 0, 3)
		if !mv.Won || !mv.ReachedHome || mv.ExtraTurn || mv.TurnPassed || mv.Phase != PhaseFinished || mv.Turn != 0 {
			t.Fatalf("move = %+v", mv)
		}
		if s.Phase != PhaseFinished || s.Winner != 0 || s.Turn != 0 || s.TurnSeq != seq+1 || len(s.Legal) != 0 {
			t.Fatalf("state = %+v", s)
		}
		if !slices.Equal(s.Placements, []int{0, 2, 1, 3}) {
			t.Fatalf("placements = %v", s.Placements)
		}
		if _, ok := s.AutoMoveToken(); ok {
			t.Fatal("AutoMoveToken after finish")
		}
	})
	t.Run("ties go to the lower seat", func(t *testing.T) {
		s := setup(t, Classic,
			[]int{56, 56, 56, 55},
			[]int{56, -1, -1, -1}, // score 57
			[]int{5, 50, -1, -1},  // score 57
			[]int{-1, -1, -1, -1}, // score 0
		)
		mustRoll(t, s, 0, 1)
		mustMove(t, s, 0, 3)
		if !slices.Equal(s.Placements, []int{0, 1, 2, 3}) {
			t.Fatalf("placements = %v", s.Placements)
		}
	})
	t.Run("quick wins with both tokens home", func(t *testing.T) {
		s := setup(t, Quick, []int{56, 54}, []int{30, -1}, []int{-1, -1})
		mustRoll(t, s, 0, 2)
		mv := mustMove(t, s, 0, 1)
		if !mv.Won || s.Winner != 0 || !slices.Equal(s.Placements, []int{0, 1, 2}) {
			t.Fatalf("move=%+v placements=%v", mv, s.Placements)
		}
	})
	t.Run("one token home is not a win", func(t *testing.T) {
		s := setup(t, Quick, []int{-1, 54}, nil)
		mustRoll(t, s, 0, 2)
		mv := mustMove(t, s, 0, 1)
		if mv.Won || s.Phase == PhaseFinished || !mv.ExtraTurn {
			t.Fatalf("move=%+v", mv)
		}
	})
}

func TestInvalidInputs(t *testing.T) {
	type action func(s *State) error
	roll := func(p, v int) action { return func(s *State) error { _, err := s.Roll(p, v); return err } }
	move := func(p, tok int) action { return func(s *State) error { _, err := s.Move(p, tok); return err } }

	awaitingRoll := func(t *testing.T) *State { return setup(t, Classic, []int{-1, -1, 10, 20}, nil, nil) }
	awaitingMove := func(t *testing.T) *State {
		s := awaitingRoll(t)
		mustRoll(t, s, 0, 6) // legal [0 2 3]
		return s
	}
	finished := func(t *testing.T) *State {
		s := setup(t, Classic, []int{56, 56, 56, 55}, nil, nil)
		mustRoll(t, s, 0, 1)
		mustMove(t, s, 0, 3)
		return s
	}

	cases := []struct {
		name  string
		state func(*testing.T) *State
		act   action
		want  error
	}{
		{"roll wrong player", awaitingRoll, roll(1, 3), ErrNotYourTurn},
		{"roll negative seat", awaitingRoll, roll(-1, 3), ErrNotYourTurn},
		{"roll seat out of range", awaitingRoll, roll(3, 3), ErrNotYourTurn},
		{"dice 0", awaitingRoll, roll(0, 0), ErrBadDice},
		{"dice 7", awaitingRoll, roll(0, 7), ErrBadDice},
		{"dice -3", awaitingRoll, roll(0, -3), ErrBadDice},
		{"move while awaiting roll", awaitingRoll, move(0, 2), ErrInvalidPhase},
		{"roll while awaiting move", awaitingMove, roll(0, 3), ErrInvalidPhase},
		{"move wrong player", awaitingMove, move(1, 0), ErrNotYourTurn},
		{"move unlisted token", awaitingMove, move(0, 1), ErrIllegalMove},
		{"move token -1", awaitingMove, move(0, -1), ErrIllegalMove},
		{"move token 4", awaitingMove, move(0, 4), ErrIllegalMove},
		{"roll after game over", finished, roll(0, 3), ErrGameOver},
		{"roll other seat after game over", finished, roll(1, 3), ErrGameOver},
		{"move after game over", finished, move(0, 0), ErrGameOver},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			s := tc.state(t)
			before := s.Clone()
			if err := tc.act(s); !errors.Is(err, tc.want) {
				t.Fatalf("err = %v, want %v", err, tc.want)
			}
			if !reflect.DeepEqual(s, before) {
				t.Fatalf("failed action changed the state")
			}
		})
	}
}

func TestTurnSeqSequence(t *testing.T) {
	s := setup(t, Classic, []int{10, -1, -1, -1}, nil, nil, nil)
	steps := []struct {
		name string
		do   func()
		seq  int
		turn int
	}{
		{"initial", func() {}, 0, 0},
		{"roll → awaiting_move", func() { mustRoll(t, s, 0, 6) }, 1, 0},
		{"move with six → extra roll", func() { mustMove(t, s, 0, 0) }, 2, 0},
		{"roll → awaiting_move", func() { mustRoll(t, s, 0, 2) }, 3, 0},
		{"plain move → pass", func() { mustMove(t, s, 0, 0) }, 4, 1},
		{"roll without legal move → pass", func() { mustRoll(t, s, 1, 3) }, 5, 2},
		{"forfeit of a player not on turn", func() { s.Forfeit(3) }, 5, 2},
		{"forfeit of the turn player", func() { s.Forfeit(2) }, 6, 0},
		{"last opponent forfeits → finished", func() { s.Forfeit(1) }, 7, 0},
	}
	for _, st := range steps {
		st.do()
		if s.TurnSeq != st.seq || s.Turn != st.turn {
			t.Fatalf("%s: seq=%d turn=%d, want %d %d", st.name, s.TurnSeq, s.Turn, st.seq, st.turn)
		}
	}
}

func TestCloneIndependence(t *testing.T) {
	s := setup(t, Classic, []int{-1, -1, 10, 20}, []int{5, -1, -1, -1}, nil)
	s.Forfeit(2)
	mustRoll(t, s, 0, 6)
	c := s.Clone()
	if !reflect.DeepEqual(s, c) {
		t.Fatal("clone differs")
	}
	c.Players[0].Tokens[2] = 44
	c.Players[1].Forfeited = true
	c.Legal[0] = 3
	c.ForfeitOrder[0] = 0
	c.Placements = append(c.Placements, 1)
	if s.Players[0].Tokens[2] != 10 || s.Players[1].Forfeited || s.Legal[0] != 0 || s.ForfeitOrder[0] != 2 || len(s.Placements) != 0 {
		t.Fatalf("mutating the clone changed the original: %+v", s)
	}
	orig := s.Clone()
	c2 := s.Clone()
	mustMove(t, c2, 0, 2)
	if !reflect.DeepEqual(s, orig) {
		t.Fatal("moving on a clone changed the original")
	}
}
