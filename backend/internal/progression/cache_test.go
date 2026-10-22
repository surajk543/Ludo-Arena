package progression

import (
	"context"
	"encoding/json"
	"reflect"
	"sync"
	"testing"
	"time"

	"github.com/google/uuid"
	dto "github.com/prometheus/client_model/go"
	"github.com/redis/go-redis/v9"

	"ludoarena/internal/metrics"
	"ludoarena/internal/playerinfo"
)

func lookups(cache, result string) float64 {
	var m dto.Metric
	if err := metrics.CacheLookups.WithLabelValues(cache, result).Write(&m); err != nil {
		panic(err)
	}
	return m.GetCounter().GetValue()
}

func (f *fixture) seat(t *testing.T, id uuid.UUID) playerinfo.Summary {
	t.Helper()
	s, err := f.svc.SeatSummary(context.Background(), id)
	if err != nil {
		t.Fatal(err)
	}
	return s
}

// pgSeat is the seat summary computed straight from PostgreSQL.
func (f *fixture) pgSeat(t *testing.T, id uuid.UUID) playerinfo.Summary {
	t.Helper()
	return f.svc.seatView(seatEntryOf(f.summary(t, id)))
}

func (f *fixture) cached(t *testing.T, key string) bool {
	t.Helper()
	n, err := f.env.RDB.Exists(context.Background(), key).Result()
	if err != nil {
		t.Fatal(err)
	}
	return n == 1
}

func (f *fixture) inSet(t *testing.T, key, member string) bool {
	t.Helper()
	ok, err := f.env.RDB.SIsMember(context.Background(), key, member).Result()
	if err != nil {
		t.Fatal(err)
	}
	return ok
}

func TestSeatCacheHitMissAndInvalidate(t *testing.T) {
	f := newFixture(t)
	ctx := context.Background()
	a := f.env.NewAccount(t)

	miss0, hit0 := lookups("seat", "miss"), lookups("seat", "hit")
	s := f.seat(t, a)
	if s.Level != 1 || s.Title != "title_rookie" || !reflect.DeepEqual(s.Loadout, playerinfo.StarterLoadout()) {
		t.Fatalf("new account seat %+v", s)
	}
	if !f.cached(t, SeatKey(a)) || f.cached(t, seatLeaseKey(a)) {
		t.Fatal("miss must fill the entry and release the lease")
	}
	if ttl := f.env.RDB.PTTL(ctx, SeatKey(a)).Val(); ttl <= 0 || ttl > SeatCacheTTL {
		t.Fatalf("seat entry TTL %s", ttl)
	}
	// A change that bypasses the writers stays invisible until invalidated:
	// the second read is served from Redis.
	if _, err := f.env.Pool.Exec(ctx, `UPDATE progression.player_progress SET xp = 600, level = 4 WHERE user_id = $1`, a); err != nil {
		t.Fatal(err)
	}
	if s := f.seat(t, a); s.Level != 1 {
		t.Fatalf("expected the cached level 1, got %d", s.Level)
	}
	if lookups("seat", "miss")-miss0 != 1 || lookups("seat", "hit")-hit0 != 1 {
		t.Fatal("expected exactly one miss then one hit")
	}
	f.svc.InvalidateSeat(ctx, a)
	if s := f.seat(t, a); s.Level != 4 || !reflect.DeepEqual(s, f.pgSeat(t, a)) {
		t.Fatalf("after invalidation %+v, want %+v", s, f.pgSeat(t, a))
	}
	// A hit and a miss return identical summaries.
	if s := f.seat(t, a); !reflect.DeepEqual(s, f.pgSeat(t, a)) {
		t.Fatalf("hit %+v differs from PostgreSQL %+v", s, f.pgSeat(t, a))
	}
	// An unreadable entry is dropped and refilled.
	f.env.RDB.Set(ctx, SeatKey(a), "{not json", time.Minute)
	if s := f.seat(t, a); s.Level != 4 {
		t.Fatalf("corrupt entry: %+v", s)
	}
	if s := f.seat(t, a); s.Level != 4 || !f.cached(t, SeatKey(a)) {
		t.Fatalf("corrupt entry not refilled: %+v", s)
	}
}

