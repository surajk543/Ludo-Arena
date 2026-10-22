package tests

import (
	"sync"
	"testing"
	"time"

	"ludoarena/botplay/tests/fakebackend"
)

func isDelta(env fakebackend.Envelope) bool {
	_, ok := env.P["v"]
	return ok && env.T != "game.state"
}

// Duplicated, stale and out-of-order deltas are ignored or trigger a resync;
// the bot still plays the game to the end with no hash mismatches.
func TestDuplicateStaleAndOutOfOrderEvents(t *testing.T) {
	t.Parallel()
	f := newFake(t, fakebackend.Options{})
	h := newHarness(t, f, nil)
	var mu sync.Mutex
	var held *fakebackend.Envelope
	n := 0
	f.SetHook(func(uid string, env fakebackend.Envelope) []fakebackend.Envelope {
		if !isDelta(env) {
			return []fakebackend.Envelope{env}
		}
		mu.Lock()
		defer mu.Unlock()
		n++
		if held != nil { // deliver the newer event first, then the held older one
			out := []fakebackend.Envelope{env, *held}
			held = nil
			return out
		}
		if n%7 == 0 && env.T != "game.finished" {
			e := env
			held = &e
			return nil
		}
		return []fakebackend.Envelope{env, env}
	})
	h.start()
	roomID := f.StartPractice(fakebackend.RoomSetup{Game: "ludo", Bots: 1, StartTokens: [][]int{{30, 40, 45, 50}, {30, 40, 45, 50}}})
	waitFor(t, 60*time.Second, "game finished", roomFinished(f, roomID))
	if h.metricValue("events_ignored_total", map[string]string{"reason": "duplicate"}) == 0 {
		t.Fatal("duplicates were not ignored")
	}
	if h.metricValue("state_resyncs_total", map[string]string{"reason": "gap"}) == 0 {
		t.Fatal("out-of-order event did not trigger a gap resync")
	}
	if h.metricValue("state_hash_mismatches_total", nil) != 0 {
		t.Fatal("hash mismatch with correct events")
	}
	uid := botUIDs(f, roomID)[0]
	if f.SyncCount(uid) < 2 {
		t.Fatalf("expected resyncs, got %d syncs", f.SyncCount(uid))
	}
}

// A missing event (gap) triggers game.request_sync and the bot recovers.
func TestGapTriggersResync(t *testing.T) {
	t.Parallel()
	f := newFake(t, fakebackend.Options{})
	h := newHarness(t, f, nil)
	var mu sync.Mutex
	turns := 0
	f.SetHook(func(uid string, env fakebackend.Envelope) []fakebackend.Envelope {
		mu.Lock()
		defer mu.Unlock()
		if env.T == "game.turn_changed" {
			turns++
			if turns == 3 {
				return nil // dropped
			}
		}
		return []fakebackend.Envelope{env}
	})
	h.start()
	roomID := f.StartPractice(fakebackend.RoomSetup{Game: "ludo", Bots: 1, StartTokens: [][]int{{30, 40, 45, 50}, {30, 40, 45, 50}}})
	waitFor(t, 60*time.Second, "game finished", roomFinished(f, roomID))
	if h.metricValue("state_resyncs_total", map[string]string{"reason": "gap"}) < 1 {
		t.Fatal("gap did not trigger a resync")
	}
	if uid := botUIDs(f, roomID)[0]; f.SyncCount(uid) < 2 {
		t.Fatalf("syncs = %d", f.SyncCount(uid))
	}
	// A dropped event that hands the turn to the bot is only detectable when
	// the next event arrives (the protocol buffers nothing), so the server may
	// auto-act once; the bot must recover right after.
	if r, _ := f.Room(roomID); r.Autos > 1 {
		t.Fatalf("bot did not recover: server auto-acted %d times", r.Autos)
	}
}

