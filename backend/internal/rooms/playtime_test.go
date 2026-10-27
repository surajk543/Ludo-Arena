package rooms

import (
	"context"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/google/uuid"

	"ludoarena/internal/game/ludo"
	"ludoarena/internal/protocol"
)

// fakePlaytime records the intervals the engine reports.
type fakePlaytime struct {
	mu    sync.Mutex
	calls []ptCall
}

type ptCall struct {
	user     uuid.UUID
	from, to time.Time
	final    bool
}

func (f *fakePlaytime) AddPlaytime(_ context.Context, userID uuid.UUID, from, to time.Time, final bool) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.calls = append(f.calls, ptCall{user: userID, from: from, to: to, final: final})
}

func (f *fakePlaytime) of(id string) []ptCall {
	f.mu.Lock()
	defer f.mu.Unlock()
	var out []ptCall
	for _, c := range f.calls {
		if c.user.String() == id {
			out = append(out, c)
		}
	}
	return out
}

// total sums a user's credited play and fails on overlapping intervals.
func (f *fakePlaytime) total(t *testing.T, id string) time.Duration {
	t.Helper()
	var sum time.Duration
	var last time.Time
	for _, c := range f.of(id) {
		if c.from.Before(last) {
			t.Fatalf("overlapping intervals for %s: %v starts before %v", id, c.from, last)
		}
		if !c.to.After(c.from) {
			t.Fatalf("empty interval %v..%v", c.from, c.to)
		}
		sum += c.to.Sub(c.from)
		last = c.to
	}
	return sum
}

// newPlayHarness is a two-seat Ludo room in the lobby with playtime
// tracking; seat 1 is a bot when bot is set.
func newPlayHarness(t *testing.T, bot bool) (*strikeHarness, *fakePlaytime) {
	t.Helper()
	h := newStrikeHarness(t, 5)
	sink := &fakePlaytime{}
	h.s.Playtime = sink
	h.s.Game.PlaytimeIdleStrikes = 1
	h.s.Game.PlaytimeCheckpoint = time.Minute
	h.runAfter = true
	h.r.Status = StatusLobby
	h.r.Mode = ModePractice
	for i := range h.r.Players {
		h.r.Players[i].UserID = uuid.NewString()
	}
	h.r.Players[1].Bot = bot
	return h, sink
}

func (h *strikeHarness) start() {
	h.t.Helper()
	h.do(func(m *mutation) error { return h.s.beginRound(m, 0) })
	if h.r.Status != StatusPlaying {
		h.t.Fatalf("status = %s", h.r.Status)
	}
}

// advance moves the clock without any room change.
func (h *strikeHarness) advance(d time.Duration) { h.now = h.now.Add(d) }

func (h *strikeHarness) uid(seat int) string { return h.r.Players[seat].UserID }

func TestPlaytimeStartsWithTheRoundNotTheLobby(t *testing.T) {
	h, sink := newPlayHarness(t, false)
	h.advance(5 * time.Minute) // lobby / matchmaking time never counts
	start := h.now
	h.start()
	for i := range h.r.Players {
		if h.r.Players[i].PlayFrom != start.UnixMilli() {
			t.Fatalf("seat %d PlayFrom = %d, want round start %d", i, h.r.Players[i].PlayFrom, start.UnixMilli())
		}
	}
	// Turn changes before the checkpoint interval credit nothing.
	h.act()
	if len(sink.calls) != 0 {
		t.Fatalf("credited before the checkpoint: %+v", sink.calls)
	}
	// The first turn change after the interval credits from the round start.
	h.advance(70 * time.Second)
	h.untilSeatChanges()
	for i := range h.r.Players {
		calls := sink.of(h.uid(i))
		if len(calls) != 1 || !calls[0].from.Equal(start) || calls[0].final {
			t.Fatalf("seat %d calls = %+v, want one checkpoint from the round start", i, calls)
		}
		if got := calls[0].to.Sub(calls[0].from); got < 70*time.Second {
			t.Fatalf("seat %d credited %s, want >= 70s", i, got)
		}
	}
}

// untilSeatChanges acts until the turn passes to another seat (one turn
// change event).
func (h *strikeHarness) untilSeatChanges() {
	h.t.Helper()
	seat, _, _, _, _, _ := h.r.turnInfo()
	for i := 0; i < 20 && h.r.Status == StatusPlaying; i++ {
		evs := h.act()
		if _, ok := findEvent(evs, protocol.TTurnChanged); ok {
			if s, _, _, _, _, _ := h.r.turnInfo(); s != seat {
				return
			}
		}
	}
}

