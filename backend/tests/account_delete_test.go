package tests

import (
	"context"
	"fmt"
	"net/http"
	"slices"
	"strings"
	"sync"
	"testing"
	"time"

	"ludoroyale/internal/progression"
	"ludoroyale/internal/rooms"
)

// Account deletion: DELETE /api/v1/account (docs/authentication.md
// "Deleting an account", docs/rest-api.md).

var confirmDelete = map[string]any{"confirm": "DELETE"}

func (e *env) deleteAccount(token string, body any) resp {
	e.t.Helper()
	return e.do("DELETE", "/api/v1/account", token, body)
}

// accountRowQueries counts, table by table, the rows that still belong to or
// mention an account. Every approved table (schema_guard_test.go) must be
// listed, so a new table cannot silently escape account deletion.
var accountRowQueries = map[string]string{
	"wallet.wallets":               `SELECT count(*) FROM wallet.wallets WHERE user_id = $1`,
	"identity.auth_identities":     `SELECT count(*) FROM identity.auth_identities WHERE user_id = $1`,
	"progression.player_progress":  `SELECT count(*) FROM progression.player_progress WHERE user_id = $1`,
	"progression.mission_progress": `SELECT count(*) FROM progression.mission_progress WHERE user_id = $1`,
	"progression.mission_claims":   `SELECT count(*) FROM progression.mission_claims WHERE user_id = $1`,
	"progression.match_receipts":   `SELECT count(*) FROM progression.match_receipts WHERE user_id = $1`,
	"progression.inventory":        `SELECT count(*) FROM progression.inventory WHERE user_id = $1`,
	"progression.loadout":          `SELECT count(*) FROM progression.loadout WHERE user_id = $1`,
	"progression.friendships": `SELECT count(*) FROM progression.friendships
		WHERE user_lo = $1 OR user_hi = $1 OR requested_by = $1`,
	"progression.player_reports": `SELECT count(*) FROM progression.player_reports
		WHERE reporter_id = $1 OR reported_id = $1`,
}

func (e *env) accountRows(t *testing.T, userID string) map[string]int {
	t.Helper()
	for _, tb := range allowedTables {
		if _, ok := accountRowQueries[tb]; !ok {
			t.Fatalf("table %s has no account-deletion check: add it to accountRowQueries and to account.eraseOnce", tb)
		}
	}
	out := map[string]int{}
	for tb, q := range accountRowQueries {
		var n int
		if err := e.app.PG.QueryRow(context.Background(), q, userID).Scan(&n); err != nil {
			t.Fatalf("%s: %v", tb, err)
		}
		out[tb] = n
	}
	return out
}

// joinPublic puts already connected clients into one public game.
func joinPublic(t *testing.T, game, variant string, cs ...*client) {
	t.Helper()
	for _, c := range cs {
		if m := c.call("matchmaking.join", map[string]any{"game": game, "variant": variant, "capacity": len(cs)}); m.T != "matchmaking.status" {
			t.Fatalf("%s matchmaking.join: %s %s", c.name, m.T, m.P)
		}
	}
	for _, c := range cs {
		waitFor(t, 5*time.Second, c.name+" game start", func() bool {
			r := c.snapshot()
			return r != nil && r.Status == "playing" && r.Variant == variant && len(r.Players) == len(cs)
		})
	}
}

