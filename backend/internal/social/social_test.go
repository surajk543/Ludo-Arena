package social

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"

	"ludoarena/internal/gameevents"
	"ludoarena/internal/playerinfo"
	"ludoarena/internal/progression"
	"ludoarena/internal/progression/progtest"
)

var testNow = time.Date(2026, 10, 21, 12, 0, 0, 0, time.UTC)

type fixture struct {
	env   *progtest.Env
	clock *progtest.Clock
	notes *progtest.Notifier
	prog  *progression.Service
	soc   *Service
}

func newFixture(t *testing.T, opts Options) *fixture {
	t.Helper()
	env := progtest.Setup(t)
	f := &fixture{env: env, clock: progtest.NewClock(testNow), notes: &progtest.Notifier{}}
	prog, err := progression.New(env.Pool, env.RDB, env.Profiles, f.notes, env.Log, progression.Options{
		CatalogPath: env.CatalogPath(), MissionsPath: env.MissionsPath(), Now: f.clock.Now})
	if err != nil {
		t.Fatal(err)
	}
	opts.Now = f.clock.Now
	f.prog = prog
	f.soc = New(env.Pool, env.RDB, env.Profiles, prog, f.notes, env.Log, opts)
	return f
}

func (f *fixture) code(id uuid.UUID) string { return f.env.Profiles.PublicID(id) }

func (f *fixture) befriend(t *testing.T, a, b uuid.UUID) {
	t.Helper()
	ctx := context.Background()
	if _, err := f.soc.Request(ctx, a, f.code(b)); err != nil {
		t.Fatal(err)
	}
	if _, err := f.soc.Accept(ctx, b, f.code(a)); err != nil {
		t.Fatal(err)
	}
}

func uids(fs []Friend) []string {
	var out []string
	for _, f := range fs {
		out = append(out, f.UID+":"+f.Status)
	}
	return out
}

func human(id uuid.UUID, won bool) gameevents.Participant {
	return gameevents.Participant{UserID: id, Won: won, Actions: 10}
}

func match(at time.Time, players ...gameevents.Participant) gameevents.MatchRecord {
	return gameevents.MatchRecord{MatchID: "r_" + uuid.NewString()[:8] + ":1", Game: "ludo", Variant: "classic", Mode: "public",
		Reason: "completed", Players: players, StartedAt: at.Add(-3 * time.Minute), FinishedAt: at}
}

func TestFriendRequestAcceptRemove(t *testing.T) {
	f := newFixture(t, Options{})
	ctx := context.Background()
	a, b := f.env.NewAccount(t), f.env.NewAccount(t)

	fr, err := f.soc.Request(ctx, a, " "+strings.ToUpper(f.code(b))+" ")
	if err != nil || fr.Status != StatusOutgoing || fr.UID != f.code(b) {
		t.Fatalf("request: %+v %v", fr, err)
	}
	msgs := f.notes.For(b, MsgFriendRequest)
	if len(msgs) != 1 {
		t.Fatalf("friend_request notifications = %d", len(msgs))
	}
	p := progtest.PayloadMap(t, msgs[0].Payload)
	if p["fromUid"] != f.code(a) || p["fromName"] != f.env.Profiles.Get(ctx, a).Name || len(p) != 2 {
		t.Fatalf("friend_request payload %v", p)
	}
	// Repeating is idempotent and does not notify again.
	if fr, err := f.soc.Request(ctx, a, f.code(b)); err != nil || fr.Status != StatusOutgoing {
		t.Fatalf("repeat: %+v %v", fr, err)
	}
	if len(f.notes.For(b, MsgFriendRequest)) != 1 {
		t.Fatal("repeat request notified again")
	}
	va, _ := f.soc.Friends(ctx, a)
	vb, _ := f.soc.Friends(ctx, b)
	if len(va.Outgoing) != 1 || len(vb.Incoming) != 1 || vb.Incoming[0].UID != f.code(a) || len(va.Friends) != 0 {
		t.Fatalf("pending views a=%+v b=%+v", va, vb)
	}
	if _, err := f.soc.Accept(ctx, a, f.code(b)); !errors.Is(err, ErrNoRequest) {
		t.Fatalf("requester cannot accept own request: %v", err)
	}
	fr, err = f.soc.Accept(ctx, b, f.code(a))
	if err != nil || fr.Status != StatusFriend {
		t.Fatalf("accept: %+v %v", fr, err)
	}
	if fr, err := f.soc.Accept(ctx, b, f.code(a)); err != nil || fr.Status != StatusFriend {
		t.Fatalf("accept is idempotent: %+v %v", fr, err)
	}
	if _, err := f.soc.Request(ctx, a, f.code(b)); !errors.Is(err, ErrAlreadyFriends) {
		t.Fatalf("request to a friend: %v", err)
	}
	va, _ = f.soc.Friends(ctx, a)
	if len(va.Friends) != 1 || va.Friends[0].Level != 1 || va.Friends[0].Title != "title_rookie" {
		t.Fatalf("friends view %+v", va)
	}
	if ok, _ := f.soc.AreFriends(ctx, b, a); !ok {
		t.Fatal("AreFriends false after accept")
	}
	if err := f.soc.Remove(ctx, b, f.code(a)); err != nil {
		t.Fatal(err)
	}
	if ok, _ := f.soc.AreFriends(ctx, a, b); ok {
		t.Fatal("still friends after remove")
	}
	if err := f.soc.Remove(ctx, b, f.code(a)); err != nil {
		t.Fatalf("remove is idempotent: %v", err)
	}
}

