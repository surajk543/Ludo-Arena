package tests

import (
	"context"
	"fmt"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/google/uuid"

	"ludoarena/internal/auth"
	"ludoarena/internal/identity"
)

// Guest persistence (docs/authentication.md "Guest persistence"): a device
// guest keeps the same account — id, coins, diamonds, XP, items, friends —
// across sign-outs and reinstalls until it is linked to Google/Facebook/
// Apple or deleted. After either, "Play as guest" on that device starts a
// brand-new guest.

// guestProgress gives a device guest progress worth keeping: a purchase
// (diamonds spent, an owned and equipped item), XP and an accepted friend.
// It returns the friend.
func (e *env) guestProgress(t *testing.T, g account) account {
	t.Helper()
	if r := e.do("POST", "/api/v1/collection/items/dice_golden/purchase", g.Token, nil); r.Status != 200 {
		t.Fatalf("purchase: %d %s", r.Status, r.Raw)
	}
	if r := e.do("PUT", "/api/v1/collection/loadout", g.Token, map[string]any{"slot": "dice", "itemId": "dice_golden"}); r.Status != 200 {
		t.Fatalf("equip: %d %s", r.Status, r.Raw)
	}
	if r := e.do("GET", "/api/v1/me", g.Token, nil); r.Status != 200 { // creates the progression row
		t.Fatalf("/me: %d %s", r.Status, r.Raw)
	}
	if _, err := e.app.PG.Exec(context.Background(),
		`UPDATE progression.player_progress SET xp = 2600, level = 4 WHERE user_id = $1`, g.UserID); err != nil {
		t.Fatal(err)
	}
	f := e.guestFromFreshIP()
	if r := e.friendRequest(f, g.UID); r.Status != 201 {
		t.Fatalf("friend request: %d %s", r.Status, r.Raw)
	}
	if r := e.do("POST", "/api/v1/friends/requests/"+f.UID+"/accept", g.Token, nil); r.Status != 200 {
		t.Fatalf("accept: %d %s", r.Status, r.Raw)
	}
	return f
}

// assertSameGuest checks that a sign-in response is the original guest with
// all of its progress.
func (e *env) assertSameGuest(t *testing.T, what string, r resp, g, friend account, coins, diamonds int64) account {
	t.Helper()
	if r.Status != 200 || r.Body["isNewUser"] != false {
		t.Fatalf("%s: %d %s, want 200 isNewUser:false", what, r.Status, r.Raw)
	}
	a := parseAuth(t, r)
	if a.UserID != g.UserID || a.UID != g.UID || a.Coins != coins || a.Diamonds != diamonds {
		t.Fatalf("%s: account %s (%s) with %d coins / %d diamonds, want %s (%s) %d / %d",
			what, a.UserID, a.UID, a.Coins, a.Diamonds, g.UserID, g.UID, coins, diamonds)
	}
	user := r.Body["user"].(map[string]any)
	if user["isGuest"] != true || num(user["xp"]) != 2600 || num(user["level"]) != 4 {
		t.Fatalf("%s: user %v", what, user)
	}
	if lo := user["loadout"].(map[string]any); lo["dice"] != "dice_golden" {
		t.Fatalf("%s: loadout %v", what, lo)
	}
	friends := e.friends(t, a).Body["friends"].([]any)
	if len(friends) != 1 || friends[0].(map[string]any)["uid"] != friend.UID {
		t.Fatalf("%s: friends %v", what, friends)
	}
	return a
}

func (e *env) logout(t *testing.T, a account) {
	t.Helper()
	if r := e.do("POST", "/api/v1/auth/logout", a.Token, map[string]any{"refreshToken": a.Refresh}); r.Status != 204 {
		t.Fatalf("logout: %d %s", r.Status, r.Raw)
	}
	if r := e.do("GET", "/api/v1/me", a.Token, nil); r.Status != 401 {
		t.Fatalf("/me after logout: %d %s", r.Status, r.Raw)
	}
}

func (e *env) guestResume(secret string) resp {
	e.t.Helper()
	return e.do("POST", "/api/v1/auth/guest/resume", "", map[string]any{"guestSecret": secret})
}

// (a) A guest signs out and taps "Play as guest" again — with the guest
// secret the app keeps, or with only the device id — and gets the same
// account back every time; no new account, no second welcome grant.
func TestGuestSignOutKeepsTheSameGuest(t *testing.T) {
	e := newEnv(t, envOpts{proxyHops: 1})
	d := devID("signout")
	g := parseAuth(t, e.deviceGuest(d))
	friend := e.guestProgress(t, g)
	coins, diamonds := e.coins(g.Token), int64(10) // dice_golden costs 40 of the 50 diamonds

	cur := g
	for i := 0; i < 3; i++ {
		e.logout(t, cur)
		cur = e.assertSameGuest(t, fmt.Sprintf("guest resume #%d", i), e.guestResume(g.GuestSecret), g, friend, coins, diamonds)
		e.logout(t, cur)
		r := e.deviceGuest(d)
		if _, has := r.Body["guestSecret"]; has {
			t.Fatalf("existing guest got a new guest secret: %s", r.Raw)
		}
		cur = e.assertSameGuest(t, fmt.Sprintf("play as guest with the device id #%d", i), r, g, friend, coins, diamonds)
	}
	if guests, devices := e.identityCounts(g.UserID); guests != 1 || devices != 1 {
		t.Fatalf("identities: %d guest / %d device, want 1/1", guests, devices)
	}
}

