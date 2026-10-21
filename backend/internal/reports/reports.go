// Package reports lets a human report another player they shared a room with
// (from the in-game player pod) and shows the reporter the review status of
// their own reports. Operators review reports through a key-protected admin
// API.
//
// Storage: progression.player_reports (migrations/006_player_reports.sql and
// 009_report_bots.sql; this package is the only reader and writer). Rooms are
// read from Redis to verify that both players hold a seat. Responses to
// players never contain account ids, reporter ids or operator notes.
//
// Bots: a bot seat is reported exactly like a person from the reporter's side
// (same checks, limits, response and "my reports" entry), so the app never
// reveals which opponents are bots. Bots are not accounts: the row stores the
// bot's per-session id with reported_bot = true and a copy of its public
// profile (reported_profile), which "my reports" shows. The operator queue
// leaves bot reports out.
//
// Limits (per reporter, rolling 24 h window): at most Options.PerDay reports
// (REPORTS_PER_DAY, default 2) and at most one report per reported player.
// Both are checked and the row inserted in one transaction that holds a
// per-reporter advisory lock, so concurrent requests cannot exceed them.
package reports

import (
	"context"
	"errors"
	"hash/fnv"
	"log/slog"
	"regexp"
	"slices"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"ludoroyale/internal/metrics"
	"ludoroyale/internal/playerinfo"
	"ludoroyale/internal/profile"
	"ludoroyale/internal/progression"
)

// Report reasons.
const (
	ReasonCheating          = "cheating"
	ReasonOffensiveName     = "offensive_name"
	ReasonAbusiveBehavior   = "abusive_behavior"
	ReasonLeavingOrStalling = "leaving_or_stalling"
	ReasonOther             = "other"
)

// Reasons lists every accepted reason.
var Reasons = []string{ReasonCheating, ReasonOffensiveName, ReasonAbusiveBehavior, ReasonLeavingOrStalling, ReasonOther}

// Review statuses.
const (
	StatusSubmitted   = "submitted"
	StatusReviewing   = "reviewing"
	StatusActionTaken = "action_taken"
	StatusDismissed   = "dismissed"
)

// Statuses lists every review status.
var Statuses = []string{StatusSubmitted, StatusReviewing, StatusActionTaken, StatusDismissed}

// Window is the rolling period of the daily limit and the duplicate rule.
const Window = 24 * time.Hour

// Limits of the list endpoints and operator notes.
const (
	MyReportsLimit    = 100
	AdminDefaultLimit = 50
	AdminMaxLimit     = 200
	MaxNoteLength     = 1000
)

// ValidReason reports whether r is a known reason.
func ValidReason(r string) bool { return slices.Contains(Reasons, r) }

// ValidStatus reports whether s is a known review status.
func ValidStatus(s string) bool { return slices.Contains(Statuses, s) }

var (
	uidPattern  = regexp.MustCompile(`^[a-z0-9_]{3,40}$`)
	roomPattern = regexp.MustCompile(`^r_[a-z0-9]{1,40}$`)
)

// Errors.
var (
	ErrInvalid         = errors.New("invalid report")
	ErrUnknownPlayer   = errors.New("unknown player")
	ErrRoomGone        = errors.New("room not found")
	ErrSelf            = errors.New("cannot report yourself")
	ErrNotInRoom       = errors.New("both players must hold a seat in the room")
	ErrAlreadyReported = errors.New("player already reported in the last 24 hours")
	ErrNotFound        = errors.New("report not found")
)

// LimitError is returned when the reporter used every report of the window.
type LimitError struct {
	Limit Limit
	Retry time.Duration
}

func (e *LimitError) Error() string { return "daily report limit reached" }

// Seat is a room seat as seen by the report checks.
type Seat struct {
	UserID string // internal id (a per-session UUID for bots)
	UID    string // public id
	Bot    bool
	// Public profile shown in the room; stored with a report against a bot.
	Name    string
	Avatar  int
	Picture *playerinfo.Picture
	Level   int
}

// RoomInfo is the part of a live room that reports need.
type RoomInfo struct {
	Game  string
	Seats []Seat // every seat, forfeited players included
}

// RoomLookup returns a live room or ErrRoomGone.
type RoomLookup func(ctx context.Context, roomID string) (RoomInfo, error)

// Players resolves public ids and levels (implemented by *progression.Service).
type Players interface {
	playerinfo.Provider
	ResolvePublicID(ctx context.Context, uid string) (uuid.UUID, error)
}

