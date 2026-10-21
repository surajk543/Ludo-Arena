package pdfreport

import (
	"strings"
	"time"

	"ludoroyale/opsbot/internal/alertmanager"
	"ludoroyale/opsbot/internal/charts"
	"ludoroyale/opsbot/internal/report"
)

// AlertFileName is the document name of a PDF alert.
func AlertFileName(alerts []alertmanager.Alert, at time.Time, loc *time.Location) string {
	name := "alerts"
	if len(alerts) > 0 {
		name = safeName(alerts[0].Name())
	}
	return "ludo-royale-alert-" + name + "-" + at.In(loc).Format("2006-01-02-1504-MST") + ".pdf"
}

func safeName(s string) string {
	var b strings.Builder
	for _, r := range s {
		switch {
		case r >= 'a' && r <= 'z', r >= 'A' && r <= 'Z', r >= '0' && r <= '9', r == '-', r == '_':
			b.WriteRune(r)
		}
	}
	if b.Len() == 0 {
		return "alert"
	}
	return b.String()
}

// AlertPDF renders a one-page alert report: the alerts, the current
// snapshot and the players/CPU/RAM charts for the last window.
func AlertPDF(alerts []alertmanager.Alert, snap report.Snapshot, ch report.Charts, m report.Meta, now time.Time, opt Options) ([]byte, error) {
	loc := m.Loc
	accent, state := colGreen, "RESOLVED"
	for _, a := range alerts {
		if a.Firing() {
			state = "FIRING"
			accent = colOrange
			if a.Severity() == "critical" {
				accent = colRed
				break
			}
		}
	}
	title := "Ludo Royale — Alert " + state
	if len(alerts) > 0 {
		title += ": " + alerts[0].Name()
		if len(alerts) > 1 {
			title += " (+" + report.Int(float64(len(alerts)-1)) + ")"
		}
	}
	stamp := report.Stamp(now, loc)
	d := newDoc(title, m.Env+" · "+stamp, "Alert · "+m.Env+" · "+stamp, accent, now, opt)

	d.section("Alerts")
	rows := make([][]string, 0, len(alerts))
	for i, a := range alerts {
		if i == report.MaxAlertsPerMessage {
			break
		}
		when := ""
		if !a.StartsAt.IsZero() {
			if a.Firing() {
				when = report.Clock(a.StartsAt, loc) + " (" + report.Ago(now.Sub(a.StartsAt)) + ")"
			} else if a.EndsAt.After(a.StartsAt) {
				when = "lasted " + report.Ago(a.EndsAt.Sub(a.StartsAt))
			}
		}
		status := "firing"
		if !a.Firing() {
			status = "resolved"
		}
		rows = append(rows, []string{status, a.Severity(), a.Name(), a.Instance(), when})
	}
	d.table([]column{{"Status", 0.12, "L"}, {"Severity", 0.12, "L"}, {"Alert", 0.30, "L"}, {"Instance", 0.24, "L"}, {"Since", 0.22, "L"}}, rows)
	for i, a := range alerts {
		if i == 3 {
			break
		}
		text := a.Summary()
		if desc := a.Description(); desc != "" {
			text += " — " + desc
		}
		d.note(a.Name() + ": " + text)
	}

	blue, orange := colAccent, colOrange
	d.section("Now")
	d.tiles([]tile{
		{Label: "Busiest host CPU", Value: report.Pct(snap.MaxCPU())},
		{Label: "Fullest host RAM", Value: report.Pct(snap.MaxRAM())},
		{Label: "Real players playing", Value: report.I(snap.PlayingHuman), Sub: "online " + report.I(snap.OnlineHuman), Accent: &blue},
		{Label: "Bots playing", Value: report.I(snap.PlayingBot), Sub: "online " + report.I(snap.OnlineBot), Accent: &orange},
	})

	window := ch.End.Sub(ch.Start)
	d.section(windowLabel(window))
	const h = 50.0
	step := window / 60
	png, err := charts.TimeChart(charts.TimeSpec{Title: "Players in game", YLabel: "players", Lines: lines(ch.Players, "actor", actorName),
		Loc: loc, Start: ch.Start, End: ch.End, Step: step, HeightMM: h})
	d.chart(png, err, h, "Players in game: no data.")
	cpu, cerr := charts.TimeChart(charts.TimeSpec{Title: "CPU usage per host", YLabel: "CPU %", Percent: true, Lines: lines(ch.CPU, "instance", ident),
		Loc: loc, Start: ch.Start, End: ch.End, Step: step, WidthMM: halfW, HeightMM: h})
	ram, rerr := charts.TimeChart(charts.TimeSpec{Title: "RAM usage per host", YLabel: "RAM %", Percent: true, Lines: lines(ch.RAM, "instance", ident),
		Loc: loc, Start: ch.Start, End: ch.End, Step: step, WidthMM: halfW, HeightMM: h})
	d.chartPair(cpu, ram, cerr, rerr, h, "CPU per host: no node_exporter data.", "RAM per host: no node_exporter data.")
	return d.bytes()
}

func windowLabel(d time.Duration) string {
	switch {
	case d <= 0:
		return "Recent history"
	case d == time.Hour:
		return "Last hour"
	case d%time.Hour == 0:
		return "Last " + report.Int(float64(d/time.Hour)) + " hours"
	}
	return "Last " + report.Ago(d)
}