func TestPlaytimeBotsAndLoadTestRoomsNeverAccrue(t *testing.T) {
	h, sink := newPlayHarness(t, true)
	h.start()
	if h.r.Players[1].PlayFrom != 0 {
		t.Fatal("a bot seat opened a playtime stretch")
	}
	h.advance(2 * time.Minute)
	h.untilSeatChanges()
	if len(sink.of(h.uid(1))) != 0 {
		t.Fatal("a bot seat was credited playtime")
	}
	if len(sink.of(h.uid(0))) != 1 {
		t.Fatalf("the person was not credited: %+v", sink.calls)
	}

	lt, ltSink := newPlayHarness(t, false)
	lt.r.LoadTest = true
	lt.start()
	lt.advance(2 * time.Minute)
	lt.untilSeatChanges()
	if len(ltSink.calls) != 0 || lt.r.Players[0].PlayFrom != 0 {
		t.Fatalf("load-test room accrued playtime: %+v", ltSink.calls)
	}
}

func TestPlaytimeDisconnectStopsAndReconnectResumes(t *testing.T) {
	h, sink := newPlayHarness(t, false)
	h.start()
	start := h.now
	u := h.uid(1)
	epoch := h.r.Players[1].ConnEpoch

	h.advance(30 * time.Second)
	h.do(func(m *mutation) error { return h.s.presence(m, u, false, epoch) })
	calls := sink.of(u)
	if len(calls) != 1 || !calls[0].final || !calls[0].from.Equal(start) || calls[0].to.Sub(calls[0].from) != 30*time.Second {
		t.Fatalf("disconnect credit = %+v, want final 30s from the start", calls)
	}
	// Offline for 5 minutes: turn changes credit nothing for this seat.
	h.advance(5 * time.Minute)
	h.untilSeatChanges()
	if len(sink.of(u)) != 1 {
		t.Fatalf("offline time was credited: %+v", sink.of(u))
	}
	// A duplicate disconnect of the same connection is a no-op.
	h.do(func(m *mutation) error { return h.s.presence(m, u, false, epoch) })
	back := h.now
	h.do(func(m *mutation) error { return h.s.presence(m, u, true, epoch+1) })
	if h.r.Players[1].PlayFrom != back.UnixMilli() {
		t.Fatalf("reconnect PlayFrom = %d, want %d", h.r.Players[1].PlayFrom, back.UnixMilli())
	}
	h.advance(61 * time.Second)
	h.untilSeatChanges()
	calls = sink.of(u)
	if len(calls) != 2 || !calls[1].from.Equal(back) {
		t.Fatalf("after reconnect calls = %+v, want a checkpoint from the reconnect", calls)
	}
	if got := sink.total(t, u); got > 30*time.Second+calls[1].to.Sub(back) {
		t.Fatalf("total %s includes the offline interval", got)
	}
}

func TestPlaytimeBackgroundPausesUntilForeground(t *testing.T) {
	h, sink := newPlayHarness(t, false)
	h.start()
	u := h.uid(0)
	h.advance(20 * time.Second)
	h.do(func(m *mutation) error { return h.s.setFocus(m, u, false) })
	if !h.r.Players[0].Away || h.r.Players[0].PlayFrom != 0 {
		t.Fatalf("background: away=%v playFrom=%d", h.r.Players[0].Away, h.r.Players[0].PlayFrom)
	}
	if c := sink.of(u); len(c) != 1 || !c[0].final || c[0].to.Sub(c[0].from) != 20*time.Second {
		t.Fatalf("background credit = %+v", c)
	}
	// Repeated background messages change nothing.
	h.advance(10 * time.Second)
	h.do(func(m *mutation) error { return h.s.setFocus(m, u, false) })
	h.advance(3 * time.Minute)
	h.untilSeatChanges()
	if len(sink.of(u)) != 1 {
		t.Fatalf("background time was credited: %+v", sink.of(u))
	}
	fg := h.now
	h.do(func(m *mutation) error { return h.s.setFocus(m, u, true) })
	if h.r.Players[0].Away || h.r.Players[0].PlayFrom != fg.UnixMilli() {
		t.Fatal("foreground did not resume accrual")
	}

	// A new connection also counts as foreground (the app only connects in
	// the foreground), even without app.focus.
	h.do(func(m *mutation) error { return h.s.setFocus(m, u, false) })
	h.do(func(m *mutation) error { return h.s.presence(m, u, false, h.r.Players[0].ConnEpoch) })
	h.do(func(m *mutation) error { return h.s.presence(m, u, true, h.r.Players[0].ConnEpoch+1) })
	if h.r.Players[0].Away || h.r.Players[0].PlayFrom == 0 {
		t.Fatal("a new connection did not clear away")
	}
}

