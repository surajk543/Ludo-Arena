package ludo

import (
	"math/rand/v2"
	"testing"

	"ludoarena/botplay/internal/profiles"
)

func loadProfiles(t *testing.T) *profiles.Set {
	t.Helper()
	ps, err := profiles.LoadFile("../../configs/profiles.yaml")
	if err != nil {
		t.Fatal(err)
	}
	return ps
}

func weights(t *testing.T, name string) profiles.Weights {
	t.Helper()
	p, ok := loadProfiles(t).Get(name)
	if !ok {
		t.Fatalf("profile %s missing", name)
	}
	return p.Weights
}

func noJitter(w profiles.Weights) profiles.Weights { w.RandomJitter = 0; return w }

// 2-player game: seat 0 red (colour 0), seat 1 yellow (colour 2).
func view(me int, dice int, legal []int, tokens [][]int) View {
	return View{MySeat: me, Colours: []int{Red, Yellow}, Tokens: tokens, Forfeited: []bool{false, false}, Dice: dice, Legal: legal}
}

func TestGeometry(t *testing.T) {
	if StartSquare(Green) != 13 || AbsIndex(Yellow, 0) != 26 || AbsIndex(Blue, 13) != 0 || AbsIndex(Red, 51) != -1 {
		t.Fatal("abs index")
	}
	for _, abs := range []int{0, 8, 13, 21, 26, 34, 39, 47} {
		if !IsSafeAbs(abs) {
			t.Fatalf("%d should be safe", abs)
		}
	}
	if IsSafeAbs(5) || !IsSafeProgress(Red, 53) || IsSafeProgress(Red, Base) {
		t.Fatal("safety")
	}
	if got := Canonical(7, 1, [][]int{{-1, -1, 5, 56}, {0, -1, -1, -1}}); got != "L|7|1|-1,-1,5,56;0,-1,-1,-1" {
		t.Fatal(got)
	}
}

func TestBalancedPrefersCapture(t *testing.T) {
	// Red token 0 at progress 10 (abs 10, not safe); dice 4 -> abs 14.
	// Yellow token at progress 40 -> abs (26+40)%52 = 14 => capture.
	// Red token 1 at progress 30 -> 34 (a safe star square).
	v := view(0, 4, []int{0, 1}, [][]int{{10, 30, -1, -1}, {40, -1, -1, -1}})
	e := NewEvaluator(nil)
	best, all, ok := e.Choose(v, noJitter(weights(t, "balanced")))
	if !ok || best.Token != 0 || best.Captures != 1 {
		t.Fatalf("balanced should capture, got %+v (all %+v)", best, all)
	}
	if !all[1].Features.ReachSafe {
		t.Fatalf("token 1 should reach a safe square: %+v", all[1])
	}
}

func TestEnteringFromBase(t *testing.T) {
	// Dice 6: enter a new token, or move token at progress 2 -> 8 (red star, safe).
	v := view(0, 6, []int{0, 1}, [][]int{{2, -1, -1, -1}, {-1, -1, -1, -1}})
	e := NewEvaluator(nil)
	w := profiles.Weights{EnterFromBase: 50, ReachSafeSquare: 5, ProgressTowardHome: 10}
	best, _, _ := e.Choose(v, w)
	if best.Token != 1 || !best.Features.EnterFromBase || best.To != 0 {
		t.Fatalf("expected entering from base, got %+v", best)
	}
	// With entering not valued, reaching the star square wins.
	best, _, _ = e.Choose(v, profiles.Weights{ReachSafeSquare: 50, ProgressTowardHome: 1})
	if best.Token != 0 || !best.Features.ReachSafe {
		t.Fatalf("expected safe square, got %+v", best)
	}
}

func TestSafeSquareIsNeverCapture(t *testing.T) {
	// Red token at progress 4, dice 4 -> progress 8 = abs 8 (safe star).
	// A yellow token sits on abs 8 (yellow progress 34): no capture on safe squares.
	v := view(0, 4, []int{0, 1}, [][]int{{4, 20, -1, -1}, {34, -1, -1, -1}})
	_, all, _ := NewEvaluator(nil).Choose(v, noJitter(weights(t, "advanced")))
	for _, c := range all {
		if c.Token == 0 && c.Captures != 0 {
			t.Fatalf("captured on a safe square: %+v", c)
		}
	}
}

