package pdfreport

import (
	"context"
	"time"

	"ludoarena/opsbot/internal/backendapi"
	"ludoarena/opsbot/internal/charts"
	"ludoarena/opsbot/internal/promapi"
	"ludoarena/opsbot/internal/report"
)

// liveChartH is the height of the /live chart (mm).
const liveChartH = 82.0

// LiveFileName is the document name of a /live report.
func LiveFileName(at time.Time, loc *time.Location) string {
	return "ludo-arena-live-" + at.In(loc).Format("2006-01-02-1504-MST") + ".pdf"
}

func toChart(pts []promapi.Point) []charts.Point {
	out := make([]charts.Point, 0, len(pts))
	for _, p := range pts {
		out = append(out, charts.Point{T: p.T, V: p.V})
	}
	return out
}

// peakMark labels a series' peak on its chart ("peak 342 · 21:14").
func peakMark(st report.SeriesStats, loc *time.Location, value string) []charts.Mark {
	if !st.Peak.OK {
		return nil
	}
	return []charts.Mark{{T: st.PeakAt, V: st.Peak.V, Label: "peak " + value + " · " + st.PeakAt.In(loc).Format("15:04")}}
}

// peakSub is a tile subtitle "at 21:14" ("" without a peak).
func peakSub(st report.SeriesStats, loc *time.Location) string {
	if !st.Peak.OK {
		return ""
	}
	return "at " + st.PeakAt.In(loc).Format("15:04")
}

// LivePDF renders the /live report: real players online now, the last 24
// hours and the list of online players (bots are never included). ctx is
// checked between sections so a cancelled report stops early.
func LivePDF(ctx context.Context, l report.Live, m report.Meta, opt Options) ([]byte, error) {
	loc := m.Loc
	stamp := report.Stamp(l.At, loc)
	d := newDoc("Ludo Arena — Live players", m.Env+" · "+stamp+" · real players only, bots excluded",
		"Live players · "+m.Env+" · "+stamp, colGreen, l.At, opt)

	ludo, snakes := l.Count(backendapi.ActivityLudo), l.Count(backendapi.ActivitySnakes)
	waiting, lobby := l.Count(backendapi.ActivityWaiting), l.Count(backendapi.ActivityLobby)
	green, purple, cyan, amber := colGreen, colPurple, colCyan, colAmber
	d.section("Right now")
	items := []tile{{Label: "Real players online", Value: report.I(l.OnlineNow()), Sub: "open app connections", Accent: &green}}
	if l.HasList() {
		items = append(items,
			tile{Label: "Playing Ludo", Value: report.I(ludo), Sub: ofTotal(ludo, l.OnlineNow(), "online"), Accent: &purple},
			tile{Label: "Playing Snakes & Ladders", Value: report.I(snakes), Sub: ofTotal(snakes, l.OnlineNow(), "online"), Accent: &cyan},
			tile{Label: "In the lobby", Value: report.I(lobbyTotal(waiting, lobby)), Sub: "waiting for a match " + report.I(waiting), Accent: &amber})
	} else {
		items = append(items,
			tile{Label: "In a game", Value: report.I(l.PlayingNow()), Sub: "both games", Accent: &purple},
			tile{Label: "Waiting in room lobbies", Value: report.I(lastValue(l.Waiting, l.At)), Accent: &amber},
			tile{Label: "Player list", Value: "off", Sub: listState(l)})
	}
	items = append(items,
		tile{Label: "Peak online (24 h)", Value: report.I(l.OnlineStats.Peak), Sub: peakSub(l.OnlineStats, loc)},
		tile{Label: "Average online (24 h)", Value: report.I(roundNum(l.OnlineStats.Avg))},
		tile{Label: "Peak in a game (24 h)", Value: report.I(l.PlayingStats.Peak), Sub: peakSub(l.PlayingStats, loc)})
	if l.HasList() {
		items = append(items, tile{Label: "New players online", Value: report.Int(float64(newOnline(l))),
			Sub: "joined in the last 24 h (listed)"})
	} else {
		items = append(items, tile{Label: "Real players in game now", Value: report.I(l.PlayingStats.Now)})
	}
	d.tiles(items)
	if l.HasList() {
		d.splitBar("What real players are doing", []share{
			{"Ludo", ludo.V, colPurple}, {"Snakes & Ladders", snakes.V, colCyan},
			{"Waiting for a match", waiting.V, colAmber}, {"Lobby", lobby.V, colSlate},
		}, report.Int)
	}
	if err := ctx.Err(); err != nil {
		return nil, ctxDone(err)
	}

	d.ensure(liveChartH + 16)
	d.section("Last 24 hours")
	png, err := charts.TimeChart(charts.TimeSpec{
		Title: "Real players online (bots excluded)", YLabel: "players", Area: true,
		Lines: []charts.Line{
			{Name: "Online", Points: toChart(l.Online)},
			{Name: "In a game", Points: toChart(l.Playing)},
			{Name: "Waiting in room lobbies", Points: toChart(l.Waiting)},
		},
		Marks: peakMark(l.OnlineStats, loc, report.I(l.OnlineStats.Peak)),
		Loc:   loc, Start: l.Start, End: l.End, Step: l.Step, HeightMM: liveChartH,
	})
	d.chart(png, err, liveChartH, "Online players: no data in the last 24 hours (ws_connections_active{actor=\"human\"}).")
	if err := ctx.Err(); err != nil {
		return nil, ctxDone(err)
	}

	d.ensure(60) // the list starts below the chart when there is room
	d.section(listTitle(l))
	switch {
	case !l.Configured:
		d.notice("The player list needs the backend operator API: set BACKEND_API_URL and BACKEND_ADMIN_KEY in the ops bot, and ADMIN_API_KEY_SHA256 on the backend.")
	case l.ListErr != "":
		d.notice("Player list unavailable: " + l.ListErr)
	case len(l.List.Users) == 0:
		d.notice("No real players are online.")
	default:
		rows := make([][]cell, 0, len(l.List.Users))
		for i, u := range l.List.Users {
			joined := plain(report.JoinedDate(u.CreatedAt, loc))
			if report.NewAccount(u.CreatedAt, l.At, report.Window) {
				joined = cell{Text: joined.Text + " · new", Color: &green, Bold: true}
			}
			act := cell{Text: report.ActivityName(u.Activity, u.Game, u.Mode)}
			switch u.Activity {
			case backendapi.ActivityLudo, backendapi.ActivitySnakes:
				c := gameColor(u.Activity)
				act.Color, act.Bold = &c, true
			case backendapi.ActivityWaiting:
				act.Color = &amber
			}
			rows = append(rows, []cell{plain(report.Int(float64(i + 1))), plain(u.UID), plain(PDFName(u.Name)), joined, act,
				plain(report.Ago(l.At.Sub(u.OnlineSince)))})
		}
		d.richTable([]column{{"#", 0.06, "C"}, {"User ID", 0.16, "L"}, {"Name", 0.22, "L"}, {"Joined", 0.16, "L"},
			{"Playing", 0.29, "L"}, {"Online for", 0.11, "R"}}, rows, colGreen)
	}
	footerNotes(d, l.Errors, "Real players only: bots and load tests are never listed or counted. Online = an open app connection. "+
		"Playing = seated in a running match; waiting = in a room that has not started; lobby = online outside a room. "+
		"The list shows players in a match first, then the longest online. Names in scripts the PDF font cannot draw are labelled; the user id is exact.")
	return d.bytes()
}