func TestPlaytimeIdleAfterMissedOwnTurn(t *testing.T) {
	h, sink := newPlayHarness(t, false)
	h.start()
	u := h.uid(1)
	h.untilSeat(1)
	// Waiting for the other player never counts as idle.
	if h.r.Players[1].PlayFrom == 0 {
		t.Fatal("waiting for another player paused playtime")
	}
	h.timeout() // seat 1 misses its own turn
	if h.r.Players[1].Strikes != 1 || h.r.Players[1].PlayFrom != 0 {
		t.Fatalf("after a missed turn: strikes=%d playFrom=%d", h.r.Players[1].Strikes, h.r.Players[1].PlayFrom)
	}
	c := sink.of(u)
	if len(c) == 0 || !c[len(c)-1].final {
		t.Fatalf("missed turn did not close the stretch: %+v", c)
	}
	n := len(c)
	// Idle: later turn changes credit nothing for seat 1.
	h.advance(2 * time.Minute)
	h.untilSeat(1)
	if len(sink.of(u)) != n {
		t.Fatalf("idle time was credited: %+v", sink.of(u)[n:])
	}
	// Acting again resumes accrual at the action.
	h.act()
	if h.r.Players[1].Strikes != 0 {
		t.Fatalf("strikes = %d after acting", h.r.Players[1].Strikes)
	}
	if h.r.Status == StatusPlaying && h.r.Players[1].PlayFrom == 0 {
		t.Fatal("acting did not resume playtime")
	}
}

func TestPlaytimeForfeitAndFinishCloseEveryStretch(t *testing.T) {
	h, sink := newPlayHarness(t, false)
	h.start()
	h.advance(40 * time.Second)
	h.do(func(m *mutation) error { return h.s.forfeit(m, 1, "left") })
	c := sink.of(h.uid(1))
	if len(c) != 1 || !c[0].final || c[0].to.Sub(c[0].from) != 40*time.Second {
		t.Fatalf("forfeit credit = %+v", c)
	}
	// Two seats: the forfeit ended the game, which closed seat 0 too.
	if h.r.Status != StatusFinished {
		t.Fatalf("status = %s", h.r.Status)
	}
	for i, p := range h.r.Players {
		if p.PlayFrom != 0 {
			t.Fatalf("seat %d still accruing after the finish", i)
		}
	}
	if c := sink.of(h.uid(0)); len(c) != 1 || !c[0].final {
		t.Fatalf("finish credit = %+v", c)
	}
	// Nothing accrues in a finished room (rematch window).
	h.advance(10 * time.Minute)
	h.do(func(m *mutation) error { return h.s.presence(m, h.uid(0), true, h.r.Players[0].ConnEpoch+1) })
	if len(sink.of(h.uid(0))) != 1 || h.r.Players[0].PlayFrom != 0 {
		t.Fatal("finished room accrued playtime")
	}
}

func TestPlaytimeFinishByWinClosesStretches(t *testing.T) {
	h, sink := newPlayHarness(t, false)
	h.start()
	// Almost finished board: seat 0 has three tokens home and one a step away.
	st := h.r.Ludo
	st.Players[0].Tokens = []int{ludo.Home, ludo.Home, ludo.Home, ludo.Home - 1}
	h.advance(90 * time.Second)
	for i := 0; i < 200 && h.r.Status == StatusPlaying; i++ {
		h.act()
	}
	if h.r.Status != StatusFinished {
		t.Skip("seeded dice did not finish the game")
	}
	for i := range h.r.Players {
		c := sink.of(h.uid(i))
		if len(c) == 0 || !c[len(c)-1].final || h.r.Players[i].PlayFrom != 0 {
			t.Fatalf("seat %d: calls=%+v playFrom=%d", i, c, h.r.Players[i].PlayFrom)
		}
		sink.total(t, h.uid(i)) // no overlaps
	}
}

func TestAppFocusCommand(t *testing.T) {
	s := New(Deps{})
	out := s.Dispatch(context.Background(), Caller{UserID: uuid.NewString()},
		protocol.Inbound{T: protocol.TAppFocus, ID: "1", P: []byte(`{}`)})
	if len(out) != 1 || !containsBytes(out[0], `"bad_request"`) {
		t.Fatalf("missing foreground: %s", out)
	}
	out = s.Dispatch(context.Background(), Caller{UserID: uuid.NewString(), Bot: true},
		protocol.Inbound{T: protocol.TAppFocus, ID: "2", P: []byte(`{"foreground":false}`)})
	if len(out) != 1 || !containsBytes(out[0], `"bad_request"`) {
		t.Fatalf("bot app.focus: %s", out)
	}
	out = s.Dispatch(context.Background(), Caller{UserID: uuid.NewString()},
		protocol.Inbound{T: protocol.TAppFocus, ID: "3", P: []byte(`{"foreground":true,"seconds":600}`)})
	if len(out) != 1 || !containsBytes(out[0], `"bad_request"`) {
		t.Fatalf("unknown field accepted: %s", out)
	}
}

func containsBytes(b []byte, sub string) bool { return strings.Contains(string(b), sub) }

func TestPlaytimeFieldsStayInternal(t *testing.T) {
	h, _ := newPlayHarness(t, false)
	h.start()
	h.r.Players[0].Away = true
	raw, err := jsonMarshal(h.r.View())
	if err != nil {
		t.Fatal(err)
	}
	for _, k := range []string{"playFrom", "away"} {
		if strings.Contains(string(raw), `"`+k+`"`) {
			t.Fatalf("client view leaks %q: %s", k, raw)
		}
	}
}
