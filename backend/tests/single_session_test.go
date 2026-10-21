package tests

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"io"
	"net/http"
	"strings"
	"testing"
	"time"

	"github.com/coder/websocket"
)

// errCode returns error.code of a REST error response ("" if none).
func errCode(r resp) string {
	e, _ := r.Body["error"].(map[string]any)
	code, _ := e["code"].(string)
	return code
}

// sidOf reads the session id claim of an application access token.
func sidOf(t *testing.T, token string) string {
	t.Helper()
	parts := strings.Split(token, ".")
	if len(parts) != 3 {
		t.Fatalf("malformed token %q", token)
	}
	raw, err := base64.RawURLEncoding.DecodeString(parts[1])
	if err != nil {
		t.Fatal(err)
	}
	var c struct {
		Sid string `json:"sid"`
	}
	if err := json.Unmarshal(raw, &c); err != nil || c.Sid == "" {
		t.Fatalf("no sid claim: %s", raw)
	}
	return c.Sid
}

// waitClosed waits for the server to close c and returns the close code.
func waitClosed(t *testing.T, c *client, within time.Duration, what string) websocket.StatusCode {
	t.Helper()
	select {
	case <-c.closed:
	case <-time.After(within):
		t.Fatalf("%s: connection not closed within %s", what, within)
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.closeCode
}

func assertOpen(t *testing.T, c *client, what string) {
	t.Helper()
	select {
	case <-c.closed:
		c.mu.Lock()
		code := c.closeCode
		c.mu.Unlock()
		t.Fatalf("%s: connection closed unexpectedly (code %d)", what, code)
	default:
	}
}

// assertReplaced checks that every way device "acct" can use its session now
// reports session_replaced: refresh, authenticated REST and the WS handshake.
func (e *env) assertReplaced(t *testing.T, acct account, what string) {
	t.Helper()
	if r := e.do("POST", "/api/v1/auth/refresh", "", map[string]any{"refreshToken": acct.Refresh}); r.Status != 401 || errCode(r) != "session_replaced" {
		t.Fatalf("%s refresh: %d %s, want 401 session_replaced", what, r.Status, r.Raw)
	}
	if r := e.do("GET", "/api/v1/me", acct.Token, nil); r.Status != 401 || errCode(r) != "session_replaced" {
		t.Fatalf("%s /me: %d %s, want 401 session_replaced", what, r.Status, r.Raw)
	}
	_, res, err := e.dial(what+"-redial", acct, nil)
	if err == nil || res == nil || res.StatusCode != http.StatusUnauthorized {
		t.Fatalf("%s WS handshake not rejected with 401: %v %v", what, err, res)
	}
	body, _ := io.ReadAll(res.Body)
	if !strings.Contains(string(body), `"session_replaced"`) {
		t.Fatalf("%s WS handshake body: %s", what, body)
	}
}

// One live human session per account: the last sign-in wins. Signing in on
// another device (guest resume, provider sign-in) ends the previous device's
// session for refresh, REST and its live WebSocket (4401, immediately).
func TestSignInElsewhereReplacesSession(t *testing.T) {
	e := newEnv(t, envOpts{})
	a := e.guest()
	ca := e.mustDial("deviceA", a)

	// Device B restores the same guest account.
	b := parseAuth(t, e.do("POST", "/api/v1/auth/guest/resume", "", map[string]any{"guestSecret": a.GuestSecret}))
	signedIn := time.Now()
	if b.UserID != a.UserID {
		t.Fatalf("resume resolved to %s, want %s", b.UserID, a.UserID)
	}
	if code := waitClosed(t, ca, 3*time.Second, "device A"); code != 4401 {
		t.Fatalf("device A close code = %d, want 4401", code)
	}
	if d := time.Since(signedIn); d > 3*time.Second {
		t.Fatalf("device A kicked after %s; the revoke must not wait for the periodic re-check", d)
	}
	e.assertReplaced(t, a, "device A")
	if n, _ := e.rdb.Exists(context.Background(), "sessrep:"+sidOf(t, a.Token)).Result(); n != 1 {
		t.Fatal("replaced session has no tombstone")
	}

	// Device B keeps working: REST, refresh rotation, WebSocket.
	if r := e.do("GET", "/api/v1/me", b.Token, nil); r.Status != 200 {
		t.Fatalf("device B /me: %d %s", r.Status, r.Raw)
	}
	b1 := parseAuth(t, e.do("POST", "/api/v1/auth/refresh", "", map[string]any{"refreshToken": b.Refresh}))
	if sidOf(t, b1.Token) != sidOf(t, b.Token) {
		t.Fatal("refresh changed the session id")
	}
	cb := e.mustDial("deviceB", b1)
	if m := cb.call("game.request_sync", map[string]any{}); m.T == "" {
		t.Fatal("device B WS not usable")
	}
	// A revoke for some other session id of this user leaves B connected.
	e.app.Gateway.RevokeSession(context.Background(), b.UserID, "not-this-session")
	time.Sleep(300 * time.Millisecond)
	assertOpen(t, cb, "device B after unrelated revoke")

	// Device C signs in with a Google account linked to the same profile:
	// B (refreshed, connected) is replaced in turn.
	idTok := e.oidc.googleToken(t, sub("single"), googleAud, time.Hour)
	if r := e.do("POST", "/api/v1/account/link/google", b1.Token, map[string]any{"idToken": idTok}); r.Status != 200 {
		t.Fatalf("link: %d %s", r.Status, r.Raw)
	}
	assertOpen(t, cb, "device B after linking") // linking is not a sign-in
	c := parseAuth(t, e.do("POST", "/api/v1/auth/google", "", map[string]any{"idToken": idTok}))
	signedIn = time.Now()
	if c.UserID != a.UserID {
		t.Fatalf("google sign-in resolved to %s", c.UserID)
	}
	if code := waitClosed(t, cb, 3*time.Second, "device B"); code != 4401 {
		t.Fatalf("device B close code = %d, want 4401", code)
	}
	if d := time.Since(signedIn); d > 3*time.Second {
		t.Fatalf("device B kicked after %s", d)
	}
	e.assertReplaced(t, b1, "device B")
	// The first device stays replaced.
	e.assertReplaced(t, a, "device A (again)")

	cc := e.mustDial("deviceC", c)
	if r := e.do("GET", "/api/v1/me", c.Token, nil); r.Status != 200 {
		t.Fatalf("device C /me: %d %s", r.Status, r.Raw)
	}
	time.Sleep(300 * time.Millisecond)
	assertOpen(t, cc, "device C")
	if cur, _ := e.rdb.Get(context.Background(), "usess:"+c.UserID).Result(); cur != sidOf(t, c.Token) {
		t.Fatalf("usess pointer = %q, want device C's session", cur)
	}
}

// Logout is a plain revocation, never "replaced", and does not affect the
// next sign-in.
func TestLogoutIsNotSessionReplaced(t *testing.T) {
	e := newEnv(t, envOpts{})
	ctx := context.Background()
	g := e.guest()
	g1 := parseAuth(t, e.do("POST", "/api/v1/auth/refresh", "", map[string]any{"refreshToken": g.Refresh}))
	if cur, _ := e.rdb.Get(ctx, "usess:"+g.UserID).Result(); cur != sidOf(t, g1.Token) {
		t.Fatalf("usess pointer = %q after refresh", cur)
	}
	if r := e.do("POST", "/api/v1/auth/logout", g1.Token, map[string]any{}); r.Status != 204 {
		t.Fatalf("logout: %d %s", r.Status, r.Raw)
	}
	if n, _ := e.rdb.Exists(ctx, "usess:"+g.UserID, "sessrep:"+sidOf(t, g1.Token)).Result(); n != 0 {
		t.Fatal("logout left the account pointer or wrote a replaced tombstone")
	}
	check := func(when string) {
		t.Helper()
		if r := e.do("POST", "/api/v1/auth/refresh", "", map[string]any{"refreshToken": g1.Refresh}); r.Status != 401 || errCode(r) != "invalid_credential" {
			t.Fatalf("refresh %s: %d %s, want 401 invalid_credential", when, r.Status, r.Raw)
		}
		if r := e.do("GET", "/api/v1/me", g1.Token, nil); r.Status != 401 || errCode(r) != "unauthorized" {
			t.Fatalf("/me %s: %d %s, want 401 unauthorized", when, r.Status, r.Raw)
		}
	}
	check("after logout")

	// Signing in again works and does not turn the logged-out session into a
	// "replaced" one.
	again := parseAuth(t, e.do("POST", "/api/v1/auth/guest/resume", "", map[string]any{"guestSecret": g.GuestSecret}))
	if again.UserID != g.UserID {
		t.Fatalf("resume resolved to %s", again.UserID)
	}
	check("after the next sign-in")
	if r := e.do("GET", "/api/v1/me", again.Token, nil); r.Status != 200 {
		t.Fatalf("/me after re-sign-in: %d %s", r.Status, r.Raw)
	}
	if n, _ := e.rdb.Exists(ctx, "sessrep:"+sidOf(t, g1.Token)).Result(); n != 0 {
		t.Fatal("the next sign-in tombstoned a logged-out session as replaced")
	}
}

// Logout works without a valid access token: the current refresh token in
// the body identifies the session. A rotated (old) refresh token never
// revokes, and the endpoint answers 204 either way.
func TestLogoutWithRefreshTokenOnly(t *testing.T) {
	e := newEnv(t, envOpts{})
	ctx := context.Background()
	g := e.guest()
	g1 := parseAuth(t, e.do("POST", "/api/v1/auth/refresh", "", map[string]any{"refreshToken": g.Refresh}))

	// The old (rotated) refresh token: 204, but the live session survives and
	// it is not treated as refresh-token reuse.
	if r := e.do("POST", "/api/v1/auth/logout", "", map[string]any{"refreshToken": g.Refresh}); r.Status != 204 {
		t.Fatalf("logout with old refresh token: %d %s", r.Status, r.Raw)
	}
	if r := e.do("GET", "/api/v1/me", g1.Token, nil); r.Status != 200 {
		t.Fatalf("old refresh token revoked the live session: %d %s", r.Status, r.Raw)
	}
	g2 := parseAuth(t, e.do("POST", "/api/v1/auth/refresh", "", map[string]any{"refreshToken": g1.Refresh}))
	if sidOf(t, g2.Token) != sidOf(t, g.Token) {
		t.Fatal("session changed")
	}

	// Unknown tokens and repeats are 204 too; malformed bodies are 400; no
	// credential at all is 401.
	if r := e.do("POST", "/api/v1/auth/logout", "", map[string]any{"refreshToken": "rt_unknownunknownunknownunknown"}); r.Status != 204 {
		t.Fatalf("logout with unknown refresh token: %d %s", r.Status, r.Raw)
	}
	if r := e.do("POST", "/api/v1/auth/logout", "", "not-an-object"); r.Status != 400 {
		t.Fatalf("malformed logout body: %d %s", r.Status, r.Raw)
	}
	if r := e.do("POST", "/api/v1/auth/logout", "", map[string]any{}); r.Status != 401 {
		t.Fatalf("logout without any credential: %d %s", r.Status, r.Raw)
	}
	if r := e.do("GET", "/api/v1/me", g2.Token, nil); r.Status != 200 {
		t.Fatalf("session revoked by a no-op logout: %d %s", r.Status, r.Raw)
	}

	// The current refresh token with no Authorization header (and, the same,
	// with an unusable one) revokes the session.
	for i, bearer := range []string{"", "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ4In0.expired"} {
		cur := g2
		if i > 0 {
			cur = parseAuth(t, e.do("POST", "/api/v1/auth/guest/resume", "", map[string]any{"guestSecret": g.GuestSecret}))
		}
		if r := e.do("POST", "/api/v1/auth/logout", bearer, map[string]any{"refreshToken": cur.Refresh}); r.Status != 204 {
			t.Fatalf("logout #%d with refresh token: %d %s", i, r.Status, r.Raw)
		}
		if r := e.do("POST", "/api/v1/auth/refresh", "", map[string]any{"refreshToken": cur.Refresh}); r.Status != 401 || errCode(r) != "invalid_credential" {
			t.Fatalf("refresh after logout #%d: %d %s, want 401 invalid_credential", i, r.Status, r.Raw)
		}
		if r := e.do("GET", "/api/v1/me", cur.Token, nil); r.Status != 401 || errCode(r) != "unauthorized" {
			t.Fatalf("/me after logout #%d: %d %s, want 401 unauthorized", i, r.Status, r.Raw)
		}
		if _, res, err := e.dial("after-logout", cur, nil); err == nil || res == nil || res.StatusCode != http.StatusUnauthorized {
			t.Fatalf("WS handshake after logout #%d not rejected with 401: %v %v", i, err, res)
		}
		if n, _ := e.rdb.Exists(ctx, "usess:"+g.UserID, "sessrep:"+sidOf(t, cur.Token)).Result(); n != 0 {
			t.Fatalf("logout #%d left the account pointer or wrote a replaced tombstone", i)
		}
		// Idempotent.
		if r := e.do("POST", "/api/v1/auth/logout", "", map[string]any{"refreshToken": cur.Refresh}); r.Status != 204 {
			t.Fatalf("repeated logout #%d: %d %s", i, r.Status, r.Raw)
		}
	}
}

// Bot sessions are outside the one-session rule: several controller tokens
// (same controller subject) and bot player sessions coexist, and none of them
// affects a human session.
func TestBotSessionsDoNotReplaceEachOther(t *testing.T) {
	e := newEnv(t, envOpts{})
	ctx := context.Background()
	human := e.guest()
	hc := e.mustDial("human", human)

	ctl1, ctl2 := e.botController(t), e.botController(t)
	var bots []*client
	for i := 0; i < 2; i++ {
		s := e.do("POST", "/api/v1/bot/sessions", ctl1, map[string]any{"mode": "loadtest", "name": "Load"})
		if s.Status != 200 {
			t.Fatalf("loadtest session: %d %s", s.Status, s.Raw)
		}
		acct := account{Token: s.Body["accessToken"].(string), UID: s.Body["uid"].(string)}
		c, _, err := e.dial("bot"+acct.UID, acct, map[string]string{"X-App-Platform": "bot"})
		if err != nil {
			t.Fatalf("bot dial: %v", err)
		}
		bots = append(bots, c)
	}
	for i, ctl := range []string{ctl1, ctl2} {
		if r := e.do("GET", "/api/v1/bot/lobbies", ctl, nil); r.Status != 200 {
			t.Fatalf("controller %d revoked: %d %s", i+1, r.Status, r.Raw)
		}
	}
	time.Sleep(300 * time.Millisecond)
	for _, b := range bots {
		assertOpen(t, b, b.name)
	}
	assertOpen(t, hc, "human")
	if r := e.do("GET", "/api/v1/me", human.Token, nil); r.Status != 200 {
		t.Fatalf("human /me: %d %s", r.Status, r.Raw)
	}
	keys, err := e.rdb.Keys(ctx, "usess:*").Result()
	if err != nil || len(keys) != 1 || keys[0] != "usess:"+human.UserID {
		t.Fatalf("usess keys = %v (%v), want only the human's", keys, err)
	}
	if keys, _ := e.rdb.Keys(ctx, "sessrep:*").Result(); len(keys) != 0 {
		t.Fatalf("unexpected replaced tombstones: %v", keys)
	}
}