// Deleting an account erases every PostgreSQL row and Redis key of it,
// revokes its sessions, closes its socket and forfeits its running game
// (which goes on for the others). The same device and Google account then
// start brand-new accounts.
func TestDeleteAccountErasesEverything(t *testing.T) {
	t.Setenv("PROGRESSION_MIN_MATCH_DURATION", "0s") // test games finish in < 1 s
	e := newEnv(t, envOpts{dice: rooms.NewSeededDice(13), proxyHops: 1})
	ctx := context.Background()

	// A: a device-bound guest (guest + device identities) linked to Google.
	devA := devID("delete")
	a := parseAuth(t, e.deviceGuest(devA))
	googleSub := devID("delete-google") // unique per run and -count iteration
	if r := e.do("POST", "/api/v1/account/link/google", a.Token,
		map[string]any{"idToken": e.oidc.googleToken(t, googleSub, googleAud, time.Hour)}); r.Status != 200 {
		t.Fatalf("link google: %d %s", r.Status, r.Raw)
	}
	b, c, d := e.guestFromFreshIP(), e.guestFromFreshIP(), e.guestFromFreshIP()
	ca, cb, cc := e.mustDial("A", a), e.mustDial("B", b), e.mustDial("C", c)

	// A finished match against B: receipt, mission progress, XP, weekly
	// leaderboard, recent players on both sides.
	joinPublic(t, "ludo", "classic", ca, cb)
	playAll(t, []*client{ca, cb})
	waitFor(t, 10*time.Second, "A progression.updated", func() bool { return ca.count("progression.updated") > 0 })
	first := ca.snapshot().ID
	for _, cl := range []*client{ca, cb} { // no more messages of the first room
		if m := cl.call("room.leave", map[string]any{"roomId": first}); m.T != "ack" {
			t.Fatalf("%s leaves the finished room: %s %s", cl.name, m.T, m.P)
		}
	}

	// Chosen name, purchases, an equipped item, a claimed reward.
	if r := e.do("PATCH", "/api/v1/me", a.Token, map[string]any{"displayName": "Ruby Falcon"}); r.Status != 200 {
		t.Fatalf("display name: %d %s", r.Status, r.Raw)
	}
	for _, item := range []string{"emote_crown", "trail_comet"} {
		if r := e.do("POST", "/api/v1/collection/items/"+item+"/purchase", a.Token, nil,
			"Idempotency-Key", "buy-"+item+"-"+runID); r.Status != 200 {
			t.Fatalf("purchase %s: %d %s", item, r.Status, r.Raw)
		}
	}
	if r := e.do("PUT", "/api/v1/collection/loadout", a.Token, map[string]any{"slot": "trail", "itemId": "trail_comet"}); r.Status != 200 {
		t.Fatalf("equip: %d %s", r.Status, r.Raw)
	}
	if _, err := e.app.PG.Exec(ctx, `INSERT INTO progression.mission_claims (user_id, period_key, mission_id)
		VALUES ($1, 'd2026-01-01', 'seeded_claim')`, a.UserID); err != nil {
		t.Fatal(err)
	}
	if err := e.rdb.SAdd(ctx, "emotes:"+a.UserID, "emote_crown").Err(); err != nil {
		t.Fatal(err)
	}

	// Friendships both ways: A–B accepted, C → A pending, A → D pending.
	if r := e.friendRequest(a, b.UID); r.Status != 201 {
		t.Fatalf("A→B: %d %s", r.Status, r.Raw)
	}
	if r := e.do("POST", "/api/v1/friends/requests/"+a.UID+"/accept", b.Token, nil); r.Status != 200 {
		t.Fatalf("B accepts: %d %s", r.Status, r.Raw)
	}
	if r := e.friendRequest(c, a.UID); r.Status != 201 {
		t.Fatalf("C→A: %d %s", r.Status, r.Raw)
	}
	if r := e.friendRequest(a, d.UID); r.Status != 201 {
		t.Fatalf("A→D: %d %s", r.Status, r.Raw)
	}

	// A running 3-player game with B and C; reports in both directions.
	joinPublic(t, "ludo", "quick", ca, cb, cc)
	roomID := ca.snapshot().ID
	aSeat := ca.seat()
	if r := e.report(b.Token, a.UID, roomID, "cheating"); r.Status != 201 {
		t.Fatalf("B reports A: %d %s", r.Status, r.Raw)
	}
	if r := e.report(a.Token, c.UID, roomID, "offensive_name"); r.Status != 201 {
		t.Fatalf("A reports C: %d %s", r.Status, r.Raw)
	}
	// A report A filed against a bot (no account behind reported_id) and a
	// pending friend request A sent to a bot.
	if _, err := e.app.PG.Exec(ctx, `INSERT INTO progression.player_reports
		(reporter_id, reported_id, reason, room_id, game, reported_bot, reported_profile)
		VALUES ($1, gen_random_uuid(), 'other', 'r_seededbot', 'ludo', TRUE, '{"uid":"b_0123456789","name":"Asha"}')`,
		a.UserID); err != nil {
		t.Fatal(err)
	}
	if err := e.rdb.HSet(ctx, "botfr:"+a.UserID, "b_0123456789",
		fmt.Sprintf(`{"name":"Asha","avatar":1,"level":1,"title":"","at":%d}`, time.Now().UnixMilli())).Err(); err != nil {
		t.Fatal(err)
	}

	// Everything the deletion must remove is really there.
	for tb, n := range e.accountRows(t, a.UserID) {
		if n == 0 {
			t.Fatalf("setup: no %s rows for A", tb)
		}
	}
	week := progression.LeaderboardKey(progression.WeekKey(time.Now()))
	redisKeys := []string{"profile:" + a.UserID, "pubid:" + a.UID, "namechg:" + a.UserID, "seat:" + a.UserID,
		"emotes:" + a.UserID, "presence:" + a.UserID, "recent:" + a.UserID, "usess:" + a.UserID,
		"user:" + a.UserID + ":room", "sess:" + sidOf(t, a.Token), "botfr:" + a.UserID}
	for _, k := range redisKeys {
		if n, _ := e.rdb.Exists(ctx, k).Result(); n != 1 {
			t.Fatalf("setup: %s missing", k)
		}
	}
	if _, err := e.rdb.ZScore(ctx, week, a.UserID).Result(); err != nil {
		t.Fatalf("setup: A not on the weekly leaderboard: %v", err)
	}
	if _, err := e.rdb.ZScore(ctx, "recent:"+b.UserID, a.UserID).Result(); err != nil {
		t.Fatalf("setup: A not in B's recent players: %v", err)
	}
	if keys, _ := e.rdb.Keys(ctx, "rl:*:"+a.UserID+":*").Result(); len(keys) == 0 {
		t.Fatal("setup: no rate-limit counters for A")
	}

	// Delete.
	r := e.deleteAccount(a.Token, confirmDelete)
	deleted := time.Now()
	if r.Status != 204 || len(r.Raw) != 0 {
		t.Fatalf("delete: %d %s", r.Status, r.Raw)
	}
	if code := waitClosed(t, ca, 3*time.Second, "A's socket"); code != 4401 {
		t.Fatalf("A's close code = %d, want 4401", code)
	}
	if d := time.Since(deleted); d > 3*time.Second {
		t.Fatalf("A's socket closed after %s", d)
	}
	ca.mu.Lock()
	reason := ca.closeReason
	ca.mu.Unlock()
	if reason != "account deleted" {
		t.Fatalf("A's close reason = %q, want \"account deleted\"", reason)
	}

	// The game goes on for B and C with A forfeited.
	waitFor(t, 3*time.Second, "A forfeited", func() bool {
		s := cb.snapshot()
		return s != nil && s.ID == roomID && s.Players[aSeat].Forfeited
	})
	if s := cb.snapshot(); s.Status != "playing" {
		t.Fatalf("room status after A left = %s, want playing", s.Status)
	}
	assertOpen(t, cb, "B")
	assertOpen(t, cc, "C")
	playAll(t, []*client{cb, cc})
	assertNoDivergence(t, []*client{cb, cc})

	// PostgreSQL: no row of A is left, B and C keep theirs.
	for tb, n := range e.accountRows(t, a.UserID) {
		if n != 0 {
			t.Errorf("%s: %d rows of A left", tb, n)
		}
	}
	for _, other := range []account{b, c, d} {
		if rows := e.accountRows(t, other.UserID); rows["wallet.wallets"] != 1 || rows["identity.auth_identities"] != 1 {
			t.Fatalf("another account was touched: %v", rows)
		}
	}
	for _, other := range []account{b, c, d} {
		if f := e.friends(t, other); strings.Contains(string(f.Raw), a.UID) {
			t.Fatalf("A still in friends of %s: %s", other.UID, f.Raw)
		}
	}
	if g := e.do("GET", "/api/v1/reports", b.Token, nil); g.Status != 200 || len(g.Body["reports"].([]any)) != 0 {
		t.Fatalf("B's report against A survived: %d %s", g.Status, g.Raw)
	}

	// Redis: the recent players of B and C are recorded without A (the match
	// record ran after the deletion), and nothing keyed by A is left except
	// short-lived replay/de-duplication keys.
	waitFor(t, 10*time.Second, "B's recent players updated", func() bool {
		rec := e.do("GET", "/api/v1/social/recent", b.Token, nil)
		return rec.Status == 200 && strings.Contains(string(rec.Raw), c.UID)
	})
	for _, viewer := range []account{b, c} {
		if rec := e.do("GET", "/api/v1/social/recent", viewer.Token, nil); strings.Contains(string(rec.Raw), a.UID) {
			t.Fatalf("A still in recent players: %s", rec.Raw)
		}
		if _, err := e.rdb.ZScore(ctx, "recent:"+viewer.UserID, a.UserID).Result(); err == nil {
			t.Fatalf("A still in recent:%s", viewer.UserID)
		}
	}
	for _, k := range redisKeys {
		if n, _ := e.rdb.Exists(ctx, k).Result(); n != 0 {
			t.Errorf("%s survived the deletion", k)
		}
	}
	if _, err := e.rdb.ZScore(ctx, week, a.UserID).Result(); err == nil {
		t.Error("A is still on the weekly leaderboard")
	}
	keys, err := e.rdb.Keys(ctx, "*"+a.UserID+"*").Result()
	if err != nil {
		t.Fatal(err)
	}
	for _, k := range keys {
		if !strings.HasPrefix(k, "idem:") && !strings.HasPrefix(k, "dedup:") && !strings.HasPrefix(k, "invite:") {
			t.Errorf("key %s survived the deletion", k)
		}
	}

	// Sessions are revoked everywhere; a second delete is 401.
	if r := e.do("POST", "/api/v1/auth/refresh", "", map[string]any{"refreshToken": a.Refresh}); r.Status != 401 || errCode(r) != "invalid_credential" {
		t.Fatalf("refresh: %d %s", r.Status, r.Raw)
	}
	if r := e.do("GET", "/api/v1/me", a.Token, nil); r.Status != 401 || errCode(r) != "unauthorized" {
		t.Fatalf("/me: %d %s", r.Status, r.Raw)
	}
	if _, res, err := e.dial("A-again", a, nil); err == nil || res == nil || res.StatusCode != http.StatusUnauthorized {
		t.Fatalf("WS handshake not rejected with 401: %v %v", err, res)
	}
	if r := e.deleteAccount(a.Token, confirmDelete); r.Status != 401 {
		t.Fatalf("second delete: %d %s", r.Status, r.Raw)
	}
	if r := e.do("POST", "/api/v1/auth/guest/resume", "", map[string]any{"guestSecret": a.GuestSecret}); r.Status != 401 {
		t.Fatalf("guest resume after deletion: %d %s", r.Status, r.Raw)
	}

	// The device is unbound: no resume, and a guest sign-in on it creates a
	// NEW account with a new welcome grant (intended after a deletion).
	if r := e.deviceResume(devA); r.Status != 404 {
		t.Fatalf("device resume after deletion: %d %s", r.Status, r.Raw)
	}
	nr := e.deviceGuest(devA)
	n := parseAuth(t, nr)
	if nr.Status != 201 || nr.Body["isNewUser"] != true || n.UserID == a.UserID || n.UID == a.UID ||
		n.Coins != a.Coins || n.Diamonds != a.Diamonds {
		t.Fatalf("guest on the same device: %d %s", nr.Status, nr.Raw)
	}
	// The same Google account also starts a new account.
	gr := e.do("POST", "/api/v1/auth/google", "", map[string]any{"idToken": e.oidc.googleToken(t, googleSub, googleAud, time.Hour)})
	g := parseAuth(t, gr)
	if gr.Body["isNewUser"] != true || g.UserID == a.UserID || g.UserID == n.UserID || g.Coins != a.Coins {
		t.Fatalf("google sign-in after deletion: %d %s", gr.Status, gr.Raw)
	}
}

