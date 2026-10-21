package tests

import (
	"encoding/json"
	"strings"
	"testing"
	"time"

	"ludoroyale/botplay/internal/config"
	"ludoroyale/botplay/tests/fakebackend"
)

// A practice Ludo game with one human (played by the fake) and one bot runs
// to completion; the bot then leaves and its session is revoked.
func TestPracticeLudoBotPlaysToCompletion(t *testing.T) {
	t.Parallel()
	f := newFake(t, fakebackend.Options{})
	h := newHarness(t, f, nil)
	h.start()
	roomID := f.StartPractice(fakebackend.RoomSetup{Game: "ludo", Bots: 1, StartTokens: [][]int{{40, 44, 48, 50}, {40, 44, 48, 50}}})
	waitFor(t, 30*time.Second, "game finished", roomFinished(f, roomID))
	bots := botUIDs(f, roomID)
	if len(bots) != 1 {
		t.Fatalf("bots seated: %v", bots)
	}
	waitFor(t, 10*time.Second, "session revoked", func() bool { return contains(f.Revoked(), bots[0]) })
	waitFor(t, 5*time.Second, "bot exited", func() bool { return h.svc.Count() == 0 })

	r, _ := f.Room(roomID)
	if r.Rolls == 0 {
		t.Fatalf("bot never rolled (autos=%d)", r.Autos)
	}
	if r.Autos != 0 {
		t.Fatalf("server had to auto-act for the bot %d times", r.Autos)
	}
	msgs := f.ClientMessages(bots[0])
	if countMsgs(msgs, "room.leave") != 1 {
		t.Fatalf("expected one room.leave, got %d", countMsgs(msgs, "room.leave"))
	}
	if h.metricValue("game_actions_total", map[string]string{"type": "roll"}) == 0 ||
		h.metricValue("games_finished_total", map[string]string{"game": "ludo"}) != 1 ||
		h.metricValue("games_started_total", map[string]string{"game": "ludo"}) != 1 ||
		h.metricValue("room_joins_total", map[string]string{"kind": "practice"}) != 1 {
		t.Fatal("metrics not recorded")
	}
	if h.metricValue("action_latency_seconds", map[string]string{"action": "roll"}) == 0 {
		t.Fatal("roll latency not observed")
	}
	if h.metricValue("compression_negotiated_total", map[string]string{"result": "negotiated"}) < 1 {
		t.Fatal("permessage-deflate not negotiated")
	}
	if h.metricValue("ws_bytes_received_total", nil) == 0 {
		t.Fatal("bytes not counted")
	}
	if h.metricValue("state_hash_mismatches_total", nil) != 0 || h.metricValue("invalid_action_responses_total", nil) != 0 {
		t.Fatalf("unexpected mismatches/errors: hash=%v errors=%v", h.metricValue("state_hash_mismatches_total", nil), h.metricValue("invalid_action_responses_total", nil))
	}
}

// Three bots in one practice match never conflict: no not_your_turn,
// stale_state or illegal_move errors, every bot acts, the game completes.
func TestMultipleBotsInOneMatchDoNotConflict(t *testing.T) {
	t.Parallel()
	f := newFake(t, fakebackend.Options{})
	h := newHarness(t, f, func(c *config.Config) { c.Bots.Behavior.DefaultProfile = "advanced" })
	h.start()
	roomID := f.StartPractice(fakebackend.RoomSetup{Game: "ludo", Bots: 3, StartTokens: [][]int{{30, 40, 45, 50}, {30, 40, 45, 50}, {30, 40, 45, 50}, {30, 40, 45, 50}}})
	waitFor(t, 60*time.Second, "game finished", roomFinished(f, roomID))
	bots := botUIDs(f, roomID)
	if len(bots) != 3 {
		t.Fatalf("bots: %v", bots)
	}
	for _, uid := range bots {
		if countMsgs(f.ClientMessages(uid), "game.roll_dice") == 0 {
			t.Fatalf("bot %s never rolled", uid)
		}
	}
	r, _ := f.Room(roomID)
	if r.Autos != 0 {
		t.Fatalf("server auto-acted %d times", r.Autos)
	}
	for _, code := range []string{"not_your_turn", "stale_state", "illegal_move", "invalid_phase"} {
		if v := h.metricValue("invalid_action_responses_total", map[string]string{"code": code}); v != 0 {
			t.Fatalf("%s errors: %v", code, v)
		}
	}
	waitFor(t, 10*time.Second, "all bots exited", func() bool { return h.svc.Count() == 0 })
	if len(f.Revoked()) != 3 {
		t.Fatalf("revoked: %v", f.Revoked())
	}
}

// Snakes & Ladders bots only roll, never double-roll (the move is applied
// as part of the roll and the phase stays awaiting_roll), and finish.
func TestSnakesBotRollsOnlyAndFinishes(t *testing.T) {
	t.Parallel()
	f := newFake(t, fakebackend.Options{})
	h := newHarness(t, f, nil)
	h.start()
	roomID := f.StartPractice(fakebackend.RoomSetup{Game: "snakes_ladders", Bots: 2, StartPos: []int{70, 75, 79}})
	waitFor(t, 60*time.Second, "snakes game finished", roomFinished(f, roomID))
	for _, uid := range botUIDs(f, roomID) {
		msgs := f.ClientMessages(uid)
		if countMsgs(msgs, "game.make_move") != 0 {
			t.Fatal("snakes bot sent make_move")
		}
		if countMsgs(msgs, "game.roll_dice") == 0 {
			t.Fatal("snakes bot never rolled")
		}
	}
	if v := h.metricValue("invalid_action_responses_total", nil); v != 0 {
		t.Fatalf("snakes bot got %v error responses (double roll?)", v)
	}
	r, _ := f.Room(roomID)
	if r.Autos != 0 {
		t.Fatalf("server auto-acted %d times", r.Autos)
	}
}

