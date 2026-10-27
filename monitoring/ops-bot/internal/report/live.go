package report

import (
	"context"
	"fmt"
	"strings"
	"time"

	"ludoarena/opsbot/internal/backendapi"
	"ludoarena/opsbot/internal/promapi"
)

// liveStep is the resolution of the /live 24-hour chart and its peak.
const liveStep = time.Minute

// Live is the /live report: the real players online right now (from the
// backend operator API) and the last 24 hours of online players
// (Prometheus). Bots are never included.
type Live struct {
	At, Start, End time.Time
	Step           time.Duration
	Configured     bool   // the backend operator API is configured
	ListErr        string // why the player list is missing
	List           backendapi.Online
	// Real players over the window: open connections, seated in a running
	// game, waiting in a room lobby.
	Online, Playing, Waiting  []promapi.Point
	OnlineStats, PlayingStats SeriesStats
	Errors                    []string
}

// HasList reports whether the per-player list is available.
func (l Live) HasList() bool { return l.Configured && l.ListErr == "" }

// OnlineNow is the number of real players online: the backend's count,
// else the latest Prometheus value.
func (l Live) OnlineNow() Num {
	if l.HasList() {
		return N(float64(l.List.Total))
	}
	return l.OnlineStats.Now
}

// Count is the number of online players with an activity (backend list only).
func (l Live) Count(activity string) Num {
	if !l.HasList() {
		return Num{}
	}
	return N(float64(l.List.Counts[activity]))
}

// PlayingNow is real players in a running game (both games).
func (l Live) PlayingNow() Num {
	if l.HasList() {
		return add(l.Count(backendapi.ActivityLudo), l.Count(backendapi.ActivitySnakes))
	}
	return l.PlayingStats.Now
}

// Live collects the /live report.
func (c *Collector) Live(ctx context.Context) Live {
	e := &errList{}
	at := c.now()
	q := c.Q
	l := Live{At: at, Start: at.Add(-Window), End: at, Step: liveStep}
	l.Online = firstPoints(c.series(ctx, e, "online chart", q.OnlineHumans(), l.Start, at, liveStep))
	l.Playing = firstPoints(c.series(ctx, e, "playing chart", q.PlayingHumans(), l.Start, at, liveStep))
	l.Waiting = firstPoints(c.series(ctx, e, "lobby chart", q.LobbyHumans(), l.Start, at, liveStep))
	l.OnlineStats = StatsOf(l.Online, at, 3*liveStep)
	l.PlayingStats = StatsOf(l.Playing, at, 3*liveStep)
	if c.Backend != nil {
		l.Configured = true
		list, err := c.Backend.Online(ctx, ListLimit)
		if err != nil {
			l.ListErr = err.Error()
		} else {
			l.List = list
		}
	}
	l.Errors = e.list
	return l
}

// peakText is "342 at 21:14" or "n/a".
func peakText(st SeriesStats, loc *time.Location) string {
	if !st.Peak.OK {
		return NA
	}
	return I(st.Peak) + " at " + st.PeakAt.In(loc).Format("15:04")
}

// LiveCaption is the one-line summary sent with the /live PDF.
func LiveCaption(l Live, m Meta) string {
	parts := []string{Esc(m.Env), I(l.OnlineNow()) + " online"}
	if l.HasList() {
		parts = append(parts, "Ludo "+I(l.Count(backendapi.ActivityLudo)), "S&amp;L "+I(l.Count(backendapi.ActivitySnakes)),
			"lobby "+I(add(l.Count(backendapi.ActivityLobby), l.Count(backendapi.ActivityWaiting))))
	} else {
		parts = append(parts, I(l.PlayingNow())+" playing")
	}
	parts = append(parts, "peak "+peakText(l.OnlineStats, m.Loc))
	return strings.Join(parts, " · ")
}

// liveTextRows is the number of players listed by the text fallback.
const liveTextRows = 25

// LiveText renders /live as Telegram HTML (used when the PDF fails).
func LiveText(l Live, m Meta) string {
	var b strings.Builder
	b.WriteString(m.header("live players", l.At) + "\n")
	fmt.Fprintf(&b, "\n<b>Online now:</b> %s real players", I(l.OnlineNow()))
	if l.HasList() {
		fmt.Fprintf(&b, "\nLudo %s · Snakes &amp; Ladders %s · waiting %s · lobby %s",
			I(l.Count(backendapi.ActivityLudo)), I(l.Count(backendapi.ActivitySnakes)),
			I(l.Count(backendapi.ActivityWaiting)), I(l.Count(backendapi.ActivityLobby)))
	} else {
		fmt.Fprintf(&b, "\nIn a game %s", I(l.PlayingNow()))
	}
	fmt.Fprintf(&b, "\n<b>Last 24 h:</b> peak %s · average %s\n", peakText(l.OnlineStats, m.Loc), I(round(l.OnlineStats.Avg)))
	switch {
	case !l.Configured:
		b.WriteString("\n<i>Player list off: set BACKEND_API_URL and BACKEND_ADMIN_KEY.</i>\n")
	case l.ListErr != "":
		b.WriteString("\n<i>Player list unavailable: " + Esc(l.ListErr) + "</i>\n")
	case len(l.List.Users) == 0:
		b.WriteString("\nNo real players online.\n")
	default:
		b.WriteString("\n")
		for i, u := range l.List.Users {
			if i == liveTextRows {
				fmt.Fprintf(&b, "… and %s more\n", Int(float64(l.List.Total-liveTextRows)))
				break
			}
			fmt.Fprintf(&b, "%d. %s <code>%s</code> · %s · joined %s · online %s\n", i+1, Esc(u.Name), Esc(u.UID),
				Esc(ActivityName(u.Activity, u.Game, u.Mode)), JoinedDate(u.CreatedAt, m.Loc), Ago(l.At.Sub(u.OnlineSince)))
		}
	}
	b.WriteString(errorsFooter(l.Errors))
	return b.String()
}
