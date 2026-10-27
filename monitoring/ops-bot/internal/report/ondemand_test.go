package report

import (
	"context"
	"errors"
	"math"
	"strings"
	"testing"
	"time"

	"ludoarena/opsbot/internal/backendapi"
	"ludoarena/opsbot/internal/promapi"
	"ludoarena/opsbot/internal/promapi/promtest"
)

func ramp(start time.Time, n int, step time.Duration, f func(i int) float64) []promapi.Point {
	pts := make([]promapi.Point, n)
	for i := range pts {
		pts[i] = promapi.Point{T: start.Add(time.Duration(i) * step), V: f(i)}
	}
	return pts
}

type stubBackend struct {
	online   backendapi.Online
	playtime backendapi.Playtime
	err      error
	limits   []int
}

func (s *stubBackend) Online(_ context.Context, limit int) (backendapi.Online, error) {
	s.limits = append(s.limits, limit)
	return s.online, s.err
}

func (s *stubBackend) Playtime(_ context.Context, hours, limit int) (backendapi.Playtime, error) {
	s.limits = append(s.limits, hours, limit)
	return s.playtime, s.err
}

func TestStatsOf(t *testing.T) {
	at := fixedAt
	pts := []promapi.Point{{T: at.Add(-3 * time.Minute), V: 4}, {T: at.Add(-2 * time.Minute), V: 10}, {T: at.Add(-time.Minute), V: -1}}
	st := StatsOf(append(pts, promapi.Point{T: at, V: math.NaN()}), at, 2*time.Minute)
	if !st.Peak.OK || st.Peak.V != 10 || !st.PeakAt.Equal(at.Add(-2*time.Minute)) || st.Avg.V != 14.0/3 || st.Now.V != 0 || !st.Now.OK {
		t.Errorf("stats = %+v", st)
	}
	if st := StatsOf(pts[:1], at, 2*time.Minute); st.Now.OK || !st.Avg.OK {
		t.Errorf("stale stats = %+v, want no Now", st)
	}
	if st := StatsOf(nil, at, time.Minute); st.Peak.OK || st.Avg.OK || st.Now.OK {
		t.Errorf("empty stats = %+v", st)
	}
}

func TestLiveFromPrometheusAndBackend(t *testing.T) {
	start := fixedAt.Add(-Window)
	online := ramp(start, 1441, time.Minute, func(i int) float64 { return float64(100 + i%300) })
	srv := promtest.New(
		promtest.Rule{Match: "ws_connections_active", Matrix: []promapi.Series{{Points: online}}},
		promtest.Rule{Match: "players_in_game", Matrix: []promapi.Series{{Points: ramp(start, 1441, time.Minute, func(int) float64 { return 40 })}}},
	)
	defer srv.Close()
	c := collector(promapi.New(srv.URL, 5*time.Second))

	l := c.Live(context.Background())
	if l.Configured || l.HasList() || l.OnlineNow().V != float64(100+1440%300) || l.OnlineStats.Peak.V != 399 {
		t.Errorf("without backend: online %v, peak %v", l.OnlineNow(), l.OnlineStats.Peak)
	}
	if l.PlayingNow().V != 40 || l.Count(backendapi.ActivityLudo).OK {
		t.Errorf("playing = %v, ludo count = %v", l.PlayingNow(), l.Count(backendapi.ActivityLudo))
	}
	got := srv.Received()
	for _, want := range []string{`sum(ws_connections_active{job="backend",actor="human"})`, `max(players_in_game{job="backend",actor="human"})`,
		`max(players_in_lobby{job="backend",actor="human"})`} {
		if !strings.Contains(strings.Join(got, "\n"), want) {
			t.Errorf("queries lack %s:\n%s", want, strings.Join(got, "\n"))
		}
	}
	if cap := LiveCaption(l, Meta{Env: "production", Loc: ist}); cap != "production · 340 online · 40 playing · peak 399 at "+l.OnlineStats.PeakAt.In(ist).Format("15:04") {
		t.Errorf("caption = %q", cap)
	}

	b := &stubBackend{online: backendapi.Online{Total: 5, Counts: map[string]int{"ludo": 2, "snakes_ladders": 1, "waiting": 1, "lobby": 1},
		Users: []backendapi.OnlineUser{{UID: "u_A", Name: "A<b>", Activity: "ludo", Game: "ludo", Mode: "public", OnlineSince: fixedAt.Add(-90 * time.Minute)}}}}
	c.Backend = b
	l = c.Live(context.Background())
	if !l.HasList() || l.OnlineNow().V != 5 || l.PlayingNow().V != 3 || b.limits[0] != ListLimit {
		t.Errorf("with backend: online %v playing %v limits %v", l.OnlineNow(), l.PlayingNow(), b.limits)
	}
	text := LiveText(l, Meta{Env: "production", Loc: ist})
	for _, want := range []string{"Online now:</b> 5 real players", "Ludo 2 · Snakes &amp; Ladders 1 · waiting 1 · lobby 1",
		"1. A&lt;b&gt; <code>u_A</code> · Ludo · Public · joined n/a · online 1h 30m"} {
		if !strings.Contains(text, want) {
			t.Errorf("text lacks %q:\n%s", want, text)
		}
	}

	b.err = errors.New("backend /api/v1/admin/ops/online: 401")
	l = c.Live(context.Background())
	if l.HasList() || l.ListErr == "" || l.OnlineNow().V != 340 {
		t.Errorf("backend error: %+v", l.ListErr)
	}
	if text := LiveText(l, Meta{Env: "production", Loc: ist}); !strings.Contains(text, "Player list unavailable: backend") {
		t.Errorf("error text = %s", text)
	}
}

