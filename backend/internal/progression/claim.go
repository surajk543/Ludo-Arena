package progression

import (
	"context"
	"errors"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"

	"ludoarena/internal/metrics"
	"ludoarena/internal/wallet"
)

// RewardView is a mission reward in API responses.
type RewardView struct {
	Coins    int64     `json:"coins"`
	Diamonds int64     `json:"diamonds"`
	XP       int64     `json:"xp"`
	Items    []ItemRef `json:"items"`
}

// MissionView is the API Mission object.
type MissionView struct {
	ID          string     `json:"id"`
	Title       string     `json:"title"`
	Description string     `json:"description"`
	Game        string     `json:"game"`
	Progress    int        `json:"progress"`
	Target      int        `json:"target"`
	Reward      RewardView `json:"reward"`
	Completed   bool       `json:"completed"`
	Claimed     bool       `json:"claimed"`
}

// MissionSet is the API MissionSet object.
type MissionSet struct {
	PeriodKey   string        `json:"periodKey"`
	ResetsAtUTC string        `json:"resetsAtUtc"`
	Missions    []MissionView `json:"missions"`
}

// EventSet is the API EventSet object (a running event).
type EventSet struct {
	ID          string        `json:"id"`
	Title       string        `json:"title"`
	Description string        `json:"description"`
	PeriodKey   string        `json:"periodKey"`
	StartsAtUTC string        `json:"startsAtUtc"`
	EndsAtUTC   string        `json:"endsAtUtc"`
	Missions    []MissionView `json:"missions"`
}

// MissionsView is the GET /missions response.
type MissionsView struct {
	Daily  MissionSet `json:"daily"`
	Weekly MissionSet `json:"weekly"`
	Events []EventSet `json:"events"`
}

func utc(t time.Time) string { return t.UTC().Format(time.RFC3339) }

func (s *Service) rewardView(r Reward) RewardView {
	v := RewardView{Coins: r.Coins, Diamonds: r.Diamonds, XP: r.XP, Items: []ItemRef{}}
	for _, id := range r.Items {
		if it := s.catalog.Get(id); it != nil {
			v.Items = append(v.Items, it.Ref())
		}
	}
	return v
}

func (s *Service) missionView(m *MissionDef, value int, claimed bool) MissionView {
	if value > m.Target {
		value = m.Target
	}
	return MissionView{ID: m.ID, Title: m.Title, Description: m.Description, Game: m.GameLabel(),
		Progress: value, Target: m.Target, Reward: s.rewardView(m.Reward), Completed: value >= m.Target, Claimed: claimed}
}

// Missions returns the current daily, weekly and event missions with the
// account's progress.
func (s *Service) Missions(ctx context.Context, userID uuid.UUID) (MissionsView, error) {
	periods := s.missions.ActivePeriods(s.now())
	keys := make([]string, len(periods))
	for i, p := range periods {
		keys[i] = p.Key
	}
	type pk struct{ period, mission string }
	values := map[pk]int{}
	claimed := map[pk]bool{}
	rows, err := s.pool.Query(ctx, `
		SELECT period_key, mission_id, value, false FROM progression.mission_progress WHERE user_id = $1 AND period_key = ANY($2)
		UNION ALL
		SELECT period_key, mission_id, 0, true FROM progression.mission_claims WHERE user_id = $1 AND period_key = ANY($2)`,
		userID, keys)
	if err != nil {
		return MissionsView{}, err
	}
	for rows.Next() {
		var k pk
		var v int
		var isClaim bool
		if err := rows.Scan(&k.period, &k.mission, &v, &isClaim); err != nil {
			rows.Close()
			return MissionsView{}, err
		}
		if isClaim {
			claimed[k] = true
		} else {
			values[k] = v
		}
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return MissionsView{}, err
	}
	out := MissionsView{Events: []EventSet{}}
	for _, p := range periods {
		ms := make([]MissionView, 0, len(p.Missions))
		for _, m := range p.Missions {
			k := pk{p.Key, m.ID}
			ms = append(ms, s.missionView(m, values[k], claimed[k]))
		}
		switch p.Kind {
		case PeriodDaily:
			out.Daily = MissionSet{PeriodKey: p.Key, ResetsAtUTC: utc(p.ResetsAt), Missions: ms}
		case PeriodWeekly:
			out.Weekly = MissionSet{PeriodKey: p.Key, ResetsAtUTC: utc(p.ResetsAt), Missions: ms}
		case PeriodEvent:
			out.Events = append(out.Events, EventSet{ID: p.Event.ID, Title: p.Event.Title, Description: p.Event.Description,
				PeriodKey: p.Key, StartsAtUTC: utc(p.StartsAt), EndsAtUTC: utc(p.ResetsAt), Missions: ms})
		}
	}
	return out, nil
}

