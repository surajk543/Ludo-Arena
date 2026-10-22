package matchmaking

import (
	"sort"

	"ludoarena/botplay/internal/config"
)

// Choice is one load-test matchmaking.join target.
type Choice struct {
	GameKey  string
	Game     string
	Variant  string
	Capacity int
}

// Mix picks games and capacities by relative weight.
type Mix struct {
	games      []string
	gameW      []float64
	capacities []int
	capW       []float64
}

// NewMix builds a picker from loadtest.game_mix / capacity_mix. Games
// disabled in bots.games are excluded.
func NewMix(gameMix map[string]float64, capMix map[int]float64, enabled map[string]bool) *Mix {
	m := &Mix{}
	keys := make([]string, 0, len(gameMix))
	for k := range gameMix {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	for _, k := range keys {
		if w := gameMix[k]; w > 0 && (enabled == nil || enabled[k]) {
			m.games = append(m.games, k)
			m.gameW = append(m.gameW, w)
		}
	}
	caps := make([]int, 0, len(capMix))
	for c := range capMix {
		caps = append(caps, c)
	}
	sort.Ints(caps)
	for _, c := range caps {
		if w := capMix[c]; w > 0 {
			m.capacities = append(m.capacities, c)
			m.capW = append(m.capW, w)
		}
	}
	return m
}

// Empty reports whether no game can be picked.
func (m *Mix) Empty() bool { return len(m.games) == 0 || len(m.capacities) == 0 }

// Pick chooses a game and capacity using u1, u2 uniform in [0,1).
func (m *Mix) Pick(u1, u2 float64) (Choice, bool) {
	if m.Empty() {
		return Choice{}, false
	}
	key := m.games[weighted(m.gameW, u1)]
	game, variant := config.GameVariant(key)
	return Choice{GameKey: key, Game: game, Variant: variant, Capacity: m.capacities[weighted(m.capW, u2)]}, true
}

func weighted(w []float64, u float64) int {
	total := 0.0
	for _, x := range w {
		total += x
	}
	t := u * total
	for i, x := range w {
		if t < x {
			return i
		}
		t -= x
	}
	return len(w) - 1
}
