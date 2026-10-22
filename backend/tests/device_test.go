package tests

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"slices"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/jackc/pgx/v5"

	"ludoarena/internal/identity"
)

// Device binding (docs/authentication.md "Device binding"): a guest is
// restored from the platform device id after an app update or reinstall.

var devSeq, ipSeq atomic.Int64

// devID returns a new valid device id, unique per call and test run (the
// test database persists between runs and -count iterations).
func devID(name string) string { return fmt.Sprintf("%s-%s-%d", name, runID, devSeq.Add(1)) }

// freshIP is a distinct client IP (X-Forwarded-For with envOpts.proxyHops),
// so tests can create more guests than the per-IP guest-creation limit.
func freshIP() string {
	n := ipSeq.Add(1)
	return fmt.Sprintf("10.%d.%d.%d", (n>>16)&255, (n>>8)&255, n&255)
}

func (e *env) deviceGuest(id string, headers ...string) resp {
	e.t.Helper()
	return e.do("POST", "/api/v1/auth/guest", "", map[string]any{"deviceId": id},
		append([]string{"X-Forwarded-For", freshIP()}, headers...)...)
}

func (e *env) deviceResume(id string, headers ...string) resp {
	e.t.Helper()
	return e.do("POST", "/api/v1/auth/device/resume", "", map[string]any{"deviceId": id}, headers...)
}

func (e *env) bindDevice(token, id string, headers ...string) resp {
	e.t.Helper()
	return e.do("PUT", "/api/v1/account/device", token, map[string]any{"deviceId": id}, headers...)
}

// deviceOwner returns the account bound to (platform, id), or "".
func (e *env) deviceOwner(platform, id string) string {
	e.t.Helper()
	sub, err := identity.DeviceSubject(identity.DeviceKey(e.app.Cfg.Auth.PublicIDKey), platform, id)
	if err != nil {
		e.t.Fatal(err)
	}
	var owner string
	err = e.app.PG.QueryRow(context.Background(),
		`SELECT user_id::text FROM identity.auth_identities WHERE provider = 'device' AND subject = $1`, sub).Scan(&owner)
	if errors.Is(err, pgx.ErrNoRows) {
		return ""
	}
	if err != nil {
		e.t.Fatal(err)
	}
	return owner
}

// identityCounts returns how many guest and device identities an account has.
func (e *env) identityCounts(userID string) (guests, devices int) {
	e.t.Helper()
	if err := e.app.PG.QueryRow(context.Background(), `
		SELECT count(*) FILTER (WHERE provider = 'guest'), count(*) FILTER (WHERE provider = 'device')
		FROM identity.auth_identities WHERE user_id = $1`, userID).Scan(&guests, &devices); err != nil {
		e.t.Fatal(err)
	}
	return guests, devices
}

// assertUserProviders checks user.isGuest and user.linkedProviders and that
// the internal device binding appears nowhere in the response.
func assertUserProviders(t *testing.T, what string, r resp, isGuest bool, providers ...string) {
	t.Helper()
	if r.Status != 200 && r.Status != 201 {
		t.Fatalf("%s: %d %s", what, r.Status, r.Raw)
	}
	user := r.Body["user"].(map[string]any)
	var got []string
	for _, p := range user["linkedProviders"].([]any) {
		got = append(got, p.(string))
	}
	if user["isGuest"] != isGuest || !slices.Equal(got, providers) {
		t.Fatalf("%s: isGuest=%v linkedProviders=%v, want %v %v", what, user["isGuest"], got, isGuest, providers)
	}
	if bytes.Contains(r.Raw, []byte(`"device"`)) {
		t.Fatalf("%s: response mentions the device provider: %s", what, r.Raw)
	}
}

