package ludo

import "fmt"

// Progress values and board sizes (see backend/docs/game-rules.md → Ludo →
// "Token position encoding").
const (
	// TrackLength is the number of squares on the shared main track.
	TrackLength = 52
	// Base is the progress of a token that is still in its base.
	Base = -1
	// LastTrack is the last progress value on the main track (0..50).
	LastTrack = 50
	// HomeColumnFirst is the first progress value in the home column (51..55).
	HomeColumnFirst = 51
	// Home is the progress of a finished token.
	Home = 56
)

// Color is a seat color; its value is the color index used for geometry.
type Color int

// Colors in clockwise order.
const (
	Red Color = iota
	Green
	Yellow
	Blue
)

var colorNames = [...]string{"red", "green", "yellow", "blue"}

// String returns "red", "green", "yellow" or "blue".
func (c Color) String() string {
	if c < Red || c > Blue {
		return fmt.Sprintf("Color(%d)", int(c))
	}
	return colorNames[c]
}

// ColorsFor returns the seat → color mapping for n players:
// 2 → [red, yellow], 3 → [red, green, yellow], 4 → [red, green, yellow, blue].
func ColorsFor(n int) ([]Color, error) {
	switch n {
	case 2:
		return []Color{Red, Yellow}, nil
	case 3:
		return []Color{Red, Green, Yellow}, nil
	case 4:
		return []Color{Red, Green, Yellow, Blue}, nil
	}
	return nil, ErrBadPlayerCount
}

// StartIndex returns the absolute main-track index of the color's start
// square (13 × color index).
func StartIndex(c Color) int { return 13 * int(c) }

// TrackIndex converts a color-relative progress value to the absolute
// main-track index 0..51. It returns -1 when the token is not on the main
// track (base, home column or home).
func TrackIndex(c Color, progress int) int {
	if progress < 0 || progress > LastTrack {
		return -1
	}
	return (StartIndex(c) + progress) % TrackLength
}

// IsSafe reports whether the absolute main-track index is a safe square: the
// four start squares (0, 13, 26, 39) or the four star squares (8, 21, 34, 47).
func IsSafe(abs int) bool {
	switch abs {
	case 0, 8, 13, 21, 26, 34, 39, 47:
		return true
	}
	return false
}

// Variant selects the rule set.
type Variant string

// Supported variants.
const (
	Classic Variant = "classic"
	Quick   Variant = "quick"
)

// Valid reports whether v is a known variant.
func (v Variant) Valid() bool { return v == Classic || v == Quick }

// TokensPerPlayer is 4 for classic and 2 for quick.
func (v Variant) TokensPerPlayer() int {
	if v == Quick {
		return 2
	}
	return 4
}

// CanEnter reports whether a roll lets a token leave base: 6 in both
// variants, and also 1 in quick.
func (v Variant) CanEnter(dice int) bool {
	return dice == 6 || (v == Quick && dice == 1)
}