// Request rules: exact confirmation, humans only, not version gated, rate
// limited per account.
func TestDeleteAccountRequestRules(t *testing.T) {
	e := newEnv(t, envOpts{proxyHops: 1})
	g := e.guestFromFreshIP()

	if r := e.deleteAccount("", confirmDelete); r.Status != 401 {
		t.Fatalf("no token: %d %s", r.Status, r.Raw)
	}
	for i, body := range []any{nil, map[string]any{"confirm": "delete"}, map[string]any{"confirm": "SUPPRIMER"},
		map[string]any{"confirm": "DELETE", "extra": true}} {
		if r := e.deleteAccount(g.Token, body); r.Status != 400 || errCode(r) != "confirmation_required" {
			t.Fatalf("bad confirmation #%d: %d %s", i, r.Status, r.Raw)
		}
	}
	if r := e.do("GET", "/api/v1/me", g.Token, nil); r.Status != 200 {
		t.Fatalf("a rejected request deleted the account: %d %s", r.Status, r.Raw)
	}

	// Bots: neither a controller nor a bot player session may delete.
	ctl := e.botController(t)
	if r := e.deleteAccount(ctl, confirmDelete); r.Status != 403 {
		t.Fatalf("bot controller: %d %s", r.Status, r.Raw)
	}
	s := e.do("POST", "/api/v1/bot/sessions", ctl, map[string]any{"mode": "loadtest", "name": "Load"})
	if s.Status != 200 {
		t.Fatalf("bot session: %d %s", s.Status, s.Raw)
	}
	if r := e.deleteAccount(s.Body["accessToken"].(string), confirmDelete); r.Status != 403 {
		t.Fatalf("bot player: %d %s", r.Status, r.Raw)
	}

	// Rate limit: 5 requests per hour per account, wrong ones included.
	if r := e.deleteAccount(g.Token, map[string]any{"confirm": "no"}); r.Status != 400 {
		t.Fatalf("fifth request: %d %s", r.Status, r.Raw)
	}
	if r := e.deleteAccount(g.Token, confirmDelete); r.Status != 429 || errCode(r) != "rate_limited" || r.Header.Get("Retry-After") == "" {
		t.Fatalf("sixth request: %d %s", r.Status, r.Raw)
	}

	// Not version gated: works without X-App-* headers (and so for an app
	// version the policy no longer supports).
	h := e.guestFromFreshIP()
	req, _ := http.NewRequest("DELETE", e.srv.URL+"/api/v1/account", strings.NewReader(`{"confirm":"DELETE"}`))
	req.Header.Set("Authorization", "Bearer "+h.Token)
	res, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	_ = res.Body.Close()
	if res.StatusCode != 204 {
		t.Fatalf("delete without app headers: %d", res.StatusCode)
	}
	for tb, n := range e.accountRows(t, h.UserID) {
		if n != 0 {
			t.Errorf("%s: %d rows left", tb, n)
		}
	}
}

