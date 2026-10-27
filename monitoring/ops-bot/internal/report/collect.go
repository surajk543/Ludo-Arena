package report

import (
	"context"
	"fmt"
	"math"
	"sort"
	"strings"
	"time"

	"ludoarena/opsbot/internal/google"
	"ludoarena/opsbot/internal/promapi"
)

// Source is the Prometheus API (implemented by *promapi.Client).
type Source interface {
	Query(ctx context.Context, expr string, at time.Time) ([]promapi.Sample, error)
	QueryRange(ctx context.Context, expr string, start, end time.Time, step time.Duration) ([]promapi.Series, error)
}

// PlaySource provides Google Play install statistics (nil: not configured).
type PlaySource interface {
	Installs(ctx context.Context, until time.Time, days int) (google.PlayReport, error)
}

// GA4Source provides Firebase Analytics statistics (nil: not configured).
type GA4Source interface {
	Summary(ctx context.Context, day time.Time, trendDays int) (google.GA4Summary, error)
}

// Collector gathers report data. Query failures never fail a report: the
// affected values become n/a and the error is listed in the report footer.
type Collector struct {
	Prom      Source
	Q         Queries
	Loc       *time.Location
	Now       func() time.Time
	Play      PlaySource
	GA4       GA4Source
	Backend   BackendSource // per-player lists for /live and /playtime (nil: not configured)
	TrendDays int
}

const rateWindow = 2 * time.Minute

type errList struct {
	seen map[string]bool
	list []string
}

func (e *errList) add(what string, err error) {
	if err == nil {
		return
	}
	msg := what + ": " + err.Error()
	if len(msg) > 160 {
		msg = msg[:160] + "…"
	}
	if e.seen == nil {
		e.seen = map[string]bool{}
	}
	if !e.seen[msg] {
		e.seen[msg] = true
		e.list = append(e.list, msg)
	}
}

// vec runs an instant query; ok is false when it failed or returned nothing.
func (c *Collector) vec(ctx context.Context, e *errList, what, expr string, at time.Time) ([]promapi.Sample, bool) {
	s, err := c.Prom.Query(ctx, expr, at)
	if err != nil {
		e.add(what, err)
		return nil, false
	}
	return s, len(s) > 0
}

// one returns the summed value of an instant query. When the query returns
// nothing and zeroIfUp is set (counters and lazily created series), the
// value is 0 as long as the backend is being scraped; otherwise it is n/a.
func (c *Collector) one(ctx context.Context, e *errList, what, expr string, at time.Time, zeroIfUp bool) Num {
	s, ok := c.vec(ctx, e, what, expr, at)
	if ok {
		if v, valid := promapi.Sum(s); valid {
			return N(math.Max(v, 0))
		}
		return Num{}
	}
	if zeroIfUp && s != nil {
		return N(0)
	}
	return Num{}
}

// labelled runs a query grouped by label. present is true when the metric
// exists (any sample); missing keys of a present metric count as 0.
func (c *Collector) labelled(ctx context.Context, e *errList, what, expr, label string, at time.Time) (map[string]float64, bool) {
	s, ok := c.vec(ctx, e, what, expr, at)
	if !ok {
		return nil, false
	}
	return promapi.ByLabel(s, label), true
}

func pick(m map[string]float64, present bool, key string) Num {
	if !present {
		return Num{}
	}
	return N(math.Max(m[key], 0))
}

func kvs(m map[string]float64) []KV {
	out := make([]KV, 0, len(m))
	for _, k := range promapi.SortedKeys(m) {
		out = append(out, KV{Key: k, V: math.Round(math.Max(m[k], 0))})
	}
	return out
}

func (c *Collector) now() time.Time {
	if c.Now != nil {
		return c.Now()
	}
	return time.Now()
}

func (c *Collector) loc() *time.Location {
	if c.Loc != nil {
		return c.Loc
	}
	return time.UTC
}

// Snapshot collects players and resource usage at the current time.
func (c *Collector) Snapshot(ctx context.Context) Snapshot {
	e := &errList{}
	s := c.snapshot(ctx, e, c.now())
	s.Errors = e.list
	return s
}

