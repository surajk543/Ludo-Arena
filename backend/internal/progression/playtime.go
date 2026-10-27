package progression

// Daily playtime milestones (docs/progression.md → Daily playtime).
//
// The room engine reports intervals of qualifying active play
// (gameevents.Playtime, rooms/playtime.go). They are added up per account and
// UTC day (the daily mission period) in Redis and written to PostgreSQL in
// batches; every milestone reward is granted in one PostgreSQL transaction
// with its claim row.
//
// Storage (no table of its own):
//   - progression.mission_progress (user, dYYYY-MM-DD, "playtime"): the day's
//     seconds, only ever raised (GREATEST), written at most every
//     PLAYTIME_FLUSH_INTERVAL of new play, when a stretch of play ends and in
//     every grant transaction;
//   - progression.mission_claims (user, dYYYY-MM-DD, milestone id): one row
//     per granted milestone; its primary key makes each reward exactly-once
//     whatever Redis says;
//   - Redis pt:{userId}:{dayKey} (hash, TTL 48 h): "ms" (the day's
//     milliseconds), "fs" (seconds last written to PostgreSQL) and
//     "g:{milestoneId}" (granted, a hint). A missing key is seeded from
//     PostgreSQL, so a Redis restart loses at most the unflushed play
//     (< PLAYTIME_FLUSH_INTERVAL) and never re-grants a reward.

import (
	"context"
	"errors"
	"fmt"
	"regexp"
	"strconv"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/redis/go-redis/v9"

	"ludoarena/internal/gameevents"
	"ludoarena/internal/metrics"
	"ludoarena/internal/wallet"
)

// PlaytimeMissionID is the mission_progress row holding a day's seconds.
// Mission ids may not start with "playtime" (reserved).
const PlaytimeMissionID = "playtime"

// Milestone statuses (API PlaytimeMilestone.status).
const (
	PlaytimeCompleted  = "completed"
	PlaytimeInProgress = "in_progress"
	PlaytimeLocked     = "locked"
)

const (
	playtimeTTL      = 48 * time.Hour
	maxDaySeconds    = 24 * 60 * 60
	maxPlaytimeSteps = 8
	// DefaultPlaytimeFlush is the default PLAYTIME_FLUSH_INTERVAL.
	DefaultPlaytimeFlush = 2 * time.Minute
)

// MsgPlaytimeUpdated is the playtime.updated push.
const MsgPlaytimeUpdated = "playtime.updated"

var playtimeIDPattern = regexp.MustCompile(`^playtime_[a-z0-9_]{1,40}$`)

// PlaytimeMilestone is one configured daily playtime threshold.
type PlaytimeMilestone struct {
	ID      string `json:"id"`
	Minutes int    `json:"minutes"`
	Reward  Reward `json:"reward"`
}

// Seconds is the milestone threshold in seconds.
func (m *PlaytimeMilestone) Seconds() int64 { return int64(m.Minutes) * 60 }

// PlaytimeConfig is missions.json → "playtime". Enabled false (or no
// section) turns the feature off: nothing is counted or granted and
// `playtime` is null in GET /missions.
type PlaytimeConfig struct {
	Enabled    bool                 `json:"enabled"`
	Milestones []*PlaytimeMilestone `json:"milestones"`
}

