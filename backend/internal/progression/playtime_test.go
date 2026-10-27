package progression

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/google/uuid"

	"ludoarena/internal/progression/progtest"
)

// testPlaytimeJSON is testMissionsJSON plus the shipped milestones.
var testPlaytimeJSON = strings.TrimSuffix(strings.TrimSpace(testMissionsJSON), "}") + `,
  "playtime": {"enabled": true, "milestones": [
    {"id": "playtime_10m", "minutes": 10, "reward": {"coins": 5000, "xp": 25}},
    {"id": "playtime_30m", "minutes": 30, "reward": {"coins": 10000, "xp": 40}},
    {"id": "playtime_60m", "minutes": 60, "reward": {"coins": 20000, "xp": 60}}
  ]}
}`

func newPlaytimeFixture(t *testing.T, raw string) *fixture {
	t.Helper()
	env := progtest.Setup(t)
	mpath := filepath.Join(t.TempDir(), "missions.json")
	if err := os.WriteFile(mpath, []byte(raw), 0o600); err != nil {
		t.Fatal(err)
	}
	f := &fixture{env: env, clock: progtest.NewClock(testNow), notes: &progtest.Notifier{}, mpath: mpath}
	f.svc = f.newService(t)
	return f
}

// play credits d of play ending now (synchronously).
func (f *fixture) play(id uuid.UUID, d time.Duration, final bool) {
	now := f.clock.Now()
	f.svc.RecordPlaytime(context.Background(), id, now.Add(-d), now, final)
}

func (f *fixture) playtime(t *testing.T, id uuid.UUID) *PlaytimeView {
	t.Helper()
	v, err := f.svc.Playtime(context.Background(), id)
	if err != nil {
		t.Fatal(err)
	}
	return v
}

func statuses(v *PlaytimeView) string {
	var s []string
	for _, m := range v.Milestones {
		s = append(s, m.Status)
	}
	return strings.Join(s, ",")
}

func (f *fixture) claims(t *testing.T, id uuid.UUID) int {
	return f.count(t, `SELECT count(*) FROM progression.mission_claims WHERE user_id = $1 AND mission_id LIKE 'playtime%'`, id)
}

func (f *fixture) cleanupPlaytime(t *testing.T, id uuid.UUID) {
	t.Cleanup(func() {
		ctx := context.Background()
		for d := -1; d <= 1; d++ {
			f.env.RDB.Del(ctx, PlaytimeKey(id, DayKey(testNow.AddDate(0, 0, d))))
		}
	})
}