func (c *Collector) snapshot(ctx context.Context, e *errList, at time.Time) Snapshot {
	q := c.Q
	s := Snapshot{At: at}
	if up, ok := c.vec(ctx, e, "backend up", q.Up(q.Backend), at); ok {
		v, _ := promapi.Sum(up)
		s.BackendUp, s.BackendTargets = N(v), N(float64(len(up)))
	}
	if up, ok := c.vec(ctx, e, "bot-play up", q.Up(q.BotPlay), at); ok {
		v, _ := promapi.Sum(up)
		s.BotPlayUp, s.BotPlayTargets = N(v), N(float64(len(up)))
	}
	backendUp := s.BackendUp.OK && s.BackendUp.V > 0

	m, present := c.labelled(ctx, e, "players_in_game", q.PlayersInGame(), "actor", at)
	s.PlayingHuman, s.PlayingBot = pick(m, present, "human"), pick(m, present, "bot")

	m, present = c.labelled(ctx, e, "ws_connections_active", q.Online(), "actor", at)
	present = present || backendUp // the gauge is created on the first connection
	s.OnlineHuman, s.OnlineBot = pick(m, present, "human"), pick(m, present, "bot")

	hosts := map[string]*Host{}
	host := func(inst string) *Host {
		if h, ok := hosts[inst]; ok {
			return h
		}
		h := &Host{Instance: inst}
		hosts[inst] = h
		return h
	}
	if v, ok := c.vec(ctx, e, "host cpu", q.HostCPU(rateWindow), at); ok {
		for _, x := range v {
			if promapi.Valid(x.Value) {
				host(x.Labels["instance"]).CPU = N(clampPct(x.Value))
			}
		}
	}
	if v, ok := c.vec(ctx, e, "host ram", q.HostRAM(), at); ok {
		for _, x := range v {
			if promapi.Valid(x.Value) {
				host(x.Labels["instance"]).RAM = N(clampPct(x.Value))
			}
		}
	}
	if v, ok := c.vec(ctx, e, "host disk", q.HostDisk(), at); ok {
		for _, x := range v {
			if promapi.Valid(x.Value) {
				host(x.Labels["instance"]).Disk = N(clampPct(x.Value))
			}
		}
	}
	for _, k := range promapi.SortedKeys(hosts) {
		s.Hosts = append(s.Hosts, *hosts[k])
	}

	procs := map[string]*Process{}
	proc := func(l map[string]string) *Process {
		key := l["job"] + "\x00" + l["instance"]
		if p, ok := procs[key]; ok {
			return p
		}
		p := &Process{Job: l["job"], Instance: l["instance"]}
		procs[key] = p
		return p
	}
	if v, ok := c.vec(ctx, e, "process rss", q.ProcRSS(), at); ok {
		for _, x := range v {
			if promapi.Valid(x.Value) {
				proc(x.Labels).RSS = N(x.Value)
			}
		}
	}
	if v, ok := c.vec(ctx, e, "process cpu", q.ProcCPU(rateWindow), at); ok {
		for _, x := range v {
			if promapi.Valid(x.Value) {
				proc(x.Labels).CPU = N(math.Max(x.Value, 0))
			}
		}
	}
	for _, k := range promapi.SortedKeys(procs) {
		s.Processes = append(s.Processes, *procs[k])
	}
	return s
}

func clampPct(v float64) float64 { return math.Min(math.Max(v, 0), 100) }

// Status collects the hourly status; withCharts adds the 24-hour series.
func (c *Collector) Status(ctx context.Context, withCharts bool) Status {
	e := &errList{}
	at := c.now()
	q := c.Q
	st := Status{Snapshot: c.snapshot(ctx, e, at)}
	backendUp := st.BackendUp.OK && st.BackendUp.V > 0

	if m, present := c.labelled(ctx, e, "rooms_in_game", q.RoomsByGame(), "game", at); present {
		st.RoomsByGame, st.RoomsOK = kvs(m), true
	}
	m, present := c.labelled(ctx, e, "players_in_lobby", q.Lobby(), "actor", at)
	st.LobbyHuman, st.LobbyBot = pick(m, present, "human"), pick(m, present, "bot")

	m, present = c.labelled(ctx, e, "matches started", q.StartedByMix(time.Hour), "mix", at)
	present = present || backendUp
	st.StartedHumanOnly = round(pick(m, present, "human_only"))
	st.StartedWithBots = round(add(pick(m, present, "mixed"), pick(m, present, "bot_only")))
	st.Finished = round(c.one(ctx, e, "matches finished", q.Completed(time.Hour), at, backendUp))
	st.NewAccounts = round(c.one(ctx, e, "new accounts", q.NewAccounts(time.Hour), at, backendUp))
	st.DAU = round(c.one(ctx, e, "DAU", q.ActiveUsers("day"), at, false))
	st.Firing = c.firing(ctx, e, Firing, at)

	if withCharts {
		st.Charts = c.charts(ctx, e, at.Add(-24*time.Hour), at, 5*time.Minute)
		end := c.hourFloor(at)
		start := end.Add(-23 * time.Hour)
		st.Charts.MatchesByGame = c.series(ctx, e, "matches per hour", q.StartedByGame(time.Hour), start, end, time.Hour)
	}
	st.Errors = e.list
	return st
}

