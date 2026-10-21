package report

import (
	"context"
	"errors"
	"strings"
	"testing"
	"time"

	"ludoroyale/opsbot/internal/google"
	"ludoroyale/opsbot/internal/promapi"
	"ludoroyale/opsbot/internal/promapi/promtest"
)

var (
	ist     = mustLoc("Asia/Kolkata")
	queries = Queries{Backend: "backend", BotPlay: "bot-play", Node: "node"}
	fixedAt = time.Date(2026, 10, 21, 17, 0, 0, 0, ist)
)

func mustLoc(name string) *time.Location {
	l, err := time.LoadLocation(name)
	if err != nil {
		panic(err)
	}
	return l
}

var S = promtest.S

func statusRules() []promtest.Rule {
	return []promtest.Rule{
		{Match: `up{job="backend"}`, Vector: []promapi.Sample{S(1, "instance", "b1:9090"), S(1, "instance", "b2:9090")}},
		{Match: `up{job="bot-play"}`, Vector: []promapi.Sample{S(0, "instance", "bp:9091")}},
		{Match: "players_in_game", Vector: []promapi.Sample{S(1234, "actor", "human"), S(456, "actor", "bot")}},
		{Match: "ws_connections_active", Vector: []promapi.Sample{S(1500, "actor", "human")}},
		{Match: "node_cpu_seconds_total", Vector: []promapi.Sample{S(41.4, "instance", "h1:9100"), S(101, "instance", "h2:9100")}},
		{Match: "node_memory", Vector: []promapi.Sample{S(63, "instance", "h1:9100")}},
		{Match: "node_filesystem", Vector: []promapi.Sample{S(38, "instance", "h1:9100")}},
		{Match: "process_resident_memory_bytes", Vector: []promapi.Sample{S(312<<20, "job", "backend", "instance", "b1:9090")}},
		{Match: "process_cpu_seconds_total", Vector: []promapi.Sample{S(38, "job", "backend", "instance", "b1:9090")}},
		{Match: "rooms_in_game", Vector: []promapi.Sample{S(300, "game", "ludo"), S(118, "game", "snakes_ladders")}},
		{Match: "matches_started_total", Vector: []promapi.Sample{S(379.6, "mix", "human_only"), S(30, "mix", "mixed"), S(10.2, "mix", "bot_only")}},
		{Match: "matches_completed_total", Vector: []promapi.Sample{S(410.4)}},
		{Match: "active_users_estimate", Vector: []promapi.Sample{S(2300)}},
		{Match: "ALERTS", Vector: []promapi.Sample{
			S(1, "alertname", "HostCPUHigh", "severity", "warning", "instance", "h1:9100"),
			S(1, "alertname", "BackendInstanceDown", "severity", "critical", "instance", "b2:9090"),
		}},
	}
}

func collector(src Source) *Collector {
	return &Collector{Prom: src, Q: queries, Loc: ist, Now: func() time.Time { return fixedAt }, TrendDays: 30}
}

func TestStatusFromFakePrometheus(t *testing.T) {
	srv := promtest.New(statusRules()...)
	defer srv.Close()
	st := collector(promapi.New(srv.URL, 5*time.Second)).Status(context.Background(), false)

	checks := []struct {
		name string
		got  Num
		want Num
	}{
		{"playing human", st.PlayingHuman, N(1234)},
		{"playing bot", st.PlayingBot, N(456)},
		{"online human", st.OnlineHuman, N(1500)},
		{"online bot (gauge not created yet)", st.OnlineBot, N(0)},
		{"lobby (gauge absent)", st.LobbyHuman, Num{}},
		{"started human-only", st.StartedHumanOnly, N(380)},
		{"started with bots", st.StartedWithBots, N(40)},
		{"finished", st.Finished, N(410)},
		{"new accounts (no series, backend up)", st.NewAccounts, N(0)},
		{"DAU", st.DAU, N(2300)},
		{"rooms", st.RoomsTotal(), N(418)},
		{"backend up", st.BackendUp, N(2)},
		{"bot-play up", st.BotPlayUp, N(0)},
		{"max CPU clamps to 100", st.MaxCPU(), N(100)},
		{"max RAM", st.MaxRAM(), N(63)},
	}
	for _, c := range checks {
		if c.got != c.want {
			t.Errorf("%s = %+v, want %+v", c.name, c.got, c.want)
		}
	}
	if len(st.Hosts) != 2 || st.Hosts[0].Instance != "h1:9100" || st.Hosts[0].Disk != N(38) || st.Hosts[1].RAM.OK {
		t.Errorf("hosts = %+v", st.Hosts)
	}
	if len(st.Processes) != 1 || st.Processes[0].RSS != N(312<<20) {
		t.Errorf("processes = %+v", st.Processes)
	}
	if len(st.Firing) != 2 || st.Firing[0].Name != "BackendInstanceDown" || st.Firing[0].Instances[0] != "b2:9090" {
		t.Errorf("firing (critical first) = %+v", st.Firing)
	}
	if len(st.Errors) != 0 {
		t.Errorf("errors = %v", st.Errors)
	}
	for _, q := range srv.Received() {
		if strings.Contains(q, "matches_started_total") && !strings.Contains(q, `mix!="loadtest"`) {
			t.Errorf("load tests not excluded: %s", q)
		}
		if strings.Contains(q, "players_in_game") && !strings.HasPrefix(q, "max by (actor)") {
			t.Errorf("cluster gauge must use max: %s", q)
		}
	}
}