func TestPlaytimeConfigValidation(t *testing.T) {
	base := strings.TrimSuffix(strings.TrimSpace(testMissionsJSON), "}")
	cases := []struct {
		name, playtime, want string
	}{
		{"valid", `{"enabled":true,"milestones":[{"id":"playtime_a","minutes":5,"reward":{"xp":1}}]}`, ""},
		{"disabled without milestones", `{"enabled":false,"milestones":[]}`, ""},
		{"enabled without milestones", `{"enabled":true,"milestones":[]}`, "enabled needs at least one milestone"},
		{"bad id", `{"enabled":true,"milestones":[{"id":"ten","minutes":5,"reward":{"xp":1}}]}`, "invalid or duplicate id"},
		{"duplicate id", `{"enabled":true,"milestones":[{"id":"playtime_a","minutes":5,"reward":{"xp":1}},{"id":"playtime_a","minutes":6,"reward":{"xp":1}}]}`, "invalid or duplicate id"},
		{"not increasing", `{"enabled":true,"milestones":[{"id":"playtime_a","minutes":10,"reward":{"xp":1}},{"id":"playtime_b","minutes":10,"reward":{"xp":1}}]}`, "increasing"},
		{"too long", `{"enabled":true,"milestones":[{"id":"playtime_a","minutes":1441,"reward":{"xp":1}}]}`, "minutes must be 1..1440"},
		{"no reward", `{"enabled":true,"milestones":[{"id":"playtime_a","minutes":5,"reward":{}}]}`, "must grant coins, diamonds or XP"},
		{"reward out of range", `{"enabled":true,"milestones":[{"id":"playtime_a","minutes":5,"reward":{"coins":2000000}}]}`, "out of range"},
		{"items", `{"enabled":true,"milestones":[{"id":"playtime_a","minutes":5,"reward":{"xp":1,"items":["dice_neon"]}}]}`, "item rewards are not supported"},
		{"unknown field", `{"enabled":true,"milestones":[{"id":"playtime_a","minutes":5,"seconds":1,"reward":{"xp":1}}]}`, "unknown field"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			_, err := ParseMissions([]byte(base+`,"playtime":`+c.playtime+`}`), repoCatalog(t))
			switch {
			case c.want == "" && err != nil:
				t.Fatalf("unexpected error: %v", err)
			case c.want != "" && (err == nil || !strings.Contains(err.Error(), c.want)):
				t.Fatalf("err = %v, want %q", err, c.want)
			}
		})
	}
	// Mission ids may not use the reserved prefix.
	reserved := strings.Replace(testMissionsJSON, `"id": "t_win"`, `"id": "playtime_win"`, 1)
	if _, err := ParseMissions([]byte(reserved), repoCatalog(t)); err == nil || !strings.Contains(err.Error(), "reserved prefix") {
		t.Fatalf("reserved prefix accepted: %v", err)
	}
}

func TestRepoPlaytimeConfig(t *testing.T) {
	ms, err := LoadMissions(filepath.Join(progtest.BackendDir(), "config", "missions.json"), repoCatalog(t))
	if err != nil {
		t.Fatal(err)
	}
	p := ms.Playtime
	if p == nil || !p.Enabled || len(p.Milestones) != 3 {
		t.Fatalf("playtime config = %+v", p)
	}
	var coins, xp int64
	for i, want := range []int{10, 30, 60} {
		m := p.Milestones[i]
		if m.Minutes != want {
			t.Fatalf("milestone %d = %d min, want %d", i, m.Minutes, want)
		}
		coins += m.Reward.Coins
		xp += m.Reward.XP
	}
	// Economy guard (docs/progression.md → Daily playtime): a full day of
	// milestones stays below one Ludo entry fee and about one daily mission
	// set plus a match of XP, so playtime cannot dominate progression.
	if coins >= 100_000 || xp > 150 {
		t.Fatalf("daily playtime rewards %d coins / %d XP exceed the economy guard", coins, xp)
	}
}

func TestDaySpans(t *testing.T) {
	mid := time.Date(2026, 10, 22, 0, 0, 0, 0, time.UTC)
	got := daySpans(mid.Add(-5*time.Minute), mid.Add(20*time.Minute))
	if len(got) != 2 || got[0][1] != mid || got[1][0] != mid || got[1][1] != mid.Add(20*time.Minute) {
		t.Fatalf("spans = %v", got)
	}
	if got := daySpans(mid, mid.Add(time.Minute)); len(got) != 1 {
		t.Fatalf("same-day spans = %v", got)
	}
	if got := daySpans(mid, mid); len(got) != 0 {
		t.Fatalf("empty interval spans = %v", got)
	}
}