func TestReciprocalDeclineCancelSelf(t *testing.T) {
	f := newFixture(t, Options{})
	ctx := context.Background()
	a, b, c := f.env.NewAccount(t), f.env.NewAccount(t), f.env.NewAccount(t)

	if _, err := f.soc.Request(ctx, a, f.code(b)); err != nil {
		t.Fatal(err)
	}
	fr, err := f.soc.Request(ctx, b, f.code(a))
	if err != nil || fr.Status != StatusFriend {
		t.Fatalf("reciprocal request should auto-accept: %+v %v", fr, err)
	}
	if len(f.notes.For(a, MsgFriendRequest)) != 0 {
		t.Fatal("auto-accept should not send a new request notification")
	}

	// Decline (by the recipient) and cancel (by the sender).
	if _, err := f.soc.Request(ctx, a, f.code(c)); err != nil {
		t.Fatal(err)
	}
	if err := f.soc.Remove(ctx, c, f.code(a)); err != nil {
		t.Fatal(err)
	}
	if vc, _ := f.soc.Friends(ctx, c); len(vc.Incoming) != 0 {
		t.Fatal("decline left the request")
	}
	if _, err := f.soc.Request(ctx, a, f.code(c)); err != nil {
		t.Fatal(err)
	}
	if err := f.soc.Remove(ctx, a, f.code(c)); err != nil {
		t.Fatal(err)
	}
	if va, _ := f.soc.Friends(ctx, a); len(va.Outgoing) != 0 {
		t.Fatal("cancel left the request")
	}

	if _, err := f.soc.Request(ctx, a, f.code(a)); !errors.Is(err, ErrSelf) {
		t.Fatalf("self: %v", err)
	}
	for _, bad := range []string{"", "u_doesnotexist", "not-a-code", f.code(uuid.New())} {
		if _, err := f.soc.Request(ctx, a, bad); !errors.Is(err, ErrUnknownPlayer) {
			t.Errorf("request %q: %v", bad, err)
		}
	}
}

