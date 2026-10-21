// Package playerinfo holds the small cross-package player summary types used
// by the HTTP API, rooms and progression without import cycles.
package playerinfo

import (
	"context"

	"github.com/google/uuid"
)

// Equip slots.
var Slots = []string{"dice", "token", "ludo_board", "snakes_board", "frame", "title", "victory", "trail"}

// StarterLoadout is the default equipped item per slot.
func StarterLoadout() map[string]string {
	return map[string]string{
		"dice": "dice_classic", "token": "token_classic", "ludo_board": "ludo_board_classic",
		"snakes_board": "snakes_board_classic", "frame": "frame_none", "title": "title_rookie",
		"victory": "victory_confetti", "trail": "trail_none",
	}
}

// Summary is a player's progression summary.
type Summary struct {
	Level       int               `json:"level"`
	XP          int64             `json:"xp"`
	LevelXP     int64             `json:"levelXp"`     // XP at the start of the current level
	NextLevelXP int64             `json:"nextLevelXp"` // XP needed to reach the next level
	Title       string            `json:"title"`
	Loadout     map[string]string `json:"loadout"`
}

// Starter returns the summary of a brand-new player.
func Starter() Summary {
	l := StarterLoadout()
	return Summary{Level: 1, XP: 0, LevelXP: 0, NextLevelXP: 100, Title: l["title"], Loadout: l}
}

// Provider returns summaries; implemented by the progression package.
type Provider interface {
	Summary(ctx context.Context, userID uuid.UUID) (Summary, error)
	Summaries(ctx context.Context, userIDs []uuid.UUID) (map[uuid.UUID]Summary, error)
}

// SeatProvider is an optional Provider extension serving the summary a room
// seat shows (level, title, loadout; XP may be 0) from a cache, so joining a
// room does not read PostgreSQL (progression.Service implements it).
type SeatProvider interface {
	SeatSummary(ctx context.Context, userID uuid.UUID) (Summary, error)
}

// SeatSummary returns p's seat summary for userID, cached when p supports it.
func SeatSummary(ctx context.Context, p Provider, userID uuid.UUID) (Summary, error) {
	if sp, ok := p.(SeatProvider); ok {
		return sp.SeatSummary(ctx, userID)
	}
	return p.Summary(ctx, userID)
}

// StarterProvider returns starter summaries for everyone (used when the
// progression subsystem is not wired, e.g. in narrow tests).
type StarterProvider struct{}

// Summary implements Provider.
func (StarterProvider) Summary(context.Context, uuid.UUID) (Summary, error) { return Starter(), nil }

// Summaries implements Provider.
func (StarterProvider) Summaries(_ context.Context, ids []uuid.UUID) (map[uuid.UUID]Summary, error) {
	out := make(map[uuid.UUID]Summary, len(ids))
	for _, id := range ids {
		out[id] = Starter()
	}
	return out, nil
}
