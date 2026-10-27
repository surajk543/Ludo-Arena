package pdfreport

import (
	"context"
	"fmt"
	"slices"
	"time"

	"ludoarena/opsbot/internal/backendapi"
	"ludoarena/opsbot/internal/charts"
	"ludoarena/opsbot/internal/report"
)

// PlaytimeFileName is the document name of a /playtime report.
func PlaytimeFileName(at time.Time, loc *time.Location) string {
	return "ludo-arena-playtime-" + at.In(loc).Format("2006-01-02-1504-MST") + ".pdf"
}

// PlaytimePDF renders the /playtime report: minutes of active play per game
// over the last 24 hours and the top players of each game.
func PlaytimePDF(ctx context.Context, p report.PlayReport, m report.Meta, opt Options) ([]byte, error) {
	loc := m.Loc
	from, to := p.At.Add(-report.Window), p.At
	if p.OK() {
		from, to = p.Data.From, p.Data.To
	}
	span := from.In(loc).Format("2 Jan 15:04") + " – " + to.In(loc).Format("2 Jan 15:04 MST")
	d := newDoc("Ludo Arena — Playtime, last 24 hours", m.Env+" · "+span+" · real players only",
		"Playtime · "+m.Env+" · "+report.Stamp(p.At, loc), colPurple, p.At, opt)
	if !p.OK() {
		d.section("Playtime")
		if !p.Configured {
			d.notice("Playtime per player needs the backend operator API: set BACKEND_API_URL and BACKEND_ADMIN_KEY in the ops bot, and ADMIN_API_KEY_SHA256 on the backend.")
		} else {
			d.notice("Playtime unavailable: " + p.Err)
		}
		return d.bytes()
	}

	ludo, snakes := p.Game(backendapi.ActivityLudo), p.Game(backendapi.ActivitySnakes)
	purple, cyan, green := colPurple, colCyan, colGreen
	d.section("Summary")
	d.tiles([]tile{
		{Label: "Ludo minutes", Value: report.Minutes(ludo.Seconds), Sub: report.Int(float64(ludo.Players)) + " players", Accent: &purple},
		{Label: "Snakes & Ladders minutes", Value: report.Minutes(snakes.Seconds), Sub: report.Int(float64(snakes.Players)) + " players", Accent: &cyan},
		{Label: "Total minutes played", Value: report.Minutes(p.TotalSeconds()), Sub: "both games", Accent: &green},
		{Label: "Total play time", Value: report.HoursMinutes(p.TotalSeconds()), Sub: "hours of active play"},
		{Label: "Per Ludo player", Value: report.PerPlayer(ludo), Sub: "average"},
		{Label: "Per Snakes & Ladders player", Value: report.PerPlayer(snakes), Sub: "average"},
		topTile("Top Ludo player", ludo),
		topTile("Top Snakes & Ladders player", snakes),
	})
	d.splitBar("Share of minutes played", []share{
		{"Ludo", float64(ludo.Seconds), colPurple}, {"Snakes & Ladders", float64(snakes.Seconds), colCyan},
	}, func(v float64) string { return minutesOf(v) + " min" })
	if err := ctx.Err(); err != nil {
		return nil, ctxDone(err)
	}

	d.ensure(66 + 16)
	d.section("Minutes played per hour")
	png, err := hourlyPlay(p, loc)
	d.chart(png, err, 66, "No play in the last 24 hours.")
	if err := ctx.Err(); err != nil {
		return nil, ctxDone(err)
	}

	for i, g := range []backendapi.GamePlaytime{ludo, snakes} {
		if i == 0 {
			d.ensure(60) // the first table starts below the chart when there is room
		} else {
			d.newPage()
		}
		d.section(fmt.Sprintf("Top %d — %s", report.ListLimit, report.GameName(g.Game)))
		if len(g.Top) == 0 {
			d.notice("Nobody played " + report.GameName(g.Game) + " in the last 24 hours.")
			continue
		}
		best := g.Top[0].Seconds
		rows := make([][]cell, 0, len(g.Top))
		for i, u := range g.Top {
			frac := 0.0
			if best > 0 {
				frac = float64(u.Seconds) / float64(best)
			}
			share := ""
			if g.Seconds > 0 {
				share = fmt.Sprintf("%.1f%%", 100*float64(u.Seconds)/float64(g.Seconds))
			}
			rows = append(rows, []cell{rankCell(i + 1), plain(u.UID), plain(PDFName(u.Name)),
				plain(report.JoinedDate(u.CreatedAt, loc)), {Text: report.Minutes(u.Seconds), Bold: i < 3},
				plain(report.HoursMinutes(u.Seconds)), barCell(frac, share)})
		}
		d.richTable([]column{{"#", 0.06, "C"}, {"User ID", 0.16, "L"}, {"Name", 0.22, "L"}, {"Joined", 0.14, "L"},
			{"Minutes", 0.1, "R"}, {"Time", 0.1, "R"}, {"Share of " + shortGame(g.Game) + " (bar vs #1)", 0.22, "L"}}, rows, gameColor(g.Game))
		if g.Players > len(g.Top) {
			d.note(fmt.Sprintf("%s more players played %s.", report.Int(float64(g.Players-len(g.Top))), report.GameName(g.Game)))
		}
		if err := ctx.Err(); err != nil {
			return nil, ctxDone(err)
		}
	}
	footerNotes(d, nil, "Active play of real players, counted by the server with the daily playtime rules: seated in a running match "+
		"with the app in the foreground and not idle (missing turns). Lobby, matchmaking, bots and load tests never count. "+
		"Minutes are summed in hourly buckets; the oldest hour is pro-rated to the 24-hour window.")
	return d.bytes()
}

func shortGame(game string) string {
	if game == backendapi.ActivitySnakes {
		return "S&L"
	}
	return report.GameName(game)
}

func topTile(label string, g backendapi.GamePlaytime) tile {
	if len(g.Top) == 0 {
		return tile{Label: label, Value: report.NA, Sub: "no play"}
	}
	u := g.Top[0]
	return tile{Label: label, Value: report.Minutes(u.Seconds) + " min", Sub: PDFName(u.Name) + " · " + u.UID}
}

// hourlyPlay is minutes per hour stacked by game (hour starting, local time).
func hourlyPlay(p report.PlayReport, loc *time.Location) ([]byte, error) {
	idx := map[int64]int{}
	var cats []string
	for _, game := range report.Games {
		for _, h := range p.Game(game).Hourly {
			if _, ok := idx[h.Hour.Unix()]; !ok {
				idx[h.Hour.Unix()] = 0
			}
		}
	}
	hours := make([]int64, 0, len(idx))
	for h := range idx {
		hours = append(hours, h)
	}
	slices.Sort(hours)
	for i, h := range hours {
		idx[h] = i
		cats = append(cats, time.Unix(h, 0).In(loc).Format("15:04"))
	}
	var bars []charts.Bars
	for _, game := range report.Games {
		b := charts.Bars{Name: report.GameName(game), Values: make([]float64, len(hours))}
		for _, h := range p.Game(game).Hourly {
			b.Values[idx[h.Hour.Unix()]] = float64(h.Seconds) / 60
		}
		bars = append(bars, b)
	}
	return charts.BarChart(charts.BarSpec{
		Title: "Minutes of active play per hour by game (hour starting, " + p.At.In(loc).Format("MST") + ")", YLabel: "minutes",
		Categories: cats, Series: bars, Stacked: true, HeightMM: 66,
	})
}
