package pdfreport

import (
	"fmt"
	"sort"
	"strings"
	"time"

	"ludoarena/opsbot/internal/charts"
	"ludoarena/opsbot/internal/promapi"
	"ludoarena/opsbot/internal/report"
)

// StatusFileName is the document name of an hourly status.
func StatusFileName(at time.Time, loc *time.Location) string {
	return "ludo-arena-status-" + at.In(loc).Format("2006-01-02-1504-MST") + ".pdf"
}

// lines converts Prometheus series to chart lines named by a label.
func lines(series []promapi.Series, label string, name func(string) string) []charts.Line {
	out := make([]charts.Line, 0, len(series))
	for _, s := range series {
		l := charts.Line{Name: name(s.Labels[label])}
		for _, p := range s.Points {
			l.Points = append(l.Points, charts.Point{T: p.T, V: p.V})
		}
		out = append(out, l)
	}
	sort.SliceStable(out, func(i, j int) bool { return seriesOrder(out[i].Name) < seriesOrder(out[j].Name) })
	return out
}

// seriesOrder lists real players before bots, then everything by name.
func seriesOrder(name string) string {
	switch name {
	case "Real players":
		return "\x00"
	case "Bots":
		return "\x01"
	}
	return name
}

func actorName(a string) string {
	switch a {
	case "human":
		return "Real players"
	case "bot":
		return "Bots"
	}
	return report.Title(a)
}

func ident(s string) string { return s }

// StatusPDF renders the hourly status report (1–2 pages).
func StatusPDF(s report.Status, m report.Meta, opt Options) ([]byte, error) {
	loc := m.Loc
	stamp := report.Stamp(s.At, loc)
	d := newDoc("Ludo Arena — Hourly status", m.Env+" · "+stamp, "Hourly status · "+m.Env+" · "+stamp, colAccent, s.At, opt)

	roomsSub := ""
	if len(s.RoomsByGame) > 0 {
		parts := make([]string, 0, len(s.RoomsByGame))
		for _, kv := range s.RoomsByGame {
			parts = append(parts, report.GameName(kv.Key)+" "+report.Int(kv.V))
		}
		roomsSub = strings.Join(parts, " · ")
	}
	blue, orange := colAccent, colOrange
	d.section("Right now")
	d.tiles([]tile{
		{Label: "Real players playing", Value: report.I(s.PlayingHuman), Accent: &blue},
		{Label: "Bots playing", Value: report.I(s.PlayingBot), Accent: &orange},
		{Label: "Real players online", Value: report.I(s.OnlineHuman), Sub: "open WebSocket connections"},
		{Label: "Bots online", Value: report.I(s.OnlineBot)},
		{Label: "Rooms in game", Value: report.I(s.RoomsTotal()), Sub: roomsSub},
		{Label: "Waiting in lobby", Value: report.I(s.LobbyHuman), Sub: "real players · bots " + report.I(s.LobbyBot)},
		{Label: "Matches started (1 h)", Value: report.I(s.StartedTotal()),
			Sub: "human-only " + report.I(s.StartedHumanOnly) + " · with bots " + report.I(s.StartedWithBots)},
		{Label: "Matches finished (1 h)", Value: report.I(s.Finished)},
		{Label: "New accounts (1 h)", Value: report.I(s.NewAccounts)},
		{Label: "DAU estimate", Value: report.I(s.DAU), Sub: "UTC day so far"},
		{Label: "Busiest host CPU", Value: report.Pct(s.MaxCPU())},
		{Label: "Fullest host RAM", Value: report.Pct(s.MaxRAM())},
	})

	d.section("Servers")
	serverTables(d, s.Snapshot)

	d.section("Active alerts")
	if len(s.Firing) == 0 {
		d.notice("No alerts are firing.")
	} else {
		rows := make([][]string, 0, len(s.Firing))
		for _, a := range s.Firing {
			rows = append(rows, []string{a.Severity, a.Name, report.Int(float64(a.Count)), strings.Join(a.Instances, ", ")})
		}
		d.table([]column{{"Severity", 0.14, "L"}, {"Alert", 0.36, "L"}, {"Count", 0.1, "R"}, {"Instances", 0.40, "L"}}, rows)
	}

	footerNotes(d, s.Errors, "Players and rooms are cluster-wide gauges; online counts are open WebSocket connections summed over backend instances. Load-test matches are excluded.")

	ch := s.Charts
	d.newPage()
	d.section("Last 24 hours")
	png, err := charts.TimeChart(charts.TimeSpec{
		Title: "Players in game: real players vs bots", YLabel: "players",
		Lines: lines(ch.Players, "actor", actorName), Loc: loc, Start: ch.Start, End: ch.End, Step: 5 * time.Minute,
	})
	d.chart(png, err, chartH, "Players in game: no data yet (players_in_game is not exported by this backend).")
	png, err = charts.TimeChart(charts.TimeSpec{
		Title: "CPU usage per host", YLabel: "CPU %", Percent: true,
		Lines: lines(ch.CPU, "instance", ident), Loc: loc, Start: ch.Start, End: ch.End, Step: 5 * time.Minute,
	})
	d.chart(png, err, chartH, "CPU per host: no node_exporter data.")
	png, err = charts.TimeChart(charts.TimeSpec{
		Title: "RAM usage per host", YLabel: "RAM %", Percent: true,
		Lines: lines(ch.RAM, "instance", ident), Loc: loc, Start: ch.Start, End: ch.End, Step: 5 * time.Minute,
	})
	d.chart(png, err, chartH, "RAM per host: no node_exporter data.")
	png, err = hourlyMatches(ch.MatchesByGame, s.At, loc)
	d.chart(png, err, chartH, "Matches started per hour: no matches in the last 24 hours.")
	return d.bytes()
}