// A wrong h on a delta is detected and triggers a resync.
func TestHashMismatchTriggersResync(t *testing.T) {
	t.Parallel()
	f := newFake(t, fakebackend.Options{})
	h := newHarness(t, f, nil)
	var mu sync.Mutex
	dice := 0
	f.SetHook(func(uid string, env fakebackend.Envelope) []fakebackend.Envelope {
		mu.Lock()
		defer mu.Unlock()
		if env.T == "game.dice_result" {
			dice++
			if dice == 2 {
				env.P["h"] = uint32(12345)
			}
		}
		return []fakebackend.Envelope{env}
	})
	h.start()
	roomID := f.StartPractice(fakebackend.RoomSetup{Game: "ludo", Bots: 1, StartTokens: [][]int{{30, 40, 45, 50}, {30, 40, 45, 50}}})
	waitFor(t, 60*time.Second, "game finished", roomFinished(f, roomID))
	if v := h.metricValue("state_hash_mismatches_total", nil); v != 1 {
		t.Fatalf("hash mismatches = %v, want 1", v)
	}
	if h.metricValue("state_resyncs_total", map[string]string{"reason": "hash_mismatch"}) != 1 {
		t.Fatal("hash mismatch did not trigger a resync")
	}
}

// A dropped network connection is re-established with backoff and
// X-Reconnect: 1, the state is resynced and verified, and the game finishes.
func TestNetworkInterruptionReconnectsAndResyncs(t *testing.T) {
	t.Parallel()
	f := newFake(t, fakebackend.Options{TurnTimeout: 5 * time.Second})
	h := newHarness(t, f, nil)
	h.start()
	roomID := f.StartPractice(fakebackend.RoomSetup{Game: "ludo", Bots: 1, StartTokens: [][]int{{20, 30, 40, 50}, {20, 30, 40, 50}}})
	var uid string
	waitFor(t, 20*time.Second, "bot rolled twice", func() bool {
		b := botUIDs(f, roomID)
		if len(b) == 0 {
			return false
		}
		uid = b[0]
		return countMsgs(f.ClientMessages(uid), "game.roll_dice") >= 2
	})
	if !f.DropConnection(uid) {
		t.Fatal("bot not connected")
	}
	waitFor(t, 10*time.Second, "reconnect handshake", func() bool {
		for _, hs := range f.Handshakes() {
			if hs.Get("X-Reconnect") == "1" {
				return true
			}
		}
		return false
	})
	waitFor(t, 60*time.Second, "game finished", roomFinished(f, roomID))
	if h.metricValue("reconnects_total", map[string]string{"result": "success"}) < 1 {
		t.Fatal("reconnect not recorded")
	}
	if h.metricValue("reconnect_resync_verifications_total", map[string]string{"result": "verified"}) < 1 {
		t.Fatal("post-reconnect resync not verified")
	}
	if h.metricValue("state_resyncs_total", map[string]string{"reason": "reconnect"}) < 1 {
		t.Fatal("no resync after reconnect")
	}
	// Server shutdown close code 1001 also reconnects.
	roomID2 := f.StartPractice(fakebackend.RoomSetup{Game: "ludo", Bots: 1, StartTokens: [][]int{{20, 30, 40, 50}, {20, 30, 40, 50}}})
	waitFor(t, 20*time.Second, "second bot playing", func() bool {
		b := botUIDs(f, roomID2)
		if len(b) == 0 {
			return false
		}
		uid = b[0]
		return countMsgs(f.ClientMessages(uid), "game.roll_dice") >= 1
	})
	before := len(f.Handshakes())
	f.CloseConnection(uid, 1001)
	waitFor(t, 10*time.Second, "reconnect after 1001", func() bool { return len(f.Handshakes()) > before })
	waitFor(t, 60*time.Second, "second game finished", roomFinished(f, roomID2))
}