// Auth: controller token via Bot-Service key; bot WS with Bearer bot token,
// subprotocol, X-App-Platform: bot and version headers. The service key and
// tokens never appear in logs. Bots never send a bot flag; the server's
// players[].bot labels them.
func TestAuthHeadersAndSecretsNeverLogged(t *testing.T) {
	t.Parallel()
	f := newFake(t, fakebackend.Options{})
	h := newHarness(t, f, nil)
	h.start()
	roomID := f.StartPractice(fakebackend.RoomSetup{Game: "ludo", Variant: "quick", Bots: 1, StartTokens: nearHome(2)})
	waitFor(t, 30*time.Second, "game finished", roomFinished(f, roomID))
	waitFor(t, 10*time.Second, "bot exited", func() bool { return h.svc.Count() == 0 })

	var tokens []string
	sawControllerAuth := false
	for _, r := range f.Requests() {
		auth := r.Header.Get("Authorization")
		switch {
		case r.Path == "/api/v1/bot/controller/token":
			if auth != "Bot-Service "+testServiceKey {
				t.Fatalf("controller token request auth = %q", auth)
			}
			sawControllerAuth = true
		case strings.HasPrefix(r.Path, "/api/v1/bot/"):
			if !strings.HasPrefix(auth, "Bearer ct_") {
				t.Fatalf("%s %s auth = %q", r.Method, r.Path, auth)
			}
			tokens = append(tokens, strings.TrimPrefix(auth, "Bearer "))
		}
		if r.Path != "/api/v1/ws" && r.Header.Get("X-App-Platform") != "" {
			t.Fatalf("REST bot endpoints must not send X-App-Platform: %s", r.Path)
		}
	}
	if !sawControllerAuth {
		t.Fatal("no controller token request")
	}
	hs := f.Handshakes()
	if len(hs) == 0 {
		t.Fatal("no websocket handshake")
	}
	for _, hdr := range hs {
		if !strings.HasPrefix(hdr.Get("Authorization"), "Bearer bt_") || hdr.Get("X-App-Platform") != "bot" ||
			!strings.Contains(hdr.Get("Sec-WebSocket-Protocol"), "ludo-royale.v1") || hdr.Get("X-App-Version") == "" ||
			hdr.Get("X-App-Build") == "" || !strings.Contains(hdr.Get("Sec-WebSocket-Extensions"), "permessage-deflate") {
			t.Fatalf("bad handshake headers: %v", hdr)
		}
		if hdr.Get("X-Reconnect") != "" {
			t.Fatal("first connection must not send X-Reconnect")
		}
		tokens = append(tokens, strings.TrimPrefix(hdr.Get("Authorization"), "Bearer "))
	}
	logs := h.logs.String()
	if strings.Contains(logs, testServiceKey) {
		t.Fatal("service key logged")
	}
	for _, tok := range tokens {
		if tok != "" && strings.Contains(logs, tok) {
			t.Fatalf("token %s… logged", tok[:6])
		}
	}
	// Bot flag: never sent by the bot, provided by the server.
	for _, body := range f.SessionBodies() {
		for k := range body {
			if strings.EqualFold(k, "bot") || strings.EqualFold(k, "isBot") {
				t.Fatalf("session request carried a bot flag: %v", body)
			}
		}
		if body["profile"] != "balanced" || !strings.HasPrefix(body["name"].(string), "Bot ") {
			t.Fatalf("session body: %v", body)
		}
	}
	for _, raw := range f.ClientMessages("") {
		var env map[string]any
		_ = json.Unmarshal([]byte(raw), &env)
		if p, ok := env["p"].(map[string]any); ok {
			if _, has := p["bot"]; has {
				t.Fatalf("bot sent a bot flag: %s", raw)
			}
		}
	}
	r, _ := f.Room(roomID)
	for _, p := range r.Players {
		if strings.HasPrefix(p.Name, "Bot ") && !p.Bot {
			t.Fatal("server should label the bot seat")
		}
	}
	if h.metricValue("bot_label_missing_total", nil) != 0 {
		t.Fatal("bot label reported missing")
	}
}

// accept_rematch: the bot answers game.rematch; when the backend refuses it
// (assignment bots may not send game.rematch in the current backend), the bot
// leaves right away instead of lingering until the rematch deadline.
func TestAcceptRematchFallsBackToLeaving(t *testing.T) {
	t.Parallel()
	f := newFake(t, fakebackend.Options{})
	h := newHarness(t, f, func(c *config.Config) { c.Bots.AcceptRematch = true })
	h.start()
	roomID := f.StartPractice(fakebackend.RoomSetup{Game: "ludo", Bots: 1, StartTokens: nearHome(2)})
	waitFor(t, 30*time.Second, "game finished", roomFinished(f, roomID))
	finished := time.Now()
	waitFor(t, 10*time.Second, "bot exited", func() bool { return h.svc.Count() == 0 })
	if time.Since(finished) > 5*time.Second {
		t.Fatal("bot lingered after the rematch was refused")
	}
	uid := botUIDs(f, roomID)[0]
	msgs := f.ClientMessages(uid)
	if countMsgs(msgs, "game.rematch") != 1 || countMsgs(msgs, "room.leave") != 1 {
		t.Fatalf("expected one rematch answer then one leave: %v", msgs[len(msgs)-2:])
	}
}
