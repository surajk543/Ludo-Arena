package tests

import (
	"context"
	"net/http"
	"net/url"
	"strings"
	"sync"
	"testing"
	"time"
)

func TestGuestAccountWalletAndSessions(t *testing.T) {
	e := newEnv(t, envOpts{})
	g := e.guest()
	if g.Coins != 1_000_000 || g.Diamonds != 50 {
		t.Fatalf("welcome grant = %d coins / %d diamonds", g.Coins, g.Diamonds)
	}
	if g.GuestSecret == "" || g.UID == "" || g.UID == g.UserID {
		t.Fatal("guest secret / public uid missing or leaking the account id")
	}
	me := e.do("GET", "/api/v1/me", g.Token, nil)
	if me.Status != 200 || me.Body["user"].(map[string]any)["isGuest"] != true ||
		me.Body["user"].(map[string]any)["actorType"] != "human" {
		t.Fatalf("/me: %d %s", me.Status, me.Raw)
	}

	// Refresh rotates; re-using the old refresh token revokes the session.
	r1 := e.do("POST", "/api/v1/auth/refresh", "", map[string]any{"refreshToken": g.Refresh})
	a1 := parseAuth(t, r1)
	if a1.Refresh == g.Refresh || a1.UserID != g.UserID {
		t.Fatal("refresh did not rotate")
	}
	reuse := e.do("POST", "/api/v1/auth/refresh", "", map[string]any{"refreshToken": g.Refresh})
	if reuse.Status != 401 || reuse.Body["error"].(map[string]any)["code"] != "refresh_reused" {
		t.Fatalf("refresh reuse: %d %s", reuse.Status, reuse.Raw)
	}
	if r := e.do("GET", "/api/v1/me", a1.Token, nil); r.Status != 401 {
		t.Fatalf("family should be revoked after reuse, got %d", r.Status)
	}

	// The durable guest secret restores the SAME account without a new bonus.
	res := parseAuth(t, e.do("POST", "/api/v1/auth/guest/resume", "", map[string]any{"guestSecret": g.GuestSecret}))
	if res.UserID != g.UserID || res.Coins != 1_000_000 {
		t.Fatalf("resume: user %s coins %d", res.UserID, res.Coins)
	}
	// Logout revokes immediately.
	if r := e.do("POST", "/api/v1/auth/logout", res.Token, map[string]any{}); r.Status != 204 {
		t.Fatalf("logout: %d", r.Status)
	}
	if r := e.do("GET", "/api/v1/me", res.Token, nil); r.Status != 401 {
		t.Fatalf("token still valid after logout: %d", r.Status)
	}
	if r := e.do("POST", "/api/v1/auth/guest/resume", "", map[string]any{"guestSecret": "gs_wrongwrongwrongwrongwrong"}); r.Status != 401 {
		t.Fatalf("bad guest secret accepted: %d", r.Status)
	}
	// Client-supplied identity is never trusted: a forged token is rejected.
	if r := e.do("GET", "/api/v1/me", "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ4In0.bad", nil); r.Status != 401 {
		t.Fatalf("forged token accepted: %d", r.Status)
	}
}

func TestGoogleLoginLinkingAndConflicts(t *testing.T) {
	e := newEnv(t, envOpts{})
	// Wrong audience / expired tokens are rejected.
	bad := e.do("POST", "/api/v1/auth/google", "", map[string]any{"idToken": e.oidc.googleToken(t, sub("x"), "other-aud", time.Hour)})
	if bad.Status != 401 {
		t.Fatalf("wrong audience accepted: %d %s", bad.Status, bad.Raw)
	}
	exp := e.do("POST", "/api/v1/auth/google", "", map[string]any{"idToken": e.oidc.googleToken(t, sub("x"), googleAud, -time.Minute)})
	if exp.Status != 401 {
		t.Fatalf("expired token accepted: %d", exp.Status)
	}

	// A guest links Google: same account id and wallet, no second bonus.
	g := e.guest()
	link := e.do("POST", "/api/v1/account/link/google", g.Token, map[string]any{"idToken": e.oidc.googleToken(t, sub("link"), googleAud, time.Hour)})
	if link.Status != 200 {
		t.Fatalf("link: %d %s", link.Status, link.Raw)
	}
	user := link.Body["user"].(map[string]any)
	if user["id"] != g.UserID || user["isGuest"] != false || link.Body["wallet"].(map[string]any)["coins"].(float64) != 1_000_000 {
		t.Fatalf("link changed account or wallet: %s", link.Raw)
	}
	// Signing in with that Google account on "another device" resolves to it
	// and, one live session per account (last sign-in wins), ends the first
	// device's session.
	other := parseAuth(t, e.do("POST", "/api/v1/auth/google", "", map[string]any{"idToken": e.oidc.googleToken(t, sub("link"), googleAud, time.Hour)}))
	if other.UserID != g.UserID || other.Coins != 1_000_000 {
		t.Fatalf("provider login resolved to %s with %d coins", other.UserID, other.Coins)
	}
	if r := e.do("GET", "/api/v1/me", g.Token, nil); r.Status != 401 || errCode(r) != "session_replaced" {
		t.Fatalf("first device after sign-in elsewhere: %d %s, want 401 session_replaced", r.Status, r.Raw)
	}
	if r := e.do("POST", "/api/v1/auth/refresh", "", map[string]any{"refreshToken": g.Refresh}); r.Status != 401 || errCode(r) != "session_replaced" {
		t.Fatalf("first device refresh: %d %s, want 401 session_replaced", r.Status, r.Raw)
	}

	// Another guest trying to link the same Google identity gets a conflict;
	// nothing is merged or moved.
	g2 := e.guest()
	conflict := e.do("POST", "/api/v1/account/link/google", g2.Token, map[string]any{"idToken": e.oidc.googleToken(t, sub("link"), googleAud, time.Hour)})
	if conflict.Status != 409 || conflict.Body["error"].(map[string]any)["code"] != "identity_conflict" {
		t.Fatalf("conflict: %d %s", conflict.Status, conflict.Raw)
	}
	if e.coins(g2.Token) != 1_000_000 || e.coins(other.Token) != 1_000_000 {
		t.Fatal("conflict changed balances")
	}
	// Linking a second, different Google account to the same profile fails
	// (from the device that is now signed in).
	again := e.do("POST", "/api/v1/account/link/google", other.Token, map[string]any{"idToken": e.oidc.googleToken(t, sub("second"), googleAud, time.Hour)})
	if again.Status != 409 || again.Body["error"].(map[string]any)["code"] != "provider_already_linked" {
		t.Fatalf("second google link: %d %s", again.Status, again.Raw)
	}
	// Re-linking the same identity is idempotent.
	if r := e.do("POST", "/api/v1/account/link/google", other.Token, map[string]any{"idToken": e.oidc.googleToken(t, sub("link"), googleAud, time.Hour)}); r.Status != 200 {
		t.Fatalf("idempotent relink: %d", r.Status)
	}
}

