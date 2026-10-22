package tests

import (
	"context"
	"encoding/json"
	"regexp"
	"slices"
	"sync"
	"testing"
	"time"

	"ludoarena/internal/rooms"
)

// Bots are indistinguishable from people (docs/websocket-protocol.md §4 and
// "Bots look like people" in docs/rest-api.md). Every test client also
// fails on any frame that carries a "bot" key (wsclient_test.go).

// publicUID is the format of every public player id, people's and bots'.
var publicUID = regexp.MustCompile(`^u_[a-km-z2-9]{12}$`)

// recentPlayers returns GET /social/recent by uid.
func (e *env) recentPlayers(t *testing.T, a account) (map[string]map[string]any, resp) {
	t.Helper()
	r := e.do("GET", "/api/v1/social/recent", a.Token, nil)
	if r.Status != 200 {
		t.Fatalf("recent: %d %s", r.Status, r.Raw)
	}
	out := map[string]map[string]any{}
	for _, x := range r.Body["players"].([]any) {
		p := x.(map[string]any)
		out[p["uid"].(string)] = p
	}
	return out, r
}

// errOf is the code of an error envelope ("" otherwise).
func errOf(m msg) string {
	var p struct {
		Code string `json:"code"`
	}
	_ = json.Unmarshal(m.P, &p)
	return p.Code
}

// noBotKey fails when a REST response marks a player as a bot.
func noBotKey(t *testing.T, what string, r resp) {
	t.Helper()
	var v any = r.Body
	if hasJSONKey(v, "bot") {
		t.Fatalf("%s marks a bot: %s", what, r.Raw)
	}
}

// Bots have the people's uid format, plausible varied levels, titles and
// cosmetics, and send quick chat and emotes (only their own emotes).
func TestBotsLookAndChatLikePeople(t *testing.T) {
	e := newEnv(t, envOpts{dice: rooms.NewSeededDice(31)})
	human := e.guest()
	hc, roomID, _ := e.practiceWithBots(t, human, []string{"Asha", "Ravi", "Meera"})
	s := hc.snapshot()
	if !publicUID.MatchString(human.UID) {
		t.Fatalf("human uid %q", human.UID)
	}
	type look struct {
		level  int
		title  string
		frame  string
		dice   string
		avatar int
	}
	looks := map[look]bool{}
	for _, seat := range s.ComputerSeats {
		p := s.Players[seat]
		if !publicUID.MatchString(p.UID) || p.Level < 1 || p.Level > 50 || p.Title == "" || len(p.Cosmetics) != 5 {
			t.Fatalf("bot seat does not look like a player: %+v", p)
		}
		looks[look{p.Level, p.Title, p.Cosmetics["frame"], p.Cosmetics["dice"], p.Avatar}] = true
	}
	if len(looks) < 2 {
		t.Fatalf("every bot looks the same: %v", looks)
	}

	// The bot clients of this room.
	var botClients []*client
	for _, c := range e.botClients {
		if seatIn(s, c.acct.UID) >= 0 {
			botClients = append(botClients, c)
		}
	}
	if len(botClients) != 3 {
		t.Fatalf("bot clients: %d", len(botClients))
	}
	quick, emoter, other := botClients[0], botClients[1], botClients[2]
	if len(emoter.acct.Emotes) == 0 {
		t.Fatal("a bot without emotes")
	}
	if m := quick.call("chat.quick", map[string]any{"roomId": roomID, "msg": "good_luck"}); m.T != "ack" {
		t.Fatalf("bot quick chat: %s %s", m.T, m.P)
	}
	if m := emoter.call("chat.emote", map[string]any{"roomId": roomID, "emote": emoter.acct.Emotes[0]}); m.T != "ack" {
		t.Fatalf("bot emote: %s %s", m.T, m.P)
	}
	notOwned := "emote_crown"
	if slices.Contains(other.acct.Emotes, notOwned) {
		notOwned = "emote_unknown"
	}
	if m := other.call("chat.emote", map[string]any{"roomId": roomID, "emote": notOwned}); m.T != "error" || errOf(m) != "item_not_owned" {
		t.Fatalf("bot emote it does not own: %s %s", m.T, m.P)
	}
	waitFor(t, 3*time.Second, "chat delivered to the human", func() bool {
		return hc.count("chat.quick") == 1 && hc.count("chat.emote") == 1
	})
	// Same server limits as people: 1 message per 3 s.
	if m := quick.call("chat.quick", map[string]any{"roomId": roomID, "msg": "gg"}); m.T != "error" || errOf(m) != "rate_limited" {
		t.Fatalf("bot chat burst: %s %s", m.T, m.P)
	}
}