func TestFriendLimits(t *testing.T) {
	f := newFixture(t, Options{MaxFriends: 3, MaxOutgoing: 2, MaxIncoming: 2})
	ctx := context.Background()
	a := f.env.NewAccount(t)
	var others []uuid.UUID
	for i := 0; i < 6; i++ {
		others = append(others, f.env.NewAccount(t))
	}
	// A request sent while a still had room...
	if _, err := f.soc.Request(ctx, others[4], f.code(a)); err != nil {
		t.Fatal(err)
	}
	for _, o := range others[:3] {
		f.befriend(t, a, o)
	}
	// ...but once a is full, new requests fail in both directions...
	if _, err := f.soc.Request(ctx, a, f.code(others[3])); !errors.Is(err, ErrFriendLimit) {
		t.Fatalf("4th friend: %v", err)
	}
	if _, err := f.soc.Request(ctx, others[3], f.code(a)); !errors.Is(err, ErrFriendLimit) {
		t.Fatalf("request to a full account: %v", err)
	}
	// ...and the earlier request can be neither accepted nor auto-accepted.
	if _, err := f.soc.Accept(ctx, a, f.code(others[4])); !errors.Is(err, ErrFriendLimit) {
		t.Fatalf("accept beyond limit: %v", err)
	}
	if _, err := f.soc.Request(ctx, a, f.code(others[4])); !errors.Is(err, ErrFriendLimit) {
		t.Fatalf("auto-accept beyond limit: %v", err)
	}
	if ids, _ := f.soc.FriendIDs(ctx, a); len(ids) != 3 {
		t.Fatalf("friends = %d", len(ids))
	}
	if v, err := f.soc.Friends(ctx, a); err != nil || v.FriendCount != 3 || v.MaxFriends != 3 || v.OnlineCount != 0 {
		t.Fatalf("counts: %+v %v", v, err)
	}
	// Pending limits.
	b := f.env.NewAccount(t)
	if _, err := f.soc.Request(ctx, b, f.code(others[3])); err != nil {
		t.Fatal(err)
	}
	if _, err := f.soc.Request(ctx, b, f.code(others[5])); err != nil {
		t.Fatal(err)
	}
	if _, err := f.soc.Request(ctx, b, f.code(others[0])); !errors.Is(err, ErrFriendLimit) {
		t.Fatalf("3rd outgoing request: %v", err)
	}
	c := f.env.NewAccount(t)
	if _, err := f.soc.Request(ctx, c, f.code(others[5])); err != nil {
		t.Fatal(err)
	}
	d := f.env.NewAccount(t)
	if _, err := f.soc.Request(ctx, d, f.code(others[5])); !errors.Is(err, ErrFriendLimit) {
		t.Fatalf("3rd incoming request: %v", err)
	}
}

func TestInvites(t *testing.T) {
	f := newFixture(t, Options{})
	ctx := context.Background()
	a, b, c := f.env.NewAccount(t), f.env.NewAccount(t), f.env.NewAccount(t)
	f.befriend(t, a, b)
	inv := gameevents.Invite{RoomID: "r_abc", Code: "K7Q2MX", Game: "ludo", ExpiresAt: testNow.Add(2 * time.Minute)}

	// Avoid straddling a fixed rate-limit window boundary.
	if s := time.Now().Second(); s > 55 {
		time.Sleep(time.Duration(61-s) * time.Second)
	}
	if err := f.soc.SendInvite(ctx, a, f.code(c), inv); !errors.Is(err, gameevents.ErrNotFriends) {
		t.Fatalf("non-friend: %v", err)
	}
	if err := f.soc.SendInvite(ctx, a, "u_nobodyhere1", inv); !errors.Is(err, gameevents.ErrNotFriends) {
		t.Fatalf("unknown uid: %v", err)
	}
	if err := f.soc.SendInvite(ctx, a, f.code(b), inv); err != nil {
		t.Fatal(err)
	}
	msgs := f.notes.For(b, MsgInvite)
	if len(msgs) != 1 || len(f.notes.For(c, MsgInvite)) != 0 {
		t.Fatalf("invite deliveries: %v", msgs)
	}
	p := progtest.PayloadMap(t, msgs[0].Payload)
	want := map[string]any{"fromUid": f.code(a), "fromName": f.env.Profiles.Get(ctx, a).Name, "roomId": "r_abc",
		"code": "K7Q2MX", "game": "ludo", "expiresAt": float64(inv.ExpiresAt.UnixMilli())}
	for k, v := range want {
		if p[k] != v {
			t.Errorf("invite %s = %v, want %v", k, p[k], v)
		}
	}
	if id, _ := p["inviteId"].(string); !strings.HasPrefix(id, "inv_") || len(p) != 7 {
		t.Fatalf("invite payload %v", p)
	}
	// Re-inviting to the same room re-delivers the same invite id.
	if err := f.soc.SendInvite(ctx, a, f.code(b), inv); err != nil {
		t.Fatal(err)
	}
	msgs = f.notes.For(b, MsgInvite)
	if progtest.PayloadMap(t, msgs[1].Payload)["inviteId"] != p["inviteId"] {
		t.Fatal("same room invite should keep its id")
	}
	// 10 per minute per sender (4 attempts used above).
	var err error
	for i := 0; i < 7 && err == nil; i++ {
		err = f.soc.SendInvite(ctx, a, f.code(b), inv)
	}
	if !errors.Is(err, ErrInviteRateLimited) {
		t.Fatalf("expected rate limit, got %v", err)
	}
}