// AlertCharts collects the players/CPU/RAM series for a PDF alert.
func (c *Collector) AlertCharts(ctx context.Context, window time.Duration) (Charts, []string) {
	e := &errList{}
	at := c.now()
	step := window / 60
	if step < 15*time.Second {
		step = 15 * time.Second
	}
	ch := c.charts(ctx, e, at.Add(-window), at, step)
	return ch, e.list
}

func (c *Collector) charts(ctx context.Context, e *errList, start, end time.Time, step time.Duration) Charts {
	q := c.Q
	return Charts{
		Start:   start,
		End:     end,
		Players: c.series(ctx, e, "players chart", q.PlayersInGame(), start, end, step),
		CPU:     c.series(ctx, e, "cpu chart", q.HostCPU(rateWindow*2), start, end, step),
		RAM:     c.series(ctx, e, "ram chart", q.HostRAM(), start, end, step),
	}
}

func (c *Collector) series(ctx context.Context, e *errList, what, expr string, start, end time.Time, step time.Duration) []promapi.Series {
	s, err := c.Prom.QueryRange(ctx, expr, start, end, step)
	if err != nil {
		e.add(what, err)
		return nil
	}
	return s
}

func (c *Collector) hourFloor(t time.Time) time.Time {
	l := t.In(c.loc())
	return time.Date(l.Year(), l.Month(), l.Day(), l.Hour(), 0, 0, 0, c.loc())
}

func (c *Collector) firing(ctx context.Context, e *errList, expr string, at time.Time) []FiringAlert {
	s, _ := c.vec(ctx, e, "alerts", expr, at)
	byName := map[string]*FiringAlert{}
	for _, x := range s {
		name := x.Labels["alertname"]
		a, ok := byName[name]
		if !ok {
			a = &FiringAlert{Name: name, Severity: x.Labels["severity"]}
			byName[name] = a
		}
		a.Count++
		if inst := x.Labels["instance"]; inst != "" {
			a.Instances = append(a.Instances, inst)
		}
		if severityRank(x.Labels["severity"]) > severityRank(a.Severity) {
			a.Severity = x.Labels["severity"]
		}
	}
	out := make([]FiringAlert, 0, len(byName))
	for _, k := range promapi.SortedKeys(byName) {
		a := byName[k]
		sort.Strings(a.Instances)
		out = append(out, *a)
	}
	sort.SliceStable(out, func(i, j int) bool { return severityRank(out[i].Severity) > severityRank(out[j].Severity) })
	return out
}

func severityRank(s string) int {
	switch strings.ToLower(s) {
	case "critical":
		return 3
	case "warning":
		return 2
	case "info":
		return 1
	}
	return 0
}

func round(n Num) Num {
	if n.OK {
		n.V = math.Round(n.V)
	}
	return n
}

// LocalDay returns local midnight of t's calendar day.
func LocalDay(t time.Time, loc *time.Location) time.Time {
	l := t.In(loc)
	return time.Date(l.Year(), l.Month(), l.Day(), 0, 0, 0, 0, loc)
}

// Yesterday returns local midnight of the day before now.
func Yesterday(now time.Time, loc *time.Location) time.Time {
	return LocalDay(now, loc).AddDate(0, 0, -1)
}

// civilDate maps a local midnight to the same calendar date at 00:00 UTC.
func civilDate(t time.Time) time.Time {
	return time.Date(t.Year(), t.Month(), t.Day(), 0, 0, 0, 0, time.UTC)
}

