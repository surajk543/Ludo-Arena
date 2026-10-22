package progression

import (
	"context"
	"errors"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"

	"ludoarena/internal/gameevents"
	"ludoarena/internal/metrics"
)

// Anti-farming thresholds (docs/progression.md → Anti-farming).
const (
	MinActions       = 3
	MinMatchDuration = 30 * time.Second
)

// Eligible reports whether a participant earns completion XP and mission
// progress: a human who did not forfeit, made at least MinActions own
// rolls/moves, in a match that lasted at least MinMatchDuration.
func Eligible(rec *gameevents.MatchRecord, p *gameevents.Participant) bool {
	return EligibleWithin(rec, p, MinMatchDuration)
}

// EligibleWithin is Eligible with a configurable minimum match duration
// (Options.MinMatchDuration; production keeps the 30 s default).
func EligibleWithin(rec *gameevents.MatchRecord, p *gameevents.Participant, minDuration time.Duration) bool {
	if p.Bot || p.Forfeited || p.Actions < MinActions {
		return false
	}
	if rec.StartedAt.IsZero() || rec.FinishedAt.IsZero() {
		return false
	}
	return rec.FinishedAt.Sub(rec.StartedAt) >= minDuration
}

// RecordMatch implements gameevents.Recorder. Each eligible human is processed
// in its own transaction that first inserts the (user, match) receipt; if the
// receipt already exists nothing else happens, so a match counts exactly once
// per player even when delivered repeatedly or concurrently. It returns the
// first per-player error (the caller may retry the whole record safely).
func (s *Service) RecordMatch(ctx context.Context, rec gameevents.MatchRecord) error {
	if rec.MatchID == "" {
		return errors.New("progression: match id required")
	}
	humans := rec.Humans()
	if len(humans) == 0 {
		return nil // bot-only games produce nothing
	}
	at := rec.FinishedAt
	if at.IsZero() {
		at = s.now()
	}
	periods := s.missions.ActivePeriods(at)
	humanIDs := make([]uuid.UUID, 0, len(humans))
	for _, h := range humans {
		humanIDs = append(humanIDs, h.UserID)
	}

	var firstErr error
	seen := map[uuid.UUID]bool{}
	for i := range humans {
		p := &humans[i]
		if seen[p.UserID] || !EligibleWithin(&rec, p, s.minMatch) {
			continue
		}
		seen[p.UserID] = true
		out, err := s.recordPlayer(ctx, &rec, p, humanIDs, periods)
		if errors.Is(err, ErrUnknownUser) {
			// Not an account (e.g. a mislabelled bot seat): retrying cannot help.
			s.log.Warn("record match: participant has no account; skipped", "match", rec.MatchID)
			continue
		}
		if err != nil {
			s.log.Error("record match failed", "match", rec.MatchID, "error", err.Error())
			if firstErr == nil {
				firstErr = err
			}
			continue
		}
		if out == nil {
			continue // already processed
		}
		s.afterRecord(ctx, p.UserID, at, out)
	}

	s.mu.RLock()
	obs := append([]MatchObserver(nil), s.observers...)
	s.mu.RUnlock()
	for _, fn := range obs {
		fn(ctx, rec)
	}
	return firstErr
}

type matchOutcome struct {
	xp        xpResult
	gained    int64
	unlocked  []*Item
	missions  []MissionProgress
	completed []string // period kinds of newly completed missions
	firstWin  bool
}