// botIn returns a bot participant with public id uid and stores its public
// card as the rooms engine does when it seats the bot.
func (f *fixture) botIn(t *testing.T, uid, name string, level int) gameevents.Participant {
	t.Helper()
	raw, _ := json.Marshal(playerinfo.BotCard{UID: uid, Name: name, Avatar: 4, Level: level, Title: "title_strategist",
		Picture: &playerinfo.Picture{ID: "pp_fox", Format: "image", Path: "profile_pictures/image/fox.png"}})
	if err := f.env.RDB.Set(context.Background(), playerinfo.BotCardKey(uid), raw, playerinfo.BotCardTTL).Err(); err != nil {
		t.Fatal(err)
	}
	return gameevents.Participant{UserID: uuid.New(), UID: uid, Bot: true, Actions: 10}
}

func TestRecentOpponentsPeopleAndPublicBots(t *testing.T) {
	f := newFixture(t, Options{})
	ctx := context.Background()
	a, b, c := f.env.NewAccount(t), f.env.NewAccount(t), f.env.NewAccount(t)
	f.befriend(t, a, c)
	kabir := f.botIn(t, "u_kabirkabirka", "Kabir", 7)
	rec := match(testNow, human(a, true), human(b, false), kabir)
	for i := 0; i < 2; i++ { // duplicate delivery is harmless
		if err := f.prog.RecordMatch(ctx, rec); err != nil {
			t.Fatal(err)
		}
	}
	quitter := human(c, false)
	quitter.Forfeited = true // forfeits still count as having met
	if err := f.prog.RecordMatch(ctx, match(testNow.Add(time.Minute), human(a, false), quitter)); err != nil {
		t.Fatal(err)
	}
	recent, err := f.soc.Recent(ctx, a)
	if err != nil {
		t.Fatal(err)
	}
	// Newest first; the bot is listed like a person (same-time entries in
	// ZSET order).
	if got := fmt.Sprint(uids(recent)); got != fmt.Sprint([]string{f.code(c) + ":friend", "u_kabirkabirka:none", f.code(b) + ":none"}) &&
		got != fmt.Sprint([]string{f.code(c) + ":friend", f.code(b) + ":none", "u_kabirkabirka:none"}) {
		t.Fatalf("recent = %v", got)
	}
	for _, r := range recent {
		if r.UID == "u_kabirkabirka" && (r.Name != "Kabir" || r.Level != 7 || r.Avatar != 4 || r.Picture == nil ||
			r.Picture.ID != "pp_fox" || r.Title != "title_strategist" || r.Online) {
			t.Fatalf("bot entry %+v", r)
		}
	}
	if rb, _ := f.soc.Recent(ctx, b); len(rb) != 2 {
		t.Fatalf("b recent = %v", uids(rb))
	}

	// One human against public-fill bots: the bots are recent players.
	solo := f.env.NewAccount(t)
	if err := f.prog.RecordMatch(ctx, match(testNow, human(solo, true), f.botIn(t, "u_tarataratara", "Tara", 3))); err != nil {
		t.Fatal(err)
	}
	if rs, _ := f.soc.Recent(ctx, solo); fmt.Sprint(uids(rs)) != "[u_tarataratara:none]" {
		t.Fatalf("public bots not recorded: %v", uids(rs))
	}
	// A pending request to the bot shows as outgoing, like to a person.
	if _, err := f.soc.Request(ctx, solo, "u_tarataratara"); err != nil {
		t.Fatal(err)
	}
	if rs, _ := f.soc.Recent(ctx, solo); fmt.Sprint(uids(rs)) != "[u_tarataratara:outgoing]" {
		t.Fatalf("after the request: %v", uids(rs))
	}

	// Practice and private-room bots (chosen computer opponents) are not.
	for _, mode := range []string{"practice", "private"} {
		p := f.env.NewAccount(t)
		m := match(testNow, human(p, true), f.botIn(t, "u_ishaishaisha", "Isha", 2))
		m.Mode = mode
		if err := f.prog.RecordMatch(ctx, m); err != nil {
			t.Fatal(err)
		}
		if rs, _ := f.soc.Recent(ctx, p); len(rs) != 0 {
			t.Fatalf("%s bots in recent players: %v", mode, uids(rs))
		}
	}

	// A bot whose card expired is forgotten.
	if err := f.env.RDB.Del(ctx, playerinfo.BotCardKey("u_tarataratara")).Err(); err != nil {
		t.Fatal(err)
	}
	if rs, _ := f.soc.Recent(ctx, solo); len(rs) != 0 {
		t.Fatalf("expired bot listed: %v", uids(rs))
	}
	if n, _ := f.env.RDB.ZCard(ctx, RecentKey(solo)).Result(); n != 0 {
		t.Fatalf("expired bot kept in the ZSET (%d)", n)
	}
	// Entries older than 14 days are not returned.
	f.clock.Set(testNow.Add(15 * 24 * time.Hour))
	if old, _ := f.soc.Recent(ctx, a); len(old) != 0 {
		t.Fatalf("stale opponents returned: %v", uids(old))
	}
}

