package opsstats

import (
	"context"
	"encoding/json"
	"errors"
	"slices"
	"strconv"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/redis/go-redis/v9"

	"ludoarena/internal/progression/progtest"
	"ludoarena/internal/rooms"
)

// These tests use the progression fixtures (test PostgreSQL, Redis DB 14)
// and are skipped without them. Keys are cleaned up; the play tests write
// hours of 2020, which nothing else uses.

func TestPlaytimeReport(t *testing.T) {
	e := progtest.Setup(t)
	ctx := context.Background()
	now := at("2020-03-01T15:30:00Z")
	s := New(e.RDB, e.Pool, e.Profiles, e.Log, Options{Now: func() time.Time { return now }})
	t.Cleanup(func() {
		var keys []string
		for h := at("2020-02-29T12:00:00Z"); h.Before(at("2020-03-01T17:00:00Z")); h = h.Add(time.Hour) {
			keys = append(keys, TotalKey(h), PlayKey(rooms.GameLudo, h), PlayKey(rooms.GameSnakes, h))
		}
		_ = e.RDB.Del(ctx, keys...).Err()
	})
	a, b, c, d, f := e.NewAccount(t), e.NewAccount(t), e.NewAccount(t), e.NewAccount(t), e.NewAccount(t)
	play := func(id uuid.UUID, game, from, to string) { s.RecordPlay(ctx, id, game, at(from), at(to)) }
	play(a, rooms.GameLudo, "2020-03-01T14:50:00Z", "2020-03-01T15:10:00Z") // 10 + 10 min
	play(b, rooms.GameLudo, "2020-03-01T15:00:00Z", "2020-03-01T15:05:00Z")
	play(b, rooms.GameSnakes, "2020-03-01T13:00:00Z", "2020-03-01T13:30:00Z")
	play(c, rooms.GameLudo, "2020-03-01T14:00:00Z", "2020-03-01T14:15:00Z")
	play(d, rooms.GameLudo, "2020-03-01T15:10:00Z", "2020-03-01T15:15:00Z")
	play(f, rooms.GameLudo, "2020-03-01T15:20:00Z", "2020-03-01T15:25:00Z")
	// Ignored: unknown game, no account, empty interval.
	play(a, "chess", "2020-03-01T15:00:00Z", "2020-03-01T15:05:00Z")
	play(uuid.Nil, rooms.GameLudo, "2020-03-01T15:00:00Z", "2020-03-01T15:05:00Z")
	play(a, rooms.GameLudo, "2020-03-01T15:05:00Z", "2020-03-01T15:00:00Z")

	if ttl := e.RDB.TTL(ctx, PlayKey(rooms.GameLudo, at("2020-03-01T15:00:00Z"))).Val(); ttl <= 25*time.Hour || ttl > PlayTTL {
		t.Fatalf("play key TTL = %v", ttl)
	}
	if ttl := e.RDB.TTL(ctx, TotalKey(at("2020-03-01T14:00:00Z"))).Val(); ttl <= 25*time.Hour || ttl > PlayTTL {
		t.Fatalf("total key TTL = %v", ttl)
	}
	if tot := e.RDB.HGetAll(ctx, TotalKey(at("2020-03-01T15:00:00Z"))).Val(); len(tot) != 1 || tot["ludo"] != "1500000" {
		t.Fatalf("15:00 totals = %v", tot)
	}

	// B, D and F tie at 300 s: ordered by uid, also across the cut.
	ties := []uuid.UUID{b, d, f}
	slices.SortFunc(ties, func(x, y uuid.UUID) int {
		px, py := e.Profiles.PublicID(x), e.Profiles.PublicID(y)
		switch {
		case px < py:
			return -1
		case px > py:
			return 1
		}
		return 0
	})
	type want struct {
		id  uuid.UUID
		sec int64
	}
	check := func(gp GamePlaytime, game string, sec, players int64, hourly []int64, top []want) {
		t.Helper()
		if gp.Game != game || gp.Seconds != sec || gp.Players != players || len(gp.Hourly) != len(hourly) || len(gp.Top) != len(top) {
			t.Fatalf("%s = %+v", game, gp)
		}
		for i, h := range hourly {
			if gp.Hourly[i].Seconds != h {
				t.Fatalf("%s hourly[%d] = %+v, want %d s", game, i, gp.Hourly[i], h)
			}
		}
		for i, w := range top {
			p := gp.Top[i]
			if p.UserID != w.id.String() || p.Seconds != w.sec || p.UID != e.Profiles.PublicID(w.id) ||
				p.Name != e.Profiles.Get(ctx, w.id).Name || p.CreatedAt == nil {
				t.Fatalf("%s top[%d] = %+v, want %v %d s", game, i, p, w.id, w.sec)
			}
		}
	}

	// Last hour: the 14:00 bucket counts half (14:30 – 15:00).
	rep, err := s.Playtime(ctx, 1, 3)
	if err != nil {
		t.Fatal(err)
	}
	if raw, _ := json.Marshal(rep); string(raw[:68]) != `{"from":"2020-03-01T14:30:00Z","to":"2020-03-01T15:30:00Z","hours":1` {
		t.Fatalf("report = %s", raw)
	}
	if len(rep.Games) != 2 || !time.Time(rep.Games[0].Hourly[0].Hour).Equal(at("2020-03-01T14:00:00Z")) {
		t.Fatalf("report = %+v", rep)
	}
	check(rep.Games[0], rooms.GameLudo, 750+1500, 5, []int64{1500, 1500},
		[]want{{a, 900}, {c, 450}, {ties[0], 300}})
	check(rep.Games[1], rooms.GameSnakes, 0, 0, []int64{0, 0}, nil)

	// Last 24 hours: everything (the oldest bucket, Feb 29 15:00, is empty).
	rep, err = s.Playtime(ctx, 24, 100)
	if err != nil {
		t.Fatal(err)
	}
	hourly := make([]int64, 25)
	hourly[22], hourly[23], hourly[24] = 0, 1500, 1500
	check(rep.Games[0], rooms.GameLudo, 3000, 5, hourly,
		[]want{{a, 1200}, {c, 900}, {ties[0], 300}, {ties[1], 300}, {ties[2], 300}})
	snakes := make([]int64, 25)
	snakes[22] = 1800
	check(rep.Games[1], rooms.GameSnakes, 1800, 1, snakes, []want{{b, 1800}})

	// Temporary unions are deleted.
	if keys, _, _ := e.RDB.Scan(ctx, 0, "ptg:tmp:*", 1000).Result(); len(keys) != 0 {
		t.Fatalf("temporary keys left: %v", keys)
	}
}