func TestPlaytimeReport(t *testing.T) {
	c := collector(nil)
	if p := c.Playtime(context.Background()); p.Configured || p.OK() {
		t.Errorf("unconfigured = %+v", p)
	}
	b := &stubBackend{playtime: backendapi.Playtime{Games: []backendapi.GamePlaytime{
		{Game: "ludo", Seconds: 9000, Players: 3, Top: []backendapi.PlayerSeconds{{UID: "u_A", Name: "Asha", Seconds: 5400}}},
		{Game: "snakes_ladders", Seconds: 1830, Players: 2},
	}}}
	c.Backend = b
	p := c.Playtime(context.Background())
	if !p.OK() || p.TotalSeconds() != 10830 || b.limits[0] != 24 || b.limits[1] != ListLimit {
		t.Fatalf("playtime = %+v, limits %v", p, b.limits)
	}
	m := Meta{Env: "production", Loc: ist}
	if cap := PlaytimeCaption(p, m); cap != "production · last 24 h · Ludo 150 min (3 players) · S&amp;L 31 min (2 players)" {
		t.Errorf("caption = %q", cap)
	}
	text := PlaytimeText(p, m)
	for _, want := range []string{"<b>Ludo</b> — 150 min · 3 players · 50m per player", "1. Asha <code>u_A</code> · 90 min",
		"<b>Snakes &amp; Ladders</b> — 31 min · 2 players · 15m per player", "No play in the last 24 hours."} {
		if !strings.Contains(text, want) {
			t.Errorf("text lacks %q:\n%s", want, text)
		}
	}
}