func TestRecentOpponentsCappedAt20(t *testing.T) {
	f := newFixture(t, Options{})
	ctx := context.Background()
	a := f.env.NewAccount(t)
	var last uuid.UUID
	for i := 0; i < 22; i++ {
		o := f.env.NewAccount(t)
		last = o
		if err := f.prog.RecordMatch(ctx, match(testNow.Add(time.Duration(i)*time.Second), human(a, false), human(o, true))); err != nil {
			t.Fatal(err)
		}
	}
	rs, err := f.soc.Recent(ctx, a)
	if err != nil {
		t.Fatal(err)
	}
	if len(rs) != 20 || rs[0].UID != f.code(last) {
		t.Fatalf("recent len=%d first=%v", len(rs), rs[0])
	}
}

func TestPresenceOnlyForFriends(t *testing.T) {
	f := newFixture(t, Options{})
	ctx := context.Background()
	a, b, c := f.env.NewAccount(t), f.env.NewAccount(t), f.env.NewAccount(t)
	f.befriend(t, a, b)
	for _, id := range []uuid.UUID{b, c} {
		if err := f.env.RDB.Set(ctx, PresenceKey(id), "1", time.Minute).Err(); err != nil {
			t.Fatal(err)
		}
	}
	if err := f.prog.RecordMatch(ctx, match(testNow, human(a, false), human(b, true), human(c, false))); err != nil {
		t.Fatal(err)
	}
	// An offline friend sorts after the online one; an online pending
	// requester is not counted.
	d := f.env.NewAccount(t)
	f.befriend(t, a, d)
	if _, err := f.soc.Request(ctx, c, f.code(a)); err != nil {
		t.Fatal(err)
	}
	v, _ := f.soc.Friends(ctx, a)
	if len(v.Friends) != 2 || !v.Friends[0].Online || v.Friends[0].UID != f.code(b) || v.Friends[1].Online {
		t.Fatalf("online friend first: %+v", v.Friends)
	}
	if v.OnlineCount != 1 || v.FriendCount != 2 || v.MaxFriends != DefaultMaxFriends || len(v.Incoming) != 1 || v.Incoming[0].Online {
		t.Fatalf("counts: online %d friends %d max %d incoming %+v", v.OnlineCount, v.FriendCount, v.MaxFriends, v.Incoming)
	}
	rs, _ := f.soc.Recent(ctx, a)
	for _, r := range rs {
		if r.UID == f.code(c) && r.Online {
			t.Fatal("presence of a non-friend must not be revealed")
		}
	}
}

func TestFriendsLeaderboard(t *testing.T) {
	f := newFixture(t, Options{})
	ctx := context.Background()
	a, b, c, d := f.env.NewAccount(t), f.env.NewAccount(t), f.env.NewAccount(t), f.env.NewAccount(t)
	f.befriend(t, a, b)
	f.befriend(t, a, d)
	// a wins with friend b: a 20+15+5, b 20+5; stranger c gets XP too but is not listed.
	if err := f.prog.RecordMatch(ctx, match(testNow, human(a, true), human(b, false), human(c, false))); err != nil {
		t.Fatal(err)
	}
	lb, err := f.soc.FriendsLeaderboard(ctx, a)
	if err != nil {
		t.Fatal(err)
	}
	if lb.PeriodKey != "w2026-W43" || len(lb.Entries) != 3 {
		t.Fatalf("leaderboard %+v", lb)
	}
	e := lb.Entries
	if e[0].UID != f.code(a) || !e[0].IsMe || e[0].WeeklyXP != 40 || e[0].Rank != 1 ||
		e[1].UID != f.code(b) || e[1].WeeklyXP != 25 || e[1].Rank != 2 ||
		e[2].UID != f.code(d) || e[2].WeeklyXP != 0 || e[2].Rank != 3 {
		t.Fatalf("entries %+v", e)
	}
	// d plays a (friends, nobody wins): d 20+5 = 25 ties with b and shares its rank.
	if err := f.prog.RecordMatch(ctx, match(testNow, human(d, false), human(a, false))); err != nil {
		t.Fatal(err)
	}
	lb, _ = f.soc.FriendsLeaderboard(ctx, a)
	ranks := map[string]int{}
	for _, en := range lb.Entries {
		ranks[en.UID] = en.Rank
	}
	if ranks[f.code(a)] != 1 || ranks[f.code(b)] != 2 || ranks[f.code(d)] != 2 || lb.Entries[0].WeeklyXP != 65 {
		t.Fatalf("ranks %v (%+v)", ranks, lb.Entries)
	}
	// Leaderboards of different weeks are independent.
	f.clock.Set(testNow.AddDate(0, 0, 7))
	if lb, _ := f.soc.FriendsLeaderboard(ctx, a); lb.PeriodKey != "w2026-W44" || lb.Entries[0].WeeklyXP != 0 {
		t.Fatalf("next week %+v", lb)
	}
}