// validatePlaytime checks the playtime section. missionIDs are the ids of
// every configured mission (a milestone id must not reuse one).
func validatePlaytime(c *PlaytimeConfig, missionIDs map[string]bool) []error {
	var errs []error
	bad := func(format string, args ...any) { errs = append(errs, fmt.Errorf(format, args...)) }
	if c.Enabled && len(c.Milestones) == 0 {
		bad("playtime: enabled needs at least one milestone")
	}
	if len(c.Milestones) > maxPlaytimeSteps {
		bad("playtime: at most %d milestones", maxPlaytimeSteps)
	}
	seen := map[string]bool{}
	prev := 0
	for i, m := range c.Milestones {
		if m == nil {
			bad("playtime.milestones[%d]: null milestone", i)
			continue
		}
		if !playtimeIDPattern.MatchString(m.ID) || seen[m.ID] || missionIDs[m.ID] {
			bad("playtime.milestones[%d]: invalid or duplicate id %q (playtime_…)", i, m.ID)
		}
		seen[m.ID] = true
		if m.Minutes < 1 || m.Minutes > 24*60 || m.Minutes <= prev {
			bad("playtime milestone %s: minutes must be 1..1440 and increasing", m.ID)
		}
		prev = m.Minutes
		r := m.Reward
		if r.Coins < 0 || r.Diamonds < 0 || r.XP < 0 || r.Coins > 1_000_000 || r.Diamonds > 1000 || r.XP > 10_000 {
			bad("playtime milestone %s: reward amounts out of range", m.ID)
		}
		if r.Coins+r.Diamonds+r.XP == 0 {
			bad("playtime milestone %s: reward must grant coins, diamonds or XP", m.ID)
		}
		if len(r.Items) > 0 {
			bad("playtime milestone %s: item rewards are not supported", m.ID)
		}
	}
	return errs
}

// PlaytimeEnabled reports whether daily playtime is counted.
func (s *Service) PlaytimeEnabled() bool {
	return s.missions.Playtime != nil && s.missions.Playtime.Enabled
}

func (s *Service) playtimeMilestones() []*PlaytimeMilestone {
	if !s.PlaytimeEnabled() {
		return nil
	}
	return s.missions.Playtime.Milestones
}

// PlaytimeKey is the Redis hash of an account's playtime on a day.
func PlaytimeKey(userID uuid.UUID, dayKey string) string {
	return "pt:" + userID.String() + ":" + dayKey
}

// ------------------------------------------------------------------- views

// PlaytimeMilestoneView is the API PlaytimeMilestone object.
type PlaytimeMilestoneView struct {
	ID      string     `json:"id"`
	Minutes int        `json:"minutes"`
	Reward  RewardView `json:"reward"`
	Status  string     `json:"status"`
}

// PlaytimeView is the API Playtime object (GET /playtime, GET /missions).
type PlaytimeView struct {
	PeriodKey   string                  `json:"periodKey"`
	ResetsAtUTC string                  `json:"resetsAtUtc"`
	Seconds     int64                   `json:"seconds"`
	Milestones  []PlaytimeMilestoneView `json:"milestones"`
}

// PlaytimeUpdated is the playtime.updated payload: the view plus the
// milestones this update granted.
type PlaytimeUpdated struct {
	PlaytimeView
	Granted []PlaytimeMilestoneView `json:"granted"`
}

func (s *Service) playtimeView(dayKey string, secs int64, granted map[string]bool) PlaytimeView {
	day, _ := time.Parse("2006-01-02", strings.TrimPrefix(dayKey, "d"))
	v := PlaytimeView{PeriodKey: dayKey, ResetsAtUTC: utc(day.AddDate(0, 0, 1)), Seconds: min(max(secs, 0), maxDaySeconds),
		Milestones: []PlaytimeMilestoneView{}}
	current := false
	for _, m := range s.playtimeMilestones() {
		st := PlaytimeLocked
		switch {
		case granted[m.ID]:
			st = PlaytimeCompleted
		case !current:
			st, current = PlaytimeInProgress, true
		}
		v.Milestones = append(v.Milestones, s.milestoneView(m, st))
	}
	return v
}

func (s *Service) milestoneView(m *PlaytimeMilestone, status string) PlaytimeMilestoneView {
	return PlaytimeMilestoneView{ID: m.ID, Minutes: m.Minutes, Reward: s.rewardView(m.Reward), Status: status}
}

// ------------------------------------------------------------ Redis state

// ptState is the Redis view of an account's day.
type ptState struct {
	ms      int64
	flushed int64 // seconds
	granted map[string]bool
}

func (st ptState) seconds() int64 { return min(st.ms/1000, maxDaySeconds) }

