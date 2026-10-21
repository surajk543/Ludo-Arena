package progression

import (
	"context"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sync"
	"testing"
	"time"

	"github.com/google/uuid"

	"ludoroyale/internal/gameevents"
	"ludoroyale/internal/playerinfo"
	"ludoroyale/internal/progression/progtest"
	"ludoroyale/internal/wallet"
)

var testNow = time.Date(2026, 10, 21, 12, 0, 0, 0, time.UTC) // Wednesday, inside autumn_cup

type fixture struct {
	env   *progtest.Env
	clock *progtest.Clock
	notes *progtest.Notifier
	svc   *Service
	mpath string
}

func newFixture(t *testing.T) *fixture {
	t.Helper()
	env := progtest.Setup(t)
	mpath := filepath.Join(t.TempDir(), "missions.json")
	if err := os.WriteFile(mpath, []byte(testMissionsJSON), 0o600); err != nil {
		t.Fatal(err)
	}
	f := &fixture{env: env, clock: progtest.NewClock(testNow), notes: &progtest.Notifier{}, mpath: mpath}
	f.svc = f.newService(t)
	return f
}

// newService builds another Service over the same database (restart).
func (f *fixture) newService(t *testing.T) *Service {
	t.Helper()
	s, err := New(f.env.Pool, f.env.RDB, f.env.Profiles, f.notes, f.env.Log,
		Options{CatalogPath: f.env.CatalogPath(), MissionsPath: f.mpath, Now: f.clock.Now})
	if err != nil {
		t.Fatal(err)
	}
	return s
}

func human(id uuid.UUID, won bool) gameevents.Participant {
	p := gameevents.Participant{UserID: id, Won: won, Actions: 12, Placement: 2}
	if won {
		p.Placement = 1
	}
	return p
}

func bot(won bool) gameevents.Participant {
	return gameevents.Participant{UserID: uuid.New(), Bot: true, Won: won, Actions: 12}
}

func match(game, variant, mode string, finished time.Time, players ...gameevents.Participant) gameevents.MatchRecord {
	hasBots := false
	for i := range players {
		players[i].Seat = i
		hasBots = hasBots || players[i].Bot
	}
	return gameevents.MatchRecord{MatchID: "r_" + uuid.NewString()[:8] + ":1", Game: game, Variant: variant, Mode: mode,
		Reason: "completed", HasBots: hasBots, Players: players, StartedAt: finished.Add(-5 * time.Minute), FinishedAt: finished}
}

func (f *fixture) summary(t *testing.T, id uuid.UUID) playerinfo.Summary {
	t.Helper()
	s, err := f.svc.Summary(context.Background(), id)
	if err != nil {
		t.Fatal(err)
	}
	return s
}

func (f *fixture) wallet(t *testing.T, id uuid.UUID) wallet.Wallet {
	t.Helper()
	w, err := wallet.GetTx(context.Background(), f.env.Pool, id)
	if err != nil {
		t.Fatal(err)
	}
	return w
}

func (f *fixture) count(t *testing.T, sql string, args ...any) int {
	t.Helper()
	var n int
	if err := f.env.Pool.QueryRow(context.Background(), sql, args...).Scan(&n); err != nil {
		t.Fatal(err)
	}
	return n
}

func (f *fixture) owns(t *testing.T, id uuid.UUID, item string) bool {
	t.Helper()
	ok, err := f.svc.Owns(context.Background(), id, item)
	if err != nil {
		t.Fatal(err)
	}
	return ok
}

func (f *fixture) befriend(t *testing.T, a, b uuid.UUID) {
	t.Helper()
	lo, hi := a, b
	if lo.String() > hi.String() {
		lo, hi = hi, lo
	}
	if _, err := f.env.Pool.Exec(context.Background(), `INSERT INTO progression.friendships (user_lo, user_hi, status, requested_by)
		VALUES ($1, $2, 'accepted', $1)`, lo, hi); err != nil {
		t.Fatal(err)
	}
}

func (f *fixture) setXP(t *testing.T, id uuid.UUID, xp int64) {
	t.Helper()
	if err := f.svc.Bootstrap(context.Background(), id); err != nil {
		t.Fatal(err)
	}
	if _, err := f.env.Pool.Exec(context.Background(), `UPDATE progression.player_progress SET xp = $2, level = $3 WHERE user_id = $1`,
		id, xp, LevelForXP(xp)); err != nil {
		t.Fatal(err)
	}
}

func (f *fixture) missionValue(t *testing.T, id uuid.UUID, period, mission string) int {
	t.Helper()
	return f.count(t, `SELECT COALESCE((SELECT value FROM progression.mission_progress
		WHERE user_id = $1 AND period_key = $2 AND mission_id = $3), 0)`, id, period, mission)
}