func TestHTTPSocialEndpoints(t *testing.T) {
	f := newFixture(t, Options{})
	rt, srv := f.env.Router(t)
	f.prog.Register(rt)
	f.soc.Register(rt)
	a, tokA := f.env.Guest(t)
	b, tokB := f.env.Guest(t)

	r := progtest.Do(t, srv, "POST", "/api/v1/friends/requests", tokA, map[string]string{"friendCode": f.code(b)}, nil)
	if r.Status != http.StatusCreated {
		t.Fatalf("request: %d %s", r.Status, r.Body)
	}
	var created struct{ Friend Friend }
	r.JSON(t, &created)
	if created.Friend.Status != StatusOutgoing || created.Friend.UID != f.code(b) {
		t.Fatalf("created %s", r.Body)
	}
	if r := progtest.Do(t, srv, "POST", "/api/v1/friends/requests", tokA, map[string]string{"friendCode": f.code(a)}, nil); r.Status != http.StatusUnprocessableEntity ||
		r.ErrorCode() != "cannot_friend_self" {
		t.Fatalf("self: %d %s", r.Status, r.Body)
	}
	if r := progtest.Do(t, srv, "POST", "/api/v1/friends/requests", tokA, map[string]string{"friendCode": "u_unknown0000"}, nil); r.Status != http.StatusNotFound {
		t.Fatalf("unknown: %d %s", r.Status, r.Body)
	}
	if r := progtest.Do(t, srv, "POST", "/api/v1/friends/requests", tokA, map[string]any{"friendCode": f.code(b), "email": "x"}, nil); r.Status != http.StatusBadRequest {
		t.Fatalf("unknown field: %d %s", r.Status, r.Body)
	}
	r = progtest.Do(t, srv, "GET", "/api/v1/friends", tokB, nil, nil)
	var fv FriendsView
	r.JSON(t, &fv)
	if r.Status != http.StatusOK || len(fv.Incoming) != 1 || fv.Friends == nil || fv.Outgoing == nil {
		t.Fatalf("GET friends: %d %s", r.Status, r.Body)
	}
	if r := progtest.Do(t, srv, "POST", "/api/v1/friends/requests/"+f.code(a)+"/accept", tokB, nil, nil); r.Status != http.StatusOK {
		t.Fatalf("accept: %d %s", r.Status, r.Body)
	}
	if r := progtest.Do(t, srv, "POST", "/api/v1/friends/requests", tokB, map[string]string{"friendCode": f.code(a)}, nil); r.Status != http.StatusConflict ||
		r.ErrorCode() != "already_friends" {
		t.Fatalf("already friends: %d %s", r.Status, r.Body)
	}
	if err := f.prog.RecordMatch(context.Background(), match(testNow, human(a, true), human(b, false))); err != nil {
		t.Fatal(err)
	}
	bodies := map[string][]byte{}
	for _, path := range []string{"/api/v1/friends", "/api/v1/social/recent", "/api/v1/leaderboards/friends"} {
		r := progtest.Do(t, srv, "GET", path, tokA, nil, nil)
		if r.Status != http.StatusOK {
			t.Fatalf("GET %s: %d %s", path, r.Status, r.Body)
		}
		bodies[path] = r.Body
		// Never expose account ids (other players' or our own) in social responses.
		for _, id := range []uuid.UUID{a, b} {
			if strings.Contains(string(r.Body), id.String()) {
				t.Fatalf("%s leaks an account id: %s", path, r.Body)
			}
		}
		for _, k := range []string{"email", "provider", "subject", `"id"`} {
			if strings.Contains(string(r.Body), k) {
				t.Fatalf("%s contains %q: %s", path, k, r.Body)
			}
		}
	}
	var lb Leaderboard
	if err := json.Unmarshal(bodies["/api/v1/leaderboards/friends"], &lb); err != nil || len(lb.Entries) != 2 || !lb.Entries[0].IsMe {
		t.Fatalf("leaderboard %s", bodies["/api/v1/leaderboards/friends"])
	}
	if !strings.Contains(string(bodies["/api/v1/social/recent"]), `"uid":"`+f.code(b)+`"`) {
		t.Fatalf("recent %s", bodies["/api/v1/social/recent"])
	}
	if r := progtest.Do(t, srv, "DELETE", "/api/v1/friends/"+f.code(b), tokA, nil, nil); r.Status != http.StatusNoContent {
		t.Fatalf("delete: %d %s", r.Status, r.Body)
	}
	if r := progtest.Do(t, srv, "POST", "/api/v1/friends/requests/"+f.code(b)+"/accept", tokA, nil, nil); r.Status != http.StatusNotFound {
		t.Fatalf("accept without request: %d %s", r.Status, r.Body)
	}
	if r := progtest.Do(t, srv, "GET", "/api/v1/friends", "", nil, nil); r.Status != http.StatusUnauthorized {
		t.Fatalf("unauthenticated: %d", r.Status)
	}
}

