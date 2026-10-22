package progression

import (
	"bytes"
	"crypto/sha256"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"sort"
	"time"

	"ludoarena/internal/gameevents"
)

// Mission metrics.
const (
	MetricComplete = "complete" // an eligible completed match
	MetricWin      = "win"      // an eligible completed match the player won
)

// Period kinds (metric label values).
const (
	PeriodDaily  = "daily"
	PeriodWeekly = "weekly"
	PeriodEvent  = "event"
)

// maxEventLength bounds an event window so its claims are never purged while
// the event is still running (claims/progress are retained 60 days).
const maxEventLength = 56 * 24 * time.Hour

// Reward is what claiming a mission grants.
type Reward struct {
	Coins    int64    `json:"coins"`
	Diamonds int64    `json:"diamonds"`
	XP       int64    `json:"xp"`
	Items    []string `json:"items"`
}

// Filter restricts which matches count for a mission. Empty fields match all.
type Filter struct {
	Game       string `json:"game"`       // ludo | snakes_ladders
	Variant    string `json:"variant"`    // classic | quick
	Mode       string `json:"mode"`       // public | private | practice
	WithFriend bool   `json:"withFriend"` // another human participant is an accepted friend
}

// MissionDef is one configured mission.
type MissionDef struct {
	ID          string `json:"id"`
	Title       string `json:"title"`
	Description string `json:"description"`
	Metric      string `json:"metric"`
	Filter      Filter `json:"filter"`
	Target      int    `json:"target"`
	Reward      Reward `json:"reward"`
}

// GameLabel is the API `game` field: any | ludo | snakes_ladders.
func (m *MissionDef) GameLabel() string {
	if m.Filter.Game == "" {
		return "any"
	}
	return m.Filter.Game
}

// counts reports whether an eligible match counts toward the mission.
func (m *MissionDef) counts(rec *gameevents.MatchRecord, p *gameevents.Participant, withFriend bool) bool {
	f := m.Filter
	switch {
	case f.Game != "" && f.Game != rec.Game,
		f.Variant != "" && f.Variant != rec.Variant,
		f.Mode != "" && f.Mode != rec.Mode,
		f.WithFriend && !withFriend,
		m.Metric == MetricWin && !p.Won:
		return false
	}
	return true
}

// EventDef is a time-boxed set of missions.
type EventDef struct {
	ID          string        `json:"id"`
	Title       string        `json:"title"`
	Description string        `json:"description"`
	StartsAt    time.Time     `json:"startsAtUtc"`
	EndsAt      time.Time     `json:"endsAtUtc"`
	Missions    []*MissionDef `json:"missions"`
}

// MissionConfig is the validated missions/events configuration.
type MissionConfig struct {
	Version    int           `json:"version"`
	DailyCount int           `json:"dailyCount"`
	Daily      []*MissionDef `json:"daily"`
	Weekly     []*MissionDef `json:"weekly"`
	Events     []*EventDef   `json:"events"`
}

// LoadMissions reads and validates a missions file against the catalog.
func LoadMissions(path string, cat *Catalog) (*MissionConfig, error) {
	raw, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("read missions: %w", err)
	}
	return ParseMissions(raw, cat)
}

// ParseMissions validates missions JSON against the catalog.
func ParseMissions(raw []byte, cat *Catalog) (*MissionConfig, error) {
	var c MissionConfig
	dec := json.NewDecoder(bytes.NewReader(raw))
	dec.DisallowUnknownFields()
	if err := dec.Decode(&c); err != nil {
		return nil, fmt.Errorf("parse missions: %w", err)
	}
	var errs []error
	bad := func(format string, args ...any) { errs = append(errs, fmt.Errorf(format, args...)) }
	seen := map[string]bool{}
	check := func(where string, m *MissionDef, event string) {
		if m == nil {
			bad("%s: null mission", where)
			return
		}
		if !idPattern.MatchString(m.ID) {
			bad("%s: invalid mission id %q", where, m.ID)
		}
		if seen[m.ID] {
			bad("%s: duplicate mission id %q", where, m.ID)
		}
		seen[m.ID] = true
		if m.Title == "" || m.Description == "" {
			bad("mission %s: title and description are required", m.ID)
		}
		if m.Metric != MetricComplete && m.Metric != MetricWin {
			bad("mission %s: metric must be complete or win", m.ID)
		}
		if m.Target < 1 || m.Target > 1000 {
			bad("mission %s: target must be 1..1000", m.ID)
		}
		switch m.Filter.Game {
		case "", "ludo", "snakes_ladders":
		default:
			bad("mission %s: invalid filter.game %q", m.ID, m.Filter.Game)
		}
		switch m.Filter.Variant {
		case "", "classic", "quick":
		default:
			bad("mission %s: invalid filter.variant %q", m.ID, m.Filter.Variant)
		}
		switch m.Filter.Mode {
		case "", "public", "private", "practice":
		default:
			bad("mission %s: invalid filter.mode %q", m.ID, m.Filter.Mode)
		}
		r := m.Reward
		if r.Coins < 0 || r.Diamonds < 0 || r.XP < 0 || r.Coins > 1_000_000 || r.Diamonds > 1000 || r.XP > 10_000 {
			bad("mission %s: reward amounts out of range", m.ID)
		}
		for _, id := range r.Items {
			it := cat.Get(id)
			switch {
			case it == nil:
				bad("mission %s: unknown reward item %q", m.ID, id)
			case event != "" && !(it.Acquisition.Type == AcqEvent && it.Acquisition.Event == event):
				bad("mission %s: reward item %s must have acquisition event %s", m.ID, id, event)
			case event == "" && !(it.Acquisition.Type == AcqMission && it.Acquisition.Mission == m.ID):
				bad("mission %s: reward item %s must have acquisition mission %s", m.ID, id, m.ID)
			}
		}
	}
	for i, m := range c.Daily {
		check(fmt.Sprintf("daily[%d]", i), m, "")
	}
	for i, m := range c.Weekly {
		check(fmt.Sprintf("weekly[%d]", i), m, "")
	}
	if c.DailyCount < 1 || c.DailyCount > len(c.Daily) {
		bad("dailyCount must be between 1 and the number of daily missions")
	}
	if len(c.Weekly) == 0 {
		bad("at least one weekly mission is required")
	}
	eventIDs := map[string]bool{}
	for i, e := range c.Events {
		if e == nil {
			bad("events[%d]: null event", i)
			continue
		}
		if !idPattern.MatchString(e.ID) || eventIDs[e.ID] {
			bad("events[%d]: invalid or duplicate id %q", i, e.ID)
		}
		eventIDs[e.ID] = true
		if e.Title == "" {
			bad("event %s: title is required", e.ID)
		}
		if e.StartsAt.IsZero() || !e.EndsAt.After(e.StartsAt) || e.EndsAt.Sub(e.StartsAt) > maxEventLength {
			bad("event %s: endsAtUtc must be after startsAtUtc and at most %d days later", e.ID, int(maxEventLength.Hours()/24))
		}
		e.StartsAt, e.EndsAt = e.StartsAt.UTC(), e.EndsAt.UTC()
		if len(e.Missions) == 0 {
			bad("event %s: needs at least one mission", e.ID)
		}
		for j, m := range e.Missions {
			check(fmt.Sprintf("event %s missions[%d]", e.ID, j), m, e.ID)
		}
	}
	if len(errs) > 0 {
		return nil, errors.Join(errs...)
	}
	return &c, nil
}