func TestOnlineReport(t *testing.T) {
	e := progtest.Setup(t)
	ctx := context.Background()
	rdb := e.RDB
	s := New(rdb, e.Pool, e.Profiles, e.Log, Options{})
	suffix := strconv.FormatInt(time.Now().UnixNano(), 36)
	var cleanup []string
	var fields []string
	t.Cleanup(func() {
		_ = rdb.Del(ctx, append(cleanup, OnlineKey)...).Err()
		_ = rdb.HDel(ctx, "idx:rooms:live", fields...).Err()
	})
	_ = rdb.Del(ctx, OnlineKey).Err()

	since := time.Now().Add(-time.Hour).UnixMilli()
	online := func(id uuid.UUID) {
		since += 1000
		if err := rdb.Set(ctx, presenceKey(id.String()), "conn", time.Minute).Err(); err != nil {
			t.Fatal(err)
		}
		rdb.ZAdd(ctx, OnlineKey, redis.Z{Score: float64(since), Member: id.String()})
		cleanup = append(cleanup, presenceKey(id.String()))
	}
	pointer := func(id uuid.UUID, room string) {
		rdb.Set(ctx, "user:"+id.String()+":room", room, time.Hour)
		cleanup = append(cleanup, "user:"+id.String()+":room")
	}
	room := func(name, status, game, mode string, index string, seats ...rooms.Player) string {
		id := "r_ops" + name + suffix
		if seats != nil {
			raw, _ := json.Marshal(rooms.Room{ID: id, Game: game, Mode: mode, Status: status, Players: seats})
			rdb.HSet(ctx, "room:"+id, "rev", "5", "s", raw)
			cleanup = append(cleanup, "room:"+id)
		}
		if index != "" {
			rdb.HSet(ctx, "idx:rooms:live", id, index)
			fields = append(fields, id)
		}
		return id
	}
	human := func(id uuid.UUID, forfeited bool) rooms.Player {
		return rooms.Player{UserID: id.String(), Forfeited: forfeited, Connected: true}
	}
	bot := rooms.Player{UserID: uuid.NewString(), Bot: true}

	lobby, waiting, ludo, snakes, forfeited := e.NewAccount(t), e.NewAccount(t), e.NewAccount(t), e.NewAccount(t), e.NewAccount(t)
	finished, gone, zero, stale := e.NewAccount(t), e.NewAccount(t), e.NewAccount(t), e.NewAccount(t)
	for _, id := range []uuid.UUID{lobby, gone, finished, zero, forfeited, waiting, snakes, ludo} {
		online(id)
	}
	// stale: in the set without presence (its instance crashed).
	rdb.ZAdd(ctx, OnlineKey, redis.Z{Score: float64(since), Member: stale.String()},
		redis.Z{Score: 1, Member: "not-an-account"})

	pointer(waiting, room("w", rooms.StatusLobby, rooms.GameSnakes, rooms.ModePrivate,
		"5|lobby|snakes_ladders|private|1|0", human(waiting, false)))
	pointer(ludo, room("p", rooms.StatusPlaying, rooms.GameLudo, rooms.ModePractice,
		"5|playing|ludo|practice|1|1", human(ludo, false), bot))
	rs := room("s", rooms.StatusPlaying, rooms.GameSnakes, rooms.ModePublic,
		"5|playing|snakes_ladders|public|1|0", human(snakes, false), human(forfeited, true))
	pointer(snakes, rs)
	pointer(forfeited, rs) // missed turns: the pointer stays until the player leaves
	pointer(finished, room("x", rooms.StatusFinished, rooms.GameLudo, rooms.ModePublic, "", human(finished, false)))
	pointer(gone, room("g", "", "", "", "5|playing|ludo|public|1|0")) // the room key expired
	pointer(zero, room("z", "", "", "", "5|playing|ludo|public|0|2")) // every person forfeited

	rep, err := s.Online(ctx, 4)
	if err != nil {
		t.Fatal(err)
	}
	if rep.Total != 8 || rep.Counts != (Counts{Ludo: 1, Snakes: 1, Waiting: 1, Lobby: 5}) || len(rep.Users) != 4 {
		t.Fatalf("report = %+v", rep)
	}
	type want struct {
		id              uuid.UUID
		act, game, mode string
	}
	for i, w := range []want{
		{ludo, "ludo", "ludo", "practice"}, {snakes, "snakes_ladders", "snakes_ladders", "public"},
		{waiting, "waiting", "snakes_ladders", "private"}, {lobby, "lobby", "", ""},
	} {
		u := rep.Users[i]
		str := func(p *string) string {
			if p == nil {
				return ""
			}
			return *p
		}
		if u.UserID != w.id.String() || u.Activity != w.act || str(u.Game) != w.game || str(u.Mode) != w.mode ||
			(w.game == "") != (u.Game == nil) || u.UID != e.Profiles.PublicID(w.id) ||
			u.Name != e.Profiles.Get(ctx, w.id).Name || u.CreatedAt == nil {
			t.Fatalf("users[%d] = %+v, want %+v", i, u, w)
		}
	}
	// The stale member was removed; the malformed one is ignored.
	if err := rdb.ZScore(ctx, OnlineKey, stale.String()).Err(); !errors.Is(err, redis.Nil) {
		t.Fatalf("stale member kept: %v", err)
	}
	rep, err = s.Online(ctx, 500)
	if err != nil || rep.Total != 8 || len(rep.Users) != 8 {
		t.Fatalf("report = %+v, %v", rep, err)
	}
	var order []uuid.UUID
	for _, u := range rep.Users[3:] {
		order = append(order, uuid.MustParse(u.UserID))
	}
	if want := []uuid.UUID{lobby, gone, finished, zero, forfeited}; !slices.Equal(order, want) {
		t.Fatalf("lobby order = %v, want %v (online since, oldest first)", order, want)
	}
}