func TestDeviceGuestCreatesOnceAndRestores(t *testing.T) {
	e := newEnv(t, envOpts{proxyHops: 1})
	ctx := context.Background()
	id := devID("first")

	r1 := e.deviceGuest(id)
	if r1.Status != 201 || r1.Body["isNewUser"] != true {
		t.Fatalf("first device guest: %d %s, want 201 isNewUser", r1.Status, r1.Raw)
	}
	g := parseAuth(t, r1)
	if g.GuestSecret == "" || g.Coins != 1_000_000 || g.Diamonds != 50 {
		t.Fatalf("new device guest: secret %q, %d coins / %d diamonds", g.GuestSecret, g.Coins, g.Diamonds)
	}

	// The same device again (an updated or reinstalled app): the same
	// account, no second welcome grant and no new guest secret.
	r2 := e.deviceGuest(id)
	if r2.Status != 200 || r2.Body["isNewUser"] != false {
		t.Fatalf("same device again: %d %s, want 200 !isNewUser", r2.Status, r2.Raw)
	}
	if _, has := r2.Body["guestSecret"]; has {
		t.Fatalf("existing account got a guest secret: %s", r2.Raw)
	}
	a2 := parseAuth(t, r2)
	if a2.UserID != g.UserID || a2.UID != g.UID || a2.Coins != g.Coins || a2.Diamonds != g.Diamonds {
		t.Fatalf("same device resolved to %s (%d coins), want %s", a2.UserID, a2.Coins, g.UserID)
	}

	r3 := e.deviceResume(id)
	if r3.Status != 200 || r3.Body["isNewUser"] != false {
		t.Fatalf("device resume: %d %s", r3.Status, r3.Raw)
	}
	if _, has := r3.Body["guestSecret"]; has {
		t.Fatalf("device resume returned a guest secret: %s", r3.Raw)
	}
	if a3 := parseAuth(t, r3); a3.UserID != g.UserID || a3.Coins != 1_000_000 {
		t.Fatalf("device resume resolved to %s", a3.UserID)
	}

	// An unknown device is 404 and creates nothing.
	unknown := devID("unknown")
	if r := e.deviceResume(unknown); r.Status != 404 || errCode(r) != "not_found" {
		t.Fatalf("unknown device: %d %s, want 404 not_found", r.Status, r.Raw)
	}
	if owner := e.deviceOwner("android", unknown); owner != "" {
		t.Fatal("device resume created a binding")
	}

	// One guest identity + one device binding, stored as an HMAC only.
	if guests, devices := e.identityCounts(g.UserID); guests != 1 || devices != 1 {
		t.Fatalf("identities: %d guest, %d device; want 1/1", guests, devices)
	}
	if owner := e.deviceOwner("android", id); owner != g.UserID {
		t.Fatalf("binding owner = %q", owner)
	}
	var raw int
	if err := e.app.PG.QueryRow(ctx, `SELECT count(*) FROM identity.auth_identities WHERE strpos(lower(subject), lower($1)) > 0`,
		id).Scan(&raw); err != nil || raw != 0 {
		t.Fatalf("raw device id stored (%d rows, %v)", raw, err)
	}
	// The guest secret from the first response still restores the account.
	if res := parseAuth(t, e.do("POST", "/api/v1/auth/guest/resume", "", map[string]any{"guestSecret": g.GuestSecret})); res.UserID != g.UserID {
		t.Fatalf("guest secret resolved to %s", res.UserID)
	}
}

