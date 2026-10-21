package tests

import (
	"context"
	"os"
	"strings"
	"sync"
	"testing"
	"time"
)

// policyWithWelcome is the test policy plus a "welcome" object (raw JSON).
func policyWithWelcome(welcome string) string {
	base := policyJSON("1.0.0", 1, "1.0.0", 1, false)
	out := strings.Replace(base, `"environment":"development",`, `"environment":"development","welcome":`+welcome+`,`, 1)
	if out == base {
		panic("policyWithWelcome: environment marker not found")
	}
	return out
}

// wallet reads (coins, diamonds) via GET /wallet.
func (e *env) wallet(t *testing.T, token string) (coins, diamonds int64) {
	t.Helper()
	r := e.do("GET", "/api/v1/wallet", token, nil)
	if r.Status != 200 {
		t.Fatalf("wallet: %d %s", r.Status, r.Raw)
	}
	return int64(r.Body["coins"].(float64)), int64(r.Body["diamonds"].(float64))
}

func (e *env) wantAppConfigWelcome(t *testing.T, coins, diamonds int64) {
	t.Helper()
	r := e.do("GET", "/api/v1/app/config?platform=android&version=1.0.0&build=1", "", nil)
	w, ok := r.Body["welcome"].(map[string]any)
	if r.Status != 200 || !ok {
		t.Fatalf("app config welcome: %d %s", r.Status, r.Raw)
	}
	if c, d := int64(w["coins"].(float64)), int64(w["diamonds"].(float64)); c != coins || d != diamonds {
		t.Fatalf("/app/config welcome = %d / %d, want %d / %d", c, d, coins, diamonds)
	}
}

// TestWelcomeGrantLiveFromPolicy: the one-time welcome grant comes from the
// app-policy file (live), applies to accounts created after a change, never
// touches existing accounts, and is still granted exactly once under
// concurrent first logins.
func TestWelcomeGrantLiveFromPolicy(t *testing.T) {
	e := newEnv(t, envOpts{})

	// Defaults: no "welcome" in the test policy, WELCOME_* unset.
	e.wantAppConfigWelcome(t, 1_000_000, 50)
	old := e.guest()
	if old.Coins != 1_000_000 || old.Diamonds != 50 {
		t.Fatalf("default grant = %d / %d", old.Coins, old.Diamonds)
	}

	// The operator changes the grant in the policy file: no restart.
	if err := e.reloadPolicy(t, policyWithWelcome(`{"coins":2000000,"diamonds":75}`)); err != nil {
		t.Fatal(err)
	}
	e.wantAppConfigWelcome(t, 2_000_000, 75)

	// The next new account gets the new amounts (response and stored wallet).
	fresh := e.guest()
	if fresh.Coins != 2_000_000 || fresh.Diamonds != 75 {
		t.Fatalf("new account grant = %d / %d, want 2000000 / 75", fresh.Coins, fresh.Diamonds)
	}
	if c, d := e.wallet(t, fresh.Token); c != 2_000_000 || d != 75 {
		t.Fatalf("new account wallet = %d / %d", c, d)
	}

	// The existing account is unchanged and resuming it grants nothing.
	if c, d := e.wallet(t, old.Token); c != 1_000_000 || d != 50 {
		t.Fatalf("existing account changed: %d / %d", c, d)
	}
	res := parseAuth(t, e.do("POST", "/api/v1/auth/guest/resume", "", map[string]any{"guestSecret": old.GuestSecret}))
	if res.UserID != old.UserID || res.Coins != 1_000_000 || res.Diamonds != 50 {
		t.Fatalf("resume re-granted: user %s %d / %d", res.UserID, res.Coins, res.Diamonds)
	}

	// Concurrent first logins of one new identity: one account, one grant of
	// the configured amount.
	tok := e.oidc.googleToken(t, sub("welcome-race"), googleAud, time.Hour)
	var wg sync.WaitGroup
	ids := make(chan string, 12)
	for i := 0; i < 12; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			if r := e.do("POST", "/api/v1/auth/google", "", map[string]any{"idToken": tok}); r.Status == 200 {
				ids <- r.Body["user"].(map[string]any)["id"].(string)
			}
		}()
	}
	wg.Wait()
	close(ids)
	seen := map[string]bool{}
	for id := range ids {
		seen[id] = true
	}
	if len(seen) != 1 {
		t.Fatalf("concurrent first logins created %d accounts", len(seen))
	}
	for id := range seen {
		var coins, diamonds int64
		if err := e.app.PG.QueryRow(context.Background(),
			`SELECT coins, diamonds FROM wallet.wallets WHERE user_id=$1`, id).Scan(&coins, &diamonds); err != nil ||
			coins != 2_000_000 || diamonds != 75 {
			t.Fatalf("raced account wallet = %d / %d (%v), want one grant of 2000000 / 75", coins, diamonds, err)
		}
	}

	// An invalid grant is rejected as a whole; the last good one stays live.
	if err := e.reloadPolicy(t, policyWithWelcome(`{"coins":-5,"diamonds":10}`)); err == nil {
		t.Fatal("negative welcome accepted")
	}
	if err := e.reloadPolicy(t, policyWithWelcome(`{"gems":5}`)); err == nil {
		t.Fatal("unknown welcome key accepted")
	}
	e.wantAppConfigWelcome(t, 2_000_000, 75)

	// Hot reload by file polling alone: a key left out falls back to
	// WELCOME_* / the default.
	writeFile(t, e.policy, policyWithWelcome(`{"diamonds":5}`))
	future := time.Now().Add(2 * time.Second)
	if err := os.Chtimes(e.policy, future, future); err != nil {
		t.Fatal(err)
	}
	waitFor(t, 10*time.Second, "polled welcome reload", func() bool {
		r := e.do("GET", "/api/v1/app/config?platform=android&version=1.0.0&build=1", "", nil)
		w, _ := r.Body["welcome"].(map[string]any)
		return w != nil && w["coins"].(float64) == 1_000_000 && w["diamonds"].(float64) == 5
	})
	if g := e.guest(); g.Coins != 1_000_000 || g.Diamonds != 5 {
		t.Fatalf("grant after polled reload = %d / %d, want 1000000 / 5", g.Coins, g.Diamonds)
	}
}