func TestRecordMatchAwardsXPOnce(t *testing.T) {
	f := newFixture(t)
	ctx := context.Background()
	a, b := f.env.NewAccount(t), f.env.NewAccount(t)
	rec := match("ludo", "classic", "public", testNow, human(a, true), human(b, false))

	for i := 0; i < 3; i++ {
		if err := f.svc.RecordMatch(ctx, rec); err != nil {
			t.Fatal(err)
		}
	}
	if got := f.summary(t, a).XP; got != XPMatchCompleted+XPWinBonus {
		t.Fatalf("winner XP = %d, want %d", got, XPMatchCompleted+XPWinBonus)
	}
	if got := f.summary(t, b).XP; got != XPMatchCompleted {
		t.Fatalf("loser XP = %d, want %d", got, XPMatchCompleted)
	}
	if n := len(f.notes.For(a, MsgProgressionUpdated)); n != 1 {
		t.Fatalf("progression.updated sent %d times, want 1", n)
	}
	if f.count(t, `SELECT count(*) FROM progression.match_receipts WHERE match_id = $1`, rec.MatchID) != 2 {
		t.Fatal("expected one receipt per human")
	}
	if !f.owns(t, a, FirstWinBadge) || f.owns(t, b, FirstWinBadge) {
		t.Fatal("first-win badge must go to the winner only")
	}
	// Weekly leaderboard (Redis) counted once.
	score, err := f.env.RDB.ZScore(ctx, LeaderboardKey(WeekKey(testNow)), a.String()).Result()
	if err != nil || int64(score) != XPMatchCompleted+XPWinBonus {
		t.Fatalf("leaderboard score = %v, %v", score, err)
	}
	p := progtest.PayloadMap(t, f.notes.For(a, MsgProgressionUpdated)[0].Payload)
	if p["xp"].(float64) != 35 || p["level"].(float64) != 1 || p["xpGained"].(float64) != 35 {
		t.Fatalf("progression.updated payload = %v", p)
	}
	if u := p["unlocked"].([]any); len(u) != 1 || u[0] != FirstWinBadge {
		t.Fatalf("unlocked = %v", u)
	}
	if ms := p["missions"].([]any); len(ms) == 0 {
		t.Fatalf("missions missing from payload: %v", p)
	}
}

func TestRecordMatchConcurrentDuplicates(t *testing.T) {
	f := newFixture(t)
	a, b := f.env.NewAccount(t), f.env.NewAccount(t)
	rec := match("snakes_ladders", "classic", "private", testNow, human(a, false), human(b, true))
	var wg sync.WaitGroup
	errs := make(chan error, 16)
	for i := 0; i < 16; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			errs <- f.svc.RecordMatch(context.Background(), rec)
		}()
	}
	wg.Wait()
	close(errs)
	for err := range errs {
		if err != nil {
			t.Fatal(err)
		}
	}
	if f.summary(t, a).XP != 20 || f.summary(t, b).XP != 35 {
		t.Fatalf("XP after concurrent duplicates: a=%d b=%d", f.summary(t, a).XP, f.summary(t, b).XP)
	}
	if v := f.missionValue(t, a, DayKey(testNow), "t_snakes"); v != 1 {
		t.Fatalf("mission counted %d times", v)
	}
	if v := f.missionValue(t, a, WeekKey(testNow), "weekly_ten_matches"); v != 1 {
		t.Fatalf("weekly mission counted %d times", v)
	}
}

func TestIneligiblePlayersGetNothing(t *testing.T) {
	f := newFixture(t)
	ctx := context.Background()
	quitter, idle, ok := f.env.NewAccount(t), f.env.NewAccount(t), f.env.NewAccount(t)
	q := human(quitter, false)
	q.Forfeited = true
	idleP := human(idle, false)
	idleP.Actions = 2
	rec := match("ludo", "classic", "public", testNow, q, idleP, human(ok, true))
	if err := f.svc.RecordMatch(ctx, rec); err != nil {
		t.Fatal(err)
	}
	for _, id := range []uuid.UUID{quitter, idle} {
		if xp := f.summary(t, id).XP; xp != 0 {
			t.Fatalf("ineligible player got %d XP", xp)
		}
		if n := f.count(t, `SELECT count(*) FROM progression.mission_progress WHERE user_id = $1`, id); n != 0 {
			t.Fatalf("ineligible player got mission progress (%d rows)", n)
		}
		if len(f.notes.For(id, MsgProgressionUpdated)) != 0 {
			t.Fatal("ineligible player notified")
		}
	}
	if f.summary(t, ok).XP != 35 {
		t.Fatal("eligible winner should still be rewarded")
	}

	// A too-short match rewards nobody.
	short := match("ludo", "classic", "public", testNow, human(ok, true), human(idle, false))
	short.StartedAt = short.FinishedAt.Add(-29 * time.Second)
	if err := f.svc.RecordMatch(ctx, short); err != nil {
		t.Fatal(err)
	}
	if f.summary(t, ok).XP != 35 || f.summary(t, idle).XP != 0 {
		t.Fatal("short match must not award XP")
	}
}

func TestBotsIgnored(t *testing.T) {
	f := newFixture(t)
	ctx := context.Background()
	if err := f.svc.RecordMatch(ctx, match("ludo", "classic", "practice", testNow, bot(true), bot(false))); err != nil {
		t.Fatalf("bot-only match: %v", err)
	}
	// Practice vs bots: the human is rewarded, bots are skipped.
	h := f.env.NewAccount(t)
	if err := f.svc.RecordMatch(ctx, match("ludo", "classic", "practice", testNow, human(h, false), bot(true), bot(false))); err != nil {
		t.Fatal(err)
	}
	if f.summary(t, h).XP != XPMatchCompleted {
		t.Fatalf("human XP vs bots = %d", f.summary(t, h).XP)
	}
	// A participant without an account (mislabelled bot) is skipped, not an error.
	if err := f.svc.RecordMatch(ctx, match("ludo", "classic", "public", testNow, human(uuid.New(), true), human(h, false))); err != nil {
		t.Fatalf("participant without account: %v", err)
	}
	if f.summary(t, h).XP != 2*XPMatchCompleted {
		t.Fatalf("human XP = %d", f.summary(t, h).XP)
	}
	// Bot ids (no account) get the starter summary without error.
	sums, err := f.svc.Summaries(ctx, []uuid.UUID{uuid.New(), h})
	if err != nil || len(sums) != 2 {
		t.Fatalf("summaries with a bot id: %v %v", sums, err)
	}
}

