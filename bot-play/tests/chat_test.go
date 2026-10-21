package tests

import (
	"encoding/json"
	"slices"
	"testing"
	"time"

	"ludoroyale/botplay/internal/config"
	"ludoroyale/botplay/tests/fakebackend"
)

// chatty makes every trigger fire (probability 1) with no typing delay.
func chatty(maxPerMatch int) func(*config.Config) {
	return func(c *config.Config) {
		c.Bots.Chat = config.ChatConfig{
			Enabled: true, MaxPerMatch: maxPerMatch, MinIntervalMS: config.MinChatIntervalMS,
			ReactionDelayMS: config.RangeMS{Min: 0, Max: 5}, EmoteShare: 0.5,
			Probability: config.ChatProbabilities{GameStart: 1, Six: 1, Capture: 1, Captured: 1, OtherCapture: 1, Win: 1, Loss: 1},
		}
	}
}

var allowedQuick = []string{"gg", "nice_move", "well_played", "good_luck", "oops", "thanks"}

// A bot plays a full game from snapshots that carry no bot flag, chats
// within the per-match cap (quick chat from the catalogue, emotes only from
// its session's list), never offers a rematch, and still leaves afterwards.
func TestBotChatsWithinCapAndStillPlays(t *testing.T) {
	t.Parallel()
	f := newFake(t, fakebackend.Options{})
	h := newHarness(t, f, chatty(2))
	h.start()
	roomID := f.StartPractice(fakebackend.RoomSetup{Game: "ludo", Bots: 2, StartTokens: [][]int{{40, 44, 48, 50}, {40, 44, 48, 50}, {40, 44, 48, 50}}})
	waitFor(t, 30*time.Second, "game finished", roomFinished(f, roomID))
	bots := botUIDs(f, roomID)
	waitFor(t, 10*time.Second, "bots exited", func() bool { return h.svc.Count() == 0 })

	r, _ := f.Room(roomID)
	if r.Autos != 0 || r.Rolls == 0 {
		t.Fatalf("bots did not play by themselves: rolls=%d autos=%d", r.Rolls, r.Autos)
	}
	if v := h.metricValue("invalid_action_responses_total", nil); v != 0 {
		t.Fatalf("error responses: %v", v)
	}
	total := 0
	for _, uid := range bots {
		chats := f.Chats(uid)
		total += len(chats)
		if len(chats) > 2 {
			t.Fatalf("bot %s sent %d chat messages (cap 2)", uid, len(chats))
		}
		for _, c := range chats {
			switch c.Type {
			case "chat.quick":
				if !slices.Contains(allowedQuick, c.Value) {
					t.Fatalf("quick chat %q", c.Value)
				}
			case "chat.emote":
				if !slices.Contains(fakebackend.DefaultEmotes, c.Value) {
					t.Fatalf("emote %q not in the session's list", c.Value)
				}
			}
		}
		for i := 1; i < len(chats); i++ {
			if gap := chats[i].At.Sub(chats[i-1].At); gap < 3*time.Second {
				t.Fatalf("messages %v apart", gap)
			}
		}
		msgs := f.ClientMessages(uid)
		if countMsgs(msgs, "room.leave") != 1 || !contains(f.Revoked(), uid) {
			t.Fatalf("bot %s did not leave after its game", uid)
		}
	}
	if total == 0 {
		t.Fatal("no bot reacted although every trigger has probability 1")
	}
	if len(f.ChatRejects()) != 0 {
		t.Fatalf("chat rejected: %v", f.ChatRejects())
	}
	if h.metricValue("chat_messages_total", map[string]string{"result": "sent"}) != float64(total) {
		t.Fatal("chat_messages_total{result=sent} does not match")
	}
}

