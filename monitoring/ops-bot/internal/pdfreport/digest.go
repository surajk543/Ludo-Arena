package pdfreport

import (
	"fmt"
	"sort"
	"strings"
	"time"

	"ludoarena/opsbot/internal/charts"
	"ludoarena/opsbot/internal/google"
	"ludoarena/opsbot/internal/report"
)

// DigestFileName is the document name of a daily report.
func DigestFileName(day time.Time) string {
	return "ludo-arena-daily-" + day.Format("2006-01-02") + ".pdf"
}

func kvRows(items []report.KV, name func(string) string) [][]string {
	rows := make([][]string, 0, len(items))
	for _, kv := range items {
		rows = append(rows, []string{name(kv.Key), report.Int(kv.V)})
	}
	return rows
}

func kvSub(items []report.KV, name func(string) string) string {
	parts := make([]string, 0, len(items))
	for _, kv := range items {
		parts = append(parts, name(kv.Key)+" "+report.Int(kv.V))
	}
	return strings.Join(parts, " · ")
}

// DigestPDF renders the daily KPI report (2–3 pages).
func DigestPDF(dg report.Digest, m report.Meta, generated time.Time, opt Options) ([]byte, error) {
	loc := m.Loc
	dayStr := report.Date(dg.Day) + " (" + dg.Day.Format("MST") + ")"
	d := newDoc("Ludo Arena — Daily KPI report", m.Env+" · "+dayStr+" · generated "+report.Stamp(generated, loc),
		"Daily KPI report · "+m.Env+" · "+dayStr, colAccent, generated, opt)

	blue, orange, red := colAccent, colOrange, colRed
	settleAccent := (*rgb)(nil)
	if dg.Settlement.OK && dg.Settlement.V > 0 {
		settleAccent = &red
	}
	d.section("The day at a glance")
	d.tiles([]tile{
		{Label: "New accounts", Value: report.I(dg.NewAccounts), Sub: kvSub(dg.NewAccountsByProvider, ident), Accent: &blue},
		{Label: "DAU estimate", Value: report.I(dg.DAU), Sub: "UTC day " + dg.DAUDay.Format("2 Jan")},
		{Label: "WAU estimate", Value: report.I(dg.WAU)},
		{Label: "Sign-ins", Value: report.I(dg.Logins)},
		{Label: "Matches started", Value: report.I(dg.Started), Sub: "finished " + report.I(dg.Completed)},
		{Label: "Human-only matches", Value: report.I(dg.HumanOnly), Sub: strings.TrimPrefix(report.Share(dg.HumanOnly, dg.Started)+" · with bots "+report.I(dg.WithBots), " · ")},
		{Label: "Peak real players in game", Value: report.I(dg.PeakHuman), Sub: "peak online " + report.I(dg.PeakOnlineHuman), Accent: &blue},
		{Label: "Peak bots in game", Value: report.I(dg.PeakBot), Sub: "peak online " + report.I(dg.PeakOnlineBot), Accent: &orange},
		{Label: "Matchmaking wait (avg)", Value: report.Secs(dg.WaitAvg), Sub: "p95 " + report.Secs(dg.WaitP95)},
		{Label: "Abandons", Value: report.I(dg.Abandons), Sub: kvSub(dg.AbandonsByReason, ident)},
		{Label: "HTTP 5xx", Value: report.I(dg.HTTP5xx), Sub: "of " + report.I(dg.HTTPTotal) + " requests"},
		{Label: "Settlement failures", Value: report.I(dg.Settlement), Sub: kvSub(dg.SettlementByOp, ident), Accent: settleAccent},
	})

	d.section("Matches by game and mode")
	if len(dg.ByGameMode) == 0 {
		d.notice("No matches were recorded.")
	} else {
		rows := make([][]string, 0, len(dg.ByGameMode))
		for _, r := range dg.ByGameMode {
			rows = append(rows, []string{report.GameName(r.Game), report.Title(r.Mode), report.Int(r.Started), report.Int(r.Completed)})
		}
		d.table([]column{{"Game", 0.35, "L"}, {"Mode", 0.25, "L"}, {"Started", 0.2, "R"}, {"Finished", 0.2, "R"}}, rows)
	}
	if len(dg.MatchmakingResults) > 0 {
		d.note("Matchmaking outcomes: " + kvSub(dg.MatchmakingResults, ident) + ". Client-reported errors: " + report.I(dg.ClientErrors) + ".")
	}

	d.section("Infrastructure peaks and alerts")
	if len(dg.PeakHosts) > 0 {
		rows := make([][]string, 0, len(dg.PeakHosts))
		for _, h := range dg.PeakHosts {
			rows = append(rows, []string{h.Instance, report.Pct(h.CPU), report.Pct(h.RAM)})
		}
		d.table([]column{{"Host", 0.6, "L"}, {"Peak CPU (5 min)", 0.2, "R"}, {"Peak RAM", 0.2, "R"}}, rows)
	} else {
		d.notice("No host metrics for this day.")
	}
	if len(dg.AlertsFired) == 0 {
		d.note("Alerts fired: none.")
	} else {
		names := make([]string, 0, len(dg.AlertsFired))
		for _, a := range dg.AlertsFired {
			names = append(names, a.Name+" ("+a.Severity+")")
		}
		d.note("Alerts fired: " + strings.Join(names, ", ") + ".")
	}

	// Page 2: store and analytics KPIs.
	d.newPage()
	playSection(d, dg.Play, dg.Trends)
	ga4Section(d, dg.GA4)

	// Page 3: trends.
	d.newPage()
	trendSection(d, dg.Trends, loc)

	footerNotes(d, dg.Errors, "Daily windows are local calendar days ("+dg.Day.Format("MST")+"); DAU/WAU are pseudonymous HyperLogLog estimates per UTC day/week. Load-test matches are excluded from match counts.")
	return d.bytes()
}

