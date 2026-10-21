// Package ludo is the authoritative, pure Ludo rules engine (variants
// "classic" and "quick") specified in backend/docs/game-rules.md.
//
// The engine performs no I/O, reads no clock, starts no goroutines and draws
// no randomness: dice values are supplied by the caller, which draws them with
// crypto/rand. A State is plain JSON-serializable data. Callers typically load
// the stored state, Clone it, apply one action and compare-and-swap the clone
// back; a failed action never modifies the state.
//
// Clarifications of the written rules, as implemented:
//
//   - SixStreak counts consecutive sixes rolled by the turn owner in the
//     current turn sequence (first roll plus extra rolls). Any non-6 roll
//     resets it to 0, as does the turn passing. A third consecutive six is
//     void even if a legal move exists.
//   - Roll never applies a move. Whenever at least one legal move exists the
//     phase becomes awaiting_move; when exactly one exists the caller (server)
//     applies it immediately with Move(player, Legal[0]).
//   - Move accepts only token indices listed in Legal, i.e. the lowest index
//     among tokens that share a progress value.
//   - TurnSeq grows by exactly 1 on every successful Roll and Move (each one
//     changes the phase and/or the turn owner, extra turns included), and by 1
//     on a Forfeit that passes the turn or ends the game. Forfeiting a player
//     who is not on turn, without ending the game, leaves TurnSeq unchanged.
//   - Dice is the last roll of the current turn; it is reset to 0 whenever a
//     new roll is awaited (extra turn or turn passed). After a winning move it
//     keeps the winning roll.
//   - In quick Ludo, entering on a 1 is an ordinary move: it grants no extra
//     turn (only a 6, a capture or reaching home do).
//   - When the game ends, Turn is the winner's seat (it is used by the state
//     hash).
//   - Placements: the winner first; then the other non-forfeited players by
//     total progress descending (each token counts progress+1, so a base
//     token is 0 and a finished token 57), ties to the lower seat; then the
//     forfeited players, most recently forfeited first.
package ludo

import (
	"errors"
	"strconv"
	"strings"

	"ludoroyale/internal/game"
)

// Errors returned by the engine. A failed call never changes the state.
var (
	ErrBadPlayerCount = errors.New("ludo: player count must be 2, 3 or 4")
	ErrBadVariant     = errors.New("ludo: unknown variant")
	ErrNotYourTurn    = errors.New("ludo: not your turn")
	ErrInvalidPhase   = errors.New("ludo: action not allowed in the current phase")
	ErrIllegalMove    = errors.New("ludo: illegal move")
	ErrBadDice        = errors.New("ludo: dice value must be 1..6")
	ErrGameOver       = errors.New("ludo: game is over")
)

// Phase is the turn phase.
type Phase string

// Turn phases.
const (
	PhaseAwaitingRoll Phase = "awaiting_roll"
	PhaseAwaitingMove Phase = "awaiting_move"
	PhaseFinished     Phase = "finished"
)

// Player is one seat. Tokens holds progress values (see the package
// constants); its length is Variant.TokensPerPlayer().
type Player struct {
	Color     Color `json:"color"`
	Tokens    []int `json:"tokens"`
	Forfeited bool  `json:"forfeited"`
}

// State is the complete, JSON-serializable game state.
type State struct {
	Variant Variant  `json:"variant"`
	Players []Player `json:"players"` // indexed by seat
	Turn    int      `json:"turn"`    // seat on turn; the winner once finished
	Phase   Phase    `json:"phase"`
	// Dice is the last roll in the current turn, 0 while a roll is awaited.
	Dice int `json:"dice"`
	// SixStreak is the number of consecutive sixes in the current turn.
	SixStreak int `json:"sixStreak"`
	// Legal lists the movable token indices while awaiting_move (deduplicated:
	// lowest index among tokens with equal progress); empty otherwise.
	Legal  []int `json:"legal"`
	Winner int   `json:"winner"` // -1 until finished
	// TurnSeq increases every time the turn owner or the phase changes.
	TurnSeq int `json:"turnSeq"`
	// Placements lists seats in finishing order once finished; empty before.
	Placements []int `json:"placements"`
	// ForfeitOrder lists forfeited seats in the order they forfeited.
	ForfeitOrder []int `json:"forfeitOrder"`
}

// Capture identifies a token sent back to base.
type Capture struct {
	Player int `json:"player"`
	Token  int `json:"token"`
}