// Refused chat messages (here: rate_limited) are never retried and never
// slow the game down or count as invalid game actions.
func TestChatRejectionsAreIgnored(t *testing.T) {
	t.Parallel()
	f := newFake(t, fakebackend.Options{RefuseChat: "rate_limited"})
	h := newHarness(t, f, chatty(3))
	h.start()
	roomID := f.StartPractice(fakebackend.RoomSetup{Game: "ludo", Bots: 1, StartTokens: [][]int{{40, 44, 48, 50}, {40, 44, 48, 50}}})
	waitFor(t, 30*time.Second, "game finished", roomFinished(f, roomID))
	waitFor(t, 10*time.Second, "bot exited", func() bool { return h.svc.Count() == 0 })
	uid := botUIDs(f, roomID)[0]
	r, _ := f.Room(roomID)
	if r.Autos != 0 {
		t.Fatalf("server auto-acted %d times", r.Autos)
	}
	if v := h.metricValue("invalid_action_responses_total", nil); v != 0 {
		t.Fatalf("chat refusals counted as invalid actions: %v", v)
	}
	sent := countMsgs(f.ClientMessages(uid), "chat.quick") + countMsgs(f.ClientMessages(uid), "chat.emote")
	if sent == 0 || sent > 3 {
		t.Fatalf("chat messages sent: %d", sent)
	}
	if got := f.ChatRejects()["rate_limited"]; got != sent {
		t.Fatalf("refused %d of %d (retries?)", got, sent)
	}
	if h.metricValue("chat_messages_total", map[string]string{"result": "rejected"}) != float64(sent) {
		t.Fatal("rejections not counted")
	}
}

// Disabled chat, a silent profile or an older backend without "emotes".
func TestChatSwitches(t *testing.T) {
	t.Parallel()
	cases := []struct {
		name      string
		opts      fakebackend.Options
		mutate    func(*config.Config)
		wantNone  bool
		wantEmote bool
	}{
		{name: "disabled", mutate: func(c *config.Config) { chatty(3)(c); c.Bots.Chat.Enabled = false }, wantNone: true},
		{name: "cap 0", mutate: chatty(0), wantNone: true},
		{name: "no emotes from the backend", opts: fakebackend.Options{OmitEmotes: true},
			mutate: func(c *config.Config) { chatty(3)(c); c.Bots.Chat.EmoteShare = 1 }},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			f := newFake(t, tc.opts)
			h := newHarness(t, f, tc.mutate)
			h.start()
			roomID := f.StartPractice(fakebackend.RoomSetup{Game: "ludo", Bots: 1, StartTokens: [][]int{{40, 44, 48, 50}, {40, 44, 48, 50}}})
			waitFor(t, 30*time.Second, "game finished", roomFinished(f, roomID))
			waitFor(t, 10*time.Second, "bot exited", func() bool { return h.svc.Count() == 0 })
			uid := botUIDs(f, roomID)[0]
			msgs := f.ClientMessages(uid)
			quick, emote := countMsgs(msgs, "chat.quick"), countMsgs(msgs, "chat.emote")
			if tc.wantNone && quick+emote != 0 {
				t.Fatalf("sent %d quick + %d emote", quick, emote)
			}
			if !tc.wantNone && emote != 0 {
				t.Fatalf("sent %d emotes without an emote list", emote)
			}
		})
	}
}

// The backend reuses a bot persona's account (and uid) for later sessions
// and de-duplicates message ids per account: a second session must not
// repeat the first one's ids (the fake never forgets an id; a repeat would
// be acked as a duplicate and the server would have to act for the bot).
// Snapshots carry no bot flag at all.
func TestPersonaReuseKeepsMessageIDsUnique(t *testing.T) {
	t.Parallel()
	f := newFake(t, fakebackend.Options{StableUIDs: true})
	h := newHarness(t, f, func(c *config.Config) { c.Bots.Identity.NamesPool = []string{"Asha"} })
	h.start()
	var uids []string
	for round := 0; round < 2; round++ {
		roomID := f.StartPractice(fakebackend.RoomSetup{Game: "ludo", Bots: 1, StartTokens: [][]int{{40, 44, 48, 50}, {40, 44, 48, 50}}})
		waitFor(t, 30*time.Second, "game finished", roomFinished(f, roomID))
		waitFor(t, 10*time.Second, "bot exited", func() bool { return h.svc.Count() == 0 })
		r, _ := f.Room(roomID)
		if r.Autos != 0 || r.Rolls == 0 {
			t.Fatalf("game %d: rolls=%d autos=%d", round, r.Rolls, r.Autos)
		}
		uids = append(uids, botUIDs(f, roomID)[0])
	}
	if uids[0] != uids[1] {
		t.Fatalf("persona uid not reused: %v", uids)
	}
	ids := map[string]bool{}
	for _, raw := range f.ClientMessages(uids[0]) {
		var env struct {
			T  string `json:"t"`
			ID string `json:"id"`
		}
		_ = json.Unmarshal([]byte(raw), &env)
		if env.ID == "" {
			continue
		}
		if ids[env.ID] {
			t.Fatalf("message id %q reused across sessions", env.ID)
		}
		ids[env.ID] = true
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
}