func TestFriendBonusAndMissionFilters(t *testing.T) {
	f := newFixture(t)
	ctx := context.Background()
	a, b, c := f.env.NewAccount(t), f.env.NewAccount(t), f.env.NewAccount(t)
	f.befriend(t, a, b)
	day, week := DayKey(testNow), WeekKey(testNow)

	// Public classic Ludo, a wins, with friend b and stranger c.
	if err := f.svc.RecordMatch(ctx, match("ludo", "classic", "public", testNow, human(a, true), human(b, false), human(c, false))); err != nil {
		t.Fatal(err)
	}
	if f.summary(t, a).XP != 20+15+5 || f.summary(t, b).XP != 20+5 || f.summary(t, c).XP != 20 {
		t.Fatalf("XP a=%d b=%d c=%d", f.summary(t, a).XP, f.summary(t, b).XP, f.summary(t, c).XP)
	}
	want := map[string]int{"t_ludo": 1, "t_snakes": 0, "t_play_two": 1, "t_friends_private": 0, "t_win": 1}
	for m, v := range want {
		if got := f.missionValue(t, a, day, m); got != v {
			t.Errorf("a %s = %d, want %d", m, got, v)
		}
	}
	if f.missionValue(t, b, day, "t_win") != 0 {
		t.Error("loser progressed a win mission")
	}
	if f.missionValue(t, a, EventKey("autumn_cup"), "autumn_quick_ludo") != 0 {
		t.Error("classic Ludo counted for a Quick Ludo event mission")
	}

	// Private Snakes with a friend: the friends mission counts for a and b; c
	// (no friend in that match) would not.
	if err := f.svc.RecordMatch(ctx, match("snakes_ladders", "classic", "private", testNow, human(a, false), human(b, true))); err != nil {
		t.Fatal(err)
	}
	if f.missionValue(t, a, day, "t_friends_private") != 1 || f.missionValue(t, a, day, "t_snakes") != 1 ||
		f.missionValue(t, a, day, "t_play_two") != 2 || f.missionValue(t, b, day, "t_win") != 1 {
		t.Fatal("private friend match progress mismatch")
	}
	if err := f.svc.RecordMatch(ctx, match("snakes_ladders", "classic", "private", testNow, human(c, true), bot(false))); err != nil {
		t.Fatal(err)
	}
	if f.missionValue(t, c, day, "t_friends_private") != 0 {
		t.Fatal("private match without a friend counted for the friends mission")
	}

	// Quick Ludo counts for the running event; progress is capped at the target.
	for i := 0; i < 4; i++ {
		if err := f.svc.RecordMatch(ctx, match("ludo", "quick", "public", testNow, human(a, false), human(c, true))); err != nil {
			t.Fatal(err)
		}
	}
	if f.missionValue(t, a, EventKey("autumn_cup"), "autumn_quick_ludo") != 3 {
		t.Fatal("event progress should be capped at its target 3")
	}
	if f.missionValue(t, a, week, "weekly_ten_matches") != 6 {
		t.Fatalf("weekly = %d", f.missionValue(t, a, week, "weekly_ten_matches"))
	}

	// Outside the event window nothing counts for the event.
	later := time.Date(2026, 11, 5, 12, 0, 0, 0, time.UTC)
	d := f.env.NewAccount(t)
	if err := f.svc.RecordMatch(ctx, match("ludo", "quick", "public", later, human(d, false), human(c, false))); err != nil {
		t.Fatal(err)
	}
	if f.count(t, `SELECT count(*) FROM progression.mission_progress WHERE user_id = $1 AND period_key LIKE 'e-%'`, d) != 0 {
		t.Fatal("event progress recorded outside the event window")
	}
}

func TestLevelUpGrantsMilestones(t *testing.T) {
	f := newFixture(t)
	ctx := context.Background()
	a, b := f.env.NewAccount(t), f.env.NewAccount(t)
	f.setXP(t, a, 95) // 5 XP below level 2

	if err := f.svc.RecordMatch(ctx, match("ludo", "classic", "public", testNow, human(a, false), human(b, false))); err != nil {
		t.Fatal(err)
	}
	s := f.summary(t, a)
	if s.Level != 2 || s.XP != 115 || s.LevelXP != 100 || s.NextLevelXP != 150 {
		t.Fatalf("summary after level-up: %+v", s)
	}
	if !f.owns(t, a, "frame_bronze") || f.owns(t, a, "token_gem") {
		t.Fatal("level 2 milestone not granted exactly")
	}
	msgs := f.notes.For(a, MsgProgressionUpdated)
	p := progtest.PayloadMap(t, msgs[len(msgs)-1].Payload)
	if p["levelUp"] != true || fmt.Sprint(p["unlocked"]) != "[frame_bronze]" {
		t.Fatalf("level-up payload = %v", p)
	}

	// Jump from level 4 to 5 with missing earlier milestones: catch-up grants
	// every milestone up to the new level.
	c := f.env.NewAccount(t)
	f.setXP(t, c, 690)
	if err := f.svc.RecordMatch(ctx, match("ludo", "classic", "public", testNow, human(c, true), human(b, false))); err != nil {
		t.Fatal(err)
	}
	if f.summary(t, c).Level != 5 {
		t.Fatalf("level = %d", f.summary(t, c).Level)
	}
	for _, it := range []string{"frame_bronze", "token_gem", "emote_laugh", "dice_neon", "title_strategist"} {
		if !f.owns(t, c, it) {
			t.Errorf("missing milestone item %s", it)
		}
	}
	if f.owns(t, c, "snakes_board_jungle") {
		t.Error("level 6 item granted at level 5")
	}

	// Max level: XP keeps growing, level stays 50.
	m := f.env.NewAccount(t)
	f.setXP(t, m, LevelStartXP(MaxLevel)+10)
	if err := f.svc.RecordMatch(ctx, match("ludo", "classic", "public", testNow, human(m, false), human(b, false))); err != nil {
		t.Fatal(err)
	}
	if s := f.summary(t, m); s.Level != MaxLevel || s.XP != LevelStartXP(MaxLevel)+30 {
		t.Fatalf("max level summary %+v", s)
	}
}