// ofTotal is "31% of online" ("" when undefined).
func ofTotal(part, total report.Num, what string) string {
	if s := report.Share(part, total); s != "" {
		return s + " of " + what
	}
	return ""
}

func lobbyTotal(waiting, lobby report.Num) report.Num {
	if !waiting.OK || !lobby.OK {
		return report.Num{}
	}
	return report.N(waiting.V + lobby.V)
}

func roundNum(n report.Num) report.Num {
	if !n.OK {
		return n
	}
	return report.N(float64(int64(n.V + 0.5)))
}

func lastValue(pts []promapi.Point, now time.Time) report.Num {
	for i := len(pts) - 1; i >= 0; i-- {
		if promapi.Valid(pts[i].V) && now.Sub(pts[i].T) <= 3*time.Minute {
			return report.N(pts[i].V)
		}
	}
	return report.Num{}
}

func listState(l report.Live) string {
	if !l.Configured {
		return "set BACKEND_API_URL"
	}
	return "backend unavailable"
}

func listTitle(l report.Live) string {
	if !l.HasList() || l.List.Total <= len(l.List.Users) {
		return "Online players"
	}
	return "Online players — first " + report.Int(float64(len(l.List.Users))) + " of " + report.Int(float64(l.List.Total))
}

// newOnline counts listed players whose account is less than a day old.
func newOnline(l report.Live) int {
	n := 0
	for _, u := range l.List.Users {
		if report.NewAccount(u.CreatedAt, l.At, report.Window) {
			n++
		}
	}
	return n
}
