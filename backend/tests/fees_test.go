package tests

import (
	"fmt"
	"os"
	"strings"
	"testing"
	"time"

	"ludoroyale/internal/rooms"
)

// policyWithFees is the test policy plus an "entryFees" object (raw JSON).
func policyWithFees(fees string) string {
	base := policyJSON("1.0.0", 1, "1.0.0", 1, false)
	out := strings.Replace(base, `"environment":"development",`, `"environment":"development","entryFees":`+fees+`,`, 1)
	if out == base {
		panic("policyWithFees: environment marker not found")
	}
	return out
}

// appConfigFees reads the live entry fees from GET /app/config.
func (e *env) appConfigFees(t *testing.T) (ludo, snakes int64) {
	t.Helper()
	r := e.do("GET", "/api/v1/app/config?platform=android&version=1.0.0&build=1", "", nil)
	fees, ok := r.Body["entryFees"].(map[string]any)
	if r.Status != 200 || !ok || len(fees) != 2 {
		t.Fatalf("app config entryFees: %d %s", r.Status, r.Raw)
	}
	return int64(fees["ludo"].(float64)), int64(fees["snakes_ladders"].(float64))
}

func (e *env) wantAppConfigFees(t *testing.T, ludo, snakes int64) {
	t.Helper()
	if l, s := e.appConfigFees(t); l != ludo || s != snakes {
		t.Fatalf("/app/config entryFees = ludo %d snakes %d, want %d / %d", l, s, ludo, snakes)
	}
}

// reloadPolicy writes the policy file and applies it like SIGHUP does.
func (e *env) reloadPolicy(t *testing.T, body string) error {
	t.Helper()
	writeFile(t, e.policy, body)
	return e.app.Policy.Reload()
}