func TestResourcesFromPrometheus(t *testing.T) {
	start := fixedAt.Add(-Window)
	step := resourcesStep
	n := int(Window/step) + 1
	cpu := ramp(start, n, step, func(i int) float64 { return float64(i % 90) })
	srv := promtest.New(
		promtest.Rule{Match: "node_cpu_seconds_total", Vector: []promapi.Sample{S(4, "instance", "h1:9100")},
			Matrix: []promapi.Series{{Labels: map[string]string{"instance": "h1:9100"}, Points: cpu}}},
		promtest.Rule{Match: "node_memory", Vector: []promapi.Sample{S(8<<30, "instance", "h1:9100")},
			Matrix: []promapi.Series{{Labels: map[string]string{"instance": "h1:9100"}, Points: ramp(start, n, step, func(int) float64 { return 140 })}}},
		promtest.Rule{Match: "postgres_pool_connections", Matrix: []promapi.Series{
			{Labels: map[string]string{"state": "acquired"}, Points: ramp(start, n, step, func(i int) float64 { return float64(i % 7) })},
			{Labels: map[string]string{"state": "idle"}, Points: ramp(start, n, step, func(int) float64 { return 3 })},
		}},
		promtest.Rule{Match: "postgres_pool_max_connections", Matrix: []promapi.Series{{Points: ramp(start, n, step, func(int) float64 { return 20 })}}},
	)
	defer srv.Close()
	r := collector(promapi.New(srv.URL, 5*time.Second)).Resources(context.Background())
	if len(r.Hosts) != 1 {
		t.Fatalf("hosts = %+v", r.Hosts)
	}
	h := r.Hosts[0]
	if h.Cores.V != 4 || h.MemBytes.V != 8<<30 || h.CPUStats.Peak.V != 89 || h.RAMStats.Peak.V != 100 || h.RAMStats.Now.V != 100 {
		t.Errorf("host = cores %v mem %v cpu peak %v ram %+v", h.Cores, h.MemBytes, h.CPUStats.Peak, h.RAMStats)
	}
	last := float64((n - 1) % 7)
	if r.PGInUseStats.Now.V != last || r.PGOpenStats.Now.V != last+3 || r.PGInUseStats.Peak.V != 6 || r.PGLimitNow.V != 20 {
		t.Errorf("pg = in use %+v open %+v limit %v", r.PGInUseStats, r.PGOpenStats.Now, r.PGLimitNow)
	}
	m := Meta{Env: "production", Loc: ist}
	if cap := ResourcesCaption(r, m); !strings.HasPrefix(cap, "production · CPU ") || !strings.Contains(cap, "(peak 89%) · RAM 100% (peak 100%) · PostgreSQL ") ||
		!strings.HasSuffix(cap, "open · limit 20") {
		t.Errorf("caption = %q", cap)
	}
	if text := ResourcesText(r, m); !strings.Contains(text, "<b>h1:9100</b>\nCPU ") || !strings.Contains(text, "peak in use 6 at") {
		t.Errorf("text = %s", text)
	}

	empty := collector(promapi.New(srv.URL+"/missing", time.Second)).Resources(context.Background())
	if len(empty.Hosts) != 0 || len(empty.Errors) == 0 || ResourcesCaption(empty, m) != "production · PostgreSQL n/a · no host metrics" {
		t.Errorf("empty = %+v caption %q", empty, ResourcesCaption(empty, m))
	}
}

func TestActivityNameAndFormats(t *testing.T) {
	for _, tc := range []struct{ act, game, mode, want string }{
		{"ludo", "ludo", "public", "Ludo · Public"}, {"snakes_ladders", "snakes_ladders", "", "Snakes & Ladders"},
		{"waiting", "ludo", "private", "Waiting · Ludo"}, {"waiting", "", "", "Waiting"}, {"lobby", "", "", "Lobby"},
	} {
		if got := ActivityName(tc.act, tc.game, tc.mode); got != tc.want {
			t.Errorf("ActivityName(%s,%s,%s) = %q, want %q", tc.act, tc.game, tc.mode, got, tc.want)
		}
	}
	for secs, want := range map[int64]string{0: "0m", 89: "1m", 3600: "1h 00m", 3900: "1h 05m", 90061: "25h 01m"} {
		if got := HoursMinutes(secs); got != want {
			t.Errorf("HoursMinutes(%d) = %q, want %q", secs, got, want)
		}
	}
	joined := time.Date(2026, 10, 21, 0, 30, 0, 0, time.UTC)
	if JoinedDate(&joined, ist) != "21 Oct 2026" || JoinedDate(nil, ist) != NA || !NewAccount(&joined, fixedAt, Window) || NewAccount(nil, fixedAt, Window) {
		t.Error("joined formatting")
	}
}
