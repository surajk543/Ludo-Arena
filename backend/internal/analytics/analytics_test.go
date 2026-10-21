package analytics

import (
	"bufio"
	"context"
	"net/http"
	"net/http/httptest"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"

	"ludoroyale/internal/metrics"
	"ludoroyale/internal/progression/progtest"
)

// A fixed far-future date keeps these global sketch keys away from real data;
// the keys are deleted before and after the test.
var day = time.Date(2031, 3, 4, 10, 0, 0, 0, time.UTC) // Tuesday

func newTracker(t *testing.T) (*Tracker, *progtest.Env, *progtest.Clock) {
	t.Helper()
	env := progtest.Setup(t)
	clock := progtest.NewClock(day)
	tr := New(env.RDB, []byte("test-active-user-key-0123456789abcdef"), env.Log)
	tr.SetClock(clock.Now)
	keys := []string{DayKey(day), DayKey(day.AddDate(0, 0, -1)), WeekKey(day)}
	env.RDB.Del(context.Background(), keys...)
	t.Cleanup(func() { env.RDB.Del(context.Background(), keys...) })
	return tr, env, clock
}

// scrape returns the value of one exported sample line.
func scrape(t *testing.T, sample string) float64 {
	t.Helper()
	srv := httptest.NewServer(metrics.Handler())
	defer srv.Close()
	resp, err := http.Get(srv.URL)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	sc := bufio.NewScanner(resp.Body)
	for sc.Scan() {
		if v, ok := strings.CutPrefix(sc.Text(), sample+" "); ok {
			f, err := strconv.ParseFloat(v, 64)
			if err != nil {
				t.Fatal(err)
			}
			return f
		}
	}
	return 0
}

func near(got, want int64) bool {
	d := got - want
	if d < 0 {
		d = -d
	}
	return float64(d) <= 0.03*float64(want)+1
}

