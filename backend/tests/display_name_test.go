package tests

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
)

func (e *env) patchName(token string, body any) resp {
	e.t.Helper()
	return e.do("PATCH", "/api/v1/me", token, body)
}

func (e *env) rename(token, name string) resp {
	e.t.Helper()
	return e.patchName(token, map[string]any{"displayName": name})
}

func userOf(t *testing.T, r resp) map[string]any {
	t.Helper()
	u, ok := r.Body["user"].(map[string]any)
	if !ok {
		t.Fatalf("no user in %d %s", r.Status, r.Raw)
	}
	return u
}

func nameOf(t *testing.T, r resp) string {
	t.Helper()
	return userOf(t, r)["displayName"].(string)
}

func errorOf(r resp) (code string, details map[string]any) {
	e, _ := r.Body["error"].(map[string]any)
	code, _ = e["code"].(string)
	details, _ = e["details"].(map[string]any)
	return code, details
}

func keys(m map[string]any) string {
	out := make([]string, 0, len(m))
	for k := range m {
		out = append(out, k)
	}
	sort.Strings(out)
	return strings.Join(out, ",")
}

// lastPayload returns the payload of the newest message of type t.
func (c *client) lastPayload(t string) map[string]any {
	c.mu.Lock()
	defer c.mu.Unlock()
	for i := len(c.all) - 1; i >= 0; i-- {
		if c.all[i].T == t {
			var p map[string]any
			_ = json.Unmarshal(c.all[i].P, &p)
			return p
		}
	}
	return nil
}

func seatName(r *roomState, uid string) string {
	for _, p := range r.Players {
		if p.UID == uid {
			return p.Name
		}
	}
	return ""
}

// metricValue scrapes one sample from the app's Prometheus handler.
func (e *env) metricValue(series string) float64 {
	e.t.Helper()
	rec := httptest.NewRecorder()
	e.app.MetricsHandler().ServeHTTP(rec, httptest.NewRequest("GET", "/metrics", nil))
	body, _ := io.ReadAll(rec.Body)
	m := regexp.MustCompile(`(?m)^` + regexp.QuoteMeta(series) + ` (\S+)$`).FindSubmatch(body)
	if m == nil {
		return 0
	}
	v, _ := strconv.ParseFloat(string(m[1]), 64)
	return v
}