func TestDailyWeeklyResetBoundaries(t *testing.T) {
	f := newFixture(t)
	ctx := context.Background()
	a, b := f.env.NewAccount(t), f.env.NewAccount(t)
	sun := time.Date(2026, 10, 25, 23, 59, 59, 0, time.UTC)
	mon := time.Date(2026, 10, 26, 0, 0, 0, 0, time.UTC)

	f.clock.Set(sun)
	if err := f.svc.RecordMatch(ctx, match("ludo", "classic", "public", sun, human(a, false), human(b, true))); err != nil {
		t.Fatal(err)
	}
	v, err := f.svc.Missions(ctx, a)
	if err != nil {
		t.Fatal(err)
	}
	if v.Daily.PeriodKey != "d2026-10-25" || v.Daily.ResetsAtUTC != "2026-10-26T00:00:00Z" ||
		v.Weekly.PeriodKey != "w2026-W43" || v.Weekly.ResetsAtUTC != "2026-10-26T00:00:00Z" {
		t.Fatalf("periods at Sunday 23:59:59: daily=%s/%s weekly=%s/%s", v.Daily.PeriodKey, v.Daily.ResetsAtUTC,
			v.Weekly.PeriodKey, v.Weekly.ResetsAtUTC)
	}
	if !missionIn(v.Daily, "t_ludo").Completed {
		t.Fatal("daily mission should be complete before the reset")
	}

	f.clock.Set(mon)
	v, err = f.svc.Missions(ctx, a)
	if err != nil {
		t.Fatal(err)
	}
	if v.Daily.PeriodKey != "d2026-10-26" || v.Weekly.PeriodKey != "w2026-W44" || v.Weekly.ResetsAtUTC != "2026-11-02T00:00:00Z" {
		t.Fatalf("periods at Monday 00:00: %s %s %s", v.Daily.PeriodKey, v.Weekly.PeriodKey, v.Weekly.ResetsAtUTC)
	}
	if missionIn(v.Daily, "t_ludo").Progress != 0 || missionIn(v.Weekly, "weekly_ten_matches").Progress != 0 {
		t.Fatal("new periods must start at zero")
	}
	// Yesterday's completed mission can no longer be claimed.
	if _, err := f.svc.Claim(ctx, a, "d2026-10-25", "t_ludo"); !errors.Is(err, ErrMissionNotFound) {
		t.Fatalf("claim of a past period: %v", err)
	}
	// A match finishing exactly at 00:00:00 belongs to the new day and week.
	if err := f.svc.RecordMatch(ctx, match("ludo", "classic", "public", mon, human(a, false), human(b, true))); err != nil {
		t.Fatal(err)
	}
	if f.missionValue(t, a, "d2026-10-26", "t_ludo") != 1 || f.missionValue(t, a, "w2026-W44", "weekly_ten_matches") != 1 ||
		f.missionValue(t, a, "w2026-W43", "weekly_ten_matches") != 1 {
		t.Fatal("boundary match assigned to the wrong period")
	}
	// Missed periods never reset XP or level.
	if f.summary(t, a).XP != 40 {
		t.Fatalf("XP after reset = %d", f.summary(t, a).XP)
	}
}

func missionIn(set MissionSet, id string) MissionView {
	for _, m := range set.Missions {
		if m.ID == id {
			return m
		}
	}
	return MissionView{}
}

func TestClaimExactlyOnce(t *testing.T) {
	f := newFixture(t)
	ctx := context.Background()
	a, b := f.env.NewAccount(t), f.env.NewAccount(t)
	day := DayKey(testNow)

	if _, err := f.svc.Claim(ctx, a, day, "t_ludo"); !errors.Is(err, ErrNotCompleted) {
		t.Fatalf("claim before completion: %v", err)
	}
	if f.count(t, `SELECT count(*) FROM progression.mission_claims WHERE user_id = $1`, a) != 0 {
		t.Fatal("failed claim left a claim row")
	}
	if _, err := f.svc.Claim(ctx, a, day, "no_such_mission"); !errors.Is(err, ErrMissionNotFound) {
		t.Fatalf("unknown mission: %v", err)
	}
	if err := f.svc.RecordMatch(ctx, match("ludo", "classic", "public", testNow, human(a, false), human(b, true))); err != nil {
		t.Fatal(err)
	}
	before := f.wallet(t, a)
	res, err := f.svc.Claim(ctx, a, day, "t_ludo")
	if err != nil {
		t.Fatal(err)
	}
	if res.Wallet.Coins != before.Coins+500 || res.Progression.XP != 20+30 || !res.Mission.Claimed || !res.Mission.Completed {
		t.Fatalf("claim result %+v", res)
	}
	if _, err := f.svc.Claim(ctx, a, day, "t_ludo"); !errors.Is(err, ErrAlreadyClaimed) {
		t.Fatalf("second claim: %v", err)
	}
	if f.wallet(t, a).Coins != before.Coins+500 {
		t.Fatal("second claim changed the wallet")
	}
	w := f.notes.For(a, MsgWalletUpdated)
	if len(w) != 1 {
		t.Fatalf("wallet.updated sent %d times", len(w))
	}
	wp := progtest.PayloadMap(t, w[0].Payload)
	if wp["reason"] != "mission" || wp["delta"].(map[string]any)["coins"].(float64) != 500 {
		t.Fatalf("wallet.updated payload %v", wp)
	}
	v, _ := f.svc.Missions(ctx, a)
	if m := missionIn(v.Daily, "t_ludo"); !m.Claimed || !m.Completed {
		t.Fatalf("mission view after claim %+v", m)
	}
}

