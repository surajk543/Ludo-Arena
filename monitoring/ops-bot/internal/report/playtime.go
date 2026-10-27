package report

import (
	"context"
	"fmt"
	"strings"
	"time"

	"ludoarena/opsbot/internal/backendapi"
)

// Games are the games of the playtime report, in display order.
var Games = []string{backendapi.ActivityLudo, backendapi.ActivitySnakes}

// PlayReport is the /playtime report: the real players with the most
// minutes of active play per game over the last 24 hours (backend operator
// API; the daily playtime rules decide what counts).
type PlayReport struct {
	At         time.Time
	Hours      int
	Configured bool
	Err        string
	Data       backendapi.Playtime
}

// OK reports whether the data is available.
func (p PlayReport) OK() bool { return p.Configured && p.Err == "" }

// Game returns one game's play (zero when unavailable).
func (p PlayReport) Game(game string) backendapi.GamePlaytime { return p.Data.Game(game) }

// TotalSeconds is the play of every game.
func (p PlayReport) TotalSeconds() int64 {
	var t int64
	for _, g := range Games {
		t += p.Game(g).Seconds
	}
	return t
}

// Playtime collects the /playtime report.
func (c *Collector) Playtime(ctx context.Context) PlayReport {
	p := PlayReport{At: c.now(), Hours: int(Window / time.Hour)}
	if c.Backend == nil {
		return p
	}
	p.Configured = true
	data, err := c.Backend.Playtime(ctx, p.Hours, ListLimit)
	if err != nil {
		p.Err = err.Error()
		return p
	}
	p.Data = data
	return p
}

// PerPlayer is the mean play per player of a game ("n/a" without players).
func PerPlayer(g backendapi.GamePlaytime) string {
	if g.Players <= 0 {
		return NA
	}
	return HoursMinutes(g.Seconds / int64(g.Players))
}

// PlaytimeCaption is the one-line summary sent with the /playtime PDF.
func PlaytimeCaption(p PlayReport, m Meta) string {
	if !p.OK() {
		return Esc(m.Env) + " · playtime, last 24 h · player data unavailable"
	}
	l, s := p.Game(backendapi.ActivityLudo), p.Game(backendapi.ActivitySnakes)
	return fmt.Sprintf("%s · last 24 h · Ludo %s min (%s) · S&amp;L %s min (%s)",
		Esc(m.Env), Minutes(l.Seconds), Count(l.Players, "player"), Minutes(s.Seconds), Count(s.Players, "player"))
}

// playtimeTextRows is the number of players per game in the text fallback.
const playtimeTextRows = 15

// PlaytimeText renders /playtime as Telegram HTML (used when the PDF fails).
func PlaytimeText(p PlayReport, m Meta) string {
	var b strings.Builder
	b.WriteString(m.header("playtime, last 24 h", p.At) + "\n")
	switch {
	case !p.Configured:
		b.WriteString("\n<i>Playtime needs the backend operator API: set BACKEND_API_URL and BACKEND_ADMIN_KEY.</i>\n")
		return b.String()
	case p.Err != "":
		b.WriteString("\n<i>Playtime unavailable: " + Esc(p.Err) + "</i>\n")
		return b.String()
	}
	for _, game := range Games {
		g := p.Game(game)
		fmt.Fprintf(&b, "\n<b>%s</b> — %s min · %s · %s per player\n",
			Esc(GameName(game)), Minutes(g.Seconds), Count(g.Players, "player"), PerPlayer(g))
		if len(g.Top) == 0 {
			b.WriteString("No play in the last 24 hours.\n")
		}
		for i, u := range g.Top {
			if i == playtimeTextRows {
				break
			}
			fmt.Fprintf(&b, "%d. %s <code>%s</code> · %s min\n", i+1, Esc(u.Name), Esc(u.UID), Minutes(u.Seconds))
		}
	}
	return b.String()
}