func TestPlaytimeMilestoneBoundaries(t *testing.T) {
	f := newPlaytimeFixture(t, testPlaytimeJSON)
	a := f.env.NewAccount(t)
	f.cleanupPlaytime(t, a)
	w0 := f.wallet(t, a)

	steps := []struct {
		add          time.Duration
		wantSeconds  int64
		wantStatuses string
		wantClaims   int
		wantCoins    int64
	}{
		{9*time.Minute + 59*time.Second, 599, "in_progress,locked,locked", 0, 0},
		{time.Second, 600, "completed,in_progress,locked", 1, 5000}, // exactly 10 min
		{time.Second, 601, "completed,in_progress,locked", 1, 5000}, // just after: no second grant
		{19*time.Minute + 58*time.Second, 1799, "completed,in_progress,locked", 1, 5000},
		{time.Second, 1800, "completed,completed,in_progress", 2, 15000}, // exactly 30 min
		{30*time.Minute - time.Second, 3599, "completed,completed,in_progress", 2, 15000},
		{time.Second, 3600, "completed,completed,completed", 3, 35000}, // exactly 60 min
		{time.Hour, 7200, "completed,completed,completed", 3, 35000},   // nothing beyond the last
	}
	for i, st := range steps {
		f.play(a, st.add, false)
		v := f.playtime(t, a)
		if v.Seconds != st.wantSeconds || statuses(v) != st.wantStatuses || f.claims(t, a) != st.wantClaims {
			t.Fatalf("step %d: seconds=%d statuses=%s claims=%d, want %d %s %d", i, v.Seconds, statuses(v),
				f.claims(t, a), st.wantSeconds, st.wantStatuses, st.wantClaims)
		}
		if got := f.wallet(t, a).Coins - w0.Coins; got != st.wantCoins {
			t.Fatalf("step %d: coins +%d, want +%d", i, got, st.wantCoins)
		}
	}
	if xp := f.summary(t, a).XP; xp != 25+40+60 {
		t.Fatalf("xp = %d, want 125", xp)
	}
	// Each grant was announced once, with the server-confirmed reward.
	var granted []string
	for _, m := range f.notes.For(a, MsgPlaytimeUpdated) {
		for _, g := range m.Payload.(PlaytimeUpdated).Granted {
			granted = append(granted, g.ID)
		}
	}
	if strings.Join(granted, ",") != "playtime_10m,playtime_30m,playtime_60m" {
		t.Fatalf("granted pushes = %v", granted)
	}
	var reasons []string
	for _, m := range f.notes.For(a, MsgWalletUpdated) {
		reasons = append(reasons, m.Payload.(WalletUpdated).Reason)
	}
	if strings.Join(reasons, ",") != "playtime,playtime,playtime" {
		t.Fatalf("wallet pushes = %v", reasons)
	}
}

func TestPlaytimeCrossingSeveralMilestonesAtOnce(t *testing.T) {
	f := newPlaytimeFixture(t, testPlaytimeJSON)
	a := f.env.NewAccount(t)
	f.cleanupPlaytime(t, a)
	w0 := f.wallet(t, a)
	f.play(a, 61*time.Minute, true)
	if got := f.wallet(t, a).Coins - w0.Coins; got != 35000 {
		t.Fatalf("coins +%d, want +35000", got)
	}
	msgs := f.notes.For(a, MsgPlaytimeUpdated)
	if len(msgs) != 1 {
		t.Fatalf("%d playtime pushes, want 1", len(msgs))
	}
	u := msgs[0].Payload.(PlaytimeUpdated)
	if len(u.Granted) != 3 || u.Granted[0].Minutes != 10 || u.Granted[2].Minutes != 60 || u.Seconds != 61*60 {
		t.Fatalf("push = %+v", u)
	}
	// One wallet and one progression push with the summed reward.
	wm := f.notes.For(a, MsgWalletUpdated)
	pm := f.notes.For(a, MsgProgressionUpdated)
	if len(wm) != 1 || wm[0].Payload.(WalletUpdated).Delta.Coins != 35000 || len(pm) != 1 || pm[0].Payload.(ProgressionUpdated).XPGained != 125 {
		t.Fatalf("wallet=%+v progression=%+v", wm, pm)
	}
	// The JSON shape on the wire (docs/websocket-protocol.md).
	raw, _ := json.Marshal(u)
	for _, k := range []string{`"periodKey":"d2026-10-21"`, `"resetsAtUtc":"2026-10-22T00:00:00Z"`, `"seconds":3660`,
		`"granted":[{"id":"playtime_10m","minutes":10,"reward":{"coins":5000,"diamonds":0,"xp":25,"items":[]},"status":"completed"}`} {
		if !strings.Contains(string(raw), k) {
			t.Fatalf("payload %s lacks %s", raw, k)
		}
	}
}