func TestConcurrentClaimsCreditOnce(t *testing.T) {
	f := newFixture(t)
	ctx := context.Background()
	a, b := f.env.NewAccount(t), f.env.NewAccount(t)
	if err := f.svc.RecordMatch(ctx, match("ludo", "classic", "public", testNow, human(a, true), human(b, false))); err != nil {
		t.Fatal(err)
	}
	before := f.wallet(t, a)
	var wg sync.WaitGroup
	var mu sync.Mutex
	ok, dup := 0, 0
	for i := 0; i < 20; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			_, err := f.svc.Claim(ctx, a, DayKey(testNow), "t_win")
			mu.Lock()
			defer mu.Unlock()
			switch {
			case err == nil:
				ok++
			case errors.Is(err, ErrAlreadyClaimed):
				dup++
			default:
				t.Errorf("unexpected: %v", err)
			}
		}()
	}
	wg.Wait()
	if ok != 1 || dup != 19 {
		t.Fatalf("ok=%d dup=%d", ok, dup)
	}
	if got := f.wallet(t, a).Coins; got != before.Coins+2000 {
		t.Fatalf("coins = %d, want %d", got, before.Coins+2000)
	}
	if xp := f.summary(t, a).XP; xp != 35+30 {
		t.Fatalf("XP = %d", xp)
	}
}

func TestWeeklyAndEventRewards(t *testing.T) {
	f := newFixture(t)
	ctx := context.Background()
	a, b := f.env.NewAccount(t), f.env.NewAccount(t)
	for i := 0; i < 10; i++ {
		if err := f.svc.RecordMatch(ctx, match("ludo", "quick", "public", testNow, human(a, false), human(b, true))); err != nil {
			t.Fatal(err)
		}
	}
	before := f.wallet(t, a)
	res, err := f.svc.Claim(ctx, a, WeekKey(testNow), "weekly_ten_matches")
	if err != nil {
		t.Fatal(err)
	}
	if res.Wallet.Coins != before.Coins+2000 || res.Wallet.Diamonds != before.Diamonds+5 {
		t.Fatalf("weekly wallet %+v (before %+v)", res.Wallet, before)
	}
	granted := map[string]bool{}
	for _, g := range res.Granted {
		granted[g.ID] = true
	}
	// 200 match XP (level 2, frame_bronze granted then) + 150 → level 3: the
	// claim grants the reward items and the level 3 milestone items.
	if granted["frame_bronze"] {
		t.Error("frame_bronze was granted by the matches, not the claim")
	}
	for _, id := range []string{"title_weekly_champion", "badge_friendly", "token_gem", "emote_laugh"} {
		if !granted[id] || !f.owns(t, a, id) {
			t.Errorf("expected %s granted, got %v", id, res.Granted)
		}
	}
	if !res.Progression.LevelUp || res.Progression.Level != 3 || res.Progression.XP != 350 {
		t.Fatalf("progression %+v", res.Progression)
	}
	ev, err := f.svc.Claim(ctx, a, EventKey("autumn_cup"), "autumn_quick_ludo")
	if err != nil || len(ev.Granted) != 1 || ev.Granted[0].ID != "dice_autumn" {
		t.Fatalf("event claim: %+v %v", ev, err)
	}
	// After the event ends it can no longer be claimed (b completed it too).
	f.clock.Set(time.Date(2026, 11, 2, 0, 0, 0, 0, time.UTC))
	if _, err := f.svc.Claim(ctx, b, EventKey("autumn_cup"), "autumn_quick_ludo"); !errors.Is(err, ErrMissionNotFound) {
		t.Fatalf("claim after event end: %v", err)
	}
}