// ProgressSummary is the `progression` object of a claim response.
type ProgressSummary struct {
	Level       int   `json:"level"`
	XP          int64 `json:"xp"`
	LevelXP     int64 `json:"levelXp"`
	NextLevelXP int64 `json:"nextLevelXp"`
	XPGained    int64 `json:"xpGained"`
	LevelUp     bool  `json:"levelUp"`
}

// ClaimResult is the POST /missions/{periodKey}/{missionId}/claim response.
type ClaimResult struct {
	Mission     MissionView     `json:"mission"`
	Wallet      wallet.Wallet   `json:"wallet"`
	Progression ProgressSummary `json:"progression"`
	Granted     []ItemRef       `json:"granted"`
}

// Claim grants a completed mission's reward exactly once. The claim row, the
// wallet credit, the XP and the items commit in one transaction; the claim
// primary key rejects every later (or concurrent) attempt.
func (s *Service) Claim(ctx context.Context, userID uuid.UUID, periodKey, missionID string) (*ClaimResult, error) {
	now := s.now()
	per := s.missions.periodByKey(now, periodKey)
	if per == nil {
		return nil, ErrMissionNotFound
	}
	m := per.Mission(missionID)
	if m == nil {
		return nil, ErrMissionNotFound
	}

	tx, err := s.pool.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		return nil, err
	}
	defer tx.Rollback(ctx) //nolint:errcheck

	oldXP, oldLevel, err := s.lockProgress(ctx, tx, userID)
	if err != nil {
		return nil, err
	}
	tag, err := tx.Exec(ctx, `INSERT INTO progression.mission_claims (user_id, period_key, mission_id) VALUES ($1, $2, $3)
		ON CONFLICT (user_id, period_key, mission_id) DO NOTHING`, userID, per.Key, m.ID)
	if err != nil {
		return nil, err
	}
	if tag.RowsAffected() == 0 {
		return nil, ErrAlreadyClaimed
	}
	var value int
	err = tx.QueryRow(ctx, `SELECT value FROM progression.mission_progress WHERE user_id = $1 AND period_key = $2 AND mission_id = $3`,
		userID, per.Key, m.ID).Scan(&value)
	if err != nil && !errors.Is(err, pgx.ErrNoRows) {
		return nil, err
	}
	if value < m.Target {
		return nil, ErrNotCompleted // rollback discards the claim row
	}

	r := m.Reward
	var wal wallet.Wallet
	if r.Coins != 0 || r.Diamonds != 0 {
		wal, err = wallet.AdjustTx(ctx, tx, userID, r.Coins, r.Diamonds)
	} else {
		wal, err = wallet.GetTx(ctx, tx, userID)
	}
	if err != nil {
		return nil, err
	}
	var granted []*Item
	for _, id := range r.Items {
		it := s.catalog.Get(id)
		isNew, err := grantItemTx(ctx, tx, userID, it)
		if err != nil {
			return nil, err
		}
		if isNew {
			granted = append(granted, it)
		}
	}
	xr, err := s.addXPTx(ctx, tx, userID, oldXP, oldLevel, r.XP)
	if err != nil {
		return nil, err
	}
	if err := tx.Commit(ctx); err != nil {
		return nil, err
	}

	// Post-commit effects.
	if xr.level != xr.oldLevel {
		s.InvalidateSeat(ctx, userID)
	}
	s.cacheGranted(ctx, userID, append(append([]*Item(nil), granted...), xr.unlocked...))
	metrics.MissionRewardsClaimed.WithLabelValues(per.Kind).Inc()
	if r.XP > 0 {
		metrics.XPAwarded.WithLabelValues("mission").Add(float64(r.XP))
	}
	if n := xr.level - xr.oldLevel; n > 0 {
		metrics.LevelUps.WithLabelValues().Add(float64(n))
	}
	if len(granted) > 0 {
		src := "mission"
		if per.Kind == PeriodEvent {
			src = "event"
		}
		metrics.CosmeticUnlocks.WithLabelValues(src).Add(float64(len(granted)))
	}
	if len(xr.unlocked) > 0 {
		metrics.CosmeticUnlocks.WithLabelValues("level").Add(float64(len(xr.unlocked)))
	}
	all := append(granted, xr.unlocked...)
	s.addWeeklyXP(ctx, userID, now, r.XP)
	if r.Coins != 0 || r.Diamonds != 0 {
		s.notify(ctx, userID, MsgWalletUpdated, WalletUpdated{Coins: wal.Coins, Diamonds: wal.Diamonds,
			Delta: WalletDelta{Coins: r.Coins, Diamonds: r.Diamonds}, Reason: "mission"})
	}
	if r.XP > 0 || len(all) > 0 {
		s.notify(ctx, userID, MsgProgressionUpdated, ProgressionUpdated{XP: xr.xp, Level: xr.level, XPGained: r.XP,
			LevelUp: xr.level > xr.oldLevel, Unlocked: itemIDs(all), Missions: []MissionProgress{}})
	}

	refs := make([]ItemRef, 0, len(all))
	for _, it := range all {
		refs = append(refs, it.Ref())
	}
	return &ClaimResult{
		Mission: s.missionView(m, value, true),
		Wallet:  wal,
		Progression: ProgressSummary{Level: xr.level, XP: xr.xp, LevelXP: LevelStartXP(xr.level),
			NextLevelXP: XPToNext(xr.level), XPGained: r.XP, LevelUp: xr.level > xr.oldLevel},
		Granted: refs,
	}, nil
}