// Options configure the service.
type Options struct {
	PerDay int // reports per rolling 24 h (default 2)
	// AdminKeySHA256 is sha256(X-Admin-Key); empty disables the admin API.
	AdminKeySHA256 []byte
	Now            func() time.Time // default time.Now
}

// Service implements player reports.
type Service struct {
	pool     *pgxpool.Pool
	profiles *profile.Service
	players  Players
	rooms    RoomLookup
	log      *slog.Logger
	opts     Options
}

// New returns the reports service.
func New(pool *pgxpool.Pool, profiles *profile.Service, players Players, rooms RoomLookup, log *slog.Logger, opts Options) *Service {
	if opts.PerDay <= 0 {
		opts.PerDay = 2
	}
	if opts.Now == nil {
		opts.Now = time.Now
	}
	if log == nil {
		log = slog.Default()
	}
	return &Service{pool: pool, profiles: profiles, players: players, rooms: rooms, log: log, opts: opts}
}

// PlayerRef is the public profile of the reported player.
type PlayerRef struct {
	UID     string              `json:"uid"`
	Name    string              `json:"name"`
	Avatar  int                 `json:"avatar"`
	Picture *playerinfo.Picture `json:"picture"`
	Level   int                 `json:"level"`
}

// Report is what the reporter sees about one of their reports.
type Report struct {
	ID        string    `json:"id"`
	Player    PlayerRef `json:"player"`
	Reason    string    `json:"reason"`
	Game      string    `json:"game"`
	RoomID    string    `json:"roomId"`
	Status    string    `json:"status"`
	CreatedAt int64     `json:"createdAt"`
	UpdatedAt int64     `json:"updatedAt"`
}

// Limit is the reporter's remaining allowance in the rolling window.
type Limit struct {
	PerDay    int `json:"perDay"`
	Remaining int `json:"remaining"`
	// ResetsAt is when Remaining next increases (the oldest counted report
	// leaves the window), unix ms; nil when no report is counted.
	ResetsAt *int64 `json:"resetsAt"`
}

// prior is a report already filed by the reporter inside the window.
type prior struct {
	reported uuid.UUID
	at       time.Time
}

// limitOf computes the allowance from the reports of the window (any order).
func limitOf(now time.Time, perDay int, recent []prior) Limit {
	times := make([]time.Time, 0, len(recent))
	for _, p := range recent {
		if p.at.After(now.Add(-Window)) {
			times = append(times, p.at)
		}
	}
	slices.SortFunc(times, func(a, b time.Time) int { return a.Compare(b) })
	l := Limit{PerDay: perDay, Remaining: max(0, perDay-len(times))}
	if len(times) > 0 {
		// With more reports than perDay (the limit was lowered), a slot frees
		// only when enough of the oldest ones have left the window.
		at := times[max(0, len(times)-perDay)].Add(Window).UnixMilli()
		l.ResetsAt = &at
	}
	return l
}

// decide applies, in order, the duplicate rule and the daily limit to a new
// report of target given the reporter's reports inside the window.
func decide(now time.Time, perDay int, recent []prior, target uuid.UUID) error {
	cutoff := now.Add(-Window)
	for _, p := range recent {
		if p.reported == target && p.at.After(cutoff) {
			return ErrAlreadyReported
		}
	}
	l := limitOf(now, perDay, recent)
	if l.Remaining > 0 {
		return nil
	}
	retry := time.Millisecond
	if l.ResetsAt != nil {
		retry = max(time.UnixMilli(*l.ResetsAt).Sub(now), time.Millisecond)
	}
	return &LimitError{Limit: l, Retry: retry}
}

// CreateInput is the POST /reports body.
type CreateInput struct {
	UID    string `json:"uid"`
	RoomID string `json:"roomId"`
	Reason string `json:"reason"`
}

// normalize validates the input shape (400 on failure).
func (in *CreateInput) normalize() error {
	in.UID = strings.ToLower(strings.TrimSpace(in.UID))
	in.RoomID = strings.TrimSpace(in.RoomID)
	if !ValidReason(in.Reason) || !uidPattern.MatchString(in.UID) || !roomPattern.MatchString(in.RoomID) {
		return ErrInvalid
	}
	return nil
}

func reasonLabel(r string) string {
	if ValidReason(r) {
		return r
	}
	return "invalid"
}

func resultLabel(err error) string {
	var le *LimitError
	switch {
	case err == nil:
		return "created"
	case errors.As(err, &le):
		return "report_limit"
	case errors.Is(err, ErrAlreadyReported):
		return "already_reported"
	case errors.Is(err, ErrSelf):
		return "cannot_report_self"
	case errors.Is(err, ErrNotInRoom):
		return "not_in_room"
	case errors.Is(err, ErrUnknownPlayer):
		return "not_found"
	case errors.Is(err, ErrRoomGone):
		return "room_not_found"
	case errors.Is(err, ErrInvalid):
		return "bad_request"
	}
	return "error"
}