func TestStatusWithoutAnyData(t *testing.T) {
	srv := promtest.New() // Prometheus up, but nothing scraped
	defer srv.Close()
	st := collector(promapi.New(srv.URL, 5*time.Second)).Status(context.Background(), true)
	for name, n := range map[string]Num{
		"playing": st.PlayingHuman, "online": st.OnlineHuman, "started": st.StartedHumanOnly,
		"accounts": st.NewAccounts, "dau": st.DAU, "rooms": st.RoomsTotal(), "cpu": st.MaxCPU(),
	} {
		if n.OK {
			t.Errorf("%s = %v, want n/a", name, n.V)
		}
	}
	if len(st.Errors) != 0 || len(st.Hosts) != 0 || len(st.Charts.Players) != 0 {
		t.Errorf("unexpected data: %+v", st)
	}
	text := StatusText(st, Meta{Env: "dev", Loc: ist})
	if !strings.Contains(text, "Real players n/a · Bots n/a") || !strings.Contains(text, "no node_exporter data") {
		t.Errorf("status text:\n%s", text)
	}
}

func TestQueryErrorsBecomeGaps(t *testing.T) {
	srv := promtest.New(promtest.Rule{Match: "players_in_game", Err: "unknown function"})
	defer srv.Close()
	st := collector(promapi.New(srv.URL, 5*time.Second)).Status(context.Background(), false)
	if st.PlayingHuman.OK || len(st.Errors) == 0 || !strings.Contains(st.Errors[0], "unknown function") {
		t.Fatalf("playing = %+v errors = %v", st.PlayingHuman, st.Errors)
	}
	if !strings.Contains(StatusText(st, Meta{Env: "dev", Loc: ist}), "Data gaps (1)") {
		t.Error("status text does not mention the data gap")
	}
}

// recSource records instant-query evaluation times.
type recSource struct {
	*promapi.Client
	at map[string]time.Time
}

func (r *recSource) Query(ctx context.Context, expr string, at time.Time) ([]promapi.Sample, error) {
	r.at[expr] = at
	return r.Client.Query(ctx, expr, at)
}

type fakePlay struct{ err error }

func (f fakePlay) Installs(context.Context, time.Time, int) (google.PlayReport, error) {
	return google.PlayReport{}, f.err
}

