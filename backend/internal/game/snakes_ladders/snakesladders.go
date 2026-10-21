// Package snakesladders is the authoritative, pure Snakes & Ladders rules
// engine specified in backend/docs/game-rules.md.
//
// The engine performs no I/O, reads no clock, starts no goroutines and draws
// no randomness: dice values are supplied by the caller, which draws them with
// crypto/rand. A State is plain JSON-serializable data. Callers typically load
// the stored state, Clone it, apply one action and compare-and-swap the clone
// back; a failed action never modifies the state.
//
// Clarifications of the written rules, as implemented:
//
//   - Roll applies the move immediately; the phase stays awaiting_roll until
//     the game is finished. There are no extra turns.
//   - TurnSeq grows by exactly 1 on every successful Roll (the turn passes or
//     the game ends) and by 1 on a Forfeit that passes the turn or ends the
//     game. Forfeiting a player who is not on turn, without ending the game,
//     leaves TurnSeq unchanged.
//   - Dice is the last roll of the current turn: 0 while a roll is awaited,
//     the winning roll once finished.
//   - A forfeited player's token stays on its square (it is shown on the
//     board and included in the state hash) but takes no further turns.
//   - When the game ends, Turn is the winner's seat (it is used by the state
//     hash).
//   - Placements: the winner first; then the other non-forfeited players by
//     square descending, ties to the lower seat; then the forfeited players,
//     most recently forfeited first.
package snakesladders

import (
	"cmp"
	"errors"
	"slices"
	"strconv"
	"strings"

	"ludoroyale/internal/game"
)

// Board constants.
const (
	// StartSquare is the off-board starting position.
	StartSquare = 0
	// FinalSquare must be reached exactly to win.
	FinalSquare = 100
)

// Transition kinds.
const (
	KindSnake  = "snake"
	KindLadder = "ladder"
)

// Snakes maps each snake head to its tail. Treat as read-only.
var Snakes = map[int]int{
	16: 6, 47: 26, 49: 11, 56: 53, 62: 19, 64: 60, 87: 24, 93: 73, 95: 75, 98: 78,
}

// Ladders maps each ladder bottom to its top. Treat as read-only.
var Ladders = map[int]int{
	1: 38, 4: 14, 9: 31, 21: 42, 28: 84, 36: 44, 51: 67, 71: 91, 80: 100,
}

// Transition returns where a token landing on square ends up and the kind of
// transition applied ("snake", "ladder", or "" with to == square).
func Transition(square int) (to int, kind string) {
	if tail, ok := Snakes[square]; ok {
		return tail, KindSnake
	}
	if top, ok := Ladders[square]; ok {
		return top, KindLadder
	}
	return square, ""
}

// Errors returned by the engine. A failed call never changes the state.
var (
	ErrBadPlayerCount = errors.New("snakes_ladders: player count must be 2, 3 or 4")
	ErrNotYourTurn    = errors.New("snakes_ladders: not your turn")
	ErrInvalidPhase   = errors.New("snakes_ladders: action not allowed in the current phase")
	ErrBadDice        = errors.New("snakes_ladders: dice value must be 1..6")
	ErrGameOver       = errors.New("snakes_ladders: game is over")
)

// Phase is the turn phase.
type Phase string

// Turn phases.
const (
	PhaseAwaitingRoll Phase = "awaiting_roll"
	PhaseFinished     Phase = "finished"
)

// State is the complete, JSON-serializable game state. Slices are indexed by
// seat.
type State struct {
	Positions []int  `json:"positions"` // 0 = off board, 1..100
	Forfeited []bool `json:"forfeited"`
	Turn      int    `json:"turn"` // seat on turn; the winner once finished
	Phase     Phase  `json:"phase"`
	// Dice is the last roll in the current turn, 0 while a roll is awaited.
	Dice   int `json:"dice"`
	Winner int `json:"winner"` // -1 until finished
	// TurnSeq increases every time the turn owner or the phase changes.
	TurnSeq int `json:"turnSeq"`
	// Placements lists seats in finishing order once finished; empty before.
	Placements []int `json:"placements"`
	// ForfeitOrder lists forfeited seats in the order they forfeited.
	ForfeitOrder []int `json:"forfeitOrder"`
}