// Period is one active mission period.
type Period struct {
	Kind     string // daily | weekly | event
	Key      string // d2026-10-21 | w2026-W43 | e-autumn_cup
	StartsAt time.Time
	ResetsAt time.Time // end of the period (exclusive)
	Event    *EventDef // event periods only
	Missions []*MissionDef
}

// Mission returns the period's mission with id, or nil.
func (p *Period) Mission(id string) *MissionDef {
	for _, m := range p.Missions {
		if m.ID == id {
			return m
		}
	}
	return nil
}

// DayStart returns 00:00 UTC of t's day.
func DayStart(t time.Time) time.Time {
	t = t.UTC()
	return time.Date(t.Year(), t.Month(), t.Day(), 0, 0, 0, 0, time.UTC)
}

// WeekStart returns Monday 00:00 UTC of t's ISO week.
func WeekStart(t time.Time) time.Time {
	d := DayStart(t)
	return d.AddDate(0, 0, -((int(d.Weekday()) + 6) % 7))
}

// DayKey is the daily period key, e.g. d2026-10-21.
func DayKey(t time.Time) string { return "d" + t.UTC().Format("2006-01-02") }

// WeekKey is the ISO-week period key, e.g. w2026-W43 (weeks start Monday 00:00 UTC).
func WeekKey(t time.Time) string {
	y, w := t.UTC().ISOWeek()
	return fmt.Sprintf("w%04d-W%02d", y, w)
}

// EventKey is an event's period key, e.g. e-autumn_cup.
func EventKey(eventID string) string { return "e-" + eventID }

// DailySelection returns the daily missions for a UTC day: DailyCount
// missions picked deterministically from the pool by hashing the day key, in
// pool order. Every player gets the same set.
func (c *MissionConfig) DailySelection(dayKey string) []*MissionDef {
	type ranked struct {
		idx  int
		hash [32]byte
	}
	rs := make([]ranked, len(c.Daily))
	for i, m := range c.Daily {
		rs[i] = ranked{idx: i, hash: sha256.Sum256([]byte(dayKey + "|" + m.ID))}
	}
	sort.Slice(rs, func(a, b int) bool { return bytes.Compare(rs[a].hash[:], rs[b].hash[:]) < 0 })
	rs = rs[:c.DailyCount]
	sort.Slice(rs, func(a, b int) bool { return rs[a].idx < rs[b].idx })
	out := make([]*MissionDef, len(rs))
	for i, r := range rs {
		out[i] = c.Daily[r.idx]
	}
	return out
}

// ActivePeriods returns the daily, weekly and running event periods at t.
func (c *MissionConfig) ActivePeriods(t time.Time) []*Period {
	t = t.UTC()
	day, week := DayStart(t), WeekStart(t)
	out := []*Period{
		{Kind: PeriodDaily, Key: DayKey(t), StartsAt: day, ResetsAt: day.AddDate(0, 0, 1), Missions: c.DailySelection(DayKey(t))},
		{Kind: PeriodWeekly, Key: WeekKey(t), StartsAt: week, ResetsAt: week.AddDate(0, 0, 7), Missions: c.Weekly},
	}
	for _, e := range c.Events {
		if !t.Before(e.StartsAt) && t.Before(e.EndsAt) {
			out = append(out, &Period{Kind: PeriodEvent, Key: EventKey(e.ID), StartsAt: e.StartsAt, ResetsAt: e.EndsAt,
				Event: e, Missions: e.Missions})
		}
	}
	return out
}

// periodByKey finds an active period at t by key.
func (c *MissionConfig) periodByKey(t time.Time, key string) *Period {
	for _, p := range c.ActivePeriods(t) {
		if p.Key == key {
			return p
		}
	}
	return nil
}