// A bot met again is the same persona (same uid, avatar, level only going
// up); it keeps its picture for BOT_PICTURE_KEEP matches, then changes it.
// Concurrent bots of one name are different personas, and practice bots
// never share personas with public-lobby bots.
func TestBotPersonaKeepsIdentityAndChangesPicture(t *testing.T) {
	e := newEnv(t, envOpts{dice: rooms.NewSeededDice(32), botPictureShare: "1", botPictureKeep: "2"})
	ctl := e.botController(t)
	human := e.guest()
	hc := e.mustDial("human", human)
	type seen struct {
		uid, picture  string
		avatar, level int
	}
	var rounds []seen
	oldRoom := ""
	for round := 0; round < 3; round++ {
		if m := hc.call("practice.start", map[string]any{"game": "snakes_ladders", "bots": 1}); m.T != "room.updated" {
			t.Fatalf("round %d practice.start: %s %s", round, m.T, m.P)
		}
		bots := e.spawnNamedBots(t, ctl, []string{"Tara"})
		waitFor(t, 10*time.Second, "practice start", func() bool {
			s := hc.snapshot()
			return s != nil && s.ID != oldRoom && s.Status == "playing"
		})
		s := hc.snapshot()
		oldRoom = s.ID
		p := s.Players[s.ComputerSeats[0]]
		if p.Picture == nil || p.Name != "Tara" || p.UID != bots[0].acct.UID {
			t.Fatalf("round %d seat: %+v", round, p)
		}
		rounds = append(rounds, seen{p.UID, p.Picture.ID, p.Avatar, p.Level})
		if m := hc.call("room.leave", map[string]any{"roomId": s.ID}); m.T != "ack" {
			t.Fatalf("leave: %s %s", m.T, m.P)
		}
		// bot-play ends the session when the bot is done.
		if r := e.do("DELETE", "/api/v1/bot/sessions/"+p.UID, ctl, nil); r.Status != 204 {
			t.Fatalf("end bot session: %d %s", r.Status, r.Raw)
		}
		bots[0].close()
	}
	for i, r := range rounds {
		if !publicUID.MatchString(r.uid) || r.uid != rounds[0].uid || r.avatar != rounds[0].avatar ||
			(i > 0 && r.level < rounds[i-1].level) {
			t.Fatalf("persona changed between matches: %+v", rounds)
		}
	}
	if rounds[0].picture != rounds[1].picture || rounds[2].picture == rounds[1].picture {
		t.Fatalf("pictures %v: want kept for 2 matches, then changed", rounds)
	}

	// Two "Tara" at once are two personas; the free one is the one above.
	_, _, both := e.practiceWithBots(t, human, []string{"Tara", "Tara"})
	if both[0].UID == both[1].UID || (both[0].UID != rounds[0].uid && both[1].UID != rounds[0].uid) {
		t.Fatalf("concurrent personas: %+v (known %s)", both, rounds[0].uid)
	}
	ctx := context.Background()
	if n, _ := e.rdb.Exists(ctx, "botprof:"+rounds[0].uid).Result(); n != 1 {
		t.Fatal("no public card for the persona")
	}
}

