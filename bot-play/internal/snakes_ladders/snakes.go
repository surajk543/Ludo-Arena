// Package snakes_ladders contains the visible Snakes & Ladders geometry from
// backend/docs/game-rules.md.
//
// Snakes & Ladders has no player choices: a bot only ever rolls. There is no
// strategy here on purpose. ExpectedDestination exists only so logs and
// tests can compare the server-confirmed destination with the documented
// board; the bot always applies the server's game.move_applied event.
package snakes_ladders

import (
	"strconv"
	"strings"
)

// Board constants.
const (
	Start  = 0
	Finish = 100
)

// Snakes maps head -> tail.
var Snakes = map[int]int{16: 6, 47: 26, 49: 11, 56: 53, 62: 19, 64: 60, 87: 24, 93: 73, 95: 75, 98: 78}

// Ladders maps bottom -> top.
var Ladders = map[int]int{1: 38, 4: 14, 9: 31, 21: 42, 28: 84, 36: 44, 51: 67, 71: 91, 80: 100}

// ExpectedDestination returns the documented destination for a roll
// (NON-AUTHORITATIVE; for diagnostics only).
func ExpectedDestination(pos, dice int) int {
	if dice < 1 || dice > 6 {
		return pos
	}
	to := pos + dice
	if to > Finish {
		return pos
	}
	if t, ok := Snakes[to]; ok {
		return t
	}
	if t, ok := Ladders[to]; ok {
		return t
	}
	return to
}

// Canonical builds the canonical state string S|{turnSeq}|{turnSeat}|{positions}.
func Canonical(turnSeq, turnSeat int, positions []int) string {
	var b strings.Builder
	b.WriteString("S|")
	b.WriteString(strconv.Itoa(turnSeq))
	b.WriteByte('|')
	b.WriteString(strconv.Itoa(turnSeat))
	b.WriteByte('|')
	for i, p := range positions {
		if i > 0 {
			b.WriteByte(',')
		}
		b.WriteString(strconv.Itoa(p))
	}
	return b.String()
}