// Concurrent deletions of one account: exactly one succeeds, the others get
// 401, and nothing is left half deleted, even with a purchase racing them.
func TestConcurrentAccountDeletion(t *testing.T) {
	e := newEnv(t, envOpts{proxyHops: 1})
	for round := 0; round < 3; round++ {
		a, friend := e.guestFromFreshIP(), e.guestFromFreshIP()
		if r := e.friendRequest(a, friend.UID); r.Status != 201 {
			t.Fatalf("friend request: %d %s", r.Status, r.Raw)
		}
		const deleters = 3
		results := make([]resp, deleters)
		var purchase resp
		var wg sync.WaitGroup
		start := make(chan struct{})
		for i := 0; i < deleters; i++ {
			wg.Add(1)
			go func(i int) {
				defer wg.Done()
				<-start
				results[i] = e.deleteAccount(a.Token, confirmDelete)
			}(i)
		}
		wg.Add(1)
		go func() {
			defer wg.Done()
			<-start
			purchase = e.do("POST", "/api/v1/collection/items/emote_crown/purchase", a.Token, nil)
		}()
		close(start)
		wg.Wait()

		var codes []int
		for _, r := range results {
			codes = append(codes, r.Status)
		}
		slices.Sort(codes)
		want := []int{204}
		for i := 1; i < deleters; i++ {
			want = append([]int{401}, want...)
		}
		slices.Sort(want)
		if !slices.Equal(codes, want) {
			t.Fatalf("round %d: delete statuses %v, want one 204 and the rest 401", round, codes)
		}
		if purchase.Status != 200 && purchase.Status != 401 && purchase.Status != 404 {
			t.Fatalf("round %d: racing purchase: %d %s", round, purchase.Status, purchase.Raw)
		}
		for tb, n := range e.accountRows(t, a.UserID) {
			if n != 0 {
				t.Fatalf("round %d: %s: %d rows left", round, tb, n)
			}
		}
		if rows := e.accountRows(t, friend.UserID); rows["wallet.wallets"] != 1 || rows["progression.friendships"] != 0 {
			t.Fatalf("round %d: friend rows %v", round, rows)
		}
		if n, _ := e.rdb.Exists(context.Background(), "usess:"+a.UserID, "profile:"+a.UserID).Result(); n != 0 {
			t.Fatalf("round %d: %d session/profile keys left", round, n)
		}
	}
}
