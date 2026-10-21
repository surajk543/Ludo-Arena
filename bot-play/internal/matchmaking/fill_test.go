package matchmaking

import (
	"testing"
	"time"

	"ludoroyale/botplay/internal/client"
	"ludoroyale/botplay/internal/config"
)

func params() FillParams {
	all := map[string]bool{config.GameLudo: true, config.GameLudoQuick: true, config.GameSnakes: true}
	return FillParams{
		Enabled: true, PerGame: all, Games: all,
		FillAfter: 10 * time.Second, MaximumWait: 28 * time.Second, MinimumHumans: 1,
		MaxBotsPerRoom: 3, RefillCooldown: 10 * time.Second, Headroom: 100,
		GameHeadroom: map[string]int{config.GameLudo: 100, config.GameLudoQuick: 100, config.GameSnakes: 100},
	}
}

func lobby(id string, capacity, humans, bots, pending int, waited time.Duration) client.Lobby {
	return client.Lobby{RoomID: id, Game: "ludo", Variant: "classic", Capacity: capacity, Humans: humans, Bots: bots,
		PendingBots: pending, WaitingMS: waited.Milliseconds()}
}

func TestFillRespectsCapacityAndRoomLimit(t *testing.T) {
	now := time.Now()
	p := params()
	p.MaxBotsPerRoom = 2
	lobbies := []client.Lobby{
		lobby("a", 4, 1, 0, 0, 15*time.Second), // free 3, room limit 2 -> 2
		lobby("b", 2, 1, 0, 0, 15*time.Second), // free 1 -> 1
		lobby("c", 4, 2, 1, 0, 15*time.Second), // free 1, room limit 2-1=1 -> 1
		lobby("d", 4, 1, 2, 0, 15*time.Second), // free 1 but room limit reached
		lobby("e", 2, 2, 0, 0, 15*time.Second), // full
	}
	plan, skipped := PlanFills(lobbies, p, NewCooldowns(), now)
	got := map[string]int{}
	for _, r := range plan {
		got[r.RoomID] = r.Count
	}
	want := map[string]int{"a": 2, "b": 1, "c": 1}
	if len(got) != len(want) {
		t.Fatalf("plan %v skipped %v", got, skipped)
	}
	for k, v := range want {
		if got[k] != v {
			t.Fatalf("room %s: got %d want %d (plan %v)", k, got[k], v, got)
		}
	}
	if skipped["d"] != SkipRoomBotLimit || skipped["e"] != SkipNoSeats {
		t.Fatalf("skips: %v", skipped)
	}
	for _, l := range lobbies {
		free := l.Capacity - l.Humans - l.Bots - l.PendingBots
		if got[l.RoomID] > free || got[l.RoomID]+l.Bots > p.MaxBotsPerRoom {
			t.Fatalf("over capacity for %s", l.RoomID)
		}
	}
}

func TestFillSkips(t *testing.T) {
	now := time.Now()
	cd := NewCooldowns()
	cd.Record("cool", now.Add(-5*time.Second))
	p := params()
	p.PerGame = map[string]bool{config.GameLudo: true, config.GameSnakes: false, config.GameLudoQuick: true}
	p.MinimumHumans = 2
	lobbies := []client.Lobby{
		lobby("pending", 4, 2, 0, 1, 15*time.Second),
		lobby("early", 4, 2, 0, 0, 5*time.Second),
		lobby("late", 4, 2, 0, 0, 29*time.Second),
		lobby("lonely", 4, 1, 0, 0, 15*time.Second),
		lobby("cool", 4, 2, 0, 0, 15*time.Second),
		{RoomID: "snakes", Game: "snakes_ladders", Variant: "classic", Capacity: 4, Humans: 2, WaitingMS: 15000},
		{RoomID: "chess", Game: "chess", Capacity: 4, Humans: 2, WaitingMS: 15000},
	}
	plan, skipped := PlanFills(lobbies, p, cd, now)
	if len(plan) != 0 {
		t.Fatalf("nothing should be filled: %v", plan)
	}
	want := map[string]SkipReason{"pending": SkipPending, "early": SkipTooEarly, "late": SkipTooLate,
		"lonely": SkipFewHumans, "cool": SkipCooldown, "snakes": SkipGameDisabled, "chess": SkipUnknownGame}
	for id, r := range want {
		if skipped[id] != r {
			t.Errorf("%s: got %q want %q", id, skipped[id], r)
		}
	}
	// After the cooldown the room is eligible again.
	if !cd.Recent("cool", now, 10*time.Second) || cd.Recent("cool", now.Add(6*time.Second), 10*time.Second) {
		t.Fatal("cooldown window")
	}
	p.Enabled = false
	if plan, _ := PlanFills([]client.Lobby{lobby("x", 4, 2, 0, 0, 15*time.Second)}, p, cd, now); len(plan) != 0 {
		t.Fatal("disabled must not plan")
	}
}

func TestFillHeadroomAndOrder(t *testing.T) {
	now := time.Now()
	p := params()
	p.Headroom = 3
	p.GameHeadroom[config.GameLudo] = 3
	lobbies := []client.Lobby{
		lobby("newer", 4, 1, 0, 0, 12*time.Second),
		lobby("older", 4, 1, 0, 0, 20*time.Second),
	}
	plan, _ := PlanFills(lobbies, p, nil, now)
	if len(plan) != 1 || plan[0].RoomID != "older" || plan[0].Count != 3 {
		t.Fatalf("oldest lobby first within headroom: %+v", plan)
	}
	p.Headroom = 10
	p.GameHeadroom[config.GameLudo] = 1
	plan, _ = PlanFills(lobbies, p, nil, now)
	if len(plan) != 1 || plan[0].Count != 1 {
		t.Fatalf("per-game headroom: %+v", plan)
	}
}

func TestMix(t *testing.T) {
	m := NewMix(map[string]float64{"ludo": 1, "snakes_ladders": 1, "ludo_quick": 0}, map[int]float64{2: 1, 4: 3}, map[string]bool{"ludo": true, "snakes_ladders": false})
	c, ok := m.Pick(0.99, 0.0)
	if !ok || c.GameKey != "ludo" || c.Game != "ludo" || c.Variant != "classic" || c.Capacity != 2 {
		t.Fatalf("pick: %+v", c)
	}
	if c, _ := m.Pick(0.1, 0.9); c.Capacity != 4 {
		t.Fatalf("capacity weight: %+v", c)
	}
	if !NewMix(map[string]float64{"ludo": 1}, map[int]float64{2: 1}, map[string]bool{"ludo": false}).Empty() {
		t.Fatal("disabled games must be excluded")
	}
}
