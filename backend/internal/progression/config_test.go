package progression

import (
	"os"
	"path/filepath"
	"reflect"
	"sort"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"

	"ludoarena/internal/gameevents"
	"ludoarena/internal/progression/progtest"
)

func repoCatalog(t *testing.T) *Catalog {
	t.Helper()
	c, err := LoadCatalog(filepath.Join(progtest.BackendDir(), "config", "catalog.json"))
	if err != nil {
		t.Fatalf("repo catalog invalid: %v", err)
	}
	return c
}

func TestLevelMath(t *testing.T) {
	cases := []struct {
		xp    int64
		level int
	}{{0, 1}, {99, 1}, {100, 2}, {249, 2}, {250, 3}, {449, 3}, {450, 4}, {520, 4}, {699, 4}, {700, 5}, {1 << 40, MaxLevel}}
	for _, c := range cases {
		if got := LevelForXP(c.xp); got != c.level {
			t.Errorf("LevelForXP(%d) = %d, want %d", c.xp, got, c.level)
		}
	}
	// Documented example: level 4 starts at 450 XP and needs 250 more.
	if LevelStartXP(4) != 450 || XPToNext(4) != 250 || XPToNext(1) != 100 {
		t.Fatalf("formula mismatch: start(4)=%d next(4)=%d next(1)=%d", LevelStartXP(4), XPToNext(4), XPToNext(1))
	}
	for l := 1; l < MaxLevel; l++ {
		if LevelStartXP(l+1)-LevelStartXP(l) != XPToNext(l) {
			t.Fatalf("threshold gap at level %d", l)
		}
		if LevelForXP(LevelStartXP(l+1)-1) != l || LevelForXP(LevelStartXP(l+1)) != l+1 {
			t.Fatalf("boundary at level %d", l+1)
		}
	}
	if LevelStartXP(MaxLevel) != 63700 {
		t.Fatalf("max level threshold = %d", LevelStartXP(MaxLevel))
	}
}

func TestRepoCatalogMatchesDoc(t *testing.T) {
	c := repoCatalog(t)
	want := map[int][]string{
		2: {"frame_bronze"}, 3: {"emote_laugh", "token_gem"}, 5: {"dice_neon", "title_strategist"},
		6: {"emote_wow", "snakes_board_jungle"}, 7: {"trail_sparkle"}, 8: {"ludo_board_midnight"},
		10: {"frame_silver", "token_royal"}, 12: {"victory_fireworks"}, 15: {"title_dice_master"},
		20: {"frame_gold"}, 30: {"title_royal"},
	}
	got := map[int][]string{}
	for _, l := range c.MilestoneLevels() {
		for _, it := range c.Milestone(l) {
			got[l] = append(got[l], it.ID)
		}
		sort.Strings(got[l])
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("milestones = %v, want %v", got, want)
	}
	if len(c.Items()) != 37 {
		t.Fatalf("catalog has %d items, want 37 (docs/cosmetics-catalog.md)", len(c.Items()))
	}
	// Shop prices are in diamonds only (owner, 21 Oct 2026).
	prices := map[string]Price{"dice_golden": {Diamonds: 40}, "token_crown": {Diamonds: 100}, "ludo_board_royal": {Diamonds: 200},
		"snakes_board_candy": {Diamonds: 200}, "trail_comet": {Diamonds: 20}, "victory_crown": {Diamonds: 40},
		"frame_royal": {Diamonds: 60}, "emote_crown": {Diamonds: 10}}
	for id, p := range prices {
		it := c.Get(id)
		if it == nil || it.Acquisition.Type != AcqPurchase || *it.Acquisition.Price != p {
			t.Errorf("%s price mismatch: %+v", id, it)
		}
	}
}

func TestCatalogValidation(t *testing.T) {
	base, err := os.ReadFile(filepath.Join(progtest.BackendDir(), "config", "catalog.json"))
	if err != nil {
		t.Fatal(err)
	}
	mutations := map[string]func(string) string{
		"duplicate id": func(s string) string {
			return strings.Replace(s, `"id": "dice_neon"`, `"id": "dice_classic"`, 1)
		},
		"two currencies": func(s string) string {
			return strings.Replace(s, `"price": {"diamonds": 40}`, `"price": {"diamonds": 40, "coins": 5}`, 1)
		},
		"coin price": func(s string) string {
			return strings.Replace(s, `"price": {"diamonds": 40}`, `"price": {"coins": 40000}`, 1)
		},
		"missing starter": func(s string) string {
			return strings.Replace(s, `"id": "trail_none"`, `"id": "trail_nothing"`, 1)
		},
		"bad level": func(s string) string {
			return strings.Replace(s, `"level": 30`, `"level": 51`, 1)
		},
		"bad rarity": func(s string) string { return strings.Replace(s, `"rarity": "legendary"`, `"rarity": "mythic"`, 1) },
		"unknown field": func(s string) string {
			return strings.Replace(s, `"version": 1`, `"version": 1, "extra": true`, 1)
		},
	}
	for name, mut := range mutations {
		if _, err := ParseCatalog([]byte(mut(string(base)))); err == nil {
			t.Errorf("%s: expected validation error", name)
		}
	}
}