func TestConcurrentFirstLoginProvisionsOnce(t *testing.T) {
	e := newEnv(t, envOpts{})
	tok := e.oidc.googleToken(t, sub("race"), googleAud, time.Hour)
	var wg sync.WaitGroup
	ids := make(chan string, 20)
	tokens := make(chan string, 20)
	for i := 0; i < 20; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			r := e.do("POST", "/api/v1/auth/google", "", map[string]any{"idToken": tok})
			if r.Status == 200 {
				ids <- r.Body["user"].(map[string]any)["id"].(string)
				tokens <- r.Body["accessToken"].(string)
			}
		}()
	}
	wg.Wait()
	close(ids)
	close(tokens)
	// One live session per account: concurrent sign-ins leave exactly one.
	live := 0
	for at := range tokens {
		if r := e.do("GET", "/api/v1/me", at, nil); r.Status == 200 {
			live++
		} else if errCode(r) != "session_replaced" {
			t.Fatalf("concurrent sign-in session: %d %s", r.Status, r.Raw)
		}
	}
	if live != 1 {
		t.Fatalf("%d live sessions after concurrent sign-ins, want 1", live)
	}
	seen := map[string]bool{}
	for id := range ids {
		seen[id] = true
	}
	if len(seen) != 1 {
		t.Fatalf("concurrent first logins created %d accounts", len(seen))
	}
	var n int
	if err := e.app.PG.QueryRow(context.Background(),
		`SELECT count(*) FROM identity.auth_identities WHERE provider='google' AND subject=$1`, sub("race")).Scan(&n); err != nil || n != 1 {
		t.Fatalf("identity rows = %d (%v)", n, err)
	}
	for id := range seen {
		var coins int64
		if err := e.app.PG.QueryRow(context.Background(), `SELECT coins FROM wallet.wallets WHERE user_id=$1`, id).Scan(&coins); err != nil || coins != 1_000_000 {
			t.Fatalf("wallet = %d (%v)", coins, err)
		}
	}
}

func TestRateLimitedGuestCreation(t *testing.T) {
	e := newEnv(t, envOpts{})
	limited := false
	for i := 0; i < 15; i++ {
		if r := e.do("POST", "/api/v1/auth/guest", "", map[string]any{}); r.Status == 429 {
			limited = true
			break
		}
	}
	if !limited {
		t.Fatal("guest creation was not rate limited")
	}
}

func TestAppleAndroidCallbackRedirect(t *testing.T) {
	e := newEnv(t, envOpts{})
	client := &http.Client{CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }}
	res, err := client.PostForm(e.srv.URL+"/api/v1/auth/apple/callback", url.Values{"code": {"abc"}, "id_token": {"x.y.z"}, "state": {"s1"}})
	if err != nil {
		t.Fatal(err)
	}
	defer res.Body.Close()
	loc := res.Header.Get("Location")
	if res.StatusCode != http.StatusSeeOther || !strings.HasPrefix(loc, "intent://callback?") ||
		!strings.Contains(loc, "package=com.ludoroyale.app;scheme=signinwithapple;end") || !strings.Contains(loc, "id_token=x.y.z") {
		t.Fatalf("callback redirect: %d %s", res.StatusCode, loc)
	}
}