// Digest collects the daily report for the local calendar day containing day.
func (c *Collector) Digest(ctx context.Context, day time.Time, withTrends bool) Digest {
	e := &errList{}
	q := c.Q
	loc := c.loc()
	start := LocalDay(day, loc)
	end := start.AddDate(0, 0, 1)
	now := c.now()
	at := end
	if at.After(now) {
		at = now
	}
	w := end.Sub(start)
	d := Digest{Day: start, End: end}

	seen := c.one(ctx, e, "backend scraped", fmt.Sprintf(`max(max_over_time(%s[%s]))`, q.Up(q.Backend), promDur(w)), at, false)
	backendSeen := seen.OK && seen.V > 0

	m, present := c.labelled(ctx, e, "new accounts", q.NewAccounts(w), "provider", at)
	d.NewAccountsByProvider = kvs(m)
	if present || backendSeen {
		d.NewAccounts = N(sumKV(d.NewAccountsByProvider))
	}
	d.Logins = round(c.one(ctx, e, "logins", q.Logins(w), at, backendSeen))

	dauDate := civilDate(start)
	dauEnd := dauDate.AddDate(0, 0, 1)
	d.DAUDay = dauDate
	dauAt := dauEnd
	if dauAt.After(now) {
		dauAt = now
	}
	d.DAU = round(c.one(ctx, e, "DAU", q.ActiveUsersMax("day", 24*time.Hour-5*time.Minute), dauAt, false))
	d.WAU = round(c.one(ctx, e, "WAU", q.ActiveUsersMax("week", 24*time.Hour-5*time.Minute), dauAt, false))

	started, _ := c.vec(ctx, e, "matches started", q.StartedByGameMode(w), at)
	completed, _ := c.vec(ctx, e, "matches completed", q.CompletedByGameMode(w), at)
	rows := map[string]*GameModeRow{}
	row := func(l map[string]string) *GameModeRow {
		k := l["game"] + "\x00" + l["mode"]
		if r, ok := rows[k]; ok {
			return r
		}
		r := &GameModeRow{Game: l["game"], Mode: l["mode"]}
		rows[k] = r
		return r
	}
	var st, cp float64
	for _, x := range started {
		if promapi.Valid(x.Value) {
			row(x.Labels).Started += math.Round(x.Value)
			st += math.Round(x.Value)
		}
	}
	for _, x := range completed {
		if promapi.Valid(x.Value) {
			row(x.Labels).Completed += math.Round(x.Value)
			cp += math.Round(x.Value)
		}
	}
	for _, k := range promapi.SortedKeys(rows) {
		d.ByGameMode = append(d.ByGameMode, *rows[k])
	}
	if len(started) > 0 || backendSeen {
		d.Started = N(st)
	}
	if len(completed) > 0 || backendSeen {
		d.Completed = N(cp)
	}
	m, present = c.labelled(ctx, e, "matches by mix", q.StartedByMix(w), "mix", at)
	present = present || backendSeen
	d.HumanOnly = round(pick(m, present, "human_only"))
	d.WithBots = round(add(pick(m, present, "mixed"), pick(m, present, "bot_only")))

	m, present = c.labelled(ctx, e, "abandons", q.Abandons(w), "reason", at)
	d.AbandonsByReason = kvs(m)
	if present || backendSeen {
		d.Abandons = N(sumKV(d.AbandonsByReason))
	}
	m, present = c.labelled(ctx, e, "peak players", q.PeakPlaying(w), "actor", at)
	d.PeakHuman, d.PeakBot = pick(m, present, "human"), pick(m, present, "bot")
	m, present = c.labelled(ctx, e, "peak online", q.PeakOnline(w), "actor", at)
	present = present || backendSeen
	d.PeakOnlineHuman, d.PeakOnlineBot = round(pick(m, present, "human")), round(pick(m, present, "bot"))

	d.WaitAvg = c.one(ctx, e, "wait avg", q.WaitAvg(w), at, false)
	d.WaitP95 = c.one(ctx, e, "wait p95", q.WaitP95(w), at, false)
	m, _ = c.labelled(ctx, e, "matchmaking results", q.MatchmakingResults(w), "result", at)
	d.MatchmakingResults = kvs(m)

	m, present = c.labelled(ctx, e, "http", q.HTTPByClass(w), "class", at)
	present = present || backendSeen
	d.HTTP5xx = round(pick(m, present, "5xx"))
	if present {
		d.HTTPTotal = N(math.Round(sumMap(m)))
	}
	m, present = c.labelled(ctx, e, "settlement failures", q.Settlement(w), "op", at)
	d.SettlementByOp = kvs(m)
	if present || backendSeen {
		d.Settlement = N(sumKV(d.SettlementByOp))
	}
	d.ClientErrors = round(c.one(ctx, e, "client errors", q.ClientErrors(w), at, backendSeen))

	hosts := map[string]*Host{}
	for _, p := range []struct {
		expr string
		set  func(h *Host, v float64)
	}{
		{q.PeakHostCPU(w), func(h *Host, v float64) { h.CPU = N(clampPct(v)) }},
		{q.PeakHostRAM(w), func(h *Host, v float64) { h.RAM = N(clampPct(v)) }},
	} {
		v, _ := c.vec(ctx, e, "peak host usage", p.expr, at)
		for _, x := range v {
			if !promapi.Valid(x.Value) {
				continue
			}
			inst := x.Labels["instance"]
			h, ok := hosts[inst]
			if !ok {
				h = &Host{Instance: inst}
				hosts[inst] = h
			}
			p.set(h, x.Value)
		}
	}
	for _, k := range promapi.SortedKeys(hosts) {
		d.PeakHosts = append(d.PeakHosts, *hosts[k])
	}
	d.AlertsFired = c.firing(ctx, e, FiredDuring(w), at)

	days := c.TrendDays
	if days < 2 {
		days = 30
	}
	civil := civilDate(start)
	if c.Play != nil {
		d.Play.Configured = true
		rep, err := c.Play.Installs(ctx, civil, days)
		if err != nil {
			d.Play.Err = err.Error()
		}
		d.Play.Report = rep
	}
	if c.GA4 != nil {
		d.GA4.Configured = true
		sum, err := c.GA4.Summary(ctx, civil, days)
		if err != nil {
			d.GA4.Err = err.Error()
		}
		d.GA4.Summary = sum
	}
	if withTrends {
		d.Trends = c.trends(ctx, e, start, days, dauEnd, now)
	}
	d.Errors = e.list
	return d
}