func TestDisplayNameChangePropagates(t *testing.T) {
	e := newEnv(t, envOpts{})
	a, b := e.guest(), e.guest()
	if r := e.do("POST", "/api/v1/friends/requests", a.Token, map[string]any{"friendCode": b.UID}); r.Status != 201 {
		t.Fatalf("friend request: %d %s", r.Status, r.Raw)
	}
	if r := e.do("POST", "/api/v1/friends/requests/"+a.UID+"/accept", b.Token, nil); r.Status != 200 {
		t.Fatalf("accept: %d %s", r.Status, r.Raw)
	}

	// a hosts a private room that is open before the change; b joins it.
	ac, bc := e.mustDial("a", a), e.mustDial("b", b)
	if r := ac.call("room.create", map[string]any{"game": "ludo", "capacity": 4}); r.T != "room.updated" {
		t.Fatalf("create: %s %s", r.T, r.P)
	}
	waitFor(t, 3*time.Second, "lobby", func() bool { s := ac.snapshot(); return s != nil && s.Code != "" })
	open := ac.snapshot()
	if r := bc.call("room.join", map[string]any{"code": open.Code}); r.T != "room.updated" {
		t.Fatalf("join: %s %s", r.T, r.P)
	}
	before := e.do("GET", "/api/v1/me", a.Token, nil)
	oldName := nameOf(t, before)
	if seatName(open, a.UID) != oldName {
		t.Fatalf("seat name %q, want %q", seatName(open, a.UID), oldName)
	}
	changed := e.metricValue(`profile_name_changes_total{result="changed"}`)

	// PATCH /me: normalized name, same response shape as GET /me.
	r := e.rename(a.Token, "  Asha   Verma ")
	if r.Status != 200 || nameOf(t, r) != "Asha Verma" {
		t.Fatalf("PATCH /me: %d %s", r.Status, r.Raw)
	}
	if keys(r.Body) != "user,wallet" || keys(r.Body) != keys(before.Body) ||
		keys(userOf(t, r)) != keys(userOf(t, before)) || keys(r.Body["wallet"].(map[string]any)) != keys(before.Body["wallet"].(map[string]any)) {
		t.Fatalf("PATCH shape %s differs from GET /me %s", r.Raw, before.Raw)
	}
	if u := userOf(t, r); u["id"] != a.UserID || u["uid"] != a.UID {
		t.Fatalf("identity changed: %v", u)
	}
	if got := nameOf(t, e.do("GET", "/api/v1/me", a.Token, nil)); got != "Asha Verma" {
		t.Fatalf("GET /me after change: %q", got)
	}
	if e.metricValue(`profile_name_changes_total{result="changed"}`) != changed+1 {
		t.Fatal("profile_name_changes_total{result=changed} not incremented")
	}

	// Friends list and friends leaderboard show the new name.
	friends := e.do("GET", "/api/v1/friends", b.Token, nil)
	if friends.Status != 200 || !strings.Contains(string(friends.Raw), `"uid":"`+a.UID+`","name":"Asha Verma"`) {
		t.Fatalf("friends: %s", friends.Raw)
	}
	lb := e.do("GET", "/api/v1/leaderboards/friends", b.Token, nil)
	if lb.Status != 200 || !strings.Contains(string(lb.Raw), `"uid":"`+a.UID+`","name":"Asha Verma"`) {
		t.Fatalf("leaderboard: %s", lb.Raw)
	}

	// The room that was already open keeps the name a joined with.
	if m := bc.call("game.request_sync", map[string]any{"roomId": open.ID}); m.T != "game.state" {
		t.Fatalf("sync: %s %s", m.T, m.P)
	}
	if got := seatName(bc.snapshot(), a.UID); got != oldName {
		t.Fatalf("open room seat renamed to %q (want %q)", got, oldName)
	}
	// A room joined after the change shows the new name (seat and preview).
	if m := ac.call("room.leave", map[string]any{"roomId": open.ID}); m.T != "ack" {
		t.Fatalf("leave: %s %s", m.T, m.P)
	}
	if m := ac.call("room.create", map[string]any{"game": "snakes_ladders", "capacity": 2}); m.T != "room.updated" {
		t.Fatalf("create 2: %s %s", m.T, m.P)
	}
	waitFor(t, 3*time.Second, "new lobby", func() bool { s := ac.snapshot(); return s != nil && s.ID != open.ID && s.Code != "" })
	fresh := ac.snapshot()
	if got := seatName(fresh, a.UID); got != "Asha Verma" {
		t.Fatalf("new room seat name %q", got)
	}
	if p := e.do("GET", "/api/v1/rooms/code/"+fresh.Code, b.Token, nil); p.Status != 200 || p.Body["hostName"] != "Asha Verma" {
		t.Fatalf("room preview: %d %s", p.Status, p.Raw)
	}

	// Pushes (friend request) carry the new name.
	c := e.guest()
	cc := e.mustDial("c", c)
	if r := e.do("POST", "/api/v1/friends/requests", a.Token, map[string]any{"friendCode": c.UID}); r.Status != 201 {
		t.Fatalf("friend request 2: %d %s", r.Status, r.Raw)
	}
	waitFor(t, 5*time.Second, "friend request push", func() bool { return cc.count("social.friend_request") > 0 })
	if p := cc.lastPayload("social.friend_request"); p["fromName"] != "Asha Verma" || p["fromUid"] != a.UID {
		t.Fatalf("friend request push: %v", p)
	}
}