func parsePtState(vals []any) ptState {
	st := ptState{granted: map[string]bool{}}
	for i := 0; i+1 < len(vals); i += 2 {
		k, _ := vals[i].(string)
		v, _ := vals[i+1].(string)
		n, _ := strconv.ParseInt(v, 10, 64)
		switch {
		case k == "ms":
			st.ms = n
		case k == "fs":
			st.flushed = n
		case strings.HasPrefix(k, "g:"):
			st.granted[k[2:]] = true
		}
	}
	return st
}

// ptAdd adds milliseconds to an existing day hash and returns it (nil when
// the hash is missing: seed it first).
var ptAdd = redis.NewScript(`
if redis.call('EXISTS', KEYS[1]) == 0 then return false end
redis.call('HINCRBY', KEYS[1], 'ms', ARGV[1])
redis.call('PEXPIRE', KEYS[1], ARGV[2])
return redis.call('HGETALL', KEYS[1])`)

// ptSeed creates a missing day hash from PostgreSQL: ARGV ttl, ms, fs,
// granted milestone ids...
var ptSeed = redis.NewScript(`
if redis.call('EXISTS', KEYS[1]) == 1 then return 0 end
redis.call('HSET', KEYS[1], 'ms', ARGV[2], 'fs', ARGV[3])
for i = 4, #ARGV do redis.call('HSET', KEYS[1], 'g:' .. ARGV[i], '1') end
redis.call('PEXPIRE', KEYS[1], ARGV[1])
return 1`)

// ptMark records a PostgreSQL write: ARGV flushed seconds, granted ids...
var ptMark = redis.NewScript(`
if redis.call('EXISTS', KEYS[1]) == 0 then return 0 end
local fs = tonumber(redis.call('HGET', KEYS[1], 'fs') or '0')
if tonumber(ARGV[1]) > fs then redis.call('HSET', KEYS[1], 'fs', ARGV[1]) end
for i = 2, #ARGV do redis.call('HSET', KEYS[1], 'g:' .. ARGV[i], '1') end
return 1`)

// pgPlaytime reads an account's stored seconds and granted milestones of a day.
func (s *Service) pgPlaytime(ctx context.Context, q querier, userID uuid.UUID, dayKey string) (int64, map[string]bool, error) {
	ids := []string{PlaytimeMissionID}
	for _, m := range s.playtimeMilestones() {
		ids = append(ids, m.ID)
	}
	rows, err := q.Query(ctx, `
		SELECT mission_id, value, false FROM progression.mission_progress
		 WHERE user_id = $1 AND period_key = $2 AND mission_id = $3
		UNION ALL
		SELECT mission_id, 0, true FROM progression.mission_claims
		 WHERE user_id = $1 AND period_key = $2 AND mission_id = ANY($4)`,
		userID, dayKey, PlaytimeMissionID, ids)
	if err != nil {
		return 0, nil, err
	}
	defer rows.Close()
	var secs int64
	granted := map[string]bool{}
	for rows.Next() {
		var id string
		var v int64
		var claim bool
		if err := rows.Scan(&id, &v, &claim); err != nil {
			return 0, nil, err
		}
		if claim {
			granted[id] = true
		} else {
			secs = v
		}
	}
	return secs, granted, rows.Err()
}

// seed creates the Redis day hash from PostgreSQL when it is missing.
func (s *Service) seed(ctx context.Context, userID uuid.UUID, dayKey string) error {
	secs, granted, err := s.pgPlaytime(ctx, s.pool, userID, dayKey)
	if err != nil {
		return err
	}
	args := []any{playtimeTTL.Milliseconds(), secs * 1000, secs}
	for id := range granted {
		args = append(args, id)
	}
	return ptSeed.Run(ctx, s.rdb, []string{PlaytimeKey(userID, dayKey)}, args...).Err()
}