func (s *Service) recordPlayer(ctx context.Context, rec *gameevents.MatchRecord, p *gameevents.Participant,
	humanIDs []uuid.UUID, periods []*Period) (*matchOutcome, error) {
	tx, err := s.pool.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		return nil, err
	}
	defer tx.Rollback(ctx) //nolint:errcheck

	oldXP, oldLevel, err := s.lockProgress(ctx, tx, p.UserID)
	if err != nil {
		return nil, err
	}
	tag, err := tx.Exec(ctx, `INSERT INTO progression.match_receipts (user_id, match_id) VALUES ($1, $2)
		ON CONFLICT (user_id, match_id) DO NOTHING`, p.UserID, rec.MatchID)
	if err != nil {
		return nil, err
	}
	if tag.RowsAffected() == 0 {
		return nil, nil // duplicate delivery: already counted
	}

	others := make([]uuid.UUID, 0, len(humanIDs))
	for _, id := range humanIDs {
		if id != p.UserID {
			others = append(others, id)
		}
	}
	withFriend := false
	if len(others) > 0 {
		if err := tx.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM progression.friendships
			WHERE status = 'accepted' AND ((user_lo = $1 AND user_hi = ANY($2)) OR (user_hi = $1 AND user_lo = ANY($2))))`,
			p.UserID, others).Scan(&withFriend); err != nil {
			return nil, err
		}
	}

	out := &matchOutcome{gained: XPMatchCompleted}
	if p.Won {
		out.gained += XPWinBonus
	}
	if withFriend {
		out.gained += XPFriendBonus
	}

	for _, per := range periods {
		for _, m := range per.Missions {
			if !m.counts(rec, p, withFriend) {
				continue
			}
			var value int
			err := tx.QueryRow(ctx, `
				INSERT INTO progression.mission_progress AS mp (user_id, period_key, mission_id, value)
				VALUES ($1, $2, $3, 1)
				ON CONFLICT (user_id, period_key, mission_id) DO UPDATE
				   SET value = LEAST(mp.value + 1, $4::int), updated_at = now()
				 WHERE mp.value < $4::int
				RETURNING value`, p.UserID, per.Key, m.ID, m.Target).Scan(&value)
			if errors.Is(err, pgx.ErrNoRows) {
				continue // already at target
			}
			if err != nil {
				return nil, err
			}
			done := value >= m.Target
			out.missions = append(out.missions, MissionProgress{ID: m.ID, Progress: value, Target: m.Target, Completed: done})
			if done {
				out.completed = append(out.completed, per.Kind)
			}
		}
	}

	if out.xp, err = s.addXPTx(ctx, tx, p.UserID, oldXP, oldLevel, out.gained); err != nil {
		return nil, err
	}
	out.unlocked = append(out.unlocked, out.xp.unlocked...)
	if p.Won {
		isNew, err := grantItemTx(ctx, tx, p.UserID, s.catalog.Get(FirstWinBadge))
		if err != nil {
			return nil, err
		}
		if isNew {
			out.firstWin = true
			out.unlocked = append(out.unlocked, s.catalog.Get(FirstWinBadge))
		}
	}
	if err := tx.Commit(ctx); err != nil {
		return nil, err
	}
	return out, nil
}

// afterRecord runs the post-commit effects of a first-time match record.
func (s *Service) afterRecord(ctx context.Context, userID uuid.UUID, at time.Time, out *matchOutcome) {
	if out.xp.level != out.xp.oldLevel {
		s.InvalidateSeat(ctx, userID)
	}
	s.cacheGranted(ctx, userID, out.unlocked)
	metrics.XPAwarded.WithLabelValues("match").Add(float64(out.gained))
	if n := out.xp.level - out.xp.oldLevel; n > 0 {
		metrics.LevelUps.WithLabelValues().Add(float64(n))
	}
	for _, kind := range out.completed {
		metrics.MissionsCompleted.WithLabelValues(kind).Inc()
	}
	if n := len(out.xp.unlocked); n > 0 {
		metrics.CosmeticUnlocks.WithLabelValues("level").Add(float64(n))
	}
	if out.firstWin {
		metrics.CosmeticUnlocks.WithLabelValues("first_win").Inc()
	}
	s.addWeeklyXP(ctx, userID, at, out.gained)
	missions := out.missions
	if missions == nil {
		missions = []MissionProgress{}
	}
	s.notify(ctx, userID, MsgProgressionUpdated, ProgressionUpdated{
		XP: out.xp.xp, Level: out.xp.level, XPGained: out.gained, LevelUp: out.xp.level > out.xp.oldLevel,
		Unlocked: itemIDs(out.unlocked), Missions: missions,
	})
}