func dayLabels(from time.Time, days int) ([]string, map[time.Time]int) {
	cats := make([]string, days)
	idx := map[time.Time]int{}
	for i := 0; i < days; i++ {
		t := from.AddDate(0, 0, i)
		cats[i] = t.Format("2 Jan")
		idx[t] = i
	}
	return cats, idx
}

func playSection(d *doc, p report.PlaySection, t report.Trends) {
	d.section("Google Play installs")
	switch {
	case !p.Configured:
		d.notice("Not configured. Set PLAY_REPORTS_BUCKET (Play Console > Download reports > Statistics > copy the Cloud Storage URI) and grant the service account \"View app information and download bulk reports\".")
		return
	case p.Err != "":
		d.notice("Unavailable: " + p.Err)
		return
	}
	latest, ok := p.Report.Latest()
	if !ok {
		d.notice("No report rows yet. Play Console bulk reports lag 1–2 days and appear once the app has installs.")
		return
	}
	val := func(col string) string {
		if v, ok := latest.Values[col]; ok {
			return report.Int(v)
		}
		return report.NA
	}
	d.note(fmt.Sprintf("Latest available day: %s (Play Console reports lag 1–2 days).", report.Date(latest.Date)))
	d.tiles([]tile{
		{Label: "User installs", Value: val(google.ColDailyUserInstalls)},
		{Label: "User uninstalls", Value: val(google.ColDailyUserUninstalls)},
		{Label: "Device installs", Value: val(google.ColDailyDeviceInstalls), Sub: "uninstalls " + val(google.ColDailyDeviceUninstalls)},
		{Label: "Active device installs", Value: val(google.ColActiveDeviceInstalls), Sub: "total user installs " + val(google.ColTotalUserInstalls)},
	})
	inCol, outCol, unit := google.ColDailyUserInstalls, google.ColDailyUserUninstalls, "users"
	if !has(p.Report.Columns, inCol) {
		inCol, outCol, unit = google.ColDailyDeviceInstalls, google.ColDailyDeviceUninstalls, "devices"
	}
	days := t.Days
	if days < 2 {
		days = 30
	}
	cats, idx := dayLabels(latest.Date.AddDate(0, 0, -(days-1)), days)
	ins := charts.Bars{Name: "Installs", Values: make([]float64, days)}
	outs := charts.Bars{Name: "Uninstalls", Values: make([]float64, days)}
	for _, day := range p.Report.Days {
		if i, ok := idx[day.Date]; ok {
			ins.Values[i] = day.Values[inCol]
			outs.Values[i] = day.Values[outCol]
		}
	}
	png, err := charts.BarChart(charts.BarSpec{
		Title: fmt.Sprintf("Installs vs uninstalls per day (%s, last %d days)", unit, days), YLabel: unit,
		Categories: cats, Series: []charts.Bars{ins, outs}, HeightMM: 58,
	})
	d.chart(png, err, 58, "No install activity in the report window.")
}

func has(list []string, s string) bool {
	for _, x := range list {
		if strings.EqualFold(x, s) {
			return true
		}
	}
	return false
}