// Create files a report by me against the player uid of room roomId.
func (s *Service) Create(ctx context.Context, me uuid.UUID, in CreateInput) (rep Report, lim Limit, err error) {
	defer func() { metrics.PlayerReports.WithLabelValues(reasonLabel(in.Reason), resultLabel(err)).Inc() }()
	if err := in.normalize(); err != nil {
		return Report{}, Limit{}, err
	}
	if in.UID == s.profiles.PublicID(me) {
		return Report{}, Limit{}, ErrSelf
	}
	target, game, bot, err := s.seats(ctx, me, in.UID, in.RoomID)
	if err != nil {
		return Report{}, Limit{}, err
	}
	now := s.opts.Now().UTC()

	tx, err := s.pool.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		return Report{}, Limit{}, err
	}
	defer tx.Rollback(ctx) //nolint:errcheck
	// Serialize every report by this reporter (all instances): the window
	// read, both checks and the insert happen under the lock.
	if _, err := tx.Exec(ctx, `SELECT pg_advisory_xact_lock($1::int, $2::int)`, lockClass, lockKey(me)); err != nil {
		return Report{}, Limit{}, err
	}
	recent, err := window(ctx, tx, me, now)
	if err != nil {
		return Report{}, Limit{}, err
	}
	if err := decide(now, s.opts.PerDay, recent, target); err != nil {
		return Report{}, Limit{}, err
	}
	id := uuid.New()
	_, err = tx.Exec(ctx, `INSERT INTO progression.player_reports
		(id, reporter_id, reported_id, reason, room_id, game, status, created_at, updated_at, reported_bot, reported_profile)
		VALUES ($1, $2, $3, $4, $5, $6, 'submitted', $7, $7, $8, $9)`,
		id, me, target, in.Reason, in.RoomID, game, now, bot != nil, bot)
	if err != nil {
		return Report{}, Limit{}, err
	}
	if err := tx.Commit(ctx); err != nil {
		return Report{}, Limit{}, err
	}
	s.log.Info("player report filed", "report", id.String(), "reason", in.Reason, "game", game, "bot", bot != nil)
	rows := []row{{id: id, reported: target, reason: in.Reason, game: game, roomID: in.RoomID,
		status: StatusSubmitted, created: now, updated: now, bot: bot}}
	out, err := s.render(ctx, rows)
	if err != nil {
		return Report{}, Limit{}, err
	}
	return out[0], limitOf(now, s.opts.PerDay, append(recent, prior{reported: target, at: now})), nil
}

// seats verifies that me and the player uid both hold a seat in roomID and
// returns the reported id (an account, or a bot's per-session id), the room's
// game and, for a bot, the public profile to store with the report.
func (s *Service) seats(ctx context.Context, me uuid.UUID, uid, roomID string) (uuid.UUID, string, *PlayerRef, error) {
	room, err := s.rooms(ctx, roomID)
	if err != nil {
		return uuid.Nil, "", nil, err
	}
	mine, theirs := false, -1
	for i, seat := range room.Seats {
		if !seat.Bot && seat.UserID == me.String() {
			mine = true
		}
		if strings.EqualFold(seat.UID, uid) {
			theirs = i
		}
	}
	var target uuid.UUID
	var bot *PlayerRef
	if theirs >= 0 {
		seat := room.Seats[theirs]
		id, perr := uuid.Parse(seat.UserID)
		if perr != nil {
			return uuid.Nil, "", nil, ErrUnknownPlayer
		}
		target = id
		if seat.Bot {
			bot = &PlayerRef{UID: seat.UID, Name: seat.Name, Avatar: seat.Avatar, Picture: seat.Picture,
				Level: max(seat.Level, 1)}
		}
	}
	if !mine {
		return uuid.Nil, "", nil, ErrNotInRoom
	}
	if theirs >= 0 {
		if target == me {
			return uuid.Nil, "", nil, ErrSelf
		}
		return target, room.Game, bot, nil
	}
	// Not seated: distinguish an unknown uid (404) from a stranger (422).
	if _, err := s.players.ResolvePublicID(ctx, uid); err != nil {
		if errors.Is(err, progression.ErrUnknownPlayer) {
			return uuid.Nil, "", nil, ErrUnknownPlayer
		}
		return uuid.Nil, "", nil, err
	}
	return uuid.Nil, "", nil, ErrNotInRoom
}

