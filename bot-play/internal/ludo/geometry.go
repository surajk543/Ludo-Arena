// Package ludo contains the visible Ludo board geometry (from
// backend/docs/game-rules.md) and a NON-AUTHORITATIVE move evaluator.
//
// The backend is the only authority for dice, legality, captures, extra turns
// and winners. This package never decides whether a move is legal and never
// simulates dice: it only scores the token indices the server already listed
// in turn.legal, using the documented geometry to estimate what each move
// would do. If the evaluator's estimate is wrong, the worst outcome is a
// weaker move choice; the server's subsequent game.move_applied event is
// always what the bot applies to its local state.
package ludo

import (
	"strconv"
	"strings"
)

// Progress encoding (relative to the token's own colour).
const (
	Base        = -1 // token in base
	LastTrack   = 50 // last main-track progress value
	FirstColumn = 51 // first home-column progress value
	Home        = 56 // finished
	TrackLen    = 52 // main track squares
	MaxRoll     = 6
)

// Colour indices in clockwise order.
const (
	Red = iota
	Green
	Yellow
	Blue
)

var colourIndex = map[string]int{"red": Red, "green": Green, "yellow": Yellow, "blue": Blue}

// ColourIndex maps a colour name from the room snapshot to its index.
func ColourIndex(name string) (int, bool) {
	i, ok := colourIndex[name]
	return i, ok
}

// DefaultColours returns the documented seat -> colour index mapping for an
// n-player game (used only when the snapshot omits colours).
func DefaultColours(n int) []int {
	switch n {
	case 2:
		return []int{Red, Yellow}
	case 3:
		return []int{Red, Green, Yellow}
	default:
		out := make([]int, n)
		for i := range out {
			out[i] = i % 4
		}
		return out
	}
}

// safeAbs are the absolute safe squares: start squares and star squares.
var safeAbs = map[int]bool{0: true, 13: true, 26: true, 39: true, 8: true, 21: true, 34: true, 47: true}

// StartSquare returns the absolute track index of a colour's start square.
func StartSquare(colour int) int { return 13 * colour }

// OnTrack reports whether a progress value is on the main track.
func OnTrack(progress int) bool { return progress >= 0 && progress <= LastTrack }

// AbsIndex converts a main-track progress value into the absolute index
// 0..51. It returns -1 for base, home column and home.
func AbsIndex(colour, progress int) int {
	if !OnTrack(progress) {
		return -1
	}
	return (13*colour + progress) % TrackLen
}

// IsSafeAbs reports whether an absolute track square is safe.
func IsSafeAbs(abs int) bool { return safeAbs[abs] }

// IsSafeProgress reports whether a token at this progress can never be
// captured (safe track square, home column or home). Base is not "safe" in
// this sense because it is not on the board.
func IsSafeProgress(colour, progress int) bool {
	switch {
	case progress >= FirstColumn:
		return true
	case OnTrack(progress):
		return IsSafeAbs(AbsIndex(colour, progress))
	default:
		return false
	}
}

// Canonical builds the documented canonical position string used for the
// state hash: L|{turnSeq}|{turnSeat}|{tokens}.
func Canonical(turnSeq, turnSeat int, tokens [][]int) string {
	var b strings.Builder
	b.WriteString("L|")
	b.WriteString(strconv.Itoa(turnSeq))
	b.WriteByte('|')
	b.WriteString(strconv.Itoa(turnSeat))
	b.WriteByte('|')
	for s, seat := range tokens {
		if s > 0 {
			b.WriteByte(';')
		}
		for t, p := range seat {
			if t > 0 {
				b.WriteByte(',')
			}
			b.WriteString(strconv.Itoa(p))
		}
	}
	return b.String()
}