// Jump describes a snake or ladder transition applied after landing.
type Jump struct {
	Kind string `json:"kind"` // "snake" | "ladder"
	From int    `json:"from"`
	To   int    `json:"to"`
}

// RollResult describes a successful Roll, which also applies the move.
type RollResult struct {
	Player int `json:"player"`
	Value  int `json:"value"`
	From   int `json:"from"`
	// Landing is the square reached before any transition (From on overshoot).
	Landing int `json:"landing"`
	// To is the final square (From on overshoot).
	To         int   `json:"to"`
	Transition *Jump `json:"transition,omitempty"`
	// Moved is false when the roll would overshoot 100.
	Moved bool `json:"moved"`
	Won   bool `json:"won"`
	// TurnPassed is true unless the roll won the game.
	TurnPassed bool `json:"turnPassed"`
	// Resulting state.
	Phase   Phase `json:"phase"`
	Turn    int   `json:"turn"`
	TurnSeq int   `json:"turnSeq"`
}

// New returns the initial state for n players (2..4): all tokens at 0, seat
// 0 to roll, TurnSeq 0.
func New(n int) (*State, error) {
	if n < 2 || n > 4 {
		return nil, ErrBadPlayerCount
	}
	return &State{
		Positions:    make([]int, n),
		Forfeited:    make([]bool, n),
		Turn:         0,
		Phase:        PhaseAwaitingRoll,
		Winner:       -1,
		Placements:   []int{},
		ForfeitOrder: []int{},
	}, nil
}

// Roll rolls value (1..6, from the caller's random source) for player and
// applies the move: overshooting 100 leaves the token in place; landing on a
// snake head or ladder bottom applies that one transition; reaching 100 wins.
// Otherwise the turn passes to the next non-forfeited player.
func (s *State) Roll(player, value int) (RollResult, error) {
	if s.Phase == PhaseFinished {
		return RollResult{}, ErrGameOver
	}
	if player != s.Turn || player < 0 || player >= len(s.Positions) {
		return RollResult{}, ErrNotYourTurn
	}
	if s.Phase != PhaseAwaitingRoll {
		return RollResult{}, ErrInvalidPhase
	}
	if value < 1 || value > 6 {
		return RollResult{}, ErrBadDice
	}

	from := s.Positions[player]
	res := RollResult{Player: player, Value: value, From: from, Landing: from, To: from}
	s.Dice = value
	if landing := from + value; landing <= FinalSquare {
		to, kind := Transition(landing)
		s.Positions[player] = to
		res.Moved, res.Landing, res.To = true, landing, to
		if kind != "" {
			res.Transition = &Jump{Kind: kind, From: landing, To: to}
		}
	}

	if res.To == FinalSquare {
		res.Won = true
		s.finish(player)
	} else {
		res.TurnPassed = true
		s.passTurn()
	}
	res.Phase, res.Turn, res.TurnSeq = s.Phase, s.Turn, s.TurnSeq
	return res, nil
}

// Forfeit removes player from the game: they take no further turns (their
// token stays on its square). If it was their turn, the turn passes. If only
// one non-forfeited player remains, that player wins. Forfeit returns true
// only when this call ended the game; it is a no-op (returning false) when
// the game is already over, the seat is invalid or already forfeited.
func (s *State) Forfeit(player int) (finished bool) {
	if s.Phase == PhaseFinished || player < 0 || player >= len(s.Forfeited) || s.Forfeited[player] {
		return false
	}
	s.Forfeited[player] = true
	s.ForfeitOrder = append(s.ForfeitOrder, player)

	if s.ActiveCount() <= 1 {
		winner := s.nextActive(player)
		if winner != s.Turn {
			s.Turn = winner
			s.Dice = 0
		}
		s.finish(winner)
		return true
	}
	if player == s.Turn {
		s.passTurn()
	}
	return false
}