func TestRepoMissionsValid(t *testing.T) {
	c := repoCatalog(t)
	ms, err := LoadMissions(filepath.Join(progtest.BackendDir(), "config", "missions.json"), c)
	if err != nil {
		t.Fatalf("repo missions invalid: %v", err)
	}
	if ms.DailyCount != 3 || len(ms.Weekly) != 1 || ms.Weekly[0].ID != "weekly_ten_matches" {
		t.Fatalf("unexpected missions config: %+v", ms)
	}
	w := ms.Weekly[0].Reward
	if w.XP != 150 || w.Diamonds <= 0 || !reflect.DeepEqual(w.Items, []string{"title_weekly_champion", "badge_friendly"}) {
		t.Fatalf("weekly reward = %+v", w)
	}
	for _, m := range ms.Daily {
		if m.Reward.XP != 30 || m.Reward.Coins < 500 || m.Reward.Coins > 2000 {
			t.Errorf("daily %s reward out of the product range: %+v", m.ID, m.Reward)
		}
	}
}

func TestMissionsValidation(t *testing.T) {
	c := repoCatalog(t)
	base := testMissionsJSON
	mutations := map[string]func(string) string{
		"unknown item": func(s string) string { return strings.Replace(s, `"dice_autumn"`, `"dice_nope"`, 1) },
		"wrong source": func(s string) string { return strings.Replace(s, `"dice_autumn"`, `"dice_golden"`, 1) },
		"bad metric":   func(s string) string { return strings.Replace(s, `"metric": "win"`, `"metric": "lose"`, 1) },
		"daily count":  func(s string) string { return strings.Replace(s, `"dailyCount": 5`, `"dailyCount": 9`, 1) },
		"event too long": func(s string) string {
			return strings.Replace(s, `"2026-11-02T00:00:00Z"`, `"2027-11-02T00:00:00Z"`, 1)
		},
		"bad game":     func(s string) string { return strings.Replace(s, `"game": "snakes_ladders"`, `"game": "chess"`, 1) },
		"duplicate id": func(s string) string { return strings.Replace(s, `"id": "t_snakes"`, `"id": "t_ludo"`, 1) },
		"zero target":  func(s string) string { return strings.Replace(s, `"target": 2`, `"target": 0`, 1) },
	}
	if _, err := ParseMissions([]byte(base), c); err != nil {
		t.Fatalf("test missions invalid: %v", err)
	}
	for name, mut := range mutations {
		if _, err := ParseMissions([]byte(mut(base)), c); err == nil {
			t.Errorf("%s: expected validation error", name)
		}
	}
}

func TestPeriodKeysAndBoundaries(t *testing.T) {
	sun := time.Date(2026, 10, 25, 23, 59, 59, 0, time.UTC)
	mon := time.Date(2026, 10, 26, 0, 0, 0, 0, time.UTC)
	if DayKey(sun) != "d2026-10-25" || DayKey(mon) != "d2026-10-26" {
		t.Fatalf("day keys: %s %s", DayKey(sun), DayKey(mon))
	}
	if WeekKey(sun) != "w2026-W43" || WeekKey(mon) != "w2026-W44" {
		t.Fatalf("week keys: %s %s", WeekKey(sun), WeekKey(mon))
	}
	if !WeekStart(sun).Equal(time.Date(2026, 10, 19, 0, 0, 0, 0, time.UTC)) || !WeekStart(mon).Equal(mon) {
		t.Fatalf("week starts: %v %v", WeekStart(sun), WeekStart(mon))
	}
	// ISO week-year boundary: 2026 has 53 ISO weeks.
	if WeekKey(time.Date(2027, 1, 1, 12, 0, 0, 0, time.UTC)) != "w2026-W53" || WeekKey(time.Date(2027, 1, 4, 0, 0, 0, 0, time.UTC)) != "w2027-W01" {
		t.Fatal("ISO year boundary")
	}
	// Non-UTC input is normalized.
	ist := time.FixedZone("IST", 5*3600+1800)
	if DayKey(time.Date(2026, 10, 26, 3, 0, 0, 0, ist)) != "d2026-10-25" {
		t.Fatal("day key must use UTC")
	}

	ms, err := ParseMissions([]byte(testMissionsJSON), repoCatalog(t))
	if err != nil {
		t.Fatal(err)
	}
	ps := ms.ActivePeriods(sun)
	if ps[0].Key != "d2026-10-25" || !ps[0].ResetsAt.Equal(mon) || ps[1].Key != "w2026-W43" || !ps[1].ResetsAt.Equal(mon) {
		t.Fatalf("periods at Sunday 23:59:59: %+v %+v", ps[0], ps[1])
	}
	ps = ms.ActivePeriods(mon)
	if ps[0].Key != "d2026-10-26" || !ps[0].ResetsAt.Equal(mon.AddDate(0, 0, 1)) || ps[1].Key != "w2026-W44" ||
		!ps[1].ResetsAt.Equal(mon.AddDate(0, 0, 7)) {
		t.Fatalf("periods at Monday 00:00: %+v %+v", ps[0], ps[1])
	}
	// The event runs [2026-10-19, 2026-11-02).
	if len(ms.ActivePeriods(time.Date(2026, 10, 19, 0, 0, 0, 0, time.UTC))) != 3 ||
		len(ms.ActivePeriods(time.Date(2026, 11, 1, 23, 59, 59, 0, time.UTC))) != 3 ||
		len(ms.ActivePeriods(time.Date(2026, 11, 2, 0, 0, 0, 0, time.UTC))) != 2 ||
		len(ms.ActivePeriods(time.Date(2026, 10, 18, 23, 59, 59, 0, time.UTC))) != 2 {
		t.Fatal("event window boundaries")
	}
}

