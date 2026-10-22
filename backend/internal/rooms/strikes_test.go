package rooms

import (
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"testing"
	"time"

	"ludoarena/internal/config"
	"ludoarena/internal/game/ludo"
	"ludoarena/internal/protocol"
)

// strikeHarness drives a two-player Ludo room in memory (no Redis): each
// step runs one mutation exactly like the WebSocket command / scheduler
// paths do inside s.mutate.
type strikeHarness struct {
	t   *testing.T
	s   *Service
	r   *Room
	now time.Time
}

type sentEvent struct {
	T string          `json:"t"`
	P json.RawMessage `json:"p"`
}

func newStrikeHarness(t *testing.T, maxStrikes int) *strikeHarness {
	t.Helper()
	h := &strikeHarness{t: t, now: time.UnixMilli(1_761_000_000_000)}
	h.s = New(Deps{
		Game: config.GameConfig{TurnTimeout: 20 * time.Second, TurnTimeoutDisconnected: 8 * time.Second,
			MaxStrikes: maxStrikes, RematchWindow: 30 * time.Second},
		Dice: NewSeededDice(11),
		Now:  func() time.Time { return h.now },
	})
	st, err := ludo.New(2, ludo.Classic)
	if err != nil {
		t.Fatal(err)
	}
	h.r = &Room{ID: "r_strikes", Game: GameLudo, Variant: string(ludo.Classic), Mode: ModePublic,
		Capacity: 2, Status: StatusPlaying, Round: 1, Ludo: st,
		Deadline: h.now.Add(20 * time.Second).UnixMilli()}
	for i := 0; i < 2; i++ {
		h.r.Players = append(h.r.Players, Player{UserID: fmt.Sprintf("user-%d", i), UID: fmt.Sprintf("u_%d", i),
			Name: fmt.Sprintf("P%d", i), Connected: true})
	}
	return h
}

func (h *strikeHarness) do(f func(m *mutation) error) []sentEvent {
	h.t.Helper()
	m := &mutation{s: h.s, r: h.r}
	if err := f(m); err != nil && !errors.Is(err, errNoop) {
		h.t.Fatalf("mutation: %v", err)
	}
	out := make([]sentEvent, 0, len(m.msgs))
	for _, raw := range m.msgs {
		var e sentEvent
		if err := json.Unmarshal(raw, &e); err != nil {
			h.t.Fatalf("event %s: %v", raw, err)
		}
		out = append(out, e)
	}
	return out
}

// timeout lets the current turn's deadline pass and fires its timer.
func (h *strikeHarness) timeout() []sentEvent {
	h.now = time.UnixMilli(h.r.Deadline).Add(time.Second)
	_, seq, _, _, _, _ := h.r.turnInfo()
	return h.do(func(m *mutation) error { return h.s.turnTimedOut(m, seq) })
}

// act makes the turn owner roll, and move when it has to choose a token.
func (h *strikeHarness) act() []sentEvent {
	seat, seq, phase, _, legal, _ := h.r.turnInfo()
	uid := h.r.Players[seat].UserID
	h.now = h.now.Add(time.Second)
	if phase == PhaseAwaitingMove {
		return h.do(func(m *mutation) error { return h.s.move(m, uid, seq, legal[0]) })
	}
	evs := h.do(func(m *mutation) error { return h.s.roll(m, uid, seq) })
	if s2, seq2, phase2, _, legal2, _ := h.r.turnInfo(); s2 == seat && phase2 == PhaseAwaitingMove && h.r.Status == StatusPlaying {
		h.now = h.now.Add(time.Second)
		evs = append(evs, h.do(func(m *mutation) error { return h.s.move(m, uid, seq2, legal2[0]) })...)
	}
	return evs
}

// untilSeat lets seat 0 play until it is [seat]'s turn.
func (h *strikeHarness) untilSeat(seat int) {
	h.t.Helper()
	for i := 0; i < 50; i++ {
		if s, _, _, _, _, _ := h.r.turnInfo(); s == seat || h.r.Status != StatusPlaying {
			return
		}
		h.act()
	}
	h.t.Fatalf("seat %d never got the turn", seat)
}

func findEvent(evs []sentEvent, t string) (sentEvent, bool) {
	for _, e := range evs {
		if e.T == t {
			return e, true
		}
	}
	return sentEvent{}, false
}

type forfeitPayload struct {
	Seat    int    `json:"seat"`
	Reason  string `json:"reason"`
	Strikes *int   `json:"strikes"`
}

