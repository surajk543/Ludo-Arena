package tests

import (
	"strings"
	"testing"
	"time"

	"ludoroyale/internal/rooms"
)

func TestMatchAwardsProgressionMissionsAndSocial(t *testing.T) {
	t.Setenv("PROGRESSION_MIN_MATCH_DURATION", "0s") // test games finish in < 1 s
	e := newEnv(t, envOpts{dice: rooms.NewSeededDice(13)})
	cs := startPublic(t, e, "ludo", "classic", 2)
	playAll(t, cs)
	for _, c := range cs {
		c := c
		waitFor(t, 10*time.Second, c.name+" progression.updated", func() bool { return c.count("progression.updated") > 0 })
		p := e.do("GET", "/api/v1/progression", c.acct.Token, nil)
		if p.Status != 200 || p.Body["xp"].(float64) < 20 {
			t.Fatalf("%s progression: %d %s", c.name, p.Status, p.Raw)
		}
		m := e.do("GET", "/api/v1/missions", c.acct.Token, nil)
		if m.Status != 200 || !strings.Contains(string(m.Raw), `"progress":1`) {
			t.Fatalf("%s missions show no progress: %s", c.name, m.Raw)
		}
		rec := e.do("GET", "/api/v1/social/recent", c.acct.Token, nil)
		other := cs[0].acct.UID
		if c == cs[0] {
			other = cs[1].acct.UID
		}
		if rec.Status != 200 || !strings.Contains(string(rec.Raw), other) || strings.Contains(string(rec.Raw), cs[0].acct.UserID) {
			t.Fatalf("%s recent opponents: %s", c.name, rec.Raw)
		}
	}
	// Winner earned the win bonus on top of completion XP.
	final := cs[0].snapshot()
	for _, c := range cs {
		xp := e.do("GET", "/api/v1/progression", c.acct.Token, nil).Body["xp"].(float64)
		if c.seat() == final.Result.WinnerSeat && xp < 35 {
			t.Fatalf("winner xp %v", xp)
		}
	}

	// Friends + private-room invite over WebSocket.
	a, b := cs[0], cs[1]
	if r := e.do("POST", "/api/v1/friends/requests", a.acct.Token, map[string]any{"friendCode": b.acct.UID}); r.Status != 201 {
		t.Fatalf("friend request: %d %s", r.Status, r.Raw)
	}
	waitFor(t, 5*time.Second, "friend request push", func() bool { return b.count("social.friend_request") > 0 })
	if r := e.do("POST", "/api/v1/friends/requests/"+a.acct.UID+"/accept", b.acct.Token, nil); r.Status != 200 {
		t.Fatalf("accept: %d %s", r.Status, r.Raw)
	}
	a.call("room.create", map[string]any{"game": "ludo", "capacity": 2})
	waitFor(t, 3*time.Second, "private lobby", func() bool { s := a.snapshot(); return s != nil && s.Mode == "private" })
	if m := a.call("room.invite", map[string]any{"roomId": a.snapshot().ID, "friendUid": b.acct.UID}); m.T != "ack" {
		t.Fatalf("invite: %s %s", m.T, m.P)
	}
	waitFor(t, 5*time.Second, "invite delivered", func() bool { return b.count("social.invite") > 0 })
	stranger := e.mustDial("stranger", e.guest())
	stranger.call("room.create", map[string]any{"game": "ludo", "capacity": 2})
	waitFor(t, 3*time.Second, "stranger lobby", func() bool { return stranger.snapshot() != nil })
	if m := stranger.call("room.invite", map[string]any{"roomId": stranger.snapshot().ID, "friendUid": b.acct.UID}); !strings.Contains(string(m.P), "not_friends") {
		t.Fatalf("non-friend invite: %s", m.P)
	}
}