func TestPlaytimeLevelUpThroughReward(t *testing.T) {
	f := newPlaytimeFixture(t, testPlaytimeJSON)
	a := f.env.NewAccount(t)
	f.cleanupPlaytime(t, a)
	f.setXP(t, a, 90) // level 1; +25 XP reaches level 2 (100 XP)
	f.play(a, 10*time.Minute, false)
	pm := f.notes.For(a, MsgProgressionUpdated)
	if len(pm) != 1 || !pm[0].Payload.(ProgressionUpdated).LevelUp || pm[0].Payload.(ProgressionUpdated).Level != 2 {
		t.Fatalf("progression pushes = %+v", pm)
	}
	if !f.owns(t, a, "frame_bronze") { // the level 2 milestone item
		t.Fatal("level milestone item not granted")
	}
}

func TestPlaytimeConcurrentCreditsGrantOnce(t *testing.T) {
	f := newPlaytimeFixture(t, testPlaytimeJSON)
	a := f.env.NewAccount(t)
	f.cleanupPlaytime(t, a)
	w0 := f.wallet(t, a)
	// 12 workers (several instances / connections) each credit a distinct
	// 1-minute interval at the same time: 12 minutes in total.
	var wg sync.WaitGroup
	now := f.clock.Now()
	for i := 0; i < 12; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			from := now.Add(-time.Duration(i+1) * time.Minute)
			f.svc.RecordPlaytime(context.Background(), a, from, from.Add(time.Minute), false)
		}(i)
	}
	wg.Wait()
	// And repeated direct grants race each other.
	for i := 0; i < 8; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			_, _, _ = f.svc.grantPlaytime(context.Background(), a, DayKey(now), 720)
		}()
	}
	wg.Wait()
	if v := f.playtime(t, a); v.Seconds != 720 || statuses(v) != "completed,in_progress,locked" {
		t.Fatalf("seconds=%d statuses=%s", v.Seconds, statuses(v))
	}
	if f.claims(t, a) != 1 || f.wallet(t, a).Coins-w0.Coins != 5000 || f.summary(t, a).XP != 25 {
		t.Fatalf("claims=%d coins+%d xp=%d: reward not exactly once", f.claims(t, a), f.wallet(t, a).Coins-w0.Coins, f.summary(t, a).XP)
	}
}

func TestPlaytimeSurvivesRedisLossAndRestart(t *testing.T) {
	f := newPlaytimeFixture(t, testPlaytimeJSON)
	a := f.env.NewAccount(t)
	f.cleanupPlaytime(t, a)
	ctx := context.Background()
	key := PlaytimeKey(a, DayKey(testNow))

	f.play(a, 12*time.Minute, false) // grants 10 min (written to PostgreSQL)
	f.play(a, time.Minute, false)    // 13 min: below the flush interval, Redis only
	if got := f.missionValue(t, a, DayKey(testNow), PlaytimeMissionID); got != 720 {
		t.Fatalf("stored seconds = %d, want 720", got)
	}
	// Redis loses the key (restart without persistence): the unsaved minute
	// is lost, nothing is granted twice.
	f.env.RDB.Del(ctx, key)
	if v := f.playtime(t, a); v.Seconds != 720 || statuses(v) != "completed,in_progress,locked" {
		t.Fatalf("after loss: seconds=%d statuses=%s", v.Seconds, statuses(v))
	}
	f.play(a, time.Minute, true) // final: written to PostgreSQL
	if got := f.missionValue(t, a, DayKey(testNow), PlaytimeMissionID); got != 780 {
		t.Fatalf("stored seconds after final = %d, want 780", got)
	}
	if f.claims(t, a) != 1 {
		t.Fatalf("claims = %d after Redis loss", f.claims(t, a))
	}

	// A server restart (new Service, same stores) sees the same state and
	// never re-grants.
	f.svc = f.newService(t)
	f.env.RDB.Del(ctx, key)
	f.play(a, 17*time.Minute, false) // 30 min
	if v := f.playtime(t, a); v.Seconds != 1800 || statuses(v) != "completed,completed,in_progress" || f.claims(t, a) != 2 {
		t.Fatalf("after restart: seconds=%d statuses=%s claims=%d", v.Seconds, statuses(v), f.claims(t, a))
	}
}

