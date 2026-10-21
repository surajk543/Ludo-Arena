package rooms

import (
	"encoding/json"
	"testing"

	"github.com/google/uuid"
)

// A persona's id depends only on (pool, name, slot): it survives a Redis
// flush, so the persona keeps its uid and its coin wallet row.
func TestPersonaIDIsStableAndDistinct(t *testing.T) {
	a := personaID(poolPublic, "Asha", 0)
	if a == uuid.Nil || a != personaID(poolPublic, " ASHA ", 0) {
		t.Fatal("persona ids are stable and case-insensitive")
	}
	if a.Version() != 5 {
		t.Fatalf("version %d, want a UUIDv5", a.Version())
	}
	seen := map[uuid.UUID]bool{}
	for _, pool := range []string{poolPublic, poolKnown} {
		for _, name := range []string{"Asha", "Ravi"} {
			for slot := 0; slot < personaSlots; slot++ {
				id := personaID(pool, name, slot)
				if seen[id] {
					t.Fatalf("duplicate persona id for %s/%s/%d", pool, name, slot)
				}
				seen[id] = true
			}
		}
	}
}

// Public and private rooms charge every seat, bots included; practice and
// load-test rooms are free.
func TestRoomFee(t *testing.T) {
	cases := []struct {
		name string
		r    Room
		want int64
	}{
		{"public with a bot", Room{Mode: ModePublic, EntryFee: 100_000, Players: []Player{{}, {Bot: true}}}, 100_000},
		{"public people only", Room{Mode: ModePublic, EntryFee: 100_000, Players: []Player{{}, {}}}, 100_000},
		{"private with a bot", Room{Mode: ModePrivate, EntryFee: 50_000, Players: []Player{{}, {Bot: true}}}, 50_000},
		{"practice", Room{Mode: ModePractice, EntryFee: 100_000, Players: []Player{{}, {Bot: true}}}, 0},
		{"load test", Room{Mode: ModePublic, EntryFee: 100_000, LoadTest: true}, 0},
	}
	for _, c := range cases {
		if got := roomFee(&c.r); got != c.want {
			t.Errorf("%s: fee %d, want %d", c.name, got, c.want)
		}
	}
	r := Room{Players: []Player{{UserID: uuid.NewString()}, {UserID: uuid.NewString(), Bot: true}, {UserID: uuid.NewString()}}}
	people, bots := seatIDs(&r)
	if len(people) != 2 || len(bots) != 1 || bots[0].String() != r.Players[1].UserID {
		t.Fatalf("seat ids %v %v", people, bots)
	}
}

// A bot seat pays into the pot and, winning, takes it like a person; the
// payout is scheduled for its wallet and the results carry the same payout
// as an all-human match.
func TestBotSeatPaysAndWinsThePot(t *testing.T) {
	h := newStrikeHarness(t, 3)
	h.r.Players[1].Bot = true
	h.r.Status = StatusLobby
	const fee = 100_000
	h.do(func(m *mutation) error { return h.s.beginRound(m, fee) })
	if h.r.Pot != 2*fee || h.r.Players[0].FeePaid != fee || h.r.Players[1].FeePaid != fee {
		t.Fatalf("pot %d fees %d/%d", h.r.Pot, h.r.Players[0].FeePaid, h.r.Players[1].FeePaid)
	}
	// The person leaves: the bot wins the pot.
	var ops []sideOp
	evs := h.do(func(m *mutation) error {
		err := h.s.forfeit(m, 0, "left")
		ops = m.ops
		return err
	})
	if h.r.Status != StatusFinished || h.r.Result == nil || h.r.Result.WinnerSeat != 1 || h.r.Result.Payout != 2*fee {
		t.Fatalf("result %+v", h.r.Result)
	}
	scheduled := false
	for _, o := range ops {
		if o.Op == "zadd" && o.K == schedKey && o.V == "payout|"+h.r.ID+"|1" {
			scheduled = true
		}
	}
	if !scheduled {
		t.Fatalf("no payout scheduled for the bot winner: %+v", ops)
	}
	fin, ok := findEvent(evs, "game.finished")
	if !ok {
		t.Fatal("no game.finished")
	}
	var p struct {
		Result struct {
			Payout int64 `json:"payout"`
		} `json:"result"`
	}
	if err := json.Unmarshal(fin.P, &p); err != nil || p.Result.Payout != 2*fee {
		t.Fatalf("game.finished payout: %s", fin.P)
	}
	mustHaveNoBotKey(t, "game.finished", fin.P)
}