func ga4Section(d *doc, g report.GA4Section) {
	d.section("Firebase Analytics (GA4)")
	switch {
	case !g.Configured:
		d.notice("Not configured. Set GA4_PROPERTY_ID and add the service account as a Viewer on the GA4 property.")
		return
	case g.Err != "":
		d.notice("Unavailable: " + g.Err)
		return
	}
	s := g.Summary
	d.note(fmt.Sprintf("%s. GA4 data for the latest day may still be processing (up to 24–48 h).", report.Date(s.Date)))
	d.tiles([]tile{
		{Label: "Installs (first_open)", Value: report.Int(s.Totals.FirstOpens), Sub: "Android + iOS"},
		{Label: "Uninstalls (app_remove)", Value: report.Int(s.Totals.AppRemoves), Sub: "Android only"},
		{Label: "Active users", Value: report.Int(s.Totals.ActiveUsers)},
		{Label: "New users", Value: report.Int(s.Totals.NewUsers)},
	})
	if len(s.Platforms) > 0 {
		rows := make([][]string, 0, len(s.Platforms))
		for _, p := range s.Platforms {
			rows = append(rows, []string{p.Platform, report.Int(p.FirstOpens), report.Int(p.AppRemoves), report.Int(p.ActiveUsers), report.Int(p.NewUsers)})
		}
		d.table([]column{{"Platform", 0.28, "L"}, {"first_open", 0.18, "R"}, {"app_remove", 0.18, "R"}, {"Active users", 0.18, "R"}, {"New users", 0.18, "R"}}, rows)
	}
	if len(s.Daily) > 0 {
		cats := make([]string, len(s.Daily))
		fo := charts.Bars{Name: "first_open", Values: make([]float64, len(s.Daily))}
		ar := charts.Bars{Name: "app_remove", Values: make([]float64, len(s.Daily))}
		for i, day := range s.Daily {
			cats[i] = day.Date.Format("2 Jan")
			fo.Values[i], ar.Values[i] = day.FirstOpens, day.AppRemoves
		}
		png, err := charts.BarChart(charts.BarSpec{
			Title: fmt.Sprintf("first_open vs app_remove per day (last %d days)", len(s.Daily)), YLabel: "events",
			Categories: cats, Series: []charts.Bars{fo, ar}, HeightMM: 58,
		})
		d.chart(png, err, 58, "No first_open or app_remove events in the window.")
	}
}

func trendSection(d *doc, t report.Trends, loc *time.Location) {
	days := t.Days
	if days < 2 {
		d.notice("Trends were not collected.")
		return
	}
	d.section(fmt.Sprintf("Trends: last %d days (%s to %s)", days, t.From.Format("2 Jan"), t.To.Format("2 Jan 2006")))
	cats, idx := dayLabels(t.From, days)
	const h = 52.0

	// DAU per UTC day.
	dau := charts.Bars{Name: "DAU", Values: make([]float64, days)}
	covered := 0
	for _, v := range t.DAU {
		if i, ok := idx[v.Day]; ok {
			dau.Values[i] = v.V
			covered++
		}
	}
	png, err := charts.BarChart(charts.BarSpec{Title: "Daily active users (estimate, UTC days)", YLabel: "users", Categories: cats, Series: []charts.Bars{dau}, HeightMM: h})
	d.chart(png, err, h, "DAU: no active_users_estimate data in Prometheus for this period.")
	if covered > 0 && covered < days {
		d.note(fmt.Sprintf("Prometheus holds DAU data for %d of the %d days (retention or a recent start).", covered, days))
	}

	png, err = charts.BarChart(charts.BarSpec{Title: "Matches started per day by game", YLabel: "matches", Categories: cats,
		Series: daySeriesBars(t.MatchesByGame, idx, days, report.GameName), Stacked: true, HeightMM: h})
	d.chart(png, err, h, "Matches per day: no data in Prometheus for this period.")

	png, err = charts.BarChart(charts.BarSpec{Title: "Peak concurrent players in game per day", YLabel: "players", Categories: cats,
		Series: daySeriesBars(t.PeakPlayers, idx, days, actorName), HeightMM: h})
	d.chart(png, err, h, "Peak players per day: no players_in_game data in Prometheus for this period.")

	var ls []charts.Line
	add := func(series []report.DaySeries, suffix string) {
		for _, s := range series {
			l := charts.Line{Name: s.Name + " " + suffix}
			for _, v := range s.Values {
				// Plot each day at local noon so ticks fall on the right date.
				l.Points = append(l.Points, charts.Point{T: time.Date(v.Day.Year(), v.Day.Month(), v.Day.Day(), 12, 0, 0, 0, loc), V: v.V})
			}
			ls = append(ls, l)
		}
	}
	add(t.CPUMax, "CPU")
	add(t.RAMMax, "RAM")
	start := time.Date(t.From.Year(), t.From.Month(), t.From.Day(), 0, 0, 0, 0, loc)
	end := time.Date(t.To.Year(), t.To.Month(), t.To.Day(), 23, 59, 0, 0, loc)
	png, err = charts.TimeChart(charts.TimeSpec{Title: "Daily peak CPU and RAM per host", YLabel: "%", Percent: true,
		Lines: ls, Loc: loc, Start: start, End: end, Step: 24 * time.Hour, HeightMM: h})
	d.chart(png, err, h, "CPU/RAM per day: no node_exporter data in Prometheus for this period.")
}

func daySeriesBars(series []report.DaySeries, idx map[time.Time]int, days int, name func(string) string) []charts.Bars {
	out := make([]charts.Bars, 0, len(series))
	for _, s := range series {
		b := charts.Bars{Name: name(s.Name), Values: make([]float64, days)}
		for _, v := range s.Values {
			if i, ok := idx[v.Day]; ok {
				b.Values[i] = v.V
			}
		}
		out = append(out, b)
	}
	sort.SliceStable(out, func(i, j int) bool { return seriesOrder(out[i].Name) < seriesOrder(out[j].Name) })
	return out
}