// lockClass namespaces the per-reporter advisory locks ("RPRT").
const lockClass int32 = 0x52505254

func lockKey(id uuid.UUID) int32 {
	h := fnv.New32a()
	h.Write(id[:])
	return int32(h.Sum32())
}

type querier interface {
	Query(ctx context.Context, sql string, args ...any) (pgx.Rows, error)
}

// window returns the reporter's reports of the rolling window.
func window(ctx context.Context, q querier, me uuid.UUID, now time.Time) ([]prior, error) {
	rows, err := q.Query(ctx, `SELECT reported_id, created_at FROM progression.player_reports
		WHERE reporter_id = $1 AND created_at > $2 ORDER BY created_at`, me, now.Add(-Window))
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []prior
	for rows.Next() {
		var p prior
		if err := rows.Scan(&p.reported, &p.at); err != nil {
			return nil, err
		}
		out = append(out, p)
	}
	return out, rows.Err()
}

type row struct {
	id                uuid.UUID
	reporter          uuid.UUID
	reported          uuid.UUID
	reason, game      string
	roomID, status    string
	note              *string
	created, updated  time.Time
	total, open, hits int
	// bot is the stored public profile of a reported bot (nil: an account).
	bot *PlayerRef
}

// accountIDs returns the distinct reported accounts of rows (bots excluded).
func accountIDs(rows []row) []uuid.UUID {
	ids := make([]uuid.UUID, 0, len(rows))
	seen := map[uuid.UUID]bool{}
	for _, r := range rows {
		if r.bot == nil && !seen[r.reported] {
			seen[r.reported] = true
			ids = append(ids, r.reported)
		}
	}
	return ids
}

// render turns rows into reporter-facing reports (public profile only): an
// account's live profile, or the profile stored with a report against a bot.
func (s *Service) render(ctx context.Context, rows []row) ([]Report, error) {
	out := make([]Report, 0, len(rows))
	if len(rows) == 0 {
		return out, nil
	}
	ids := accountIDs(rows)
	profs := s.profiles.GetMany(ctx, ids)
	sums, err := s.players.Summaries(ctx, ids)
	if err != nil {
		return nil, err
	}
	for _, r := range rows {
		var player PlayerRef
		if r.bot != nil {
			player = *r.bot
		} else {
			p := profs[r.reported]
			player = PlayerRef{UID: p.UID, Name: p.Name, Avatar: p.Avatar, Picture: sums[r.reported].Picture,
				Level: sums[r.reported].Level}
		}
		out = append(out, Report{ID: r.id.String(), Player: player,
			Reason: r.reason, Game: r.game, RoomID: r.roomID, Status: r.status,
			CreatedAt: r.created.UnixMilli(), UpdatedAt: r.updated.UnixMilli()})
	}
	return out, nil
}

// Mine lists my reports (newest first, at most 100) and my allowance.
func (s *Service) Mine(ctx context.Context, me uuid.UUID) ([]Report, Limit, error) {
	now := s.opts.Now().UTC()
	rows, err := s.pool.Query(ctx, `SELECT id, reported_id, reason, game, room_id, status, created_at, updated_at,
		       CASE WHEN reported_bot THEN reported_profile END
		  FROM progression.player_reports WHERE reporter_id = $1
		 ORDER BY created_at DESC, id DESC LIMIT $2`, me, MyReportsLimit)
	if err != nil {
		return nil, Limit{}, err
	}
	var list []row
	for rows.Next() {
		var r row
		if err := rows.Scan(&r.id, &r.reported, &r.reason, &r.game, &r.roomID, &r.status, &r.created, &r.updated, &r.bot); err != nil {
			rows.Close()
			return nil, Limit{}, err
		}
		list = append(list, r)
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return nil, Limit{}, err
	}
	recent, err := window(ctx, s.pool, me, now)
	if err != nil {
		return nil, Limit{}, err
	}
	out, err := s.render(ctx, list)
	if err != nil {
		return nil, Limit{}, err
	}
	return out, limitOf(now, s.opts.PerDay, recent), nil
}

// ------------------------------------------------------------------ admin

// AdminPlayer identifies a player to operators (public id and name only).
type AdminPlayer struct {
	UID  string `json:"uid"`
	Name string `json:"name"`
}

// ReportedStats counts every report against the reported player.
type ReportedStats struct {
	Total     int `json:"total"`     // all reports
	Open      int `json:"open"`      // submitted + reviewing
	Reporters int `json:"reporters"` // distinct reporters
}