// Simulated reinstall: tokens and the guest secret are gone; only the device
// id is left. Coins, diamonds, inventory and loadout come back.
func TestDeviceRestoreAfterReinstallKeepsProgress(t *testing.T) {
	e := newEnv(t, envOpts{proxyHops: 1})
	id := devID("reinstall")
	g := parseAuth(t, e.deviceGuest(id))
	if r := e.do("POST", "/api/v1/collection/items/dice_golden/purchase", g.Token, nil); r.Status != 200 {
		t.Fatalf("purchase: %d %s", r.Status, r.Raw)
	}
	if r := e.do("PUT", "/api/v1/collection/loadout", g.Token, map[string]any{"slot": "dice", "itemId": "dice_golden"}); r.Status != 200 {
		t.Fatalf("equip: %d %s", r.Status, r.Raw)
	}
	before := e.do("GET", "/api/v1/me", g.Token, nil)
	if before.Status != 200 {
		t.Fatalf("/me: %d %s", before.Status, before.Raw)
	}
	userBefore := before.Body["user"].(map[string]any)

	for _, how := range []string{"device resume", "guest with device"} {
		var r resp
		if how == "device resume" {
			r = e.deviceResume(id)
		} else {
			r = e.deviceGuest(id)
		}
		if r.Status != 200 {
			t.Fatalf("%s: %d %s", how, r.Status, r.Raw)
		}
		a := parseAuth(t, r)
		if a.UserID != g.UserID || a.Coins != 1_000_000 || a.Diamonds != 10 {
			t.Fatalf("%s: account %s with %d coins / %d diamonds", how, a.UserID, a.Coins, a.Diamonds)
		}
		user := r.Body["user"].(map[string]any)
		for _, k := range []string{"uid", "displayName", "level", "xp", "title"} {
			if user[k] != userBefore[k] {
				t.Fatalf("%s: user.%s = %v, want %v", how, k, user[k], userBefore[k])
			}
		}
		if lo := user["loadout"].(map[string]any); lo["dice"] != "dice_golden" {
			t.Fatalf("%s: loadout %v", how, lo)
		}
		col := e.do("GET", "/api/v1/collection", a.Token, nil)
		owned := false
		for _, it := range col.Body["items"].([]any) {
			item := it.(map[string]any)
			if item["id"] == "dice_golden" {
				owned = item["owned"] == true && item["equipped"] == true
			}
		}
		if col.Status != 200 || !owned {
			t.Fatalf("%s: purchased item not owned/equipped: %d", how, col.Status)
		}
	}
}

// The same device id string on Android and iOS is two different devices.
func TestDevicePlatformsAreSeparate(t *testing.T) {
	e := newEnv(t, envOpts{proxyHops: 1})
	id := devID("shared")
	ra, ri := e.deviceGuest(id), e.deviceGuest(id, "X-App-Platform", "ios")
	if ra.Status != 201 || ri.Status != 201 {
		t.Fatalf("android %d / ios %d, want 201 for both", ra.Status, ri.Status)
	}
	a, i := parseAuth(t, ra), parseAuth(t, ri)
	if a.UserID == i.UserID {
		t.Fatal("android and ios device ids share an account")
	}
	if r := parseAuth(t, e.deviceResume(id)); r.UserID != a.UserID {
		t.Fatalf("android resume resolved to %s", r.UserID)
	}
	if r := parseAuth(t, e.deviceResume(id, "X-App-Platform", "ios")); r.UserID != i.UserID {
		t.Fatalf("ios resume resolved to %s", r.UserID)
	}
	if e.deviceOwner("android", id) != a.UserID || e.deviceOwner("ios", id) != i.UserID {
		t.Fatal("bindings not namespaced by platform")
	}
}

