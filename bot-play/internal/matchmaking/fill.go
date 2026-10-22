// Package matchmaking contains the public-lobby fill planner (public_fill
// mode) and the load-test game/capacity mix picker.
package matchmaking

import (
	"sort"
	"sync"
	"time"

	"ludoarena/botplay/internal/client"
	"ludoarena/botplay/internal/config"
)

// FillParams are the inputs to one planning round.
type FillParams struct {
	Enabled        bool            // public fill mode + public_matchmaking.enabled + bots.enabled
	PerGame        map[string]bool // public_matchmaking.per_game
	Games          map[string]bool // bots.games
	FillAfter      time.Duration
	MaximumWait    time.Duration
	MinimumHumans  int
	MaxBotsPerRoom int
	RefillCooldown time.Duration
	// Headroom is how many more bots the service may start now (global).
	Headroom int
	// GameHeadroom is how many more bots may start per game key.
	GameHeadroom map[string]int
}

// FillRequest is one planned POST /bot/lobbies/{roomId}/fill.
type FillRequest struct {
	RoomID string
	Game   string // config game key
	Count  int
}

// SkipReason explains why a lobby was not filled (for debug logs/tests).
type SkipReason string

// Skip reasons.
const (
	SkipDisabled     SkipReason = "disabled"
	SkipGameDisabled SkipReason = "game_disabled"
	SkipTooEarly     SkipReason = "too_early"
	SkipTooLate      SkipReason = "too_late"
	SkipFewHumans    SkipReason = "few_humans"
	SkipPending      SkipReason = "pending_bots"
	SkipCooldown     SkipReason = "cooldown"
	SkipNoSeats      SkipReason = "no_free_seats"
	SkipRoomBotLimit SkipReason = "max_bots_per_room"
	SkipNoHeadroom   SkipReason = "no_headroom"
	SkipUnknownGame  SkipReason = "unknown_game"
	SkipInvalidLobby SkipReason = "invalid_lobby"
)

// Cooldowns remembers the last fill request per room.
type Cooldowns struct {
	mu   sync.Mutex
	last map[string]time.Time
}

// NewCooldowns creates an empty tracker.
func NewCooldowns() *Cooldowns { return &Cooldowns{last: map[string]time.Time{}} }

// Record notes a fill request for roomID at now.
func (c *Cooldowns) Record(roomID string, now time.Time) {
	c.mu.Lock()
	c.last[roomID] = now
	c.mu.Unlock()
}

// Recent reports whether roomID had a request within d of now.
func (c *Cooldowns) Recent(roomID string, now time.Time, d time.Duration) bool {
	c.mu.Lock()
	defer c.mu.Unlock()
	t, ok := c.last[roomID]
	return ok && now.Sub(t) < d
}

// Prune forgets entries older than d.
func (c *Cooldowns) Prune(now time.Time, d time.Duration) {
	c.mu.Lock()
	for k, t := range c.last {
		if now.Sub(t) >= d {
			delete(c.last, k)
		}
	}
	c.mu.Unlock()
}

// PlanFills decides which lobbies to fill and with how many bots.
//
// A lobby is filled only when ALL hold: fill is enabled for its game (both
// bots.games and public_matchmaking.per_game); it has waited >=
// fill_after_seconds and < maximum_wait_seconds; it has >= minimum_humans
// humans; it has no pendingBots; no request for it was made within
// refill_cooldown_seconds. The count is
// min(free seats, max_bots_per_room - bots, global headroom, game headroom)
// where free seats = capacity - humans - bots - pendingBots. Lobbies that
// waited longest are served first.
func PlanFills(lobbies []client.Lobby, p FillParams, cd *Cooldowns, now time.Time) (plan []FillRequest, skipped map[string]SkipReason) {
	skipped = map[string]SkipReason{}
	if !p.Enabled {
		for _, l := range lobbies {
			skipped[l.RoomID] = SkipDisabled
		}
		return nil, skipped
	}
	sorted := append([]client.Lobby(nil), lobbies...)
	sort.SliceStable(sorted, func(i, j int) bool { return sorted[i].WaitingMS > sorted[j].WaitingMS })
	headroom := p.Headroom
	gameRoom := map[string]int{}
	for k, v := range p.GameHeadroom {
		gameRoom[k] = v
	}
	for _, l := range sorted {
		key := config.GameKey(l.Game, l.Variant)
		waited := time.Duration(l.WaitingMS) * time.Millisecond
		free := l.Capacity - l.Humans - l.Bots - l.PendingBots
		roomBots := p.MaxBotsPerRoom - l.Bots - l.PendingBots
		switch {
		case l.RoomID == "" || l.Capacity < 2 || l.Capacity > 4:
			skipped[l.RoomID] = SkipInvalidLobby
			continue
		case key == "":
			skipped[l.RoomID] = SkipUnknownGame
			continue
		case !p.PerGame[key] || !p.Games[key]:
			skipped[l.RoomID] = SkipGameDisabled
			continue
		case l.PendingBots > 0:
			skipped[l.RoomID] = SkipPending
			continue
		case waited < p.FillAfter:
			skipped[l.RoomID] = SkipTooEarly
			continue
		case waited >= p.MaximumWait:
			skipped[l.RoomID] = SkipTooLate
			continue
		case l.Humans < p.MinimumHumans:
			skipped[l.RoomID] = SkipFewHumans
			continue
		case cd != nil && cd.Recent(l.RoomID, now, p.RefillCooldown):
			skipped[l.RoomID] = SkipCooldown
			continue
		case free <= 0:
			skipped[l.RoomID] = SkipNoSeats
			continue
		case roomBots <= 0:
			skipped[l.RoomID] = SkipRoomBotLimit
			continue
		}
		count := min(free, roomBots, headroom, gameRoom[key])
		if count <= 0 {
			skipped[l.RoomID] = SkipNoHeadroom
			continue
		}
		headroom -= count
		gameRoom[key] -= count
		plan = append(plan, FillRequest{RoomID: l.RoomID, Game: key, Count: count})
	}
	return plan, skipped
}
