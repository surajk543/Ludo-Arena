package social

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
)

func TestLiveBotRequests(t *testing.T) {
	ttl := DefaultBotRequestTTL
	at := func(d time.Duration) string {
		return fmt.Sprintf(`{"name":"N","avatar":2,"level":1,"title":"","at":%d}`, testNow.Add(-d).UnixMilli())
	}
	cases := []struct {
		name      string
		raw       map[string]string
		wantLive  []string
		wantStale []string
	}{
		{"empty", nil, nil, nil},
		{"newest first", map[string]string{"b_old": at(2 * time.Hour), "b_new": at(time.Minute)},
			[]string{"b_new", "b_old"}, nil},
		{"lapsed at exactly the TTL", map[string]string{"b_edge": at(ttl), "b_in": at(ttl - time.Millisecond)},
			[]string{"b_in"}, []string{"b_edge"}},
		{"unreadable entries are dropped", map[string]string{"b_bad": "{", "b_ok": at(0)},
			[]string{"b_ok"}, []string{"b_bad"}},
		{"same time: by uid", map[string]string{"b_b": at(time.Hour), "b_a": at(time.Hour)},
			[]string{"b_a", "b_b"}, nil},
	}
	for _, c := range cases {
		live, stale := liveBotRequests(c.raw, testNow, ttl)
		var got []string
		for _, p := range live {
			got = append(got, p.uid)
		}
		if strings.Join(got, ",") != strings.Join(c.wantLive, ",") || strings.Join(stale, ",") != strings.Join(c.wantStale, ",") {
			t.Errorf("%s: live %v stale %v", c.name, got, stale)
		}
	}
}

func TestMergeOutgoing(t *testing.T) {
	person := func(uid string, ago time.Duration) datedFriend {
		return datedFriend{at: testNow.Add(-ago), f: Friend{UID: uid, Status: StatusOutgoing}}
	}
	bot := func(uid string, ago time.Duration) pendingBot {
		return pendingBot{uid: uid, req: botRequest{Name: "Bot name", At: testNow.Add(-ago).UnixMilli()}}
	}
	cases := []struct {
		name   string
		people []datedFriend
		bots   []pendingBot
		want   string
	}{
		{"none", nil, nil, ""},
		{"people only", []datedFriend{person("u_a", time.Hour), person("u_b", 2*time.Hour)}, nil, "u_a,u_b"},
		{"interleaved", []datedFriend{person("u_a", time.Hour), person("u_b", 3*time.Hour)},
			[]pendingBot{bot("b_x", 2*time.Hour), bot("b_y", time.Minute)}, "b_y,u_a,b_x,u_b"},
	}
	for _, c := range cases {
		out := mergeOutgoing(c.people, c.bots)
		var got []string
		for _, f := range out {
			got = append(got, f.UID)
			if f.Status != StatusOutgoing {
				t.Errorf("%s: %s has status %s", c.name, f.UID, f.Status)
			}
		}
		if out == nil || strings.Join(got, ",") != c.want {
			t.Errorf("%s: %v", c.name, got)
		}
	}
}

// fakeBots is a BotLookup over a fixed set of bot seats.
func fakeBots(bots ...BotProfile) BotLookup {
	return func(_ context.Context, _ uuid.UUID, uid string) (BotProfile, error) {
		for _, b := range bots {
			if b.UID == uid {
				return b, nil
			}
		}
		return BotProfile{}, ErrUnknownPlayer
	}
}