func TestTouchAndEstimates(t *testing.T) {
	tr, env, clock := newTracker(t)
	ctx := context.Background()
	users := make([]uuid.UUID, 140)
	for i := range users {
		users[i] = uuid.New()
	}
	// Yesterday: users 0..99. Today: users 40..139 (60 returning, 40 new).
	clock.Set(day.AddDate(0, 0, -1))
	for _, u := range users[:100] {
		if err := tr.Touch(ctx, u); err != nil {
			t.Fatal(err)
		}
	}
	clock.Set(day)
	for _, u := range users[40:] {
		for i := 0; i < 2; i++ { // repeated touches count once
			if err := tr.Touch(ctx, u); err != nil {
				t.Fatal(err)
			}
		}
	}
	e, err := tr.Estimates(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if !near(e.Day, 100) || !near(e.Week, 140) || !near(e.Returning, 60) {
		t.Fatalf("estimates %+v, want ~{Day:100 Week:140 Returning:60}", e)
	}
	ttl := env.RDB.TTL(ctx, DayKey(day)).Val()
	if ttl < 39*24*time.Hour || ttl > 40*24*time.Hour {
		t.Fatalf("sketch TTL = %v", ttl)
	}
	if err := tr.Update(ctx); err != nil {
		t.Fatal(err)
	}
	if v := scrape(t, `active_users_estimate{window="day"}`); !near(int64(v), 100) {
		t.Fatalf("day gauge = %v", v)
	}
	if v := scrape(t, `active_users_estimate{window="week"}`); !near(int64(v), 140) {
		t.Fatalf("week gauge = %v", v)
	}
	if v := scrape(t, `returning_users_estimate{window="day"}`); !near(int64(v), 60) {
		t.Fatalf("returning gauge = %v", v)
	}
}

func TestPseudonymsAreKeyed(t *testing.T) {
	env := progtest.Setup(t)
	u := uuid.New()
	a := New(env.RDB, []byte("key-one-0123456789abcdef0123456789"), nil)
	b := New(env.RDB, []byte("key-two-0123456789abcdef0123456789"), nil)
	pa := a.pseudonym(u)
	if pa == b.pseudonym(u) || pa == a.pseudonym(uuid.New()) || strings.Contains(pa, strings.ReplaceAll(u.String(), "-", "")) ||
		len(pa) != 64 || pa != a.pseudonym(u) {
		t.Fatalf("pseudonym %q not a stable keyed hash", pa)
	}
	if DayKey(time.Date(2026, 10, 21, 23, 59, 59, 0, time.UTC)) != "au:d:20261021" || WeekKey(time.Date(2026, 10, 26, 0, 0, 0, 0, time.UTC)) != "au:w:2026-W44" {
		t.Fatal("sketch key format")
	}
}

func TestTelemetryEndpoint(t *testing.T) {
	tr, env, _ := newTracker(t)
	rt, srv := env.Router(t)
	tr.Register(rt)
	post := func(body any) progtest.Response {
		return progtest.Do(t, srv, "POST", "/api/v1/telemetry/events", "", body, nil)
	}
	errs0 := scrape(t, `client_errors_total{kind="client_error"}`)
	hash0 := scrape(t, `client_errors_total{kind="hash_mismatch"}`)
	ok0 := scrape(t, `client_reconnect_total{result="success"}`)
	fail0 := scrape(t, `client_reconnect_total{result="failure"}`)

	r := post(map[string]any{"events": []map[string]any{
		{"kind": "client_error", "count": 2},
		{"kind": "hash_mismatch", "count": 1},
		{"kind": "reconnect_success", "count": 50}, // capped at 20
		{"kind": "reconnect_failure", "count": 0},  // ignored
		{"kind": "user_email", "count": 1},         // not whitelisted: ignored
	}})
	if r.Status != http.StatusAccepted || strings.TrimSpace(string(r.Body)) != `{"accepted":3}` {
		t.Fatalf("telemetry: %d %s", r.Status, r.Body)
	}
	if scrape(t, `client_errors_total{kind="client_error"}`)-errs0 != 2 ||
		scrape(t, `client_errors_total{kind="hash_mismatch"}`)-hash0 != 1 ||
		scrape(t, `client_reconnect_total{result="success"}`)-ok0 != 20 ||
		scrape(t, `client_reconnect_total{result="failure"}`)-fail0 != 0 {
		t.Fatal("telemetry counters not incremented as expected")
	}
	if scrape(t, `client_errors_total{kind="user_email"}`) != 0 {
		t.Fatal("unknown kind created a metric label")
	}

	tooMany := make([]map[string]any, 9)
	for i := range tooMany {
		tooMany[i] = map[string]any{"kind": "client_error", "count": 1}
	}
	for name, body := range map[string]any{
		"too many":      map[string]any{"events": tooMany},
		"empty":         map[string]any{"events": []any{}},
		"extra field":   map[string]any{"events": []map[string]any{{"kind": "client_error", "count": 1, "uid": "u_x"}}},
		"not an object": []int{1, 2},
	} {
		if r := post(body); r.Status != http.StatusBadRequest {
			t.Errorf("%s: %d %s", name, r.Status, r.Body)
		}
	}
	req, _ := http.NewRequest("POST", srv.URL+"/api/v1/telemetry/events", strings.NewReader(`{"events":[{"kind":"client_error","count":1}]}`))
	if resp, err := srv.Client().Do(req); err != nil || resp.StatusCode != http.StatusBadRequest {
		t.Fatalf("missing app headers should be rejected by the version gate: %v", err)
	}
}

func TestRunUpdatesUntilCancelled(t *testing.T) {
	tr, _, _ := newTracker(t)
	tr.interval = 10 * time.Millisecond
	if err := tr.Touch(context.Background(), uuid.New()); err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan struct{})
	go func() { tr.Run(ctx); close(done) }()
	time.Sleep(50 * time.Millisecond)
	cancel()
	select {
	case <-done:
	case <-time.After(2 * time.Second):
		t.Fatal("Run did not stop")
	}
	if v := scrape(t, `active_users_estimate{window="day"}`); v != 1 {
		t.Fatalf("day gauge = %v", v)
	}
}