// (b) Reinstall: tokens and the guest secret are gone (Android) or kept in
// the keychain (iOS); only the device id is certain. Restore and "Play as
// guest" both land in the same guest, also when it had signed out before
// the app was uninstalled.
func TestGuestReinstallKeepsTheSameGuest(t *testing.T) {
	e := newEnv(t, envOpts{proxyHops: 1})
	for _, tc := range []struct{ platform, id string }{
		{"android", devID("reinstall")},
		{"ios", strings.ToUpper(uuid.NewString())}, // the app's keychain UUID v4
	} {
		h := []string{"X-App-Platform", tc.platform}
		g := parseAuth(t, e.deviceGuest(tc.id, h...))
		friend := e.guestProgress(t, g)
		coins := e.coins(g.Token)
		e.logout(t, g) // signed out, then uninstalled

		for _, how := range []string{"device resume", "play as guest"} {
			var r resp
			if how == "device resume" {
				r = e.deviceResume(tc.id, h...)
			} else {
				r = e.deviceGuest(tc.id, h...)
			}
			e.assertSameGuest(t, tc.platform+" reinstall, "+how, r, g, friend, coins, 10)
		}
		// iOS keeps the keychain (guest secret) across a reinstall.
		e.assertSameGuest(t, tc.platform+" guest secret", e.guestResume(g.GuestSecret), g, friend, coins, 10)
	}
}

// (c) The owner's rule: a guest that saves its progress to a Google /
// Facebook / Apple account that was not registered yet moves into that
// account; "Play as guest" on the device then starts a brand-new guest, and
// the saved account is reached only by signing in with the provider.
func TestLinkedGuestLeavesTheDevice(t *testing.T) {
	e := newEnv(t, envOpts{proxyHops: 1})
	d := devID("linked")
	g := parseAuth(t, e.deviceGuest(d))
	friend := e.guestProgress(t, g)
	coins := e.coins(g.Token)
	googleSub := devID("linked-google")
	googleTok := func() string { return e.oidc.googleToken(t, googleSub, googleAud, time.Hour) }

	link := e.do("POST", "/api/v1/account/link/google", g.Token, map[string]any{"idToken": googleTok()})
	assertUserProviders(t, "link", link, false, "google")
	if l := link.Body["user"].(map[string]any); l["id"] != g.UserID || num(link.Body["wallet"].(map[string]any)["diamonds"]) != 10 {
		t.Fatalf("link changed the account: %s", link.Raw)
	}
	if guests, devices := e.identityCounts(g.UserID); guests != 0 || devices != 0 {
		t.Fatalf("linked account keeps %d guest / %d device identities", guests, devices)
	}
	if owner := e.deviceOwner("android", d); owner != "" {
		t.Fatalf("device still bound to %s", owner)
	}
	e.logout(t, g)

	// Its guest secret and the device no longer reach it.
	if r := e.guestResume(g.GuestSecret); r.Status != 401 || errCode(r) != "invalid_credential" {
		t.Fatalf("guest secret of a linked account: %d %s, want 401 invalid_credential", r.Status, r.Raw)
	}
	if r := e.deviceResume(d); r.Status != 404 || errCode(r) != "not_found" {
		t.Fatalf("device resume after linking: %d %s, want 404", r.Status, r.Raw)
	}

	// "Play as guest": a new guest with a new welcome grant, bound to the
	// device, which persists from then on.
	nr := e.deviceGuest(d)
	n := parseAuth(t, nr)
	if nr.Status != 201 || nr.Body["isNewUser"] != true || n.GuestSecret == "" || n.UserID == g.UserID ||
		n.Coins != 1_000_000 || n.Diamonds != 50 {
		t.Fatalf("play as guest after linking: %d %s, want a new guest", nr.Status, nr.Raw)
	}
	assertUserProviders(t, "new guest", nr, true, "guest")
	if owner := e.deviceOwner("android", d); owner != n.UserID {
		t.Fatalf("device bound to %q, want the new guest", owner)
	}
	if a := parseAuth(t, e.deviceGuest(d)); a.UserID != n.UserID {
		t.Fatalf("second play as guest resolved to %s", a.UserID)
	}
	if a := parseAuth(t, e.deviceResume(d)); a.UserID != n.UserID {
		t.Fatalf("device resume resolved to %s", a.UserID)
	}

	// Google reaches the saved account with all of its progress.
	gr := e.do("POST", "/api/v1/auth/google", "", map[string]any{"idToken": googleTok()})
	s := parseAuth(t, gr)
	if gr.Body["isNewUser"] != false || s.UserID != g.UserID || s.Coins != coins || s.Diamonds != 10 {
		t.Fatalf("google sign-in: %d %s", gr.Status, gr.Raw)
	}
	if fs := e.friends(t, s).Body["friends"].([]any); len(fs) != 1 || fs[0].(map[string]any)["uid"] != friend.UID {
		t.Fatalf("saved account's friends: %v", fs)
	}
	// A linked account is never bound to a device again.
	if r := e.bindDevice(s.Token, d); r.Status != 409 || errCode(r) != "not_a_guest" {
		t.Fatalf("bind a linked account: %d %s, want 409 not_a_guest", r.Status, r.Raw)
	}
	if r := e.bindDevice(s.Token, devID("other")); r.Status != 409 || errCode(r) != "not_a_guest" {
		t.Fatalf("bind a linked account to a free device: %d %s, want 409 not_a_guest", r.Status, r.Raw)
	}
	if owner := e.deviceOwner("android", d); owner != n.UserID {
		t.Fatalf("device moved to %q", owner)
	}
	// Re-linking the same identity (idempotent) changes nothing.
	if r := e.do("POST", "/api/v1/account/link/google", s.Token, map[string]any{"idToken": googleTok()}); r.Status != 200 {
		t.Fatalf("idempotent relink: %d %s", r.Status, r.Raw)
	}
}