// Concurrent first calls for the same new device create exactly one account
// (one welcome grant) and leave one live session.
func TestConcurrentDeviceGuestCreatesOneAccount(t *testing.T) {
	e := newEnv(t, envOpts{proxyHops: 1})
	id := devID("race")
	type result struct {
		status             int
		uid, token, secret string
		coins, diamonds    int64
	}
	results := make(chan result, 20)
	start := make(chan struct{})
	var wg sync.WaitGroup
	for i := 0; i < 20; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			<-start
			r := e.deviceGuest(id)
			out := result{status: r.Status}
			if r.Status == 200 || r.Status == 201 {
				a := parseAuth(t, r)
				out.uid, out.token, out.secret, out.coins, out.diamonds = a.UserID, a.Token, a.GuestSecret, a.Coins, a.Diamonds
			}
			results <- out
		}()
	}
	close(start)
	wg.Wait()
	close(results)

	created, uids, tokens := 0, map[string]bool{}, []string{}
	for r := range results {
		switch {
		case r.status == 201 && r.secret != "":
			created++
		case r.status == 200 && r.secret == "":
		default:
			t.Fatalf("concurrent device guest: status %d (secret %t)", r.status, r.secret != "")
		}
		if r.coins != 1_000_000 || r.diamonds != 50 {
			t.Fatalf("wallet %d / %d", r.coins, r.diamonds)
		}
		uids[r.uid] = true
		tokens = append(tokens, r.token)
	}
	if created != 1 || len(uids) != 1 {
		t.Fatalf("%d creations, %d accounts; want exactly 1/1", created, len(uids))
	}
	var uid string
	for u := range uids {
		uid = u
	}
	if guests, devices := e.identityCounts(uid); guests != 1 || devices != 1 {
		t.Fatalf("identities: %d guest, %d device; want 1/1", guests, devices)
	}
	if owner := e.deviceOwner("android", id); owner != uid {
		t.Fatalf("binding owner = %q, want %s", owner, uid)
	}
	var coins, diamonds int64
	if err := e.app.PG.QueryRow(context.Background(), `SELECT coins, diamonds FROM wallet.wallets WHERE user_id = $1`,
		uid).Scan(&coins, &diamonds); err != nil || coins != 1_000_000 || diamonds != 50 {
		t.Fatalf("wallet = %d / %d (%v)", coins, diamonds, err)
	}
	live := 0
	for _, tok := range tokens {
		if r := e.do("GET", "/api/v1/me", tok, nil); r.Status == 200 {
			live++
		} else if errCode(r) != "session_replaced" {
			t.Fatalf("concurrent sign-in session: %d %s", r.Status, r.Raw)
		}
	}
	if live != 1 {
		t.Fatalf("%d live sessions, want 1", live)
	}
}

// PUT /account/device binds a device to an existing account (e.g. a guest
// created before device binding existed), never moves another account's
// device, and keeps one device per account.
func TestBindDeviceToExistingAccount(t *testing.T) {
	e := newEnv(t, envOpts{proxyHops: 1})
	g := e.guest()
	d1, d2 := devID("bindone"), devID("bindtwo")
	if r := e.bindDevice(g.Token, d1); r.Status != 200 || string(bytes.TrimSpace(r.Raw)) != "{}" {
		t.Fatalf("bind: %d %s, want 200 {}", r.Status, r.Raw)
	}
	if r := e.bindDevice(g.Token, d1); r.Status != 200 {
		t.Fatalf("idempotent bind: %d %s", r.Status, r.Raw)
	}
	if guests, devices := e.identityCounts(g.UserID); guests != 1 || devices != 1 {
		t.Fatalf("identities: %d guest, %d device", guests, devices)
	}
	assertUserProviders(t, "/me after bind", e.do("GET", "/api/v1/me", g.Token, nil), true, "guest")

	// After a reinstall the device restores the account.
	a := parseAuth(t, e.deviceResume(d1))
	if a.UserID != g.UserID || a.Coins != 1_000_000 {
		t.Fatalf("resume after bind resolved to %s", a.UserID)
	}

	// Another account cannot take the device; nothing moves.
	other := e.guest()
	if r := e.bindDevice(other.Token, d1); r.Status != 409 || errCode(r) != "identity_conflict" {
		t.Fatalf("bind another account's device: %d %s, want 409 identity_conflict", r.Status, r.Raw)
	}
	if owner := e.deviceOwner("android", d1); owner != g.UserID {
		t.Fatalf("conflict moved the device to %s", owner)
	}
	if _, devices := e.identityCounts(other.UserID); devices != 0 {
		t.Fatal("conflict bound a device to the other account")
	}

	// Moved to a new phone: binding d2 replaces d1.
	if r := e.bindDevice(a.Token, d2); r.Status != 200 {
		t.Fatalf("rebind: %d %s", r.Status, r.Raw)
	}
	if r := e.deviceResume(d1); r.Status != 404 || errCode(r) != "not_found" {
		t.Fatalf("old device after rebind: %d %s, want 404", r.Status, r.Raw)
	}
	if b := parseAuth(t, e.deviceResume(d2)); b.UserID != g.UserID {
		t.Fatalf("new device resolved to %s", b.UserID)
	}
	if _, devices := e.identityCounts(g.UserID); devices != 1 {
		t.Fatalf("%d device bindings, want 1", devices)
	}
	// The released device can now be bound elsewhere.
	if r := e.bindDevice(other.Token, d1); r.Status != 200 || e.deviceOwner("android", d1) != other.UserID {
		t.Fatalf("bind released device: %d %s", r.Status, r.Raw)
	}
	if r := e.bindDevice("", d1); r.Status != 401 {
		t.Fatalf("unauthenticated bind: %d", r.Status)
	}
}