// RollResult describes a successful Roll.
type RollResult struct {
	Player int `json:"player"`
	Value  int `json:"value"`
	// SixStreak is the consecutive-six count including this roll (3 when
	// voided). The state's SixStreak is reset to 0 if the turn passed.
	SixStreak int `json:"sixStreak"`
	// Legal lists the movable tokens; empty when voided or no move exists.
	Legal []int `json:"legal"`
	// Voided is true for a third consecutive six (no move, turn passes).
	Voided bool `json:"voided"`
	// TurnPassed is true when the roll ended the turn (voided or no legal
	// move); Turn then holds the next seat.
	TurnPassed bool `json:"turnPassed"`
	// Resulting state.
	Phase   Phase `json:"phase"`
	Turn    int   `json:"turn"`
	TurnSeq int   `json:"turnSeq"`
}

// MoveResult describes a successful Move.
type MoveResult struct {
	Player   int       `json:"player"`
	Token    int       `json:"token"`
	From     int       `json:"from"`
	To       int       `json:"to"`
	Captures []Capture `json:"captures"`
	// ReachedHome is true when the token arrived at progress 56.
	ReachedHome bool `json:"reachedHome"`
	// ExtraTurn is true when the same player rolls again (not set on a win).
	ExtraTurn bool `json:"extraTurn"`
	// TurnPassed is true when the turn moved to the next seat.
	TurnPassed bool `json:"turnPassed"`
	// Won is true when this move won the game (phase is then finished).
	Won bool `json:"won"`
	// Resulting state.
	Phase   Phase `json:"phase"`
	Turn    int   `json:"turn"`
	TurnSeq int   `json:"turnSeq"`
}

// New returns the initial state for n players (2..4) of the given variant:
// all tokens in base, seat 0 to roll, TurnSeq 0.
func New(n int, v Variant) (*State, error) {
	colors, err := ColorsFor(n)
	if err != nil {
		return nil, err
	}
	if !v.Valid() {
		return nil, ErrBadVariant
	}
	players := make([]Player, n)
	for i, c := range colors {
		tokens := make([]int, v.TokensPerPlayer())
		for t := range tokens {
			tokens[t] = Base
		}
		players[i] = Player{Color: c, Tokens: tokens}
	}
	return &State{
		Variant:      v,
		Players:      players,
		Turn:         0,
		Phase:        PhaseAwaitingRoll,
		Legal:        []int{},
		Winner:       -1,
		Placements:   []int{},
		ForfeitOrder: []int{},
	}, nil
}

// Clone returns a deep copy of s.
func (s *State) Clone() *State {
	c := *s
	c.Players = make([]Player, len(s.Players))
	for i, p := range s.Players {
		p.Tokens = append([]int{}, p.Tokens...)
		c.Players[i] = p
	}
	c.Legal = append([]int{}, s.Legal...)
	c.Placements = append([]int{}, s.Placements...)
	c.ForfeitOrder = append([]int{}, s.ForfeitOrder...)
	return &c
}

// TurnPlayer returns the seat on turn (the winner once finished).
func (s *State) TurnPlayer() int { return s.Turn }

// ActiveCount returns the number of non-forfeited players.
func (s *State) ActiveCount() int {
	n := 0
	for _, p := range s.Players {
		if !p.Forfeited {
			n++
		}
	}
	return n
}

// CanonicalString returns the canonical position string
// `L|{turnSeq}|{turnSeat}|{tokens}` used for the state hash.
func (s *State) CanonicalString() string { return s.CanonicalStringAt(s.TurnSeq, s.Turn) }

// CanonicalStringAt is CanonicalString with the given turnSeq and turn seat
// instead of the state's own. Callers use it to hash the intermediate
// positions they announce (for example a move_applied event sent before the
// turn_changed event that carries the new TurnSeq).
func (s *State) CanonicalStringAt(turnSeq, turnSeat int) string {
	var b strings.Builder
	b.WriteString("L|")
	b.WriteString(strconv.Itoa(turnSeq))
	b.WriteByte('|')
	b.WriteString(strconv.Itoa(turnSeat))
	b.WriteByte('|')
	for i, p := range s.Players {
		if i > 0 {
			b.WriteByte(';')
		}
		for j, t := range p.Tokens {
			if j > 0 {
				b.WriteByte(',')
			}
			b.WriteString(strconv.Itoa(t))
		}
	}
	return b.String()
}

// Hash returns the FNV-1a 32-bit hash of CanonicalString().
func (s *State) Hash() uint32 { return game.FNV1a32(s.CanonicalString()) }

// HashAt returns the FNV-1a 32-bit hash of CanonicalStringAt(turnSeq, turnSeat).
func (s *State) HashAt(turnSeq, turnSeat int) uint32 {
	return game.FNV1a32(s.CanonicalStringAt(turnSeq, turnSeat))
}