// AdminReport is the operator view of a report.
type AdminReport struct {
	ID            string        `json:"id"`
	Reporter      AdminPlayer   `json:"reporter"`
	Reported      AdminPlayer   `json:"reported"`
	Reason        string        `json:"reason"`
	RoomID        string        `json:"roomId"`
	Game          string        `json:"game"`
	Status        string        `json:"status"`
	Note          *string       `json:"note"`
	CreatedAt     int64         `json:"createdAt"`
	UpdatedAt     int64         `json:"updatedAt"`
	ReportedStats ReportedStats `json:"reportedStats"`
}

// AdminEnabled reports whether the admin API is configured.
func (s *Service) AdminEnabled() bool { return len(s.opts.AdminKeySHA256) == 32 }

const adminSelect = `
	SELECT p.id, p.reporter_id, p.reported_id, p.reason, p.game, p.room_id, p.status, p.note,
	       p.created_at, p.updated_at, st.total, st.open, st.reporters
	  FROM page p
	  CROSS JOIN LATERAL (
	        SELECT count(*)::int AS total,
	               (count(*) FILTER (WHERE r.status IN ('submitted', 'reviewing')))::int AS open,
	               count(DISTINCT r.reporter_id)::int AS reporters
	          FROM progression.player_reports r WHERE r.reported_id = p.reported_id) st
	 ORDER BY p.created_at DESC, p.id DESC`

func (s *Service) adminRows(ctx context.Context, sql string, args ...any) ([]AdminReport, error) {
	rows, err := s.pool.Query(ctx, sql, args...)
	if err != nil {
		return nil, err
	}
	var list []row
	for rows.Next() {
		var r row
		if err := rows.Scan(&r.id, &r.reporter, &r.reported, &r.reason, &r.game, &r.roomID, &r.status, &r.note,
			&r.created, &r.updated, &r.total, &r.open, &r.hits); err != nil {
			rows.Close()
			return nil, err
		}
		list = append(list, r)
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return nil, err
	}
	var ids []uuid.UUID
	for _, r := range list {
		ids = append(ids, r.reporter, r.reported)
	}
	profs := s.profiles.GetMany(ctx, ids)
	out := make([]AdminReport, 0, len(list))
	for _, r := range list {
		rep, red := profs[r.reporter], profs[r.reported]
		out = append(out, AdminReport{ID: r.id.String(),
			Reporter: AdminPlayer{UID: rep.UID, Name: rep.Name}, Reported: AdminPlayer{UID: red.UID, Name: red.Name},
			Reason: r.reason, RoomID: r.roomID, Game: r.game, Status: r.status, Note: r.note,
			CreatedAt: r.created.UnixMilli(), UpdatedAt: r.updated.UnixMilli(),
			ReportedStats: ReportedStats{Total: r.total, Open: r.open, Reporters: r.hits}})
	}
	return out, nil
}

// AdminList lists reports newest first, optionally filtered by status.
// Reports against bots are not part of the queue (nothing to review).
func (s *Service) AdminList(ctx context.Context, status string, limit int) ([]AdminReport, error) {
	return s.adminRows(ctx, `WITH page AS (
		SELECT * FROM progression.player_reports WHERE NOT reported_bot AND ($1 = '' OR status = $1)
		 ORDER BY created_at DESC, id DESC LIMIT $2)`+adminSelect, status, limit)
}

// AdminUpdate changes a report's status and/or operator note ("" clears the
// note). Nil arguments leave the field unchanged. Reports against bots are not
// in the queue and answer ErrNotFound.
func (s *Service) AdminUpdate(ctx context.Context, id uuid.UUID, status, note *string) (AdminReport, error) {
	var noteArg *string
	if note != nil && *note != "" {
		noteArg = note
	}
	tag, err := s.pool.Exec(ctx, `UPDATE progression.player_reports
		   SET status = COALESCE($2, status),
		       note = CASE WHEN $3 THEN $4 ELSE note END,
		       updated_at = $5
		 WHERE id = $1 AND NOT reported_bot`, id, status, note != nil, noteArg, s.opts.Now().UTC())
	if err != nil {
		return AdminReport{}, err
	}
	if tag.RowsAffected() == 0 {
		return AdminReport{}, ErrNotFound
	}
	// Read back after the update so the per-player counts include it.
	out, err := s.adminRows(ctx, `WITH page AS (
		SELECT * FROM progression.player_reports WHERE id = $1 AND NOT reported_bot)`+adminSelect, id)
	if err != nil {
		return AdminReport{}, err
	}
	if len(out) == 0 {
		return AdminReport{}, ErrNotFound
	}
	s.log.Info("player report reviewed", "report", id.String(), "status", out[0].Status, "note_changed", note != nil)
	return out[0], nil
}