// 4409 (session replaced) must not auto-reconnect: the bot exits and its
// session is revoked.
func TestReplacedSessionDoesNotReconnect(t *testing.T) {
	t.Parallel()
	f := newFake(t, fakebackend.Options{TurnTimeout: 10 * time.Second})
	h := newHarness(t, f, nil)
	h.start()
	roomID := f.StartPractice(fakebackend.RoomSetup{Game: "ludo", Bots: 1})
	var uid string
	waitFor(t, 20*time.Second, "bot connected", func() bool {
		b := botUIDs(f, roomID)
		if len(b) == 0 {
			return false
		}
		uid = b[0]
		return contains(f.ConnectedUIDs(), uid)
	})
	before := len(f.Handshakes())
	f.CloseConnection(uid, 4409)
	waitFor(t, 10*time.Second, "session revoked", func() bool { return contains(f.Revoked(), uid) })
	time.Sleep(300 * time.Millisecond)
	if len(f.Handshakes()) != before {
		t.Fatal("bot reconnected after 4409")
	}
	if h.metricValue("bot_connection_failures_total", map[string]string{"reason": "replaced"}) != 1 {
		t.Fatal("replaced close not recorded")
	}
}

// Maintenance (close 4503, upgrade 503) pauses the bot; it reconnects after
// maintenance ends (staggered) and finishes the game.
func TestMaintenanceBackoffThenResume(t *testing.T) {
	t.Parallel()
	f := newFake(t, fakebackend.Options{TurnTimeout: 8 * time.Second})
	h := newHarness(t, f, nil)
	h.start()
	roomID := f.StartPractice(fakebackend.RoomSetup{Game: "ludo", Bots: 1, StartTokens: [][]int{{30, 40, 45, 50}, {30, 40, 45, 50}}})
	var uid string
	waitFor(t, 20*time.Second, "bot playing", func() bool {
		b := botUIDs(f, roomID)
		if len(b) == 0 {
			return false
		}
		uid = b[0]
		return countMsgs(f.ClientMessages(uid), "game.roll_dice") >= 1
	})
	start := time.Now()
	f.SetMaintenance(true)
	waitFor(t, 5*time.Second, "bot disconnected", func() bool { return !contains(f.ConnectedUIDs(), uid) })
	time.Sleep(1500 * time.Millisecond)
	f.SetMaintenance(false)
	waitFor(t, 15*time.Second, "bot reconnected", func() bool { return contains(f.ConnectedUIDs(), uid) })
	if time.Since(start) < time.Second {
		t.Fatal("bot did not back off during maintenance")
	}
	waitFor(t, 60*time.Second, "game finished", roomFinished(f, roomID))
	if h.metricValue("bot_connection_failures_total", map[string]string{"reason": "maintenance"}) < 1 {
		t.Fatal("maintenance not recorded")
	}
}

// Error codes: rate_limited (retry) slows the bot down and it retries;
// stale_state triggers a sync and the bot acts again on fresh state.
func TestErrorCodesRateLimitedAndStaleState(t *testing.T) {
	t.Parallel()
	f := newFake(t, fakebackend.Options{TurnTimeout: 5 * time.Second})
	h := newHarness(t, f, nil)
	var mu sync.Mutex
	rolls := 0
	f.SetCommandHook(func(uid, typ string) (string, bool) {
		mu.Lock()
		defer mu.Unlock()
		if typ != "game.roll_dice" {
			return "", false
		}
		rolls++
		switch rolls {
		case 1:
			return "rate_limited", true
		case 3:
			return "stale_state", false
		}
		return "", false
	})
	h.start()
	roomID := f.StartPractice(fakebackend.RoomSetup{Game: "ludo", Bots: 1, StartTokens: [][]int{{40, 44, 48, 50}, {40, 44, 48, 50}}})
	waitFor(t, 60*time.Second, "game finished", roomFinished(f, roomID))
	if h.metricValue("invalid_action_responses_total", map[string]string{"code": "rate_limited"}) != 1 ||
		h.metricValue("invalid_action_responses_total", map[string]string{"code": "stale_state"}) != 1 {
		t.Fatal("error responses not recorded")
	}
	if h.metricValue("state_resyncs_total", map[string]string{"reason": "stale_state"}) != 1 {
		t.Fatal("stale_state did not trigger a sync")
	}
	if r, _ := f.Room(roomID); r.Autos != 0 {
		t.Fatalf("bot did not retry after errors (server auto-acted %d times)", r.Autos)
	}
}