func TestDisplayNameSurvivesSignInAndCacheLoss(t *testing.T) {
	e := newEnv(t, envOpts{})
	ctx := context.Background()
	google := func(subject string) account {
		return parseAuth(t, e.do("POST", "/api/v1/auth/google", "", map[string]any{"idToken": e.oidc.googleToken(t, sub(subject), googleAud, time.Hour)}))
	}
	g := google("dn-google")
	if got := nameOf(t, e.do("GET", "/api/v1/me", g.Token, nil)); got != "Tester" {
		t.Fatalf("provider name %q", got)
	}
	if r := e.rename(g.Token, "Rahul Kumar"); r.Status != 200 {
		t.Fatalf("rename: %d %s", r.Status, r.Raw)
	}
	// A later Google sign-in (given_name "Tester") does not overwrite it.
	again := e.do("POST", "/api/v1/auth/google", "", map[string]any{"idToken": e.oidc.googleToken(t, sub("dn-google"), googleAud, time.Hour)})
	if again.Status != 200 || nameOf(t, again) != "Rahul Kumar" || userOf(t, again)["id"] != g.UserID {
		t.Fatalf("Google sign-in after rename: %d %s", again.Status, again.Raw)
	}
	g3 := parseAuth(t, again)
	if got := nameOf(t, e.do("GET", "/api/v1/me", g3.Token, nil)); got != "Rahul Kumar" {
		t.Fatalf("after Google sign-in: %q", got)
	}

	// A guest who chose a name keeps it when linking Google.
	h := e.guest()
	if r := e.rename(h.Token, "Putri Ayu"); r.Status != 200 {
		t.Fatalf("guest rename: %d %s", r.Status, r.Raw)
	}
	link := e.do("POST", "/api/v1/account/link/google", h.Token, map[string]any{"idToken": e.oidc.googleToken(t, sub("dn-link"), googleAud, time.Hour)})
	if link.Status != 200 || nameOf(t, link) != "Putri Ayu" {
		t.Fatalf("link: %d %s", link.Status, link.Raw)
	}

	// Redis lost the profile: reads and the next sign-in restore the name
	// from PostgreSQL.
	if err := e.rdb.Del(ctx, "profile:"+g3.UserID).Err(); err != nil {
		t.Fatal(err)
	}
	if got := nameOf(t, e.do("GET", "/api/v1/me", g3.Token, nil)); got != "Rahul Kumar" {
		t.Fatalf("GET /me after cache loss: %q", got)
	}
	_ = e.rdb.Del(ctx, "profile:"+g3.UserID, "profile:"+h.UserID)
	if got := nameOf(t, e.do("POST", "/api/v1/auth/google", "", map[string]any{"idToken": e.oidc.googleToken(t, sub("dn-google"), googleAud, time.Hour)})); got != "Rahul Kumar" {
		t.Fatalf("Google sign-in after cache loss: %q", got)
	}
	if n, _ := e.rdb.HGet(ctx, "profile:"+g3.UserID, "name").Result(); n != "Rahul Kumar" {
		t.Fatalf("cache not rebuilt at sign-in: %q", n)
	}
	// h is linked now: it is reached through Google (its guest secret ended
	// with the link), and its chosen name wins over Google's.
	if got := nameOf(t, e.do("POST", "/api/v1/auth/google", "", map[string]any{"idToken": e.oidc.googleToken(t, sub("dn-link"), googleAud, time.Hour)})); got != "Putri Ayu" {
		t.Fatalf("linked guest's Google sign-in after cache loss: %q", got)
	}
	// A guest (no provider name at all) gets its chosen name back as well.
	k := e.guest()
	if r := e.rename(k.Token, "Siti Rahma"); r.Status != 200 {
		t.Fatalf("guest rename: %d %s", r.Status, r.Raw)
	}
	_ = e.rdb.Del(ctx, "profile:"+k.UserID)
	resumed := e.do("POST", "/api/v1/auth/guest/resume", "", map[string]any{"guestSecret": k.GuestSecret})
	if resumed.Status != 200 || nameOf(t, resumed) != "Siti Rahma" {
		t.Fatalf("guest resume after cache loss: %d %s", resumed.Status, resumed.Raw)
	}
}