// accrue adds ms to the account's day in Redis (seeding it when missing).
func (s *Service) accrue(ctx context.Context, userID uuid.UUID, dayKey string, ms int64) (ptState, error) {
	key := []string{PlaytimeKey(userID, dayKey)}
	for attempt := 0; attempt < 2; attempt++ {
		vals, err := ptAdd.Run(ctx, s.rdb, key, ms, playtimeTTL.Milliseconds()).Slice()
		if err == nil {
			return parsePtState(vals), nil
		}
		if !errors.Is(err, redis.Nil) {
			return ptState{}, err
		}
		if err := s.seed(ctx, userID, dayKey); err != nil {
			metrics.PlaytimeErrors.WithLabelValues("seed").Inc()
			return ptState{}, err
		}
	}
	return ptState{}, errors.New("playtime: day hash missing after seeding")
}

func (s *Service) mark(ctx context.Context, userID uuid.UUID, dayKey string, secs int64, granted []string) {
	if s.rdb == nil {
		return
	}
	args := []any{secs}
	for _, id := range granted {
		args = append(args, id)
	}
	if err := ptMark.Run(context.WithoutCancel(ctx), s.rdb, []string{PlaytimeKey(userID, dayKey)}, args...).Err(); err != nil {
		// Harmless: the hint is only an optimization; PostgreSQL decides.
		metrics.CacheWriteErrors.WithLabelValues("playtime", "mark").Inc()
	}
}

// --------------------------------------------------------------- accrual

var _ gameevents.Playtime = (*Service)(nil)

// AddPlaytime implements gameevents.Playtime. The work runs in the
// background (the room engine calls it right after a commit); Run waits for
// it on shutdown.
func (s *Service) AddPlaytime(ctx context.Context, userID uuid.UUID, from, to time.Time, final bool) {
	if !s.PlaytimeEnabled() || s.rdb == nil || !to.After(from) {
		return
	}
	s.ptWG.Add(1)
	go func() {
		defer s.ptWG.Done()
		ctx, cancel := context.WithTimeout(context.WithoutCancel(ctx), 10*time.Second)
		defer cancel()
		s.RecordPlaytime(ctx, userID, from, to, final)
	}()
}

// daySpans splits [from, to) at UTC midnights.
func daySpans(from, to time.Time) [][2]time.Time {
	var out [][2]time.Time
	for from.Before(to) {
		end := DayStart(from).AddDate(0, 0, 1)
		if end.After(to) {
			end = to
		}
		out = append(out, [2]time.Time{from, end})
		from = end
	}
	return out
}

// RecordPlaytime credits [from, to) synchronously: each UTC day's part is
// added in Redis; reached milestones are granted (with a PostgreSQL write of
// the day's seconds), otherwise the seconds are written when enough unsaved
// play built up or a stretch ended (final). The current day's progress is
// pushed as playtime.updated.
func (s *Service) RecordPlaytime(ctx context.Context, userID uuid.UUID, from, to time.Time, final bool) {
	if !s.PlaytimeEnabled() || s.rdb == nil {
		return
	}
	today := DayKey(s.now())
	for _, span := range daySpans(from.UTC(), to.UTC()) {
		dayKey := DayKey(span[0])
		ms := span[1].Sub(span[0]).Milliseconds()
		if ms <= 0 {
			continue
		}
		st, err := s.accrue(ctx, userID, dayKey, ms)
		if err != nil {
			metrics.PlaytimeErrors.WithLabelValues("accrue").Inc()
			s.log.Warn("playtime accrual failed; interval dropped", "error", err.Error())
			continue
		}
		metrics.PlaytimeCredited.Add(float64(ms) / 1000)
		secs := st.seconds()
		var granted []*PlaytimeMilestone
		endOfDay := dayKey != DayKey(to.UTC())
		switch {
		case s.due(secs, st.granted):
			granted, st.granted, err = s.grantPlaytime(ctx, userID, dayKey, secs)
			if err != nil {
				if !errors.Is(err, ErrUnknownUser) {
					metrics.PlaytimeErrors.WithLabelValues("grant").Inc()
					s.log.Error("playtime reward grant failed; retried on the next credit or read", "error", err.Error())
				}
				continue
			}
		case secs-st.flushed >= int64(s.ptFlush.Seconds()) || ((final || endOfDay) && secs > st.flushed):
			if err := s.flushPlaytime(ctx, userID, dayKey, secs); err != nil {
				metrics.PlaytimeErrors.WithLabelValues("flush").Inc()
				s.log.Warn("playtime flush failed; kept in Redis", "error", err.Error())
			}
		}
		if dayKey != today {
			continue // a finished day: its grant was announced by wallet/progression pushes
		}
		msg := PlaytimeUpdated{PlaytimeView: s.playtimeView(dayKey, secs, st.granted), Granted: []PlaytimeMilestoneView{}}
		for _, m := range granted {
			msg.Granted = append(msg.Granted, s.milestoneView(m, PlaytimeCompleted))
		}
		s.notify(ctx, userID, MsgPlaytimeUpdated, msg)
	}
}