func TestForfeitAfterMaxConsecutiveTimeouts(t *testing.T) {
	for _, max := range []int{1, 3, config.DefaultMaxStrikes} {
		t.Run(fmt.Sprintf("max_%d", max), func(t *testing.T) {
			h := newStrikeHarness(t, max)
			for missed := 1; missed <= max; missed++ {
				h.untilSeat(1)
				if h.r.Status != StatusPlaying {
					t.Fatalf("game ended before %d missed turns", missed)
				}
				evs := h.timeout()
				p := h.r.Players[1]
				fe, forfeited := findEvent(evs, protocol.TPlayerForfeited)
				if missed < max {
					if forfeited || p.Forfeited || p.Strikes != missed {
						t.Fatalf("after %d missed turns: forfeited=%v strikes=%d", missed, p.Forfeited, p.Strikes)
					}
					// The server played for the player and reported the strike.
					de, ok := findEvent(evs, protocol.TDiceResult)
					var d struct {
						Seat, Strikes int
						Auto          bool
					}
					if !ok || json.Unmarshal(de.P, &d) != nil || d.Seat != 1 || !d.Auto || d.Strikes != missed {
						t.Fatalf("auto roll after %d missed turns: %s", missed, de.P)
					}
					if pv := h.r.View().Players[1]; pv.ForfeitWhy != "" || pv.Strikes != missed {
						t.Fatalf("view after %d missed turns: %+v", missed, pv)
					}
					continue
				}
				if !forfeited || !p.Forfeited || p.ForfeitWhy != "timeouts" {
					t.Fatalf("not forfeited after %d missed turns: %+v", missed, p)
				}
				var fp forfeitPayload
				if err := json.Unmarshal(fe.P, &fp); err != nil {
					t.Fatal(err)
				}
				if fp.Seat != 1 || fp.Reason != "timeouts" || fp.Strikes == nil || *fp.Strikes != max {
					t.Fatalf("player.forfeited payload %s", fe.P)
				}
				if _, auto := findEvent(evs, protocol.TDiceResult); auto {
					t.Fatal("the forfeiting timeout must not roll for the player")
				}
				v := h.r.View()
				if pv := v.Players[1]; !pv.Forfeited || pv.ForfeitWhy != "timeouts" || pv.Strikes != max {
					t.Fatalf("view after forfeit: %+v", pv)
				}
				if pv := v.Players[0]; pv.ForfeitWhy != "" {
					t.Fatalf("active player has forfeitWhy %q", pv.ForfeitWhy)
				}
				// forfeitWhy is not part of the state hash.
				if v.H != h.r.Ludo.Hash() {
					t.Fatalf("snapshot h %d != engine hash %d", v.H, h.r.Ludo.Hash())
				}
				// Two players: the remaining one wins by forfeit.
				if h.r.Status != StatusFinished || h.r.Result == nil || h.r.Result.Reason != "forfeit" || h.r.Result.WinnerSeat != 0 {
					t.Fatalf("result after forfeit: status=%s %+v", h.r.Status, h.r.Result)
				}
			}
		})
	}
}

func TestOwnActionResetsStrikes(t *testing.T) {
	h := newStrikeHarness(t, config.DefaultMaxStrikes)
	miss := func(n int) {
		t.Helper()
		for i := 0; i < n; i++ {
			h.untilSeat(1)
			h.timeout()
		}
	}
	miss(config.DefaultMaxStrikes - 1)
	if p := h.r.Players[1]; p.Forfeited || p.Strikes != config.DefaultMaxStrikes-1 {
		t.Fatalf("before acting: %+v", p)
	}
	h.untilSeat(1)
	evs := h.act()
	de, ok := findEvent(evs, protocol.TDiceResult)
	var d struct{ Seat, Strikes int }
	if !ok || json.Unmarshal(de.P, &d) != nil || d.Seat != 1 || d.Strikes != 0 {
		t.Fatalf("own roll: %s", de.P)
	}
	if p := h.r.Players[1]; p.Strikes != 0 {
		t.Fatalf("strikes after an own action = %d", p.Strikes)
	}
	// Strikes count consecutive misses only: it takes MAX_STRIKES more.
	miss(config.DefaultMaxStrikes - 1)
	if p := h.r.Players[1]; p.Forfeited || p.Strikes != config.DefaultMaxStrikes-1 {
		t.Fatalf("forfeited before %d consecutive misses: %+v", config.DefaultMaxStrikes, p)
	}
	h.untilSeat(1)
	evs = h.timeout()
	if _, ok := findEvent(evs, protocol.TPlayerForfeited); !ok || !h.r.Players[1].Forfeited {
		t.Fatalf("not forfeited after %d consecutive misses", config.DefaultMaxStrikes)
	}
}

func TestLeftForfeitCarriesStrikes(t *testing.T) {
	h := newStrikeHarness(t, config.DefaultMaxStrikes)
	h.untilSeat(1)
	h.timeout()
	h.untilSeat(1)
	h.timeout()
	evs := h.do(func(m *mutation) error { return h.s.forfeit(m, 1, "left") })
	fe, ok := findEvent(evs, protocol.TPlayerForfeited)
	var fp forfeitPayload
	if !ok || json.Unmarshal(fe.P, &fp) != nil || fp.Reason != "left" || fp.Strikes == nil || *fp.Strikes != 2 {
		t.Fatalf("left forfeit payload %s", fe.P)
	}
	if pv := h.r.View().Players[1]; pv.ForfeitWhy != "left" {
		t.Fatalf("view forfeitWhy %q", pv.ForfeitWhy)
	}
}

func TestPlayerViewForfeitWhyOnlyForForfeitedSeats(t *testing.T) {
	r := &Room{ID: "r_v", Game: GameLudo, Status: StatusFinished, Players: []Player{
		{UID: "u_0", Forfeited: true, ForfeitWhy: "timeouts", Strikes: 5},
		{UID: "u_1", ForfeitWhy: "left"}, // left the finished room: not a forfeit
		{UID: "u_2"},
	}}
	raw, err := json.Marshal(r.View())
	if err != nil {
		t.Fatal(err)
	}
	var v struct {
		Players []map[string]any `json:"players"`
	}
	if err := json.Unmarshal(raw, &v); err != nil {
		t.Fatal(err)
	}
	if got := v.Players[0]["forfeitWhy"]; got != "timeouts" {
		t.Fatalf("forfeited seat forfeitWhy = %v", got)
	}
	for _, i := range []int{1, 2} {
		if _, ok := v.Players[i]["forfeitWhy"]; ok {
			t.Fatalf("seat %d must omit forfeitWhy: %s", i, raw)
		}
	}
	if !strings.Contains(string(raw), `"strikes":5`) {
		t.Fatalf("strikes missing: %s", raw)
	}
}
