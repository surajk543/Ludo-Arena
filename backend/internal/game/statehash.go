// Package game holds helpers shared by the game engines in its subpackages
// (ludo, snakes_ladders).
package game

const (
	fnv32Offset = 2166136261
	fnv32Prime  = 16777619
)

// FNV1a32 returns the 32-bit FNV-1a hash of s, as used for the per-event state
// hash `h` (see backend/docs/game-rules.md → "State hash"):
//
//	h = 2166136261; for each byte b: h ^= b; h = (h * 16777619) mod 2^32
func FNV1a32(s string) uint32 {
	h := uint32(fnv32Offset)
	for i := 0; i < len(s); i++ {
		h ^= uint32(s[i])
		h *= fnv32Prime
	}
	return h
}