func TestSeatCacheInvalidatedByEveryWriter(t *testing.T) {
	f := newFixture(t)
	ctx := context.Background()
	a, b := f.env.NewAccount(t), f.env.NewAccount(t)

	// Level-up from a recorded match.
	f.setXP(t, a, 95)
	if s := f.seat(t, a); s.Level != 1 {
		t.Fatalf("level %d", s.Level)
	}
	if err := f.svc.RecordMatch(ctx, match("ludo", "classic", "public", testNow, human(a, false), human(b, false))); err != nil {
		t.Fatal(err)
	}
	if s := f.seat(t, a); s.Level != 2 {
		t.Fatalf("seat after match level-up: %+v", s)
	}

	// Level-up from a mission claim (t_ludo: +30 XP).
	c := f.env.NewAccount(t)
	f.setXP(t, c, 75)
	if err := f.svc.RecordMatch(ctx, match("ludo", "classic", "public", testNow, human(c, false), human(b, false))); err != nil {
		t.Fatal(err)
	}
	if s := f.seat(t, c); s.Level != 1 { // 95 XP, cached
		t.Fatalf("level %d", s.Level)
	}
	if _, err := f.svc.Claim(ctx, c, DayKey(testNow), "t_ludo"); err != nil {
		t.Fatal(err)
	}
	if s := f.seat(t, c); s.Level != 2 {
		t.Fatalf("seat after claim level-up: %+v", s)
	}

	// Purchase changes ownership only; equipping changes the seat.
	f.env.SetDiamonds(t, a, 1000) // the token costs more than the welcome grant
	if _, err := f.svc.Purchase(ctx, a, "token_crown"); err != nil {
		t.Fatal(err)
	}
	if s := f.seat(t, a); s.Loadout["token"] != "token_classic" {
		t.Fatalf("purchase must not equip: %+v", s.Loadout)
	}
	if _, err := f.svc.Equip(ctx, a, "token", "token_crown"); err != nil {
		t.Fatal(err)
	}
	if s := f.seat(t, a); s.Loadout["token"] != "token_crown" {
		t.Fatalf("seat after equip: %+v", s.Loadout)
	}
	// Title (a loadout slot) from a level-5 milestone, then reset to starter.
	d := f.env.NewAccount(t)
	f.setXP(t, d, 690)
	if err := f.svc.RecordMatch(ctx, match("ludo", "classic", "public", testNow, human(d, true), human(b, false))); err != nil {
		t.Fatal(err)
	}
	if s := f.seat(t, d); s.Level != 5 || s.Title != "title_rookie" {
		t.Fatalf("seat %+v", s)
	}
	if _, err := f.svc.Equip(ctx, d, "title", "title_strategist"); err != nil {
		t.Fatal(err)
	}
	if s := f.seat(t, d); s.Title != "title_strategist" || s.Loadout["title"] != "title_strategist" {
		t.Fatalf("seat after title equip: %+v", s)
	}
	if _, err := f.svc.Equip(ctx, d, "title", ""); err != nil {
		t.Fatal(err)
	}
	if s := f.seat(t, d); s.Title != "title_rookie" {
		t.Fatalf("seat after title reset: %+v", s)
	}
}

// A fill whose PostgreSQL read began before a writer's commit must not store
// the old value once the writer invalidated.
func TestSeatFillLosesToConcurrentInvalidation(t *testing.T) {
	f := newFixture(t)
	ctx := context.Background()
	a := f.env.NewAccount(t)
	keys := []string{SeatKey(a), seatLeaseKey(a)}
	stale, _ := jsonString(seatEntry{Level: 1})

	// Filler: miss + lease, then (slow) PostgreSQL read...
	if n, err := seatGet.Run(ctx, f.env.RDB, keys, "filler", 5000).Int(); err != nil || n != 1 {
		t.Fatalf("lease: %d %v", n, err)
	}
	// ...a second reader meanwhile gets no lease (it reads PostgreSQL only)...
	if n, _ := seatGet.Run(ctx, f.env.RDB, keys, "other", 5000).Int(); n != 0 {
		t.Fatal("second lease granted")
	}
	// ...a writer commits and invalidates...
	f.svc.InvalidateSeat(ctx, a)
	// ...so the filler's stale write is refused.
	if n, _ := seatFill.Run(ctx, f.env.RDB, keys, "filler", stale, 60000).Int(); n != 0 || f.cached(t, SeatKey(a)) {
		t.Fatal("stale fill stored after invalidation")
	}

	// Stress: readers race an equip loop; the final cached value must match
	// PostgreSQL without any extra invalidation.
	f.env.SetDiamonds(t, a, 1000) // the token costs more than the welcome grant
	if _, err := f.svc.Purchase(ctx, a, "token_crown"); err != nil {
		t.Fatal(err)
	}
	var wg sync.WaitGroup
	stop := make(chan struct{})
	for i := 0; i < 8; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for {
				select {
				case <-stop:
					return
				default:
				}
				if _, err := f.svc.SeatSummary(ctx, a); err != nil {
					t.Error(err)
					return
				}
			}
		}()
	}
	for i := 0; i < 30; i++ {
		item := "token_crown"
		if i%2 == 1 {
			item = ""
		}
		if _, err := f.svc.Equip(ctx, a, "token", item); err != nil {
			t.Fatal(err)
		}
	}
	close(stop)
	wg.Wait()
	if got, want := f.seat(t, a), f.pgSeat(t, a); !reflect.DeepEqual(got, want) {
		t.Fatalf("cached seat %+v != PostgreSQL %+v", got.Loadout, want.Loadout)
	}
}