func TestPurchases(t *testing.T) {
	f := newFixture(t)
	ctx := context.Background()
	a := f.env.NewAccount(t)
	start := f.wallet(t, a) // 1,000,000 coins, 50 diamonds

	if _, err := f.svc.Purchase(ctx, a, "dice_neon"); !errors.Is(err, ErrItemLocked) {
		t.Fatalf("level item purchase: %v", err)
	}
	if _, err := f.svc.Purchase(ctx, a, "nope"); !errors.Is(err, ErrItemNotFound) {
		t.Fatalf("unknown item: %v", err)
	}
	res, err := f.svc.Purchase(ctx, a, "dice_golden")
	if err != nil {
		t.Fatal(err)
	}
	if res.Wallet.Diamonds != start.Diamonds-40 || !res.Item.Owned || res.Item.Equipped {
		t.Fatalf("purchase result %+v", res)
	}
	if _, err := f.svc.Purchase(ctx, a, "dice_golden"); !errors.Is(err, ErrAlreadyOwned) {
		t.Fatalf("second purchase: %v", err)
	}
	// 10 diamonds left: a 60-diamond frame fails and leaves nothing behind.
	if _, err := f.svc.Purchase(ctx, a, "frame_royal"); !errors.Is(err, wallet.ErrInsufficientFunds) {
		t.Fatalf("insufficient funds: %v", err)
	}
	if f.owns(t, a, "frame_royal") || f.count(t, `SELECT count(*) FROM progression.inventory WHERE user_id = $1 AND item_id = 'frame_royal'`, a) != 0 {
		t.Fatal("failed purchase left an inventory row")
	}
	// Shop prices are diamonds only: a 100-diamond token after a top-up.
	f.env.SetDiamonds(t, a, 110)
	if _, err := f.svc.Purchase(ctx, a, "token_crown"); err != nil {
		t.Fatal(err)
	}
	end := f.wallet(t, a)
	if end.Coins != start.Coins || end.Diamonds != 10 {
		t.Fatalf("wallet %+v, want coins %d (unchanged) diamonds 10", end, start.Coins)
	}
	w := f.notes.For(a, MsgWalletUpdated)
	if len(w) != 2 || progtest.PayloadMap(t, w[0].Payload)["reason"] != "purchase" {
		t.Fatalf("wallet.updated messages %v", w)
	}
}

func TestConcurrentPurchases(t *testing.T) {
	f := newFixture(t)
	ctx := context.Background()
	a := f.env.NewAccount(t)
	var wg sync.WaitGroup
	results := make(chan error, 10)
	for i := 0; i < 10; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			_, err := f.svc.Purchase(ctx, a, "dice_golden")
			results <- err
		}()
	}
	wg.Wait()
	close(results)
	ok := 0
	for err := range results {
		if err == nil {
			ok++
		} else if !errors.Is(err, ErrAlreadyOwned) {
			t.Fatalf("unexpected: %v", err)
		}
	}
	if ok != 1 || f.wallet(t, a).Diamonds != progtest.WelcomeDiamonds-40 {
		t.Fatalf("ok=%d diamonds=%d", ok, f.wallet(t, a).Diamonds)
	}

	// Two different items that are not affordable together: exactly one wins
	// and the balance never goes negative.
	b := f.env.NewAccount(t)
	var wg2 sync.WaitGroup
	errs := make([]error, 2)
	for i, item := range []string{"dice_golden", "ludo_board_royal"} {
		wg2.Add(1)
		go func(i int, item string) {
			defer wg2.Done()
			_, errs[i] = f.svc.Purchase(ctx, b, item)
		}(i, item)
	}
	wg2.Wait()
	if (errs[0] == nil) == (errs[1] == nil) {
		t.Fatalf("expected exactly one success: %v", errs)
	}
	w := f.wallet(t, b)
	if w.Diamonds < 0 || (w.Diamonds != 10 && w.Diamonds != 20) {
		t.Fatalf("diamonds = %d", w.Diamonds)
	}
	if n := f.count(t, `SELECT count(*) FROM progression.inventory WHERE user_id = $1`, b); n != 1 {
		t.Fatalf("inventory rows = %d", n)
	}
}

func TestWalletConsistency(t *testing.T) {
	f := newFixture(t)
	ctx := context.Background()
	a, b := f.env.NewAccount(t), f.env.NewAccount(t)
	start := f.wallet(t, a)
	for i := 0; i < 10; i++ {
		won := i%2 == 0
		if err := f.svc.RecordMatch(ctx, match("snakes_ladders", "classic", "public", testNow, human(a, won), human(b, !won))); err != nil {
			t.Fatal(err)
		}
	}
	var rewardsC, rewardsD, spentC, spentD int64
	for _, c := range []struct{ period, mission string }{
		{DayKey(testNow), "t_snakes"}, {DayKey(testNow), "t_play_two"}, {DayKey(testNow), "t_win"},
		{WeekKey(testNow), "weekly_ten_matches"},
	} {
		res, err := f.svc.Claim(ctx, a, c.period, c.mission)
		if err != nil {
			t.Fatalf("claim %s: %v", c.mission, err)
		}
		rewardsC += res.Mission.Reward.Coins
		rewardsD += res.Mission.Reward.Diamonds
	}
	for _, item := range []string{"emote_crown", "trail_comet", "snakes_board_candy", "victory_crown"} {
		res, err := f.svc.Purchase(ctx, a, item)
		if errors.Is(err, wallet.ErrInsufficientFunds) {
			continue
		}
		if err != nil {
			t.Fatal(err)
		}
		p := f.svc.Catalog().Get(item).Acquisition.Price
		spentC += p.Coins
		spentD += p.Diamonds
		_ = res
	}
	end := f.wallet(t, a)
	if end.Coins != start.Coins+rewardsC-spentC || end.Diamonds != start.Diamonds+rewardsD-spentD {
		t.Fatalf("wallet %+v != start %+v + rewards (%d, %d) - spent (%d, %d)", end, start, rewardsC, rewardsD, spentC, spentD)
	}
	if end.Coins < 0 || end.Diamonds < 0 {
		t.Fatal("negative balance")
	}
}

