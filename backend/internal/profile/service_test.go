package profile_test

import (
	"context"
	"errors"
	"fmt"
	"sync"
	"testing"
	"time"

	"github.com/google/uuid"

	"ludoroyale/internal/profile"
	"ludoroyale/internal/progression/progtest"
)

// Same key as progtest, so public ids match the shared fixtures.
const testKey = "test-public-id-key-0123456789abcdef"

type fixture struct {
	env   *progtest.Env
	svc   *profile.Service
	clock *progtest.Clock
}

func newFixture(t *testing.T, perDay int) *fixture {
	env := progtest.Setup(t)
	clock := progtest.NewClock(time.Date(2026, 10, 21, 12, 0, 0, 0, time.UTC))
	svc := profile.New(env.RDB, []byte(testKey)).
		WithPostgres(env.Pool, profile.Options{NameChangesPerDay: perDay, Now: clock.Now})
	return &fixture{env: env, svc: svc, clock: clock}
}

// account creates an account and removes its name-change counter afterwards.
func (f *fixture) account(t *testing.T) uuid.UUID {
	id := f.env.NewAccount(t)
	t.Cleanup(func() { f.env.RDB.Del(context.Background(), profile.NameChangesKey(id)) })
	return id
}

func (f *fixture) storedName(t *testing.T, id uuid.UUID) *string {
	t.Helper()
	var name *string
	if err := f.env.Pool.QueryRow(context.Background(),
		`SELECT display_name FROM progression.player_progress WHERE user_id = $1`, id).Scan(&name); err != nil {
		t.Fatal(err)
	}
	return name
}

func (f *fixture) cachedName(t *testing.T, id uuid.UUID) string {
	t.Helper()
	n, _ := f.env.RDB.HGet(context.Background(), "profile:"+id.String(), "name").Result()
	return n
}

func TestChosenNameWinsOverProviderNames(t *testing.T) {
	f := newFixture(t, 3)
	ctx := context.Background()
	id := f.account(t)

	// Without a chosen name, provider names refresh the profile (as before).
	if p, err := f.svc.Save(ctx, id, "Google Name"); err != nil || p.Name != "Google Name" {
		t.Fatalf("provider name: %+v %v", p, err)
	}
	p, changed, err := f.svc.ChangeName(ctx, id, "  Asha   Verma ")
	if err != nil || !changed || p.Name != "Asha Verma" || p.UID != f.svc.PublicID(id) {
		t.Fatalf("ChangeName: %+v %v %v", p, changed, err)
	}
	if n := f.storedName(t, id); n == nil || *n != "Asha Verma" {
		t.Fatalf("stored name %v", n)
	}
	if got := f.cachedName(t, id); got != "Asha Verma" {
		t.Fatalf("cached name %q", got)
	}
	// Sign-ins (provider name, guest/device with no name) never overwrite it.
	for _, provider := range []string{"Google Name", "Apple Name", ""} {
		if p, err := f.svc.Save(ctx, id, provider); err != nil || p.Name != "Asha Verma" {
			t.Fatalf("Save(%q) = %+v %v", provider, p, err)
		}
	}
	if got := f.svc.Get(ctx, id).Name; got != "Asha Verma" {
		t.Fatalf("Get = %q", got)
	}
}

func TestLostCacheIsRebuiltFromPostgres(t *testing.T) {
	f := newFixture(t, 3)
	ctx := context.Background()
	chosen, plain := f.account(t), f.account(t)
	stranger := uuid.New() // no account (e.g. a bot id)
	if _, _, err := f.svc.ChangeName(ctx, chosen, "Rahul_99"); err != nil {
		t.Fatal(err)
	}
	f.env.RDB.Del(ctx, "profile:"+chosen.String(), "profile:"+plain.String())

	// Get rebuilds the cache from PostgreSQL.
	if got := f.svc.Get(ctx, chosen).Name; got != "Rahul_99" {
		t.Fatalf("Get after cache loss = %q", got)
	}
	if got := f.cachedName(t, chosen); got != "Rahul_99" {
		t.Fatalf("cache not rebuilt: %q", got)
	}
	f.env.RDB.Del(ctx, "profile:"+chosen.String())
	m := f.svc.GetMany(ctx, []uuid.UUID{chosen, plain, stranger})
	if m[chosen].Name != "Rahul_99" || m[plain].Name != f.svc.GuestName(plain) || m[stranger].Name != f.svc.GuestName(stranger) {
		t.Fatalf("GetMany after cache loss = %+v", m)
	}
	if f.cachedName(t, chosen) != "Rahul_99" || f.cachedName(t, plain) != f.svc.GuestName(plain) {
		t.Fatal("GetMany did not rebuild the cache")
	}
	if n, _ := f.env.RDB.Exists(ctx, "profile:"+stranger.String()).Result(); n != 0 {
		t.Fatal("cache entry created for an id without an account")
	}
	// Sign-in also restores it.
	f.env.RDB.Del(ctx, "profile:"+chosen.String())
	if p, err := f.svc.Save(ctx, chosen, ""); err != nil || p.Name != "Rahul_99" {
		t.Fatalf("Save after cache loss = %+v %v", p, err)
	}
}