func TestConcurrentReciprocalRequests(t *testing.T) {
	f := newFixture(t, Options{MaxFriends: 1})
	ctx := context.Background()
	for i := 0; i < 5; i++ {
		a, b := f.env.NewAccount(t), f.env.NewAccount(t)
		errs := make(chan error, 2)
		go func() { _, err := f.soc.Request(ctx, a, f.code(b)); errs <- err }()
		go func() { _, err := f.soc.Request(ctx, b, f.code(a)); errs <- err }()
		for j := 0; j < 2; j++ {
			if err := <-errs; err != nil {
				t.Fatalf("concurrent reciprocal request: %v", err)
			}
		}
		if ok, _ := f.soc.AreFriends(ctx, a, b); !ok {
			t.Fatal("reciprocal requests must end as friends")
		}
	}
	// Two accepts racing for the last friend slot: exactly one wins.
	a, b, c := f.env.NewAccount(t), f.env.NewAccount(t), f.env.NewAccount(t)
	if _, err := f.soc.Request(ctx, b, f.code(a)); err != nil {
		t.Fatal(err)
	}
	if _, err := f.soc.Request(ctx, c, f.code(a)); err != nil {
		t.Fatal(err)
	}
	errs := make(chan error, 2)
	for _, o := range []uuid.UUID{b, c} {
		go func(o uuid.UUID) { _, err := f.soc.Accept(ctx, a, f.code(o)); errs <- err }(o)
	}
	e1, e2 := <-errs, <-errs
	if (e1 == nil) == (e2 == nil) || (!errors.Is(e1, ErrFriendLimit) && !errors.Is(e2, ErrFriendLimit)) {
		t.Fatalf("racing accepts: %v / %v", e1, e2)
	}
	if ids, _ := f.soc.FriendIDs(ctx, a); len(ids) != 1 {
		t.Fatalf("friends = %d, limit 1", len(ids))
	}
}

func TestBotsCannotUseProgressionOrSocial(t *testing.T) {
	f := newFixture(t, Options{})
	rt, srv := f.env.Router(t)
	f.prog.Register(rt)
	f.soc.Register(rt)
	bot := f.env.BotToken(t)
	for _, c := range []struct{ method, path string }{
		{"GET", "/api/v1/progression"}, {"GET", "/api/v1/missions"}, {"GET", "/api/v1/collection"},
		{"POST", "/api/v1/collection/items/emote_crown/purchase"}, {"GET", "/api/v1/friends"},
		{"GET", "/api/v1/social/recent"}, {"GET", "/api/v1/leaderboards/friends"},
	} {
		if r := progtest.Do(t, srv, c.method, c.path, bot, nil, nil); r.Status != http.StatusForbidden {
			t.Errorf("%s %s with a bot token: %d %s", c.method, c.path, r.Status, r.Body)
		}
	}
}