func (c *Collector) trends(ctx context.Context, e *errList, lastDay time.Time, days int, dauEnd, now time.Time) Trends {
	q := c.Q
	loc := c.loc()
	first := lastDay.AddDate(0, 0, -(days - 1))
	t := Trends{Days: days, From: civilDate(first), To: civilDate(lastDay)}
	// Evaluate at the end of each local day (local midnight), every 24 h.
	start, end := first.AddDate(0, 0, 1), lastDay.AddDate(0, 0, 1)
	if end.After(now) {
		end = now
	}
	label := func(ts time.Time) time.Time { return civilDate(ts.Add(-12 * time.Hour).In(loc)) }
	daily := func(what, expr, key string) []DaySeries {
		return toDaySeries(c.series(ctx, e, what, expr, start, end, 24*time.Hour), key, label)
	}
	t.MatchesByGame = daily("matches per day", q.StartedByGame(24*time.Hour), "game")
	t.PeakPlayers = daily("peak players per day", q.PeakPlaying(24*time.Hour), "actor")
	t.CPUMax = daily("cpu max per day", q.PeakHostCPU(24*time.Hour), "instance")
	t.RAMMax = daily("ram max per day", q.PeakHostRAM(24*time.Hour), "instance")
	// DAU is a per-UTC-day sketch: evaluate at UTC midnights.
	dEnd := dauEnd
	if dEnd.After(now) {
		dEnd = now
	}
	dStart := dauEnd.AddDate(0, 0, -(days - 1))
	utcLabel := func(ts time.Time) time.Time { return civilDate(ts.UTC().Add(-12 * time.Hour)) }
	dau := toDaySeries(c.series(ctx, e, "DAU per day", q.ActiveUsersMax("day", 24*time.Hour-5*time.Minute), dStart, dEnd, 24*time.Hour), "", utcLabel)
	if len(dau) > 0 {
		t.DAU = dau[0].Values
	}
	return t
}

func toDaySeries(series []promapi.Series, key string, label func(time.Time) time.Time) []DaySeries {
	byName := map[string]map[time.Time]float64{}
	for _, s := range series {
		name := s.Labels[key]
		if byName[name] == nil {
			byName[name] = map[time.Time]float64{}
		}
		for _, p := range s.Points {
			if promapi.Valid(p.V) {
				byName[name][label(p.T)] += p.V
			}
		}
	}
	out := make([]DaySeries, 0, len(byName))
	for _, name := range promapi.SortedKeys(byName) {
		ds := DaySeries{Name: name}
		for day, v := range byName[name] {
			ds.Values = append(ds.Values, DayValue{Day: day, V: math.Max(v, 0)})
		}
		sort.Slice(ds.Values, func(i, j int) bool { return ds.Values[i].Day.Before(ds.Values[j].Day) })
		out = append(out, ds)
	}
	return out
}

func sumKV(k []KV) float64 {
	var t float64
	for _, x := range k {
		t += x.V
	}
	return t
}

func sumMap(m map[string]float64) float64 {
	var t float64
	for _, v := range m {
		t += v
	}
	return t
}