// TurnPlayer returns the seat on turn (the winner once finished).
func (s *State) TurnPlayer() int { return s.Turn }

// ActiveCount returns the number of non-forfeited players.
func (s *State) ActiveCount() int {
	n := 0
	for _, f := range s.Forfeited {
		if !f {
			n++
		}
	}
	return n
}

// Clone returns a deep copy of s.
func (s *State) Clone() *State {
	c := *s
	c.Positions = append([]int{}, s.Positions...)
	c.Forfeited = append([]bool{}, s.Forfeited...)
	c.Placements = append([]int{}, s.Placements...)
	c.ForfeitOrder = append([]int{}, s.ForfeitOrder...)
	return &c
}

// CanonicalString returns the canonical position string
// `S|{turnSeq}|{turnSeat}|{positions}` used for the state hash.
func (s *State) CanonicalString() string { return s.CanonicalStringAt(s.TurnSeq, s.Turn) }

// CanonicalStringAt is CanonicalString with the given turnSeq and turn seat
// instead of the state's own. Callers use it to hash the intermediate
// positions they announce (for example a move_applied event sent before the
// turn_changed event that carries the new TurnSeq).
func (s *State) CanonicalStringAt(turnSeq, turnSeat int) string {
	var b strings.Builder
	b.WriteString("S|")
	b.WriteString(strconv.Itoa(turnSeq))
	b.WriteByte('|')
	b.WriteString(strconv.Itoa(turnSeat))
	b.WriteByte('|')
	for i, p := range s.Positions {
		if i > 0 {
			b.WriteByte(',')
		}
		b.WriteString(strconv.Itoa(p))
	}
	return b.String()
}

// Hash returns the FNV-1a 32-bit hash of CanonicalString().
func (s *State) Hash() uint32 { return game.FNV1a32(s.CanonicalString()) }

// HashAt returns the FNV-1a 32-bit hash of CanonicalStringAt(turnSeq, turnSeat).
func (s *State) HashAt(turnSeq, turnSeat int) uint32 {
	return game.FNV1a32(s.CanonicalStringAt(turnSeq, turnSeat))
}

// nextActive returns the next non-forfeited seat after seat, wrapping around.
func (s *State) nextActive(seat int) int {
	n := len(s.Forfeited)
	for i := 1; i <= n; i++ {
		next := (seat + i) % n
		if !s.Forfeited[next] {
			return next
		}
	}
	return seat
}

func (s *State) passTurn() {
	s.Turn = s.nextActive(s.Turn)
	s.Dice = 0
	s.TurnSeq++
}

func (s *State) finish(winner int) {
	s.Turn = winner
	s.Winner = winner
	s.Phase = PhaseFinished
	s.TurnSeq++
	s.Placements = s.placements(winner)
}

// placements computes the finishing order: winner, other active players by
// square desc (ties → lower seat), forfeited players latest-forfeit first.
func (s *State) placements(winner int) []int {
	n := len(s.Positions)
	out := []int{winner}
	var active []int
	for seat := range n {
		if seat != winner && !s.Forfeited[seat] {
			active = append(active, seat)
		}
	}
	slices.SortStableFunc(active, func(a, b int) int {
		if c := cmp.Compare(s.Positions[b], s.Positions[a]); c != 0 {
			return c
		}
		return cmp.Compare(a, b)
	})
	out = append(out, active...)

	seen := make([]bool, n)
	for _, seat := range out {
		seen[seat] = true
	}
	for i := len(s.ForfeitOrder) - 1; i >= 0; i-- {
		if seat := s.ForfeitOrder[i]; seat >= 0 && seat < n && s.Forfeited[seat] && !seen[seat] {
			seen[seat] = true
			out = append(out, seat)
		}
	}
	for seat := range n {
		if s.Forfeited[seat] && !seen[seat] {
			out = append(out, seat)
		}
	}
	return out
}