func TestHomeCompletion(t *testing.T) {
	// Token 0 at 53 + dice 3 = 56 (home). Token 1 at 20 -> 23.
	v := view(0, 3, []int{0, 1}, [][]int{{53, 20, -1, -1}, {-1, -1, -1, -1}})
	for _, p := range []string{"beginner", "balanced", "advanced"} {
		best, _, _ := NewEvaluator(nil).Choose(v, noJitter(weights(t, p)))
		if best.Token != 0 || !best.Features.CompleteHome {
			t.Fatalf("%s should complete home, got %+v", p, best)
		}
	}
}

func TestAvoidAndEscapeDanger(t *testing.T) {
	// Yellow token at yellow progress 36 = abs 10. Red token 0 at progress 9
	// (abs 9) is NOT threatened (behind); moving it 2 -> abs 11 lands 1 ahead
	// of yellow: dangerous. Token 1 at progress 22 -> 24 (abs 24): safe from it.
	v := view(0, 2, []int{0, 1}, [][]int{{9, 22, -1, -1}, {36, -1, -1, -1}})
	best, all, _ := NewEvaluator(nil).Choose(v, noJitter(weights(t, "advanced")))
	if best.Token != 1 {
		t.Fatalf("advanced should avoid danger, got %+v / %+v", best, all)
	}
	var danger Candidate
	for _, c := range all {
		if c.Token == 0 {
			danger = c
		}
	}
	if !danger.Features.Endangered {
		t.Fatalf("token 0 destination should be endangered: %+v", danger)
	}
	// Escape: red token at progress 12 (abs 12) with yellow at abs 10 behind it
	// (threatened). Dice 5 -> abs 17, 7 ahead of yellow: escaped.
	v = view(0, 5, []int{0, 1}, [][]int{{12, 30, -1, -1}, {36, -1, -1, -1}})
	_, all, _ = NewEvaluator(nil).Choose(v, noJitter(weights(t, "advanced")))
	for _, c := range all {
		if c.Token == 0 && !c.Features.Escapes {
			t.Fatalf("token 0 should escape: %+v", c)
		}
	}
}

func TestDeterministicWithSeed(t *testing.T) {
	v := view(0, 3, []int{0, 1, 2}, [][]int{{5, 15, 25, -1}, {-1, -1, -1, -1}})
	w := weights(t, "beginner") // jitter-heavy
	run := func(seed uint64) []int {
		e := NewEvaluator(rand.New(rand.NewPCG(seed, seed)))
		var out []int
		for i := 0; i < 20; i++ {
			b, _, _ := e.Choose(v, w)
			out = append(out, b.Token)
		}
		return out
	}
	a, b := run(99), run(99)
	for i := range a {
		if a[i] != b[i] {
			t.Fatalf("same seed differs: %v vs %v", a, b)
		}
	}
	// Without jitter, ties are broken by destination progress then index.
	tie := view(0, 3, []int{2, 1}, [][]int{{-1, 10, 10, -1}, {-1, -1, -1, -1}})
	best, _, _ := NewEvaluator(nil).Choose(tie, profiles.Weights{})
	if best.Token != 1 {
		t.Fatalf("tie-break must pick lower index, got %d", best.Token)
	}
}

func TestOnlyServerLegalTokensAreConsidered(t *testing.T) {
	// Token 0 would capture, but the server did not list it.
	v := view(0, 4, []int{1}, [][]int{{10, 30, -1, -1}, {40, -1, -1, -1}})
	best, all, _ := NewEvaluator(nil).Choose(v, weights(t, "advanced"))
	if best.Token != 1 || len(all) != 1 {
		t.Fatalf("evaluator considered a non-legal token: %+v", all)
	}
	if _, _, ok := NewEvaluator(nil).Choose(view(0, 4, nil, v.Tokens), weights(t, "advanced")); ok {
		t.Fatal("no legal moves must yield ok=false")
	}
}