func TestDailySelectionDeterministic(t *testing.T) {
	c := repoCatalog(t)
	ms, err := LoadMissions(filepath.Join(progtest.BackendDir(), "config", "missions.json"), c)
	if err != nil {
		t.Fatal(err)
	}
	distinct := map[string]bool{}
	day := time.Date(2026, 10, 1, 0, 0, 0, 0, time.UTC)
	for i := 0; i < 30; i++ {
		key := DayKey(day.AddDate(0, 0, i))
		a, b := ms.DailySelection(key), ms.DailySelection(key)
		if len(a) != 3 || !reflect.DeepEqual(a, b) {
			t.Fatalf("selection for %s not deterministic", key)
		}
		seen := map[string]bool{}
		var ids []string
		for _, m := range a {
			if seen[m.ID] {
				t.Fatalf("duplicate mission in %s", key)
			}
			seen[m.ID] = true
			ids = append(ids, m.ID)
		}
		distinct[strings.Join(ids, ",")] = true
	}
	if len(distinct) < 5 {
		t.Fatalf("daily selection barely varies: %d distinct sets in 30 days", len(distinct))
	}
}

func TestEligibility(t *testing.T) {
	start := time.Date(2026, 10, 21, 12, 0, 0, 0, time.UTC)
	rec := gameevents.MatchRecord{StartedAt: start, FinishedAt: start.Add(MinMatchDuration)}
	ok := gameevents.Participant{UserID: uuid.New(), Actions: MinActions}
	if !Eligible(&rec, &ok) {
		t.Fatal("minimum eligible participant rejected")
	}
	for name, p := range map[string]gameevents.Participant{
		"forfeited":   {Actions: 10, Forfeited: true},
		"few actions": {Actions: MinActions - 1},
		"bot":         {Actions: 10, Bot: true},
	} {
		if Eligible(&rec, &p) {
			t.Errorf("%s: should be ineligible", name)
		}
	}
	short := rec
	short.FinishedAt = start.Add(MinMatchDuration - time.Second)
	if Eligible(&short, &ok) {
		t.Error("short match should be ineligible")
	}
}

// testMissionsJSON makes every daily mission active (dailyCount = pool size)
// so DB tests do not depend on the day's selection.
const testMissionsJSON = `{
  "version": 1,
  "dailyCount": 5,
  "daily": [
    {"id": "t_ludo", "title": "Ludo", "description": "Complete 1 Ludo match.", "metric": "complete",
     "filter": {"game": "ludo"}, "target": 1, "reward": {"coins": 500, "xp": 30}},
    {"id": "t_snakes", "title": "Snakes", "description": "Complete 1 Snakes & Ladders match.", "metric": "complete",
     "filter": {"game": "snakes_ladders"}, "target": 1, "reward": {"coins": 500, "xp": 30}},
    {"id": "t_play_two", "title": "Two", "description": "Complete 2 matches.", "metric": "complete",
     "target": 2, "reward": {"coins": 1000, "xp": 30}},
    {"id": "t_friends_private", "title": "Friends", "description": "Private match with a friend.", "metric": "complete",
     "filter": {"mode": "private", "withFriend": true}, "target": 1, "reward": {"coins": 1500, "xp": 30}},
    {"id": "t_win", "title": "Win", "description": "Win 1 match.", "metric": "win",
     "target": 1, "reward": {"coins": 2000, "xp": 30}}
  ],
  "weekly": [
    {"id": "weekly_ten_matches", "title": "Weekly", "description": "Complete 10 matches.", "metric": "complete",
     "target": 10, "reward": {"coins": 2000, "diamonds": 5, "xp": 150, "items": ["title_weekly_champion", "badge_friendly"]}}
  ],
  "events": [
    {"id": "autumn_cup", "title": "Autumn Cup", "description": "Quick Ludo.",
     "startsAtUtc": "2026-10-19T00:00:00Z", "endsAtUtc": "2026-11-02T00:00:00Z",
     "missions": [
       {"id": "autumn_quick_ludo", "title": "Sprint", "description": "Complete 3 Quick Ludo matches.", "metric": "complete",
        "filter": {"game": "ludo", "variant": "quick"}, "target": 3, "reward": {"coins": 1000, "xp": 30, "items": ["dice_autumn"]}}
     ]}
  ]
}`