// Concurrent binds never move a device or leave an account with two.
func TestConcurrentBindDevice(t *testing.T) {
	e := newEnv(t, envOpts{proxyHops: 1})
	guests := make([]account, 8)
	for i := range guests {
		guests[i] = parseAuth(t, e.do("POST", "/api/v1/auth/guest", "", map[string]any{}, "X-Forwarded-For", freshIP()))
	}
	run := func(n int, call func(i int) resp) []resp {
		out := make([]resp, n)
		var wg sync.WaitGroup
		for i := 0; i < n; i++ {
			wg.Add(1)
			go func() { defer wg.Done(); out[i] = call(i) }()
		}
		wg.Wait()
		return out
	}

	// Eight accounts race for one device: exactly one gets it.
	d := devID("contested")
	winner := ""
	for i, r := range run(len(guests), func(i int) resp { return e.bindDevice(guests[i].Token, d) }) {
		switch {
		case r.Status == 200 && winner == "":
			winner = guests[i].UserID
		case r.Status == 409 && errCode(r) == "identity_conflict":
		default:
			t.Fatalf("contested bind: %d %s", r.Status, r.Raw)
		}
	}
	if winner == "" || e.deviceOwner("android", d) != winner {
		t.Fatalf("contested device owner = %q, winner %q", e.deviceOwner("android", d), winner)
	}

	// One account binds eight devices at once: one binding remains.
	g := guests[0]
	if g.UserID == winner {
		g = guests[1]
	}
	ids := make([]string, 8)
	for i := range ids {
		ids[i] = devID("multi")
	}
	for _, r := range run(len(ids), func(i int) resp { return e.bindDevice(g.Token, ids[i]) }) {
		if r.Status != 200 {
			t.Fatalf("concurrent rebind: %d %s", r.Status, r.Raw)
		}
	}
	if _, devices := e.identityCounts(g.UserID); devices != 1 {
		t.Fatalf("%d device bindings after concurrent rebinds, want 1", devices)
	}
}