func jsonString(v any) (string, error) {
	raw, err := json.Marshal(v)
	return string(raw), err
}

func TestEmoteCache(t *testing.T) {
	f := newFixture(t)
	ctx := context.Background()
	a, b := f.env.NewAccount(t), f.env.NewAccount(t)
	key := EmotesKey(a)

	if !f.owns(t, a, "emote_wave") || f.cached(t, key) {
		t.Fatal("starter emotes are owned without any lookup")
	}
	if f.owns(t, a, "emote_crown") {
		t.Fatal("unbought emote owned")
	}
	// Purchase, then the very next emote works.
	if _, err := f.svc.Purchase(ctx, a, "emote_crown"); err != nil {
		t.Fatal(err)
	}
	if !f.owns(t, a, "emote_crown") || !f.inSet(t, key, "emote_crown") {
		t.Fatal("purchased emote not owned / not cached")
	}
	if ttl := f.env.RDB.PTTL(ctx, key).Val(); ttl <= 0 || ttl > EmoteCacheTTL {
		t.Fatalf("emote set TTL %s", ttl)
	}
	hit0 := lookups("emotes", "hit")
	if !f.owns(t, a, "emote_crown") || lookups("emotes", "hit")-hit0 != 1 {
		t.Fatal("repeat emote was not a cache hit")
	}

	// Write-through: a level-3 milestone grants emote_laugh into the set.
	f.setXP(t, a, LevelStartXP(3)-5)
	if err := f.svc.RecordMatch(ctx, match("ludo", "classic", "public", testNow, human(a, false), human(b, false))); err != nil {
		t.Fatal(err)
	}
	if !f.inSet(t, key, "emote_laugh") {
		t.Fatal("milestone emote not written through to the cached set")
	}

	// A grant the set missed (fill raced the grant) is confirmed in
	// PostgreSQL and repaired; a non-owned emote stays rejected.
	if _, err := f.env.Pool.Exec(ctx, `INSERT INTO progression.inventory (user_id, item_id) VALUES ($1, 'emote_wow')`, a); err != nil {
		t.Fatal(err)
	}
	v0 := lookups("emotes", "verify")
	if !f.owns(t, a, "emote_wow") || !f.inSet(t, key, "emote_wow") || lookups("emotes", "verify")-v0 != 1 {
		t.Fatal("missed grant not confirmed and repaired")
	}
	if f.owns(t, b, "emote_crown") || f.owns(t, b, "emote_wow") {
		t.Fatal("other account owns a's emotes")
	}
}

func TestCachesFallBackToPostgresWhenRedisFails(t *testing.T) {
	f := newFixture(t)
	ctx := context.Background()
	a := f.env.NewAccount(t)
	f.setXP(t, a, 300)
	if _, err := f.svc.Purchase(ctx, a, "emote_crown"); err != nil {
		t.Fatal(err)
	}
	dead := redis.NewClient(&redis.Options{Addr: "127.0.0.1:1", DialTimeout: 50 * time.Millisecond, MaxRetries: -1})
	defer dead.Close()
	svc, err := New(f.env.Pool, dead, f.env.Profiles, f.notes, f.env.Log,
		Options{CatalogPath: f.env.CatalogPath(), MissionsPath: f.mpath, Now: f.clock.Now})
	if err != nil {
		t.Fatal(err)
	}
	e0 := lookups("seat", "error")
	s, err := svc.SeatSummary(ctx, a)
	if err != nil || s.Level != LevelForXP(300) {
		t.Fatalf("seat without Redis: %+v %v", s, err)
	}
	if lookups("seat", "error")-e0 != 1 {
		t.Fatal("Redis failure not counted")
	}
	if ok, err := svc.Owns(ctx, a, "emote_crown"); err != nil || !ok {
		t.Fatalf("emote without Redis: %v %v", ok, err)
	}
	if ok, err := svc.Owns(ctx, a, "emote_wow"); err != nil || ok {
		t.Fatalf("unowned emote without Redis: %v %v", ok, err)
	}
	// Writers still succeed; only the cache write fails.
	if _, err := svc.Equip(ctx, a, "token", ""); err != nil {
		t.Fatal(err)
	}
	if _, err := svc.Purchase(ctx, a, "trail_comet"); err != nil {
		t.Fatal(err)
	}
}