// A guest that tries to save its progress to a provider account that
// already has its own game account gets 409 identity_conflict and loses
// nothing: it stays the device guest (secret, device binding, progress), even
// after the player signs in to that other account instead.
func TestLinkConflictKeepsTheGuest(t *testing.T) {
	e := newEnv(t, envOpts{proxyHops: 1})
	googleSub := devID("taken-google")
	googleTok := func() string { return e.oidc.googleToken(t, googleSub, googleAud, time.Hour) }
	x := parseAuth(t, e.do("POST", "/api/v1/auth/google", "", map[string]any{"idToken": googleTok()}))

	d := devID("conflict")
	g := parseAuth(t, e.deviceGuest(d))
	friend := e.guestProgress(t, g)
	coins := e.coins(g.Token)

	r := e.do("POST", "/api/v1/account/link/google", g.Token, map[string]any{"idToken": googleTok()})
	if r.Status != 409 || errCode(r) != "identity_conflict" {
		t.Fatalf("link a taken identity: %d %s, want 409 identity_conflict", r.Status, r.Raw)
	}
	assertUserProviders(t, "/me after the conflict", e.do("GET", "/api/v1/me", g.Token, nil), true, "guest")
	if guests, devices := e.identityCounts(g.UserID); guests != 1 || devices != 1 {
		t.Fatalf("identities after the conflict: %d guest / %d device", guests, devices)
	}

	// "Sign in to that account instead": the other account, untouched; it
	// cannot take the device.
	xs := parseAuth(t, e.do("POST", "/api/v1/auth/google", "", map[string]any{"idToken": googleTok()}))
	if xs.UserID != x.UserID || xs.UserID == g.UserID || xs.Coins != 1_000_000 {
		t.Fatalf("sign in instead resolved to %s with %d coins", xs.UserID, xs.Coins)
	}
	if r := e.bindDevice(xs.Token, d); r.Status != 409 || errCode(r) != "not_a_guest" {
		t.Fatalf("bind the other account: %d %s", r.Status, r.Raw)
	}
	// "Switch back to guest" / "Play as guest": the same guest.
	e.assertSameGuest(t, "guest secret", e.guestResume(g.GuestSecret), g, friend, coins, 10)
	e.assertSameGuest(t, "play as guest", e.deviceGuest(d), g, friend, coins, 10)
	e.assertSameGuest(t, "device resume", e.deviceResume(d), g, friend, coins, 10)
}