// Older app versions "forget the guest" on sign-out (DELETE /account/device,
// then they drop the guest secret). The server keeps the binding, so their
// next "Play as guest" with the device id is the same guest as well.
func TestUnbindDeviceKeepsTheGuest(t *testing.T) {
	e := newEnv(t, envOpts{proxyHops: 1})
	d := devID("forget")
	g := parseAuth(t, e.deviceGuest(d))
	if r := e.do("DELETE", "/api/v1/account/device", g.Token, nil); r.Status != 204 {
		t.Fatalf("unbind: %d %s", r.Status, r.Raw)
	}
	// Idempotent, and (like logout) not blocked by the version gate.
	if r := e.do("DELETE", "/api/v1/account/device", g.Token, nil,
		"X-App-Platform", "", "X-App-Version", "", "X-App-Build", ""); r.Status != 204 {
		t.Fatalf("second unbind: %d %s", r.Status, r.Raw)
	}
	if r := e.do("DELETE", "/api/v1/account/device", "", nil); r.Status != 401 {
		t.Fatalf("unauthenticated unbind: %d", r.Status)
	}
	if guests, devices := e.identityCounts(g.UserID); guests != 1 || devices != 1 {
		t.Fatalf("identities after unbind: %d guest, %d device", guests, devices)
	}
	e.logout(t, g)
	if r := e.deviceGuest(d); r.Status != 200 || parseAuth(t, r).UserID != g.UserID {
		t.Fatalf("play as guest after an old app's unbind: %d %s, want the same guest", r.Status, r.Raw)
	}
	if a := parseAuth(t, e.deviceResume(d)); a.UserID != g.UserID {
		t.Fatalf("resume after unbind resolved to %s", a.UserID)
	}
}

// The device binding is internal: never listed, never "linked", not linkable.
func TestDeviceBindingIsNotALinkedProvider(t *testing.T) {
	e := newEnv(t, envOpts{proxyHops: 1})
	d := devID("hidden")
	r := e.deviceGuest(d)
	assertUserProviders(t, "device guest", r, true, "guest")
	g := parseAuth(t, r)
	assertUserProviders(t, "/me", e.do("GET", "/api/v1/me", g.Token, nil), true, "guest")
	ref := e.do("POST", "/api/v1/auth/refresh", "", map[string]any{"refreshToken": g.Refresh})
	assertUserProviders(t, "refresh", ref, true, "guest")
	res := e.deviceResume(d)
	assertUserProviders(t, "device resume", res, true, "guest")
	tok := parseAuth(t, res).Token

	if r := e.do("POST", "/api/v1/account/link/device", tok, map[string]any{"deviceId": d}); r.Status != 404 {
		t.Fatalf("link/device: %d %s, want 404", r.Status, r.Raw)
	}
	// Save Progress makes it a linked account: the guest credential and the
	// device binding are gone with it (guest_persistence_test.go covers what
	// the device does next).
	link := e.do("POST", "/api/v1/account/link/google", tok, map[string]any{"idToken": e.oidc.googleToken(t, devID("devicelink"), googleAud, time.Hour)})
	assertUserProviders(t, "link google", link, false, "google")
	if r := e.deviceResume(d); r.Status != 404 || errCode(r) != "not_found" {
		t.Fatalf("device resume of a linked account: %d %s, want 404", r.Status, r.Raw)
	}
	if guests, devices := e.identityCounts(g.UserID); guests != 0 || devices != 0 {
		t.Fatalf("linked account keeps %d guest / %d device identities", guests, devices)
	}
}

