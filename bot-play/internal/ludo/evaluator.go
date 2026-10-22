package ludo

import (
	"math"
	"math/rand/v2"
	"sort"

	"ludoarena/botplay/internal/profiles"
)

// View is the visible state the evaluator needs. Everything comes from the
// server snapshot / deltas; nothing is simulated.
type View struct {
	MySeat    int
	Colours   []int   // colour index per seat
	Tokens    [][]int // progress per seat per token
	Forfeited []bool  // per seat
	Dice      int     // server-reported dice value for this turn
	Legal     []int   // server-provided legal token indices
}

// Candidate is the evaluation of one server-provided legal token.
type Candidate struct {
	Token    int
	From     int
	To       int // estimated destination progress (non-authoritative)
	Captures int
	Features Features
	Score    float64
}

// Features are the boolean/scalar signals derived from geometry.
type Features struct {
	EnterFromBase bool
	Captures      int
	ReachSafe     bool
	Progress      float64 // destination progress / 56
	CompleteHome  bool
	Escapes       bool    // leaves a threatened square for an unthreatened one
	EscapeRisk    float64 // weight factor for the escape (0.5..1 by progress)
	Endangered    bool    // destination is threatened
	DangerRisk    float64 // weight factor for the danger (0.5..1 by progress)
}

// Evaluator scores legal moves with profile weights. It is deterministic for
// a given rng seed. It is not safe for concurrent use (one per bot).
type Evaluator struct {
	rng *rand.Rand
}

// NewEvaluator creates an evaluator using the given seeded rng. A nil rng
// disables jitter.
func NewEvaluator(rng *rand.Rand) *Evaluator { return &Evaluator{rng: rng} }

// Choose scores every legal token and returns the best candidate plus all
// candidates (sorted best first). ok is false when there is nothing to choose.
//
// Tie-break (deterministic): higher score, then higher destination progress,
// then lower token index.
func (e *Evaluator) Choose(v View, w profiles.Weights) (best Candidate, all []Candidate, ok bool) {
	if len(v.Legal) == 0 || v.MySeat < 0 || v.MySeat >= len(v.Tokens) {
		return Candidate{}, nil, false
	}
	all = make([]Candidate, 0, len(v.Legal))
	for _, tok := range v.Legal {
		c := e.evaluate(v, tok)
		c.Score = score(c.Features, w)
		if w.RandomJitter > 0 && e.rng != nil {
			c.Score += w.RandomJitter * (e.rng.Float64()*2 - 1)
		}
		all = append(all, c)
	}
	sort.SliceStable(all, func(i, j int) bool {
		a, b := all[i], all[j]
		if math.Abs(a.Score-b.Score) > 1e-9 {
			return a.Score > b.Score
		}
		if a.To != b.To {
			return a.To > b.To
		}
		return a.Token < b.Token
	})
	return all[0], all, true
}

func score(f Features, w profiles.Weights) float64 {
	s := 0.0
	if f.EnterFromBase {
		s += w.EnterFromBase
	}
	s += w.CaptureOpponent * float64(f.Captures)
	if f.ReachSafe {
		s += w.ReachSafeSquare
	}
	s += w.ProgressTowardHome * f.Progress
	if f.CompleteHome {
		s += w.CompleteHome
	}
	if f.Escapes {
		s += w.EscapeDanger * f.EscapeRisk
	}
	if f.Endangered {
		s -= w.AvoidDanger * f.DangerRisk
	}
	return s
}

func (e *Evaluator) evaluate(v View, tok int) Candidate {
	me := v.MySeat
	c := Candidate{Token: tok, From: Base, To: Base}
	if tok < 0 || tok >= len(v.Tokens[me]) {
		return c
	}
	colour := colourOf(v, me)
	from := v.Tokens[me][tok]
	c.From = from
	to := destination(from, v.Dice)
	c.To = to
	if to == Base { // not computable from visible state; score neutral
		return c
	}
	f := &c.Features
	f.EnterFromBase = from == Base
	f.Progress = float64(to) / float64(Home)
	f.CompleteHome = to == Home
	// Entering from base always lands on the (safe) start square; that is
	// rewarded through EnterFromBase only. Reaching home is CompleteHome.
	f.ReachSafe = from != Base && to != Home &&
		IsSafeProgress(colour, to) && !IsSafeProgress(colour, from)

	// Captures: destination on a non-safe main-track square shared with
	// tokens of other non-forfeited seats.
	var captured map[[2]int]bool
	if OnTrack(to) {
		abs := AbsIndex(colour, to)
		if !IsSafeAbs(abs) {
			for s := range v.Tokens {
				if s == me || forfeited(v, s) {
					continue
				}
				oc := colourOf(v, s)
				for t, p := range v.Tokens[s] {
					if OnTrack(p) && AbsIndex(oc, p) == abs {
						if captured == nil {
							captured = map[[2]int]bool{}
						}
						captured[[2]int{s, t}] = true
					}
				}
			}
		}
	}
	f.Captures = len(captured)
	c.Captures = f.Captures

	// Danger before and after the move.
	if OnTrack(from) && !IsSafeProgress(colour, from) {
		if threatened(v, colour, from, nil) {
			if !(OnTrack(to) && !IsSafeProgress(colour, to) && threatened(v, colour, to, captured)) {
				f.Escapes = true
				f.EscapeRisk = risk(from)
			}
		}
	}
	if OnTrack(to) && !IsSafeProgress(colour, to) && threatened(v, colour, to, captured) {
		f.Endangered = true
		f.DangerRisk = risk(to)
	}
	return c
}

// risk scales a danger term by how much progress would be lost (0.5..1).
func risk(progress int) float64 {
	if progress < 0 {
		return 0.5
	}
	return 0.5 + 0.5*float64(progress)/float64(LastTrack)
}

// destination estimates the destination progress of a legal move. Entering
// from base uses the whole roll and lands on progress 0.
func destination(from, dice int) int {
	if dice < 1 || dice > MaxRoll {
		return Base
	}
	if from == Base {
		return 0
	}
	to := from + dice
	if to > Home || from >= Home {
		return Base
	}
	return to
}

// threatened reports whether a token of colour at progress p (on the main
// track) could be reached by an opponent token that is 1..6 squares behind it
// on the main track and would still be on the main track after moving that
// far. Tokens in `ignore` (about to be captured) are not counted.
func threatened(v View, colour, p int, ignore map[[2]int]bool) bool {
	abs := AbsIndex(colour, p)
	if abs < 0 {
		return false
	}
	for s := range v.Tokens {
		if s == v.MySeat || forfeited(v, s) {
			continue
		}
		oc := colourOf(v, s)
		for t, op := range v.Tokens[s] {
			if !OnTrack(op) || ignore[[2]int{s, t}] {
				continue
			}
			oabs := AbsIndex(oc, op)
			dist := (abs - oabs + TrackLen) % TrackLen
			if dist >= 1 && dist <= MaxRoll && op+dist <= LastTrack {
				return true
			}
		}
	}
	return false
}

func colourOf(v View, seat int) int {
	if seat < len(v.Colours) {
		return v.Colours[seat]
	}
	d := DefaultColours(len(v.Tokens))
	if seat < len(d) {
		return d[seat]
	}
	return seat % 4
}

func forfeited(v View, seat int) bool {
	return seat < len(v.Forfeited) && v.Forfeited[seat]
}