// due reports whether a reached milestone is not granted yet (per the hint).
func (s *Service) due(secs int64, granted map[string]bool) bool {
	for _, m := range s.playtimeMilestones() {
		if secs >= m.Seconds() && !granted[m.ID] {
			return true
		}
	}
	return false
}

// upsertPlaytime raises an account's stored seconds of a day (never lowers
// them) and returns the stored value. Bot wallets never get rows.
const upsertPlaytime = `
	INSERT INTO progression.mission_progress AS mp (user_id, period_key, mission_id, value)
	SELECT w.user_id, $2, $3, $4 FROM wallet.wallets w WHERE w.user_id = $1 AND NOT w.is_bot
	ON CONFLICT (user_id, period_key, mission_id) DO UPDATE
	   SET value = GREATEST(mp.value, EXCLUDED.value), updated_at = now()
	RETURNING value`

// flushPlaytime writes a day's seconds to PostgreSQL.
func (s *Service) flushPlaytime(ctx context.Context, userID uuid.UUID, dayKey string, secs int64) error {
	var stored int64
	err := s.pool.QueryRow(ctx, upsertPlaytime, userID, dayKey, PlaytimeMissionID, secs).Scan(&stored)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil // not an account (deleted meanwhile)
	}
	if err != nil {
		return err
	}
	s.mark(ctx, userID, dayKey, stored, nil)
	return nil
}