func TestEquip(t *testing.T) {
	f := newFixture(t)
	ctx := context.Background()
	a := f.env.NewAccount(t)
	if _, err := f.svc.Equip(ctx, a, "dice", "dice_golden"); !errors.Is(err, ErrItemLocked) {
		t.Fatalf("locked item: %v", err)
	}
	if _, err := f.svc.Equip(ctx, a, "token", "dice_classic"); !errors.Is(err, ErrWrongSlot) {
		t.Fatalf("wrong slot: %v", err)
	}
	if _, err := f.svc.Equip(ctx, a, "emote", "emote_wave"); !errors.Is(err, ErrUnknownSlot) {
		t.Fatalf("emotes are not equipped: %v", err)
	}
	if _, err := f.svc.Equip(ctx, a, "dice", "dice_nope"); !errors.Is(err, ErrItemNotFound) {
		t.Fatalf("unknown item: %v", err)
	}
	if _, err := f.svc.Purchase(ctx, a, "dice_golden"); err != nil {
		t.Fatal(err)
	}
	lo, err := f.svc.Equip(ctx, a, "dice", "dice_golden")
	if err != nil || lo["dice"] != "dice_golden" || lo["token"] != "token_classic" {
		t.Fatalf("equip: %v %v", lo, err)
	}
	// Title shows up in summaries once owned + equipped.
	f.setXP(t, a, LevelStartXP(5)-1)
	b := f.env.NewAccount(t)
	if err := f.svc.RecordMatch(ctx, match("ludo", "classic", "public", testNow, human(a, false), human(b, false))); err != nil {
		t.Fatal(err)
	}
	if _, err := f.svc.Equip(ctx, a, "title", "title_strategist"); err != nil {
		t.Fatal(err)
	}
	if s := f.summary(t, a); s.Title != "title_strategist" || s.Loadout["dice"] != "dice_golden" {
		t.Fatalf("summary %+v", s)
	}
	col, err := f.svc.Collection(ctx, a)
	if err != nil {
		t.Fatal(err)
	}
	for _, it := range col.Items {
		switch it.ID {
		case "dice_golden", "title_strategist":
			if !it.Owned || !it.Equipped {
				t.Errorf("%s: %+v", it.ID, it)
			}
		case "dice_classic", "emote_wave":
			if !it.Owned || it.Equipped {
				t.Errorf("%s: %+v", it.ID, it)
			}
		case "frame_royal":
			if it.Owned || it.Acquisition.Price == nil || it.Acquisition.Price.Diamonds != 60 {
				t.Errorf("%s: %+v", it.ID, it)
			}
		}
	}
	// Unequip (empty id) and equipping a starter both fall back to starter.
	if lo, err := f.svc.Equip(ctx, a, "dice", ""); err != nil || lo["dice"] != "dice_classic" {
		t.Fatalf("unequip: %v %v", lo, err)
	}
	if lo, err := f.svc.Equip(ctx, a, "title", "title_rookie"); err != nil || lo["title"] != "title_rookie" {
		t.Fatalf("starter equip: %v %v", lo, err)
	}
	if n := f.count(t, `SELECT count(*) FROM progression.loadout WHERE user_id = $1`, a); n != 0 {
		t.Fatalf("starter slots should have no rows, got %d", n)
	}
}

func TestStatePersistsAcrossRestart(t *testing.T) {
	f := newFixture(t)
	ctx := context.Background()
	a, b := f.env.NewAccount(t), f.env.NewAccount(t)
	rec := match("ludo", "classic", "public", testNow, human(a, true), human(b, false))
	if err := f.svc.RecordMatch(ctx, rec); err != nil {
		t.Fatal(err)
	}
	if _, err := f.svc.Claim(ctx, a, DayKey(testNow), "t_win"); err != nil {
		t.Fatal(err)
	}
	if _, err := f.svc.Purchase(ctx, a, "trail_comet"); err != nil {
		t.Fatal(err)
	}
	if _, err := f.svc.Equip(ctx, a, "trail", "trail_comet"); err != nil {
		t.Fatal(err)
	}
	before := f.summary(t, a)

	restarted := f.newService(t)
	after, err := restarted.Summary(ctx, a)
	if err != nil {
		t.Fatal(err)
	}
	if after.XP != before.XP || after.Level != before.Level || after.Loadout["trail"] != "trail_comet" {
		t.Fatalf("after restart %+v, before %+v", after, before)
	}
	v, err := restarted.Missions(ctx, a)
	if err != nil {
		t.Fatal(err)
	}
	if m := missionIn(v.Daily, "t_win"); !m.Claimed {
		t.Fatal("claim lost across restart")
	}
	if _, err := restarted.Claim(ctx, a, DayKey(testNow), "t_win"); !errors.Is(err, ErrAlreadyClaimed) {
		t.Fatalf("re-claim after restart: %v", err)
	}
	// The same match delivered to the new instance is still a duplicate.
	if err := restarted.RecordMatch(ctx, rec); err != nil {
		t.Fatal(err)
	}
	if s, _ := restarted.Summary(ctx, a); s.XP != before.XP {
		t.Fatalf("duplicate match after restart changed XP: %d -> %d", before.XP, s.XP)
	}
	if ok, _ := restarted.Owns(ctx, a, "trail_comet"); !ok {
		t.Fatal("inventory lost across restart")
	}
}