func serverTables(d *doc, s report.Snapshot) {
	if len(s.Hosts) == 0 {
		d.notice("No host metrics (node_exporter not scraped).")
	} else {
		rows := make([][]string, 0, len(s.Hosts))
		for _, h := range s.Hosts {
			rows = append(rows, []string{h.Instance, report.Pct(h.CPU), report.Pct(h.RAM), report.Pct(h.Disk)})
		}
		d.table([]column{{"Host", 0.55, "L"}, {"CPU", 0.15, "R"}, {"RAM", 0.15, "R"}, {"Disk", 0.15, "R"}}, rows)
	}
	if len(s.Processes) > 0 {
		rows := make([][]string, 0, len(s.Processes))
		for _, p := range s.Processes {
			rows = append(rows, []string{p.Job, p.Instance, report.Bytes(p.RSS), report.Pct(p.CPU)})
		}
		d.table([]column{{"Process", 0.2, "L"}, {"Instance", 0.4, "L"}, {"Memory (RSS)", 0.2, "R"}, {"CPU (1 core = 100%)", 0.2, "R"}}, rows)
	}
	d.note(fmt.Sprintf("Scrape targets up: backend %s/%s · bot-play %s/%s.",
		report.I(s.BackendUp), report.I(s.BackendTargets), report.I(s.BotPlayUp), report.I(s.BotPlayTargets)))
}

func hourlyMatches(series []promapi.Series, at time.Time, loc *time.Location) ([]byte, error) {
	l := at.In(loc)
	end := time.Date(l.Year(), l.Month(), l.Day(), l.Hour(), 0, 0, 0, loc)
	cats := make([]string, 24)
	index := map[int64]int{}
	for i := 0; i < 24; i++ {
		t := end.Add(time.Duration(i-23) * time.Hour)
		index[t.Unix()] = i
		cats[i] = t.Add(-time.Hour).Format("15:04")
	}
	var bars []charts.Bars
	for _, s := range series {
		b := charts.Bars{Name: report.GameName(s.Labels["game"]), Values: make([]float64, 24)}
		for _, p := range s.Points {
			if i, ok := index[p.T.Unix()]; ok && promapi.Valid(p.V) {
				b.Values[i] = p.V
			}
		}
		bars = append(bars, b)
	}
	sort.SliceStable(bars, func(i, j int) bool { return bars[i].Name < bars[j].Name })
	return charts.BarChart(charts.BarSpec{
		Title: "Matches started per hour by game (hour starting, " + end.Format("MST") + ")", YLabel: "matches",
		Categories: cats, Series: bars, Stacked: true, HeightMM: chartH,
	})
}

func footerNotes(d *doc, errs []string, explain string) {
	d.ensure(14)
	d.pdf.Ln(2)
	d.note(explain)
	if len(errs) > 0 {
		shown := errs
		if len(shown) > 5 {
			shown = shown[:5]
		}
		d.note("Data gaps: " + strings.Join(shown, "; "))
	}
}