// Milestone is one level milestone in GET /progression.
type Milestone struct {
	Level   int       `json:"level"`
	Rewards []ItemRef `json:"rewards"`
	Reached bool      `json:"reached"`
}

// ProgressionView is the GET /progression response.
type ProgressionView struct {
	Level       int         `json:"level"`
	XP          int64       `json:"xp"`
	LevelXP     int64       `json:"levelXp"`
	NextLevelXP int64       `json:"nextLevelXp"`
	MaxLevel    int         `json:"maxLevel"`
	Title       string      `json:"title"`
	Milestones  []Milestone `json:"milestones"`
}

// Progression returns the account's level, XP and milestones.
func (s *Service) Progression(ctx context.Context, userID uuid.UUID) (ProgressionView, error) {
	sum, err := s.Summary(ctx, userID)
	if err != nil {
		return ProgressionView{}, err
	}
	v := ProgressionView{Level: sum.Level, XP: sum.XP, LevelXP: sum.LevelXP, NextLevelXP: sum.NextLevelXP,
		MaxLevel: MaxLevel, Title: sum.Title, Milestones: []Milestone{}}
	for _, lvl := range s.catalog.MilestoneLevels() {
		ms := Milestone{Level: lvl, Reached: sum.Level >= lvl, Rewards: []ItemRef{}}
		for _, it := range s.catalog.Milestone(lvl) {
			ms.Rewards = append(ms.Rewards, it.Ref())
		}
		v.Milestones = append(v.Milestones, ms)
	}
	return v, nil
}