func TestPlaytimeReadGrantsAMissedReward(t *testing.T) {
	f := newPlaytimeFixture(t, testPlaytimeJSON)
	a := f.env.NewAccount(t)
	f.cleanupPlaytime(t, a)
	// The seconds reached PostgreSQL but the grant never ran (crash).
	if _, err := f.env.Pool.Exec(context.Background(), `INSERT INTO progression.mission_progress
		(user_id, period_key, mission_id, value) VALUES ($1, $2, 'playtime', 700)`, a, DayKey(testNow)); err != nil {
		t.Fatal(err)
	}
	w0 := f.wallet(t, a)
	if v := f.playtime(t, a); statuses(v) != "completed,in_progress,locked" {
		t.Fatalf("statuses = %s", statuses(v))
	}
	if f.wallet(t, a).Coins-w0.Coins != 5000 {
		t.Fatal("read did not grant the reached milestone")
	}
	f.playtime(t, a)
	if f.claims(t, a) != 1 || f.wallet(t, a).Coins-w0.Coins != 5000 {
		t.Fatal("a second read granted again")
	}
}

func TestPlaytimeDailyResetAtUTCMidnight(t *testing.T) {
	f := newPlaytimeFixture(t, testPlaytimeJSON)
	a := f.env.NewAccount(t)
	f.cleanupPlaytime(t, a)
	mid := time.Date(2026, 10, 22, 0, 0, 0, 0, time.UTC)
	f.clock.Set(mid.Add(-8 * time.Minute))
	f.play(a, 0, false)
	// One stretch from 23:52 to 00:12: 8 minutes count for the 21st, 12 for the 22nd.
	f.clock.Set(mid.Add(12 * time.Minute))
	f.svc.RecordPlaytime(context.Background(), a, mid.Add(-8*time.Minute), mid.Add(12*time.Minute), true)
	if got := f.missionValue(t, a, DayKey(mid.Add(-time.Minute)), PlaytimeMissionID); got != 480 {
		t.Fatalf("previous day stored %d s, want 480 (written when its day ended)", got)
	}
	v := f.playtime(t, a)
	if v.PeriodKey != "d2026-10-22" || v.Seconds != 720 || statuses(v) != "completed,in_progress,locked" {
		t.Fatalf("new day: %+v (%s)", v, statuses(v))
	}
	if v.ResetsAtUTC != "2026-10-23T00:00:00Z" {
		t.Fatalf("resetsAtUtc = %s", v.ResetsAtUTC)
	}
	if n := f.count(t, `SELECT count(*) FROM progression.mission_claims WHERE user_id = $1 AND period_key = 'd2026-10-21'`, a); n != 0 {
		t.Fatalf("previous day got %d claims for 8 minutes", n)
	}
	// Pushes describe only the current day.
	for _, m := range f.notes.For(a, MsgPlaytimeUpdated) {
		if m.Payload.(PlaytimeUpdated).PeriodKey != "d2026-10-22" {
			t.Fatalf("push for a past day: %+v", m.Payload)
		}
	}
}