func TestFriendRequestsToBots(t *testing.T) {
	asha := BotProfile{UID: "b_00000000a1", Name: "Asha", Avatar: 4, Level: 1, Title: "title_rookie"}
	omar := BotProfile{UID: "b_00000000b2", Name: "Omar", Avatar: 9, Level: 1}
	f := newFixture(t, Options{MaxFriends: 2, MaxOutgoing: 2, Bots: fakeBots(asha, omar)})
	ctx := context.Background()
	a, h1, h2 := f.env.NewAccount(t), f.env.NewAccount(t), f.env.NewAccount(t)

	// A request to a bot answers like one to a person.
	fr, err := f.soc.Request(ctx, a, " "+strings.ToUpper(asha.UID)+" ")
	want := Friend{UID: asha.UID, Name: "Asha", Avatar: 4, Level: 1, Title: "title_rookie", Status: StatusOutgoing}
	if err != nil || fr != want {
		t.Fatalf("request: %+v %v", fr, err)
	}
	if again, err := f.soc.Request(ctx, a, asha.UID); err != nil || again != want {
		t.Fatalf("repeat: %+v %v", again, err)
	}
	if len(f.notes.For(a, MsgFriendRequest)) != 0 {
		t.Fatal("a bot request notified someone")
	}
	// Pending requests to people and bots share the cap (2).
	if _, err := f.soc.Request(ctx, a, f.code(h1)); err != nil {
		t.Fatal(err)
	}
	if _, err := f.soc.Request(ctx, a, omar.UID); !errors.Is(err, ErrFriendLimit) {
		t.Fatalf("bot request over the pending cap: %v", err)
	}
	if _, err := f.soc.Request(ctx, a, f.code(h2)); !errors.Is(err, ErrFriendLimit) {
		t.Fatalf("person request over the pending cap: %v", err)
	}
	v, err := f.soc.Friends(ctx, a)
	if err != nil || len(v.Outgoing) != 2 || v.Outgoing[0].UID != f.code(h1) && v.Outgoing[1].UID != f.code(h1) {
		t.Fatalf("outgoing: %+v %v", v.Outgoing, err)
	}
	// Never accepted; unknown codes stay unknown.
	if _, err := f.soc.Accept(ctx, a, asha.UID); !errors.Is(err, ErrUnknownPlayer) {
		t.Fatalf("accept from a bot: %v", err)
	}
	if _, err := f.soc.Request(ctx, a, "b_ffffffffff"); !errors.Is(err, ErrUnknownPlayer) {
		t.Fatalf("unknown bot code: %v", err)
	}

	// Cancel (twice: the second is a no-op), then the slot is free again.
	for i := 0; i < 2; i++ {
		if err := f.soc.Remove(ctx, a, asha.UID); err != nil {
			t.Fatalf("cancel #%d: %v", i, err)
		}
	}
	if err := f.soc.Remove(ctx, a, "b_ffffffffff"); !errors.Is(err, ErrUnknownPlayer) {
		t.Fatalf("remove unknown: %v", err)
	}
	if _, err := f.soc.Request(ctx, a, omar.UID); err != nil {
		t.Fatalf("after cancel: %v", err)
	}

	// After DefaultBotRequestTTL the request lapses and is pruned.
	f.clock.Set(testNow.Add(DefaultBotRequestTTL))
	v, err = f.soc.Friends(ctx, a)
	if err != nil || len(v.Outgoing) != 1 || v.Outgoing[0].UID != f.code(h1) {
		t.Fatalf("after the TTL: %+v %v", v.Outgoing, err)
	}
	if n, _ := f.env.RDB.HLen(ctx, BotRequestsKey(a)).Result(); n != 0 {
		t.Fatalf("%d lapsed entries left", n)
	}
	f.clock.Set(testNow)

	// At the friend cap a request to a bot is refused like any other.
	full := f.env.NewAccount(t)
	f.befriend(t, full, h1)
	f.befriend(t, full, h2)
	if _, err := f.soc.Request(ctx, full, asha.UID); !errors.Is(err, ErrFriendLimit) {
		t.Fatalf("request at the friend cap: %v", err)
	}

	// Without a lookup, bot codes are unknown.
	plain := newFixture(t, Options{})
	if _, err := plain.soc.Request(ctx, a, asha.UID); !errors.Is(err, ErrUnknownPlayer) {
		t.Fatalf("no lookup: %v", err)
	}
}
