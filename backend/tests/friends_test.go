package tests

import (
	"sync"
	"testing"
	"time"
)

// Friends cap (FRIENDS_MAX, default 20) and the online/friend counts of
// GET /friends.

// guestFromFreshIP creates a guest from a distinct client IP (needs
// envOpts.proxyHops) so a test can create more than the per-IP guest limit.
func (e *env) guestFromFreshIP() account {
	e.t.Helper()
	return parseAuth(e.t, e.do("POST", "/api/v1/auth/guest", "", map[string]any{}, "X-Forwarded-For", freshIP()))
}

func (e *env) friendRequest(from account, to string) resp {
	e.t.Helper()
	return e.do("POST", "/api/v1/friends/requests", from.Token, map[string]any{"friendCode": to})
}

func (e *env) friends(t *testing.T, a account) resp {
	t.Helper()
	r := e.do("GET", "/api/v1/friends", a.Token, nil)
	if r.Status != 200 {
		t.Fatalf("friends: %d %s", r.Status, r.Raw)
	}
	return r
}

func TestFriendLimitAndOnlineCount(t *testing.T) {
	e := newEnv(t, envOpts{proxyHops: 1})
	z := e.guestFromFreshIP()

	// 19 friends: each requests z, z accepts.
	var fs []account
	for i := 0; i < 19; i++ {
		f := e.guestFromFreshIP()
		if r := e.friendRequest(f, z.UID); r.Status != 201 {
			t.Fatalf("request %d: %d %s", i, r.Status, r.Raw)
		}
		if r := e.do("POST", "/api/v1/friends/requests/"+f.UID+"/accept", z.Token, nil); r.Status != 200 {
			t.Fatalf("accept %d: %d %s", i, r.Status, r.Raw)
		}
		fs = append(fs, f)
	}

	// z (19 friends) requests three players who then accept concurrently:
	// exactly one takes the last slot.
	ps := []account{e.guestFromFreshIP(), e.guestFromFreshIP(), e.guestFromFreshIP()}
	for _, p := range ps {
		if r := e.friendRequest(z, p.UID); r.Status != 201 {
			t.Fatalf("z request: %d %s", r.Status, r.Raw)
		}
	}
	results := make([]resp, len(ps))
	var wg sync.WaitGroup
	for i, p := range ps {
		wg.Add(1)
		go func(i int, p account) {
			defer wg.Done()
			results[i] = e.do("POST", "/api/v1/friends/requests/"+z.UID+"/accept", p.Token, nil)
		}(i, p)
	}
	wg.Wait()
	won, lost := 0, []account{}
	for i, r := range results {
		switch {
		case r.Status == 200:
			won++
		case r.Status == 422 && errCode(r) == "friend_limit":
			lost = append(lost, ps[i])
		default:
			t.Fatalf("concurrent accept: %d %s", r.Status, r.Raw)
		}
	}
	if won != 1 || len(lost) != 2 {
		t.Fatalf("concurrent accepts: %d won", won)
	}
	if v := e.friends(t, z); num(v.Body["friendCount"]) != 20 || num(v.Body["maxFriends"]) != 20 {
		t.Fatalf("z at the cap: %s", v.Raw)
	}

	// The 21st friend is refused in both directions and via auto-accept.
	y := e.guestFromFreshIP()
	if r := e.friendRequest(z, y.UID); r.Status != 422 || errCode(r) != "friend_limit" {
		t.Fatalf("full account sends request: %d %s", r.Status, r.Raw)
	}
	if r := e.friendRequest(y, z.UID); r.Status != 422 || errCode(r) != "friend_limit" {
		t.Fatalf("request to full account: %d %s", r.Status, r.Raw)
	}
	if r := e.friendRequest(lost[0], z.UID); r.Status != 422 || errCode(r) != "friend_limit" {
		t.Fatalf("auto-accept beyond the cap: %d %s", r.Status, r.Raw)
	}
	if v := e.friends(t, z); num(v.Body["friendCount"]) != 20 || len(v.Body["friends"].([]any)) != 20 {
		t.Fatalf("friend count changed: %s", v.Raw)
	}
	// After removing a friend the slot is free again.
	if r := e.do("DELETE", "/api/v1/friends/"+fs[18].UID, z.Token, nil); r.Status != 204 {
		t.Fatalf("remove: %d %s", r.Status, r.Raw)
	}
	if r := e.friendRequest(y, z.UID); r.Status != 201 {
		t.Fatalf("request after removal: %d %s", r.Status, r.Raw)
	}

	// Online: one friend connected over WebSocket, the others offline.
	online := e.mustDial("online-friend", fs[3])
	defer online.close()
	var v resp
	waitFor(t, 5*time.Second, "onlineCount 1", func() bool {
		v = e.friends(t, z)
		return num(v.Body["onlineCount"]) == 1
	})
	list := v.Body["friends"].([]any)
	first := list[0].(map[string]any)
	if first["uid"] != fs[3].UID || first["online"] != true || list[1].(map[string]any)["online"] != false ||
		num(v.Body["friendCount"]) != 19 || num(v.Body["maxFriends"]) != 20 {
		t.Fatalf("online friend first: %s", v.Raw)
	}
	// Presence is never revealed for pending requests.
	if inc := v.Body["outgoing"].([]any); len(inc) != 2 {
		t.Fatalf("outgoing: %s", v.Raw)
	}
	if inc := v.Body["incoming"].([]any); len(inc) != 1 || inc[0].(map[string]any)["online"] != false {
		t.Fatalf("incoming: %s", v.Raw)
	}
}
