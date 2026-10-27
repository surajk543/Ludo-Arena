package tests

import (
	"context"
	"encoding/json"
	"strings"
	"testing"
	"time"

	"ludoarena/internal/progression"
	"ludoarena/internal/rooms"
)

// TestPlaytimeOverTheRealProtocol plays a public match through the gateway:
// the player who already has 9:58 of today's playtime crosses 10 minutes in
// the match and receives the server-confirmed reward (playtime.updated with
// granted, wallet.updated reason "playtime"); the opponent, whose app went to
// the background (app.focus), accrues nothing while away.
func TestPlaytimeOverTheRealProtocol(t *testing.T) {
	t.Setenv("PROGRESSION_MIN_MATCH_DURATION", "0s")
	e := newEnv(t, envOpts{dice: rooms.NewSeededDice(13)})
	ctx := context.Background()
	cs := startPublic(t, e, "ludo", "classic", 2)
	a, b := cs[0], cs[1]
	day := progression.DayKey(time.Now())
	if _, err := e.app.PG.Exec(ctx, `INSERT INTO progression.mission_progress (user_id, period_key, mission_id, value)
		VALUES ($1, $2, 'playtime', 598)`, a.acct.UserID, day); err != nil {
		t.Fatal(err)
	}
	coinsBefore := e.coins(a.acct.Token)

	if m := b.call("app.focus", map[string]any{"foreground": false}); m.T != "ack" {
		t.Fatalf("app.focus: %s %s", m.T, m.P)
	}
	if m := b.call("app.focus", map[string]any{}); !strings.Contains(string(m.P), "bad_request") {
		t.Fatalf("app.focus without foreground: %s %s", m.T, m.P)
	}
	time.Sleep(2500 * time.Millisecond) // a few seconds of active play for a
	playAll(t, cs)

	var granted struct {
		PeriodKey string `json:"periodKey"`
		Seconds   int64  `json:"seconds"`
		Granted   []struct {
			ID      string `json:"id"`
			Minutes int    `json:"minutes"`
			Reward  struct {
				Coins int64 `json:"coins"`
				XP    int64 `json:"xp"`
			} `json:"reward"`
			Status string `json:"status"`
		} `json:"granted"`
	}
	waitFor(t, 10*time.Second, "playtime grant push", func() bool {
		for _, m := range a.messages("playtime.updated") {
			if json.Unmarshal(m.P, &granted) == nil && len(granted.Granted) > 0 {
				return true
			}
		}
		return false
	})
	g := granted.Granted[0]
	if granted.PeriodKey != day || granted.Seconds < 600 || g.ID != "playtime_10m" || g.Minutes != 10 ||
		g.Status != "completed" || g.Reward.Coins != 5000 || g.Reward.XP != 25 {
		t.Fatalf("grant push = %+v", granted)
	}
	waitFor(t, 5*time.Second, "wallet.updated playtime", func() bool {
		for _, m := range a.messages("wallet.updated") {
			if strings.Contains(string(m.P), `"reason":"playtime"`) {
				return true
			}
		}
		return false
	})
	// Server-confirmed balances: fee and payout aside, exactly one reward.
	r := e.do("GET", "/api/v1/playtime", a.acct.Token, nil)
	if r.Status != 200 || !strings.Contains(string(r.Raw), `"id":"playtime_10m","minutes":10`) ||
		!strings.Contains(string(r.Raw), `"status":"completed"`) {
		t.Fatalf("GET /playtime = %d %s", r.Status, r.Raw)
	}
	final := a.snapshot()
	wantCoins := coinsBefore + 5000
	if final.Result.WinnerSeat == a.seat() {
		wantCoins += final.Result.Payout
	}
	waitFor(t, 5*time.Second, "settled wallet", func() bool { return e.coins(a.acct.Token) == wantCoins })

	// b was in the background for the whole match: no playtime.
	rb := e.do("GET", "/api/v1/playtime", b.acct.Token, nil)
	if rb.Status != 200 || rb.Body["seconds"].(float64) >= 2 {
		t.Fatalf("away player playtime = %s", rb.Raw)
	}
	for _, m := range b.messages("playtime.updated") {
		if strings.Contains(string(m.P), `"granted":[{`) {
			t.Fatalf("away player got a grant: %s", m.P)
		}
	}
}

// messages returns the received messages of a type, in order.
func (c *client) messages(t string) []msg {
	c.mu.Lock()
	defer c.mu.Unlock()
	var out []msg
	for _, m := range c.all {
		if m.T == t {
			out = append(out, m)
		}
	}
	return out
}