// Bots met in public matches are recent players like people: listed with
// their profile, still after their session ended, with the same actions
// (a friend request stays pending). Practice bots are not recorded.
func TestBotsInRecentPlayers(t *testing.T) {
	e := newEnv(t, envOpts{dice: rooms.NewSeededDice(33), botPictureShare: "1"})
	ctl := e.botController(t)
	human := e.guest()
	hc := e.mustDial("human", human)
	hc.call("matchmaking.join", map[string]any{"game": "snakes_ladders", "capacity": 2})
	waitFor(t, 3*time.Second, "lobby", func() bool { return hc.snapshot() != nil })
	roomID := hc.snapshot().ID
	if r := e.do("POST", "/api/v1/bot/lobbies/"+roomID+"/fill", ctl, map[string]any{"count": 1}); r.Status != 200 {
		t.Fatalf("fill: %d %s", r.Status, r.Raw)
	}
	bots := e.spawnNamedBots(t, ctl, []string{"Kabir"})
	waitFor(t, 10*time.Second, "public game", func() bool { return hc.snapshot().Status == "playing" })
	s := hc.snapshot()
	if len(s.ComputerSeats) != 0 || s.PendingBots != 0 {
		t.Fatalf("a public room reveals its bots: %v pending %d", s.ComputerSeats, s.PendingBots)
	}
	seat := s.Players[seatIn(s, bots[0].acct.UID)]
	var wg sync.WaitGroup
	for _, c := range []*client{hc, bots[0]} {
		wg.Add(1)
		go func(c *client) { defer wg.Done(); c.playUntilFinished(90 * time.Second) }(c)
	}
	wg.Wait()

	var got map[string]any
	waitFor(t, 5*time.Second, "bot in recent players", func() bool {
		list, _ := e.recentPlayers(t, human)
		got = list[seat.UID]
		return got != nil
	})
	if got["name"] != seat.Name || num(got["avatar"]) != int64(seat.Avatar) || num(got["level"]) != int64(seat.Level) ||
		got["title"] != seat.Title || seat.Picture == nil || pictureID(got["picture"]) != seat.Picture.ID ||
		got["status"] != "none" || got["online"] != false {
		t.Fatalf("recent bot %v, seat %+v", got, seat)
	}

	// bot-play ends the session; the bot stays in recent players.
	if r := e.do("DELETE", "/api/v1/bot/sessions/"+seat.UID, ctl, nil); r.Status != 204 {
		t.Fatalf("end bot session: %d %s", r.Status, r.Raw)
	}
	list, raw := e.recentPlayers(t, human)
	noBotKey(t, "recent players", raw)
	if list[seat.UID] == nil || len(list) != 1 {
		t.Fatalf("recent after the session ended: %s", raw.Raw)
	}
	// Add friend from Recent: pending like a request to a person.
	if r := e.friendRequest(human, seat.UID); r.Status != 201 || r.Body["friend"].(map[string]any)["status"] != "outgoing" {
		t.Fatalf("request from recent: %d %s", r.Status, r.Raw)
	}
	if list, _ := e.recentPlayers(t, human); list[seat.UID]["status"] != "outgoing" {
		t.Fatalf("recent status: %v", list[seat.UID])
	}
	f := e.friends(t, human)
	noBotKey(t, "friends", f)
	if got := outgoingUIDs(t, f); !slices.Equal(got, []string{seat.UID}) {
		t.Fatalf("outgoing: %v", got)
	}

	// Practice bots (computer opponents the player chose) are not recorded.
	pc, practiceRoom, _ := e.practiceWithBots(t, human, []string{"Isha"})
	if m := pc.call("room.leave", map[string]any{"roomId": practiceRoom}); m.T != "ack" {
		t.Fatalf("leave practice: %s %s", m.T, m.P)
	}
	time.Sleep(1500 * time.Millisecond) // the finished practice match is recorded meanwhile
	if list, r := e.recentPlayers(t, human); len(list) != 1 || list[seat.UID] == nil {
		t.Fatalf("practice bots in recent players: %s", r.Raw)
	}

	// Once the bot's card expired it is forgotten, like a deleted account.
	ctx := context.Background()
	if err := e.rdb.Del(ctx, "botprof:"+seat.UID).Err(); err != nil {
		t.Fatal(err)
	}
	if list, r := e.recentPlayers(t, human); len(list) != 0 {
		t.Fatalf("expired bot still listed: %s", r.Raw)
	}
	if n, _ := e.rdb.ZCard(ctx, "recent:"+human.UserID).Result(); n != 0 {
		t.Fatalf("expired bot not forgotten: %d members", n)
	}
}