func TestBootstrapAndResolvePublicID(t *testing.T) {
	f := newFixture(t)
	ctx := context.Background()
	a := f.env.NewAccount(t)
	if f.count(t, `SELECT count(*) FROM progression.player_progress WHERE user_id = $1`, a) != 0 {
		t.Fatal("row should not exist before first access")
	}
	if s := f.summary(t, a); s.Level != 1 || s.NextLevelXP != 100 || s.Title != "title_rookie" {
		t.Fatalf("starter summary %+v", s)
	}
	pub := f.env.Profiles.PublicID(a)
	if f.count(t, `SELECT count(*) FROM progression.player_progress WHERE user_id = $1 AND public_id = $2`, a, pub) != 1 {
		t.Fatal("lazy bootstrap did not store the public id")
	}
	if id, err := f.svc.ResolvePublicID(ctx, pub); err != nil || id != a {
		t.Fatalf("resolve from DB: %v %v", id, err)
	}
	// Redis fallback when the durable row does not exist yet.
	b := f.env.NewAccount(t)
	if id, err := f.svc.ResolvePublicID(ctx, f.env.Profiles.PublicID(b)); err != nil || id != b {
		t.Fatalf("resolve via Redis: %v %v", id, err)
	}
	if f.count(t, `SELECT count(*) FROM progression.player_progress WHERE user_id = $1`, b) != 1 {
		t.Fatal("resolve via Redis must persist the mapping")
	}
	for _, bad := range []string{"", "u_", "x_abcdefghijk", "u_zzzzzzzzzzzz", "u_' OR 1=1"} {
		if _, err := f.svc.ResolvePublicID(ctx, bad); !errors.Is(err, ErrUnknownPlayer) {
			t.Errorf("resolve %q: %v", bad, err)
		}
	}
	if err := f.svc.Bootstrap(ctx, uuid.New()); !errors.Is(err, ErrUnknownUser) {
		t.Fatalf("bootstrap without account: %v", err)
	}
	if err := f.svc.Bootstrap(ctx, a); err != nil {
		t.Fatalf("bootstrap is idempotent: %v", err)
	}
}

func TestPurgeRetention(t *testing.T) {
	f := newFixture(t)
	ctx := context.Background()
	a := f.env.NewAccount(t)
	if err := f.svc.Bootstrap(ctx, a); err != nil {
		t.Fatal(err)
	}
	now := f.clock.Now()
	exec := func(sql string, args ...any) {
		t.Helper()
		if _, err := f.env.Pool.Exec(ctx, sql, args...); err != nil {
			t.Fatal(err)
		}
	}
	exec(`INSERT INTO progression.match_receipts (user_id, match_id, processed_at) VALUES ($1, 'old', $2), ($1, 'new', $3)`,
		a, now.Add(-15*24*time.Hour), now.Add(-13*24*time.Hour))
	exec(`INSERT INTO progression.mission_progress (user_id, period_key, mission_id, value, updated_at) VALUES
		($1, 'd2026-08-01', 'x', 1, $2), ($1, 'd2026-10-01', 'x', 1, $3), ($1, $4, 'weekly_ten_matches', 1, $2)`,
		a, now.Add(-61*24*time.Hour), now.Add(-20*24*time.Hour), WeekKey(now))
	exec(`INSERT INTO progression.mission_claims (user_id, period_key, mission_id, claimed_at) VALUES
		($1, 'd2026-08-01', 'x', $2), ($1, 'd2026-10-01', 'x', $3)`, a, now.Add(-61*24*time.Hour), now.Add(-20*24*time.Hour))

	if _, err := f.svc.Purge(ctx); err != nil {
		t.Fatal(err)
	}
	if got := f.count(t, `SELECT count(*) FROM progression.match_receipts WHERE user_id = $1`, a); got != 1 {
		t.Fatalf("receipts left = %d, want 1", got)
	}
	// The old row of the *current* week is kept even though it is old.
	if got := f.count(t, `SELECT count(*) FROM progression.mission_progress WHERE user_id = $1`, a); got != 2 {
		t.Fatalf("progress left = %d, want 2", got)
	}
	if got := f.count(t, `SELECT count(*) FROM progression.mission_claims WHERE user_id = $1`, a); got != 1 {
		t.Fatalf("claims left = %d, want 1", got)
	}
}

func TestNilNotifier(t *testing.T) {
	env := progtest.Setup(t)
	mpath := filepath.Join(t.TempDir(), "missions.json")
	if err := os.WriteFile(mpath, []byte(testMissionsJSON), 0o600); err != nil {
		t.Fatal(err)
	}
	s, err := New(env.Pool, env.RDB, env.Profiles, nil, nil, Options{CatalogPath: env.CatalogPath(), MissionsPath: mpath,
		Now: func() time.Time { return testNow }})
	if err != nil {
		t.Fatal(err)
	}
	a, b := env.NewAccount(t), env.NewAccount(t)
	if err := s.RecordMatch(context.Background(), match("ludo", "classic", "public", testNow, human(a, true), human(b, false))); err != nil {
		t.Fatal(err)
	}
	if _, err := s.Claim(context.Background(), a, DayKey(testNow), "t_win"); err != nil {
		t.Fatal(err)
	}
	if _, err := s.Purchase(context.Background(), a, "emote_crown"); err != nil {
		t.Fatal(err)
	}
}

func TestBadConfigFailsStartup(t *testing.T) {
	env := progtest.Setup(t)
	bad := filepath.Join(t.TempDir(), "missions.json")
	if err := os.WriteFile(bad, []byte(`{"version":1,"dailyCount":3,"daily":[],"weekly":[]}`), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := New(env.Pool, env.RDB, env.Profiles, nil, env.Log, Options{CatalogPath: env.CatalogPath(), MissionsPath: bad}); err == nil {
		t.Fatal("invalid missions config must fail startup")
	}
	if _, err := New(env.Pool, env.RDB, env.Profiles, nil, env.Log, Options{CatalogPath: "/nonexistent.json"}); err == nil {
		t.Fatal("missing catalog must fail startup")
	}
}