// grantPlaytime grants every reached milestone of a day exactly once, in one
// transaction: the day's seconds (raised to secs), one claim row per new
// milestone (the primary key rejects a second grant, whatever Redis said),
// the wallet credit and the XP. It returns the milestones granted now and
// every granted milestone of the day.
func (s *Service) grantPlaytime(ctx context.Context, userID uuid.UUID, dayKey string, secs int64) ([]*PlaytimeMilestone, map[string]bool, error) {
	tx, err := s.pool.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		return nil, nil, err
	}
	defer tx.Rollback(ctx) //nolint:errcheck

	oldXP, oldLevel, err := s.lockProgress(ctx, tx, userID)
	if err != nil {
		return nil, nil, err
	}
	var stored int64
	if err := tx.QueryRow(ctx, upsertPlaytime, userID, dayKey, PlaytimeMissionID, secs).Scan(&stored); err != nil {
		return nil, nil, mapFK(err)
	}
	var granted []*PlaytimeMilestone
	var reward Reward
	for _, m := range s.playtimeMilestones() {
		if stored < m.Seconds() {
			break
		}
		tag, err := tx.Exec(ctx, `INSERT INTO progression.mission_claims (user_id, period_key, mission_id) VALUES ($1, $2, $3)
			ON CONFLICT (user_id, period_key, mission_id) DO NOTHING`, userID, dayKey, m.ID)
		if err != nil {
			return nil, nil, err
		}
		if tag.RowsAffected() == 1 {
			granted = append(granted, m)
			reward.Coins += m.Reward.Coins
			reward.Diamonds += m.Reward.Diamonds
			reward.XP += m.Reward.XP
		}
	}
	_, all, err := s.pgPlaytime(ctx, tx, userID, dayKey)
	if err != nil {
		return nil, nil, err
	}
	var wal wallet.Wallet
	if reward.Coins != 0 || reward.Diamonds != 0 {
		if wal, err = wallet.AdjustTx(ctx, tx, userID, reward.Coins, reward.Diamonds); err != nil {
			return nil, nil, err
		}
	}
	xr, err := s.addXPTx(ctx, tx, userID, oldXP, oldLevel, reward.XP)
	if err != nil {
		return nil, nil, err
	}
	if err := tx.Commit(ctx); err != nil {
		return nil, nil, err
	}

	ids := make([]string, 0, len(all))
	for id := range all {
		ids = append(ids, id)
	}
	s.mark(ctx, userID, dayKey, stored, ids)
	if len(granted) == 0 {
		return nil, all, nil
	}
	// Post-commit effects (as for a mission claim).
	if xr.level != xr.oldLevel {
		s.InvalidateSeat(ctx, userID)
	}
	s.cacheGranted(ctx, userID, xr.unlocked)
	for _, m := range granted {
		metrics.PlaytimeMilestones.WithLabelValues(strconv.Itoa(m.Minutes)).Inc()
	}
	if reward.XP > 0 {
		metrics.XPAwarded.WithLabelValues("playtime").Add(float64(reward.XP))
	}
	if n := xr.level - xr.oldLevel; n > 0 {
		metrics.LevelUps.WithLabelValues().Add(float64(n))
	}
	if len(xr.unlocked) > 0 {
		metrics.CosmeticUnlocks.WithLabelValues("level").Add(float64(len(xr.unlocked)))
	}
	s.addWeeklyXP(ctx, userID, s.now(), reward.XP)
	if reward.Coins != 0 || reward.Diamonds != 0 {
		s.notify(ctx, userID, MsgWalletUpdated, WalletUpdated{Coins: wal.Coins, Diamonds: wal.Diamonds,
			Delta: WalletDelta{Coins: reward.Coins, Diamonds: reward.Diamonds}, Reason: "playtime"})
	}
	if reward.XP > 0 || len(xr.unlocked) > 0 {
		s.notify(ctx, userID, MsgProgressionUpdated, ProgressionUpdated{XP: xr.xp, Level: xr.level, XPGained: reward.XP,
			LevelUp: xr.level > xr.oldLevel, Unlocked: itemIDs(xr.unlocked), Missions: []MissionProgress{}})
	}
	return granted, all, nil
}

// ------------------------------------------------------------------- reads

// Playtime returns today's playtime of an account (nil while the feature is
// disabled). PostgreSQL decides which milestones are completed; a reached
// milestone whose grant failed earlier is granted now.
func (s *Service) Playtime(ctx context.Context, userID uuid.UUID) (*PlaytimeView, error) {
	if !s.PlaytimeEnabled() {
		return nil, nil
	}
	dayKey := DayKey(s.now())
	secs, granted, err := s.pgPlaytime(ctx, s.pool, userID, dayKey)
	if err != nil {
		return nil, err
	}
	if s.rdb != nil {
		vals, err := s.rdb.HGetAll(ctx, PlaytimeKey(userID, dayKey)).Result()
		switch {
		case err != nil:
			s.log.Warn("playtime cache unavailable; reading PostgreSQL", "error", err.Error())
		case len(vals) == 0:
			if err := s.seed(ctx, userID, dayKey); err != nil {
				metrics.PlaytimeErrors.WithLabelValues("seed").Inc()
			}
		default:
			if ms, _ := strconv.ParseInt(vals["ms"], 10, 64); ms/1000 > secs {
				secs = min(ms/1000, maxDaySeconds)
			}
		}
	}
	if s.due(secs, granted) {
		if _, all, err := s.grantPlaytime(ctx, userID, dayKey, secs); err == nil {
			granted = all
		} else if !errors.Is(err, ErrUnknownUser) {
			metrics.PlaytimeErrors.WithLabelValues("grant").Inc()
			s.log.Error("playtime reward grant failed on read", "error", err.Error())
		}
	}
	v := s.playtimeView(dayKey, secs, granted)
	return &v, nil
}