func TestNameChangeLimitIsRolling(t *testing.T) {
	f := newFixture(t, 2)
	ctx := context.Background()
	id := f.account(t)
	t0 := f.clock.Now()

	change := func(name string) (bool, error) {
		_, changed, err := f.svc.ChangeName(ctx, id, name)
		return changed, err
	}
	if c, err := change("Name One"); err != nil || !c {
		t.Fatalf("1st: %v %v", c, err)
	}
	f.clock.Set(t0.Add(time.Hour))
	if c, err := change("Name Two"); err != nil || !c {
		t.Fatalf("2nd: %v %v", c, err)
	}
	// The same name again is a no-op and does not count.
	if c, err := change(" Name   Two "); err != nil || c {
		t.Fatalf("same name: %v %v", c, err)
	}
	f.clock.Set(t0.Add(2 * time.Hour))
	_, err := change("Name Three")
	var lim *profile.LimitError
	if !errors.As(err, &lim) || lim.Limit != 2 || lim.RetryAfter != 22*time.Hour {
		t.Fatalf("3rd: %v", err)
	}
	if got := *f.storedName(t, id); got != "Name Two" {
		t.Fatalf("rejected change was stored: %q", got)
	}
	// Invalid names never consume the limit either.
	var ne *profile.NameError
	if _, err := change("x"); !errors.As(err, &ne) || ne.Reason != profile.ReasonTooShort {
		t.Fatalf("invalid: %v", err)
	}
	// 24 h after the first change one slot is free again.
	f.clock.Set(t0.Add(24*time.Hour + time.Millisecond))
	if c, err := change("Name Three"); err != nil || !c {
		t.Fatalf("after window: %v %v", c, err)
	}
	if _, err := change("Name Four"); !errors.As(err, &lim) || lim.RetryAfter != time.Hour-time.Millisecond {
		t.Fatalf("4th: %v", err)
	}
}

func TestPinningTheShownNameDoesNotCount(t *testing.T) {
	f := newFixture(t, 1)
	ctx := context.Background()
	id := f.account(t)
	shown := f.svc.Get(ctx, id).Name // generated "Player XXXX"
	if _, changed, err := f.svc.ChangeName(ctx, id, shown); err != nil || changed {
		t.Fatalf("pin: %v %v", changed, err)
	}
	if n := f.storedName(t, id); n == nil || *n != shown {
		t.Fatalf("pinned name not stored: %v", n)
	}
	if n, _ := f.env.RDB.ZCard(ctx, profile.NameChangesKey(id)).Result(); n != 0 {
		t.Fatalf("pin counted: %d", n)
	}
	// The one allowed change is still available.
	if _, changed, err := f.svc.ChangeName(ctx, id, "Dewi Lestari"); err != nil || !changed {
		t.Fatalf("change after pin: %v %v", changed, err)
	}
}

func TestConcurrentChangesRespectLimit(t *testing.T) {
	f := newFixture(t, 2)
	ctx := context.Background()
	id := f.account(t)
	var wg sync.WaitGroup
	var mu sync.Mutex
	ok, limited := 0, 0
	for i := 0; i < 6; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			_, _, err := f.svc.ChangeName(ctx, id, fmt.Sprintf("Racer %d", i))
			mu.Lock()
			defer mu.Unlock()
			var lim *profile.LimitError
			switch {
			case err == nil:
				ok++
			case errors.As(err, &lim):
				limited++
			default:
				t.Errorf("change %d: %v", i, err)
			}
		}(i)
	}
	wg.Wait()
	if ok != 2 || limited != 4 {
		t.Fatalf("ok %d limited %d, want 2 / 4", ok, limited)
	}
	// PostgreSQL and the cache agree on the winner.
	if stored := f.storedName(t, id); stored == nil || *stored != f.cachedName(t, id) {
		t.Fatalf("stored %v, cached %q", stored, f.cachedName(t, id))
	}
}

func TestChangeNameNeedsPostgres(t *testing.T) {
	env := progtest.Setup(t)
	svc := profile.New(env.RDB, []byte(testKey))
	if _, _, err := svc.ChangeName(context.Background(), uuid.New(), "Asha"); !errors.Is(err, profile.ErrNoStore) {
		t.Fatalf("err = %v", err)
	}
}

func TestSaveNewSkipsPostgres(t *testing.T) {
	env := progtest.Setup(t)
	// No PostgreSQL attached: SaveNew must not need it.
	svc := profile.New(env.RDB, []byte(testKey))
	ctx := context.Background()
	id := uuid.New()
	t.Cleanup(func() { env.RDB.Del(ctx, "profile:"+id.String()) })
	if p, err := svc.SaveNew(ctx, id, "  Google   Name "); err != nil || p.Name != "Google Name" {
		t.Fatalf("SaveNew(provider) = %+v %v", p, err)
	}
	if p, err := svc.SaveNew(ctx, id, ""); err != nil || p.Name != svc.GuestName(id) {
		t.Fatalf("SaveNew(guest) = %+v %v", p, err)
	}
}