func TestDisplayNameLimitValidationAndAuth(t *testing.T) {
	e := newEnv(t, envOpts{})

	// At most 3 successful changes per rolling 24 h; repeating the current
	// name is a no-op that does not count.
	u := e.guest()
	for _, n := range []string{"Name One", "Name Two", "Name Three"} {
		if r := e.rename(u.Token, n); r.Status != 200 || nameOf(t, r) != n {
			t.Fatalf("rename %q: %d %s", n, r.Status, r.Raw)
		}
	}
	unchanged := e.metricValue(`profile_name_changes_total{result="unchanged"}`)
	if r := e.rename(u.Token, " Name  Three "); r.Status != 200 || nameOf(t, r) != "Name Three" {
		t.Fatalf("same name: %d %s", r.Status, r.Raw)
	}
	if e.metricValue(`profile_name_changes_total{result="unchanged"}`) != unchanged+1 {
		t.Fatal("unchanged metric not incremented")
	}
	over := e.rename(u.Token, "Name Four")
	code, details := errorOf(over)
	retry, _ := strconv.Atoi(over.Header.Get("Retry-After"))
	if over.Status != 429 || code != "rate_limited" || retry < 1 || retry > 24*3600+1 ||
		details["reason"] != "name_change_limit" || details["limit"] != float64(3) {
		t.Fatalf("4th change: %d %s (Retry-After %q)", over.Status, over.Raw, over.Header.Get("Retry-After"))
	}
	if got := nameOf(t, e.do("GET", "/api/v1/me", u.Token, nil)); got != "Name Three" {
		t.Fatalf("name after limit: %q", got)
	}

	// Invalid names → 400 invalid_name with a reason; they never count.
	v := e.guest()
	invalid := []struct{ name, reason string }{
		{"ab", "too_short"},
		{"   ", "too_short"},
		{"abcdefghijklmnopq", "too_long"},
		{"😀😀😀", "invalid_characters"},
		{"Ra\U0000200dhul", "invalid_characters"},
		{"Asha!", "invalid_characters"},
		{"B o t Max", "reserved"},
		{"ADMIN", "reserved"},
		{"Ludo Arena", "reserved"},
		{"Ludo Royale", "reserved"},
		{"Madarchod", "inappropriate"},
	}
	for _, c := range invalid {
		r := e.rename(v.Token, c.name)
		code, details := errorOf(r)
		if r.Status != 400 || code != "invalid_name" || details["reason"] != c.reason {
			t.Fatalf("%q: %d %s, want invalid_name/%s", c.name, r.Status, r.Raw, c.reason)
		}
	}
	// Malformed bodies → 400 bad_request.
	for _, body := range []any{
		map[string]any{"displayName": "Asha", "avatar": 3}, // unknown field
		map[string]any{},
		map[string]any{"displayName": nil},
		map[string]any{"displayName": 5},
	} {
		if r := e.patchName(v.Token, body); r.Status != 400 {
			t.Fatalf("body %v: %d %s", body, r.Status, r.Raw)
		} else if code, _ := errorOf(r); code != "bad_request" {
			t.Fatalf("body %v: %s", body, r.Raw)
		}
	}
	// Scripts of the supported locales are accepted, and the failures above
	// did not use up the limit (3 changes still possible).
	for _, n := range []string{"राहुल", "علی رضا", "Putri Ayu"} {
		if r := e.rename(v.Token, n); r.Status != 200 || nameOf(t, r) != n {
			t.Fatalf("rename %q: %d %s", n, r.Status, r.Raw)
		}
	}
	if r := e.rename(v.Token, "محمد"); r.Status != 429 {
		t.Fatalf("4th change after invalid attempts: %d %s", r.Status, r.Raw)
	}

	// Bots (controller and bot player tokens) cannot change names.
	ctl := e.botController(t)
	if r := e.rename(ctl, "Asha"); r.Status != http.StatusForbidden {
		t.Fatalf("controller token: %d %s", r.Status, r.Raw)
	}
	bot, err := e.app.BotAuth.IssueBot(context.Background(), uuid.Nil, "r_test", false, "Asha", "balanced", time.Minute)
	if err != nil {
		t.Fatal(err)
	}
	if r := e.rename(bot.Token, "Asha"); r.Status != http.StatusForbidden {
		t.Fatalf("bot token: %d %s", r.Status, r.Raw)
	}
	if r := e.rename("", "Asha"); r.Status != http.StatusUnauthorized {
		t.Fatalf("no token: %d", r.Status)
	}
}
