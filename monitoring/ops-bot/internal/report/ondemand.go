package report

// Shared pieces of the on-demand command reports (/live, /playtime,
// /metrics): the backend operator API source, series statistics and
// display names.

import (
	"context"
	"math"
	"time"

	"ludoarena/opsbot/internal/backendapi"
	"ludoarena/opsbot/internal/promapi"
)

// BackendSource is the backend operator API (implemented by
// *backendapi.Client; nil when BACKEND_API_URL is not set).
type BackendSource interface {
	Online(ctx context.Context, limit int) (backendapi.Online, error)
	Playtime(ctx context.Context, hours, limit int) (backendapi.Playtime, error)
}

// ListLimit is the number of players listed by /live and per game by /playtime.
const ListLimit = 100

// Window is the period of the on-demand reports.
const Window = 24 * time.Hour

// SeriesStats summarises a time series: the latest value, the mean and the
// highest value with its time.
type SeriesStats struct {
	Now, Avg, Peak Num
	PeakAt         time.Time
}

// StatsOf computes SeriesStats over the valid points. Now is the last point
// when it is at most stale old at `at` (a stopped exporter is not "now").
func StatsOf(pts []promapi.Point, at time.Time, stale time.Duration) SeriesStats {
	var st SeriesStats
	var sum float64
	n := 0
	var last promapi.Point
	for _, p := range pts {
		if !promapi.Valid(p.V) {
			continue
		}
		v := math.Max(p.V, 0)
		sum += v
		n++
		if !st.Peak.OK || v > st.Peak.V {
			st.Peak, st.PeakAt = N(v), p.T
		}
		last = promapi.Point{T: p.T, V: v}
	}
	if n == 0 {
		return st
	}
	st.Avg = N(sum / float64(n))
	if at.Sub(last.T) <= stale {
		st.Now = N(last.V)
	}
	return st
}

// firstPoints returns the points of the first series (single-series queries).
func firstPoints(s []promapi.Series) []promapi.Point {
	if len(s) == 0 {
		return nil
	}
	return s[0].Points
}

// ActivityName describes what an online player is doing: "Ludo · Public",
// "Waiting · Snakes & Ladders", "Lobby".
func ActivityName(activity, game, mode string) string {
	withMode := func(s string) string {
		if mode == "" {
			return s
		}
		return s + " · " + Title(mode)
	}
	switch activity {
	case backendapi.ActivityLudo, backendapi.ActivitySnakes:
		return withMode(GameName(activity))
	case backendapi.ActivityWaiting:
		if game == "" {
			return "Waiting"
		}
		return "Waiting · " + GameName(game)
	case backendapi.ActivityLobby:
		return "Lobby"
	}
	return Title(activity)
}

// Minutes formats seconds as whole minutes with thousands separators.
func Minutes(secs int64) string { return Int(math.Round(float64(secs) / 60)) }

// HoursMinutes formats seconds as "3h 05m" (or "42m").
func HoursMinutes(secs int64) string {
	m := int64(math.Round(float64(secs) / 60))
	if m < 60 {
		return Int(float64(m)) + "m"
	}
	return Int(float64(m/60)) + "h " + twoDigits(m%60) + "m"
}

func twoDigits(n int64) string {
	if n < 10 {
		return "0" + Int(float64(n))
	}
	return Int(float64(n))
}

// Count formats a count with its noun: "1 player", "1,204 players".
func Count(n int, noun string) string {
	if n == 1 {
		return "1 " + noun
	}
	return Int(float64(n)) + " " + noun + "s"
}

// JoinedDate formats an account creation time ("2 Oct 2026"), "n/a" when unknown.
func JoinedDate(t *time.Time, loc *time.Location) string {
	if t == nil || t.IsZero() {
		return NA
	}
	return t.In(loc).Format("2 Jan 2006")
}

// NewAccount reports whether the account was created within d before at.
func NewAccount(t *time.Time, at time.Time, d time.Duration) bool {
	return t != nil && !t.IsZero() && at.Sub(*t) < d
}