func TestPlaytimeNeverForBotsOrWhenDisabled(t *testing.T) {
	f := newPlaytimeFixture(t, testPlaytimeJSON)
	ctx := context.Background()
	// A bot persona's coin wallet is not an account.
	botID := uuid.New()
	if _, err := f.env.Pool.Exec(ctx, `INSERT INTO wallet.wallets (user_id, coins, diamonds, is_bot) VALUES ($1, 100, 0, TRUE)`, botID); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _, _ = f.env.Pool.Exec(ctx, `DELETE FROM wallet.wallets WHERE user_id = $1`, botID) })
	f.cleanupPlaytime(t, botID)
	f.play(botID, time.Hour, true)
	if n := f.count(t, `SELECT count(*) FROM progression.mission_progress WHERE user_id = $1`, botID); n != 0 {
		t.Fatalf("bot got %d progress rows", n)
	}
	if n := f.claims(t, botID); n != 0 {
		t.Fatalf("bot got %d claims", n)
	}
	if w := f.wallet(t, botID); w.Coins != 100 {
		t.Fatalf("bot wallet changed: %+v", w)
	}

	off := newPlaytimeFixture(t, strings.Replace(testPlaytimeJSON, `"enabled": true`, `"enabled": false`, 1))
	a := off.env.NewAccount(t)
	off.cleanupPlaytime(t, a)
	off.play(a, time.Hour, true)
	if v := off.playtime(t, a); v != nil {
		t.Fatalf("disabled playtime view = %+v", v)
	}
	mv, err := off.svc.Missions(ctx, a)
	if err != nil || mv.Playtime != nil || off.claims(t, a) != 0 {
		t.Fatalf("disabled: missions.playtime=%v claims=%d err=%v", mv.Playtime, off.claims(t, a), err)
	}
}

func TestPlaytimeHTTP(t *testing.T) {
	f := newPlaytimeFixture(t, testPlaytimeJSON)
	rt, srv := f.env.Router(t)
	f.svc.Register(rt)
	id, tok := f.env.Guest(t)
	f.cleanupPlaytime(t, id)
	f.play(id, 11*time.Minute, false)

	res := progtest.Do(t, srv, "GET", "/api/v1/playtime", tok, nil, nil)
	if res.Status != 200 {
		t.Fatalf("GET /playtime = %d %s", res.Status, res.Body)
	}
	var v PlaytimeView
	res.JSON(t, &v)
	if v.Seconds != 660 || len(v.Milestones) != 3 || v.Milestones[0].Status != PlaytimeCompleted ||
		v.Milestones[1].Reward.Coins != 10000 || v.Milestones[1].Status != PlaytimeInProgress {
		t.Fatalf("GET /playtime = %s", res.Body)
	}
	res = progtest.Do(t, srv, "GET", "/api/v1/missions", tok, nil, nil)
	var mv struct {
		Playtime *PlaytimeView `json:"playtime"`
	}
	res.JSON(t, &mv)
	if res.Status != 200 || mv.Playtime == nil || mv.Playtime.Seconds != 660 {
		t.Fatalf("GET /missions playtime = %s", res.Body)
	}
	if res := progtest.Do(t, srv, "GET", "/api/v1/playtime", "", nil, nil); res.Status != 401 {
		t.Fatalf("anonymous GET /playtime = %d", res.Status)
	}

	off := newPlaytimeFixture(t, testMissionsJSON) // no playtime section
	rt2, srv2 := off.env.Router(t)
	off.svc.Register(rt2)
	_, tok2 := off.env.Guest(t)
	if res := progtest.Do(t, srv2, "GET", "/api/v1/playtime", tok2, nil, nil); res.Status != 404 || res.ErrorCode() != "not_found" {
		t.Fatalf("disabled GET /playtime = %d %s", res.Status, res.Body)
	}
	res = progtest.Do(t, srv2, "GET", "/api/v1/missions", tok2, nil, nil)
	if !strings.Contains(string(res.Body), `"playtime":null`) {
		t.Fatalf("disabled GET /missions = %s", res.Body)
	}
}
