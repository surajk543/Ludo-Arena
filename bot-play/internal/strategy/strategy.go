// Package strategy turns a profile into concrete decisions: how long to
// think before an action and which server-listed legal Ludo token to move.
//
// Snakes & Ladders has no decisions (the bot only rolls), so the only thing a
// profile changes there is think time.
package strategy

import (
	"math/rand/v2"
	"time"

	"ludoarena/botplay/internal/config"
	"ludoarena/botplay/internal/connection"
	"ludoarena/botplay/internal/ludo"
	"ludoarena/botplay/internal/profiles"
)

// DeadlineFraction caps think time at this fraction of the time remaining
// before the server's turn deadline, so a bot never times out by thinking.
const DeadlineFraction = 0.4

// Strategy is per-bot (not safe for concurrent use).
type Strategy struct {
	rng  *rand.Rand
	eval *ludo.Evaluator
}

// New creates a strategy with a deterministic seed.
func New(seed uint64) *Strategy {
	r := rand.New(rand.NewPCG(seed, seed^0x9e3779b97f4a7c15))
	// The evaluator gets its own stream so think-time draws never change
	// move jitter (keeps move choice reproducible for a seed).
	er := rand.New(rand.NewPCG(seed^0xbf58476d1ce4e5b9, seed))
	return &Strategy{rng: r, eval: ludo.NewEvaluator(er)}
}

// ThinkRange resolves the effective think-time range:
//   - load test: loadtest.think_time_ms (when override != nil);
//   - otherwise the profile range clamped into bots.think_time [min_ms,max_ms].
func ThinkRange(p *profiles.Profile, global config.ThinkTimeConfig, override *config.RangeMS) (lo, hi time.Duration) {
	var a, b int
	switch {
	case override != nil:
		a, b = override.Min, override.Max
	case p != nil:
		a = clamp(p.ThinkTime.MinMS, global.MinMS, global.MaxMS)
		b = clamp(p.ThinkTime.MaxMS, global.MinMS, global.MaxMS)
	default:
		a, b = global.MinMS, global.MaxMS
	}
	if a > b {
		a = b
	}
	return time.Duration(a) * time.Millisecond, time.Duration(b) * time.Millisecond
}

// ThinkDelay picks how long to wait before acting. remaining is the time
// left until the server deadline (<= 0 when unknown or already passed);
// the delay never exceeds DeadlineFraction of it.
func (s *Strategy) ThinkDelay(p *profiles.Profile, global config.ThinkTimeConfig, override *config.RangeMS, remaining time.Duration, hasDeadline bool) time.Duration {
	lo, hi := ThinkRange(p, global, override)
	d := lo
	switch {
	case hi <= lo:
	case global.Randomize || override != nil:
		d = lo + time.Duration(s.rng.Int64N(int64(hi-lo)+1))
	default:
		d = lo + (hi-lo)/2
	}
	if hasDeadline {
		if remaining <= 0 {
			return 0
		}
		if c := time.Duration(float64(remaining) * DeadlineFraction); d > c {
			d = c
		}
	}
	return d
}

// Float64 exposes the strategy's rng for small probabilistic choices
// (disconnect simulation, malformed injection).
func (s *Strategy) Float64() float64 { return s.rng.Float64() }

// IntN exposes the strategy's rng.
func (s *Strategy) IntN(n int) int { return s.rng.IntN(n) }

// ChooseLudoMove scores the server-provided legal tokens with the profile's
// weights and returns the best one. It never adds tokens the server did not
// list.
func (s *Strategy) ChooseLudoMove(room *connection.Room, mySeat int, p *profiles.Profile) (token int, cands []ludo.Candidate, ok bool) {
	legal := room.Turn.Legal
	if len(legal) == 0 {
		return 0, nil, false
	}
	if len(legal) == 1 || p == nil {
		return legal[0], nil, true
	}
	v := ViewFromRoom(room, mySeat)
	best, all, ok := s.eval.Choose(v, p.Weights)
	if !ok {
		return legal[0], nil, true
	}
	return best.Token, all, true
}

// ViewFromRoom builds the evaluator's visible-state view from a snapshot.
func ViewFromRoom(room *connection.Room, mySeat int) ludo.View {
	n := len(room.Board.Tokens)
	v := ludo.View{
		MySeat:    mySeat,
		Tokens:    room.Board.Tokens,
		Dice:      room.Turn.Dice,
		Legal:     room.Turn.Legal,
		Colours:   make([]int, n),
		Forfeited: make([]bool, n),
	}
	def := ludo.DefaultColours(n)
	for i := 0; i < n; i++ {
		v.Colours[i] = def[i]
		if pl := room.Player(i); pl != nil {
			if c, ok := ludo.ColourIndex(pl.Color); ok {
				v.Colours[i] = c
			}
			v.Forfeited[i] = pl.Forfeited
		}
	}
	return v
}

func clamp(v, lo, hi int) int {
	if v < lo {
		return lo
	}
	if v > hi {
		return hi
	}
	return v
}