// TestEntryFeesLiveFromPolicy covers the entry-fee contract: built-in
// defaults, live changes from the app-policy file (explicit reload and file
// polling), rooms keeping the fee they were created with, matchmaking never
// mixing fees, the insufficient-funds path and free practice.
func TestEntryFeesLiveFromPolicy(t *testing.T) {
	e := newEnv(t, envOpts{dice: rooms.NewSeededDice(5)})
	welcome := e.app.Cfg.Wallet.WelcomeCoins
	if welcome < 100_000 {
		t.Fatalf("welcome grant %d cannot cover the default Ludo fee", welcome)
	}

	// Defaults: the test policy has no entryFees and ENTRY_FEE_* are unset.
	e.wantAppConfigFees(t, 100_000, 50_000)

	// A private Snakes room and a public Ludo lobby opened at the defaults.
	host, friend := e.guest(), e.guest()
	hc, fc := e.mustDial("host", host), e.mustDial("friend", friend)
	if r := hc.call("room.create", map[string]any{"game": "snakes_ladders", "capacity": 2}); r.T != "ack" {
		t.Fatalf("create: %s %s", r.T, r.P)
	}
	waitFor(t, 3*time.Second, "private lobby", func() bool { return hc.snapshot() != nil && hc.snapshot().Code != "" })
	oldRoom := hc.snapshot()
	if oldRoom.EntryFee != 50_000 {
		t.Fatalf("private snakes room fee = %d, want 50000", oldRoom.EntryFee)
	}
	if r := fc.call("room.join", map[string]any{"code": oldRoom.Code}); r.T != "room.updated" {
		t.Fatalf("join: %s %s", r.T, r.P)
	}
	waiter := e.mustDial("waiter", e.guest())
	if r := waiter.call("matchmaking.join", map[string]any{"game": "ludo", "variant": "classic", "capacity": 2}); r.T != "matchmaking.status" {
		t.Fatalf("matchmaking.join: %s %s", r.T, r.P)
	}
	waitFor(t, 3*time.Second, "public lobby", func() bool { return waiter.snapshot() != nil })
	oldLobby := waiter.snapshot()
	if oldLobby.EntryFee != 100_000 {
		t.Fatalf("public ludo lobby fee = %d, want 100000", oldLobby.EntryFee)
	}

	// The operator raises both fees in the policy file: applied without a
	// restart and served by /app/config.
	if err := e.reloadPolicy(t, policyWithFees(`{"ludo":150000,"snakes_ladders":70000}`)); err != nil {
		t.Fatal(err)
	}
	e.wantAppConfigFees(t, 150_000, 70_000)

	// The existing private room keeps the fee it was created with.
	waitFor(t, 3*time.Second, "both connected", func() bool {
		s := hc.snapshot()
		return len(s.Players) == 2 && s.Players[0].Connected && s.Players[1].Connected
	})
	if r := hc.call("game.start", map[string]any{"roomId": oldRoom.ID}); r.T != "ack" {
		t.Fatalf("start: %s %s", r.T, r.P)
	}
	waitFor(t, 5*time.Second, "old room playing", func() bool { return hc.snapshot().Status == "playing" })
	if s := hc.snapshot(); s.EntryFee != 50_000 || s.Pot != 100_000 {
		t.Fatalf("existing room changed fee: entryFee %d pot %d", s.EntryFee, s.Pot)
	}
	for _, a := range []account{host, friend} {
		if got := e.coins(a.Token); got != welcome-50_000 {
			t.Fatalf("existing room debit: coins %d, want %d", got, welcome-50_000)
		}
	}

	// New rooms use the live fee. Matchmaking skips the lobby opened at the
	// old fee, so the two new players are matched with each other at 70,000.
	cs := startPublic(t, e, "ludo", "classic", 2)
	if s := cs[0].snapshot(); s.ID == oldLobby.ID || s.EntryFee != 150_000 || s.Pot != 300_000 {
		t.Fatalf("new public room: id %s (old %s) entryFee %d pot %d", s.ID, oldLobby.ID, s.EntryFee, s.Pot)
	}
	for _, c := range cs {
		if got := e.coins(c.acct.Token); got != welcome-150_000 {
			t.Fatalf("%s coins after start = %d, want %d", c.name, got, welcome-150_000)
		}
	}
	if s := waiter.snapshot(); s.Status != "lobby" || len(s.Players) != 1 || s.EntryFee != 100_000 {
		t.Fatalf("old-fee lobby was joined or changed: status %s players %d fee %d", s.Status, len(s.Players), s.EntryFee)
	}
	h2 := e.mustDial("host2", e.guest())
	if r := h2.call("room.create", map[string]any{"game": "snakes_ladders", "capacity": 3}); r.T != "ack" {
		t.Fatalf("create 2: %s %s", r.T, r.P)
	}
	waitFor(t, 3*time.Second, "new private lobby", func() bool { return h2.snapshot() != nil })
	if fee := h2.snapshot().EntryFee; fee != 70_000 {
		t.Fatalf("new private snakes room fee = %d, want 70000", fee)
	}

	// Hot reload by file polling alone (APP_POLICY_POLL_SECONDS=1s here). A
	// game left out of entryFees falls back to ENTRY_FEE_* / the default.
	writeFile(t, e.policy, policyWithFees(`{"ludo":120000}`))
	future := time.Now().Add(2 * time.Second)
	if err := os.Chtimes(e.policy, future, future); err != nil {
		t.Fatal(err)
	}
	waitFor(t, 10*time.Second, "polled policy reload", func() bool {
		l, s := e.appConfigFees(t)
		return l == 120_000 && s == 50_000
	})
	if e.app.Rooms.EntryFee("ludo") != 120_000 || e.app.Rooms.EntryFee("snakes_ladders") != 50_000 {
		t.Fatalf("rooms see stale fees: %v", e.app.Rooms.EntryFees())
	}

	// An invalid file is rejected as a whole; the last good fees stay live.
	if err := e.reloadPolicy(t, policyWithFees(`{"ludo":-1,"snakes_ladders":40000}`)); err == nil {
		t.Fatal("negative fee accepted")
	}
	if err := e.reloadPolicy(t, policyWithFees(`{"chess":10}`)); err == nil {
		t.Fatal("unknown game accepted")
	}
	e.wantAppConfigFees(t, 120_000, 50_000)

	// A fee above the player's balance: matchmaking and room creation are
	// refused with insufficient_funds; practice stays free.
	over := welcome + 1
	if err := e.reloadPolicy(t, policyWithFees(fmt.Sprintf(`{"ludo":%d,"snakes_ladders":%d}`, over, over))); err != nil {
		t.Fatal(err)
	}
	poor := e.guest()
	pc := e.mustDial("poor", poor)
	if r := pc.call("matchmaking.join", map[string]any{"game": "ludo", "variant": "quick", "capacity": 2}); r.T != "error" || !strings.Contains(string(r.P), "insufficient_funds") {
		t.Fatalf("matchmaking with too few coins: %s %s", r.T, r.P)
	}
	if r := pc.call("room.create", map[string]any{"game": "snakes_ladders", "capacity": 2}); r.T != "error" || !strings.Contains(string(r.P), "insufficient_funds") {
		t.Fatalf("room.create with too few coins: %s %s", r.T, r.P)
	}
	if r := pc.call("practice.start", map[string]any{"game": "ludo", "variant": "quick", "bots": 1}); r.T != "ack" {
		t.Fatalf("practice.start: %s %s", r.T, r.P)
	}
	waitFor(t, 3*time.Second, "practice lobby", func() bool { return pc.snapshot() != nil })
	if s := pc.snapshot(); s.Mode != "practice" || s.EntryFee != 0 {
		t.Fatalf("practice room: mode %s entryFee %d", s.Mode, s.EntryFee)
	}
	if got := e.coins(poor.Token); got != welcome {
		t.Fatalf("refused/free actions changed coins: %d", got)
	}
}