func TestDeviceValidation(t *testing.T) {
	e := newEnv(t, envOpts{proxyHops: 1})
	// PUT /account/device is rate limited per account (10/min): spread the
	// rejected binds over several guests.
	var users []string
	var tok string
	calls := 0
	bindToken := func() string {
		if calls%8 == 0 {
			g := parseAuth(t, e.do("POST", "/api/v1/auth/guest", "", map[string]any{}, "X-Forwarded-For", freshIP()))
			users, tok = append(users, g.UserID), g.Token
		}
		calls++
		return tok
	}
	valid := devID("valid")
	bad := []any{"", "short", strings.Repeat("a1", 33), "9774d56d682e549c", "0000000000000000",
		"00000000-0000-0000-0000-000000000000", "ffffffffffffffff", "abcd efgh ijkl mnop", "abcd_efgh_ijkl_mnop",
		"abcdefgh12345678!", "abcdefgh1234567é", 12345678901234567, true}
	for _, id := range bad {
		body := map[string]any{"deviceId": id}
		if r := e.do("POST", "/api/v1/auth/guest", "", body, "X-Forwarded-For", freshIP()); r.Status != 400 || errCode(r) != "bad_request" {
			t.Fatalf("guest with deviceId %v: %d %s, want 400 bad_request", id, r.Status, r.Raw)
		}
		if r := e.do("POST", "/api/v1/auth/device/resume", "", body); r.Status != 400 || errCode(r) != "bad_request" {
			t.Fatalf("resume with deviceId %v: %d %s, want 400 bad_request", id, r.Status, r.Raw)
		}
		if r := e.do("PUT", "/api/v1/account/device", bindToken(), body); r.Status != 400 || errCode(r) != "bad_request" {
			t.Fatalf("bind deviceId %v: %d %s, want 400 bad_request", id, r.Status, r.Raw)
		}
	}
	// A missing deviceId is only allowed on /auth/guest (plain new guest).
	for _, path := range []string{"/api/v1/auth/device/resume", "/api/v1/account/device"} {
		method := "POST"
		if strings.HasSuffix(path, "/account/device") {
			method = "PUT"
		}
		if r := e.do(method, path, bindToken(), map[string]any{}); r.Status != 400 || errCode(r) != "bad_request" {
			t.Fatalf("%s without deviceId: %d %s", path, r.Status, r.Raw)
		}
		if r := e.do(method, path, bindToken(), map[string]any{"deviceId": valid, "extra": 1}); r.Status != 400 {
			t.Fatalf("%s with an unknown field: %d %s", path, r.Status, r.Raw)
		}
	}
	if r := e.do("POST", "/api/v1/auth/guest", "", map[string]any{"deviceId": valid, "extra": 1}, "X-Forwarded-For", freshIP()); r.Status != 400 {
		t.Fatalf("guest with an unknown field: %d %s", r.Status, r.Raw)
	}
	// The platform comes from X-App-Platform and must be android or ios.
	for _, platform := range []string{"", "web", "windows"} {
		h := []string{"X-App-Platform", platform, "X-Forwarded-For", freshIP()}
		if r := e.deviceGuest(valid, h...); r.Status != 400 {
			t.Fatalf("guest on platform %q: %d %s", platform, r.Status, r.Raw)
		}
		if r := e.deviceResume(valid, h...); r.Status != 400 {
			t.Fatalf("resume on platform %q: %d %s", platform, r.Status, r.Raw)
		}
		if r := e.bindDevice(bindToken(), valid, h...); r.Status != 400 {
			t.Fatalf("bind on platform %q: %d %s", platform, r.Status, r.Raw)
		}
	}
	if e.deviceOwner("android", valid) != "" || e.deviceOwner("ios", valid) != "" {
		t.Fatal("a rejected request bound the device")
	}
	for _, u := range users {
		if _, devices := e.identityCounts(u); devices != 0 {
			t.Fatal("a rejected bind stored a device")
		}
	}
}

// Device sign-ins are human sign-ins: one live session per account.
func TestDeviceSignInReplacesOtherSession(t *testing.T) {
	e := newEnv(t, envOpts{proxyHops: 1})
	d := devID("session")
	a := parseAuth(t, e.deviceGuest(d))
	ca := e.mustDial("deviceA", a)

	b := parseAuth(t, e.deviceResume(d))
	if b.UserID != a.UserID {
		t.Fatalf("resume resolved to %s", b.UserID)
	}
	if code := waitClosed(t, ca, 3*time.Second, "device A"); code != 4401 {
		t.Fatalf("device A close code = %d, want 4401", code)
	}
	e.assertReplaced(t, a, "device A")

	// /auth/guest with a bound device is a sign-in as well.
	c := parseAuth(t, e.deviceGuest(d))
	if c.UserID != a.UserID {
		t.Fatalf("guest with device resolved to %s", c.UserID)
	}
	e.assertReplaced(t, b, "device B")
	if r := e.do("GET", "/api/v1/me", c.Token, nil); r.Status != 200 {
		t.Fatalf("latest session /me: %d %s", r.Status, r.Raw)
	}
}