func TestDigestFromFakePrometheus(t *testing.T) {
	srv := promtest.New(
		promtest.Rule{Match: `up{job="backend"}`, Vector: []promapi.Sample{S(1)}},
		promtest.Rule{Match: "auth_accounts_created_total", Vector: []promapi.Sample{S(301.4, "provider", "google"), S(211, "provider", "guest")}},
		promtest.Rule{Match: `window="day"`, Vector: []promapi.Sample{S(2510)}},
		promtest.Rule{Match: `window="week"`, Vector: []promapi.Sample{S(9800)}},
		promtest.Rule{Match: "sum by (game, mode) (increase(matches_started_total", Vector: []promapi.Sample{
			S(3010, "game", "ludo", "mode", "public"), S(1180, "game", "snakes_ladders", "mode", "public")}},
		promtest.Rule{Match: "sum by (game, mode) (increase(matches_completed_total", Vector: []promapi.Sample{S(2950, "game", "ludo", "mode", "public")}},
		promtest.Rule{Match: "sum by (mix)", Vector: []promapi.Sample{S(4000, "mix", "human_only"), S(190, "mix", "mixed")}},
		promtest.Rule{Match: "max_over_time(players_in_game", Vector: []promapi.Sample{S(1534, "actor", "human"), S(512, "actor", "bot")}},
		promtest.Rule{Match: "histogram_quantile", Vector: []promapi.Sample{S(18.4)}},
		promtest.Rule{Match: "http_requests_total", Vector: []promapi.Sample{S(250000, "class", "2xx"), S(988, "class", "4xx"), S(12, "class", "5xx")}},
	)
	defer srv.Close()
	rec := &recSource{Client: promapi.New(srv.URL, 5*time.Second), at: map[string]time.Time{}}
	c := collector(rec)
	c.Play = fakePlay{err: errors.New("google: 403 forbidden")}
	day := time.Date(2026, 10, 20, 0, 0, 0, 0, ist)
	d := c.Digest(context.Background(), day, false)

	if d.NewAccounts != N(512) || len(d.NewAccountsByProvider) != 2 || d.NewAccountsByProvider[0] != (KV{"google", 301}) {
		t.Errorf("accounts = %+v %+v", d.NewAccounts, d.NewAccountsByProvider)
	}
	if d.Started != N(4190) || d.Completed != N(2950) || len(d.ByGameMode) != 2 || d.ByGameMode[0].Completed != 2950 {
		t.Errorf("matches = %+v %+v %+v", d.Started, d.Completed, d.ByGameMode)
	}
	if d.HumanOnly != N(4000) || d.WithBots != N(190) || d.PeakHuman != N(1534) || d.PeakBot != N(512) {
		t.Errorf("mix/peaks = %+v %+v %+v %+v", d.HumanOnly, d.WithBots, d.PeakHuman, d.PeakBot)
	}
	if d.HTTP5xx != N(12) || d.HTTPTotal != N(251000) || d.Settlement != N(0) || d.WaitAvg.OK {
		t.Errorf("reliability = %+v %+v %+v avg=%+v", d.HTTP5xx, d.HTTPTotal, d.Settlement, d.WaitAvg)
	}
	if d.DAU != N(2510) || d.WAU != N(9800) || !d.DAUDay.Equal(time.Date(2026, 10, 20, 0, 0, 0, 0, time.UTC)) {
		t.Errorf("DAU = %+v WAU = %+v day %v", d.DAU, d.WAU, d.DAUDay)
	}
	if !d.Play.Configured || d.Play.Err == "" || d.GA4.Configured {
		t.Errorf("google sections = %+v %+v", d.Play, d.GA4)
	}
	// Windows end at local midnight (18:30 UTC); DAU is read at UTC midnight.
	for expr, at := range rec.at {
		switch {
		case strings.Contains(expr, "active_users_estimate"):
			if want := time.Date(2026, 10, 21, 0, 0, 0, 0, time.UTC); !at.Equal(want) {
				t.Errorf("DAU evaluated at %v, want %v", at, want)
			}
			if !strings.Contains(expr, "[1435m]") {
				t.Errorf("DAU window skips the first minutes of the UTC day: %s", expr)
			}
		case strings.Contains(expr, "auth_accounts_created_total"):
			if want := time.Date(2026, 10, 21, 0, 0, 0, 0, ist); !at.Equal(want) || !strings.Contains(expr, "[1d]") {
				t.Errorf("accounts evaluated at %v (%s)", at, expr)
			}
		}
	}
	text := DigestText(d, Meta{Env: "production", Loc: ist})
	for _, want := range []string{"Tue 20 Oct 2026 (IST)", "New accounts 512 (google 301 · guest 211)", "Human-only 4,000 (95%) · with bots 190",
		"HTTP 5xx 12 of 251,000 requests", "unavailable: google: 403 forbidden", "<b>Firebase Analytics</b>\nnot configured (set GA4_PROPERTY_ID)"} {
		if !strings.Contains(text, want) {
			t.Errorf("digest text lacks %q:\n%s", want, text)
		}
	}
}

func TestDigestTrends(t *testing.T) {
	day := time.Date(2026, 10, 20, 0, 0, 0, 0, ist)
	end := day.AddDate(0, 0, 1)
	var pts []promapi.Point
	for i := 0; i < 3; i++ { // only the last three days are in retention
		pts = append(pts, promapi.Point{T: end.AddDate(0, 0, -i), V: float64(100 + i)})
	}
	srv := promtest.New(
		promtest.Rule{Match: "sum by (game) (increase(matches_started_total", Matrix: []promapi.Series{{Labels: map[string]string{"game": "ludo"}, Points: pts}}},
		promtest.Rule{Match: `window="day"`, Matrix: []promapi.Series{{Labels: map[string]string{}, Points: []promapi.Point{
			{T: time.Date(2026, 10, 21, 0, 0, 0, 0, time.UTC), V: 2510}}}}},
	)
	defer srv.Close()
	d := collector(promapi.New(srv.URL, 5*time.Second)).Digest(context.Background(), day, true)
	tr := d.Trends
	if tr.Days != 30 || !tr.To.Equal(time.Date(2026, 10, 20, 0, 0, 0, 0, time.UTC)) || !tr.From.Equal(time.Date(2026, 9, 21, 0, 0, 0, 0, time.UTC)) {
		t.Fatalf("range = %v..%v (%d)", tr.From, tr.To, tr.Days)
	}
	if len(tr.MatchesByGame) != 1 || len(tr.MatchesByGame[0].Values) != 3 {
		t.Fatalf("matches by game = %+v", tr.MatchesByGame)
	}
	last := tr.MatchesByGame[0].Values[2]
	if !last.Day.Equal(time.Date(2026, 10, 20, 0, 0, 0, 0, time.UTC)) || last.V != 100 {
		t.Errorf("value at local midnight belongs to the previous day: %+v", last)
	}
	if len(tr.DAU) != 1 || !tr.DAU[0].Day.Equal(time.Date(2026, 10, 20, 0, 0, 0, 0, time.UTC)) {
		t.Errorf("DAU trend = %+v", tr.DAU)
	}
}