// (d) After the guest deletes its account, nothing restores it and "Play as
// guest" on the device starts a new guest with a new welcome grant.
func TestDeletedGuestStartsANewGuest(t *testing.T) {
	e := newEnv(t, envOpts{proxyHops: 1})
	d := devID("deleted")
	g := parseAuth(t, e.deviceGuest(d))
	e.guestProgress(t, g)
	if r := e.deleteAccount(g.Token, confirmDelete); r.Status != 204 {
		t.Fatalf("delete: %d %s", r.Status, r.Raw)
	}
	if r := e.guestResume(g.GuestSecret); r.Status != 401 {
		t.Fatalf("guest resume after deletion: %d %s", r.Status, r.Raw)
	}
	if r := e.deviceResume(d); r.Status != 404 {
		t.Fatalf("device resume after deletion: %d %s", r.Status, r.Raw)
	}
	nr := e.deviceGuest(d)
	n := parseAuth(t, nr)
	if nr.Status != 201 || nr.Body["isNewUser"] != true || n.UserID == g.UserID || n.UID == g.UID ||
		n.Coins != 1_000_000 || n.Diamonds != 50 || n.GuestSecret == "" {
		t.Fatalf("play as guest after deletion: %d %s", nr.Status, nr.Raw)
	}
	if fs := e.friends(t, n).Body["friends"].([]any); len(fs) != 0 {
		t.Fatalf("new guest has friends: %v", fs)
	}
	if a := parseAuth(t, e.deviceGuest(d)); a.UserID != n.UserID {
		t.Fatalf("the new guest is the device guest from now on; got %s", a.UserID)
	}
}

// Guest credentials written before linking removed them (older servers) are
// ignored for a linked account, and its device binding is released for the
// device's next guest.
func TestLegacyGuestCredentialsOfALinkedAccount(t *testing.T) {
	e := newEnv(t, envOpts{proxyHops: 1})
	ctx := context.Background()
	x := parseAuth(t, e.do("POST", "/api/v1/auth/google", "", map[string]any{
		"idToken": e.oidc.googleToken(t, devID("legacy-google"), googleAud, time.Hour)}))
	d, secret := devID("legacy"), "gs_legacy_"+devID("secret")
	key := identity.DeviceKey(e.app.Cfg.Auth.PublicIDKey)
	devSub, err := identity.DeviceSubject(key, "android", d)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := e.app.PG.Exec(ctx, `INSERT INTO identity.auth_identities (provider, subject, user_id)
		VALUES ('device', $1, $3), ('guest', $2, $3)`, devSub, auth.HashSecret(secret), x.UserID); err != nil {
		t.Fatal(err)
	}
	if r := e.guestResume(secret); r.Status != 401 || errCode(r) != "invalid_credential" {
		t.Fatalf("legacy guest secret: %d %s", r.Status, r.Raw)
	}
	if r := e.deviceResume(d); r.Status != 404 {
		t.Fatalf("legacy device binding: %d %s", r.Status, r.Raw)
	}
	nr := e.deviceGuest(d)
	if n := parseAuth(t, nr); nr.Status != 201 || n.UserID == x.UserID || e.deviceOwner("android", d) != n.UserID {
		t.Fatalf("play as guest on a legacy-bound device: %d %s", nr.Status, nr.Raw)
	}

	// PUT /account/device releases a legacy binding too.
	d2 := devID("legacy2")
	devSub2, _ := identity.DeviceSubject(key, "android", d2)
	if _, err := e.app.PG.Exec(ctx, `DELETE FROM identity.auth_identities WHERE provider = 'device' AND user_id = $1`, x.UserID); err != nil {
		t.Fatal(err)
	}
	if _, err := e.app.PG.Exec(ctx, `INSERT INTO identity.auth_identities (provider, subject, user_id)
		VALUES ('device', $1, $2)`, devSub2, x.UserID); err != nil {
		t.Fatal(err)
	}
	g := e.guestFromFreshIP()
	if r := e.bindDevice(g.Token, d2); r.Status != 200 || e.deviceOwner("android", d2) != g.UserID {
		t.Fatalf("bind a legacy-bound device: %d %s", r.Status, r.Raw)
	}
}

// Linking and binding one guest at the same time never leave a linked
// account bound to a device.
func TestConcurrentLinkAndBind(t *testing.T) {
	e := newEnv(t, envOpts{proxyHops: 1})
	for i := 0; i < 6; i++ {
		g := e.guestFromFreshIP()
		d := devID("race-bind")
		var link, bind resp
		var wg sync.WaitGroup
		wg.Add(2)
		go func() {
			defer wg.Done()
			link = e.do("POST", "/api/v1/account/link/google", g.Token,
				map[string]any{"idToken": e.oidc.googleToken(t, devID("race-google"), googleAud, time.Hour)})
		}()
		go func() { defer wg.Done(); bind = e.bindDevice(g.Token, d) }()
		wg.Wait()
		if link.Status != 200 {
			t.Fatalf("link: %d %s", link.Status, link.Raw)
		}
		if bind.Status != 200 && (bind.Status != 409 || errCode(bind) != "not_a_guest") {
			t.Fatalf("bind: %d %s", bind.Status, bind.Raw)
		}
		if guests, devices := e.identityCounts(g.UserID); guests != 0 || devices != 0 || e.deviceOwner("android", d) != "" {
			t.Fatalf("round %d: linked account keeps %d guest / %d device identities", i, guests, devices)
		}
	}
}
