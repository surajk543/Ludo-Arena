// Package account deletes an account and everything tied to it
// (DELETE /api/v1/account; docs/authentication.md "Deleting an account").
//
// Order of a deletion:
//
//  1. The account leaves its active room the way room.leave does (a game in
//     progress is forfeited and goes on for the others), while the account
//     still exists.
//  2. One PostgreSQL transaction deletes every row of the account: reports
//     it filed and reports filed against it, friendships on both sides,
//     mission progress and claims, match receipts, inventory, loadout, coin
//     pack purchase records (store transaction references), the
//     progression row (XP, level, chosen display name, public id), every
//     identity (guest secret hash, device binding, Google/Facebook/Apple
//     subjects) and the wallet. It locks the progression row first and then
//     the wallet, the lock order of every progression write, so it cannot
//     deadlock with a claim, purchase or match record; concurrent deletions
//     of one account serialize on those locks and only the first finds the
//     account (ErrNotFound for the others). Nothing is deleted if it fails.
//  3. Redis: every human session is revoked (refresh → 401, REST → 401), the
//     live WebSocket is closed with 4401 "account deleted" on whichever
//     instance holds it, and the account's caches and counters are removed
//     (profile, public-id mapping, name-change window, seat/emote caches,
//     presence, recent players on both sides, pending friend requests to
//     bots, weekly leaderboard entries, per-account rate-limit counters). This step is best effort and
//     idempotent: a failure is logged and the next DELETE with a still-live
//     session repeats it (and answers 401, the account being gone).
//
// What remains is listed in docs/authentication.md: pseudonymous aggregates
// without account ids (HyperLogLog active-user sketches, Prometheus
// counters) and short-lived keys that expire on their own.
package account

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/redis/go-redis/v9"

	"ludoarena/internal/auth"
	"ludoarena/internal/httpapi"
	"ludoarena/internal/metrics"
	"ludoarena/internal/profile"
	"ludoarena/internal/progression"
	"ludoarena/internal/ratelimit"
	"ludoarena/internal/social"
)

// ConfirmWord is the literal the request body must carry
// ({"confirm":"DELETE"}); clients never localize it.
const ConfirmWord = "DELETE"

// ErrNotFound: the account does not exist (already deleted).
var ErrNotFound = errors.New("account: not found")

// Deps wires the Service.
type Deps struct {
	PG       *pgxpool.Pool
	RDB      *redis.Client
	Log      *slog.Logger
	Auth     *auth.Service
	Profiles *profile.Service
	Limiter  *ratelimit.Limiter
	// LeaveRoom takes the account out of its active room (rooms.LeaveActive).
	LeaveRoom func(ctx context.Context, userID string) error
	// CloseSockets closes the account's live WebSocket on every instance
	// (websocket.Gateway.CloseAccount).
	CloseSockets func(ctx context.Context, userID string)
	// UserRules are the per-account rate limits whose counters are removed.
	UserRules []ratelimit.Rule
	// Now is the clock (default time.Now).
	Now func() time.Time
}

// Service deletes accounts.
type Service struct{ d Deps }

// New returns a Service.
func New(d Deps) *Service {
	if d.Now == nil {
		d.Now = time.Now
	}
	return &Service{d: d}
}

// Erased counts the PostgreSQL rows a deletion removed (logged; never ids).
type Erased struct {
	ReportsFiled, ReportsAgainst, Friendships, MissionProgress, MissionClaims,
	MatchReceipts, Inventory, Loadout, Purchases, Progress, Identities, Wallets int64
}

// Delete deletes the account userID; sessionID is the caller's session (also
// revoked). ErrNotFound if the account no longer exists; the Redis cleanup
// still runs then, so a retry after a partial failure completes it. Any other
// error means nothing was deleted from PostgreSQL.
func (s *Service) Delete(ctx context.Context, userID uuid.UUID, sessionID string) (Erased, error) {
	uid := userID.String()
	if s.d.LeaveRoom != nil {
		if err := s.d.LeaveRoom(ctx, uid); err != nil {
			s.d.Log.Warn("account deletion: leaving the active room failed", "error", err.Error())
		}
	}
	e, err := s.erase(ctx, userID)
	if err != nil && !errors.Is(err, ErrNotFound) {
		return Erased{}, err
	}
	s.purge(ctx, userID, sessionID)
	return e, err
}

// erase runs the PostgreSQL transaction, retrying a deadlock or
// serialization failure (should a future writer take locks in another order).
func (s *Service) erase(ctx context.Context, userID uuid.UUID) (Erased, error) {
	for attempt := 1; ; attempt++ {
		e, err := s.eraseOnce(ctx, userID)
		var pgErr *pgconn.PgError
		if attempt < 3 && errors.As(err, &pgErr) && (pgErr.Code == "40P01" || pgErr.Code == "40001") {
			continue
		}
		return e, err
	}
}

func (s *Service) eraseOnce(ctx context.Context, userID uuid.UUID) (Erased, error) {
	ctx, cancel := context.WithTimeout(ctx, 15*time.Second)
	defer cancel()
	tx, err := s.d.PG.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		return Erased{}, err
	}
	defer tx.Rollback(ctx) //nolint:errcheck

	// Lock order of every progression write: progress row, then wallet.
	if _, err := tx.Exec(ctx, `SELECT 1 FROM progression.player_progress WHERE user_id = $1 FOR UPDATE`, userID); err != nil {
		return Erased{}, err
	}
	var one int
	// Bot wallets (is_bot) are not accounts and are never deleted here.
	err = tx.QueryRow(ctx, `SELECT 1 FROM wallet.wallets WHERE user_id = $1 AND NOT is_bot FOR UPDATE`, userID).Scan(&one)
	if errors.Is(err, pgx.ErrNoRows) {
		return Erased{}, ErrNotFound
	}
	if err != nil {
		return Erased{}, err
	}

	var e Erased
	// Children first, explicitly (every progression table also cascades
	// from wallet.wallets except player_reports.reported_id, which may hold
	// a bot id since migration 009; identity.auth_identities does not).
	steps := []struct {
		n   *int64
		sql string
	}{
		{&e.ReportsFiled, `DELETE FROM progression.player_reports WHERE reporter_id = $1`},
		{&e.ReportsAgainst, `DELETE FROM progression.player_reports WHERE reported_id = $1`},
		{&e.Friendships, `DELETE FROM progression.friendships WHERE user_lo = $1 OR user_hi = $1`},
		{&e.MissionProgress, `DELETE FROM progression.mission_progress WHERE user_id = $1`},
		{&e.MissionClaims, `DELETE FROM progression.mission_claims WHERE user_id = $1`},
		{&e.MatchReceipts, `DELETE FROM progression.match_receipts WHERE user_id = $1`},
		{&e.Inventory, `DELETE FROM progression.inventory WHERE user_id = $1`},
		{&e.Loadout, `DELETE FROM progression.loadout WHERE user_id = $1`},
		{&e.Purchases, `DELETE FROM progression.purchases WHERE user_id = $1`},
		{&e.Progress, `DELETE FROM progression.player_progress WHERE user_id = $1`},
		{&e.Identities, `DELETE FROM identity.auth_identities WHERE user_id = $1`},
		{&e.Wallets, `DELETE FROM wallet.wallets WHERE user_id = $1 AND NOT is_bot`},
	}
	for _, st := range steps {
		tag, err := tx.Exec(ctx, st.sql, userID)
		if err != nil {
			return Erased{}, err
		}
		*st.n = tag.RowsAffected()
	}
	if e.Wallets != 1 {
		return Erased{}, ErrNotFound
	}
	return e, tx.Commit(ctx)
}

// leaderboardWeeks is how many ISO weeks of lb:xp:{week} can still exist
// (21-day TTL refreshed by every write of a week, so up to 4 weeks back).
const leaderboardWeeks = 5

// purge removes the account's Redis state (best effort, idempotent).
func (s *Service) purge(ctx context.Context, userID uuid.UUID, sessionID string) {
	ctx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()
	uid := userID.String()
	warn := func(step string, err error) {
		if err != nil && !errors.Is(err, redis.Nil) {
			s.d.Log.Warn("account deletion: redis cleanup failed", "step", step, "error", err.Error())
		}
	}

	// Sessions first: nothing can authenticate as the account any more.
	if s.d.Auth != nil {
		_, err := s.d.Auth.EndAccountSessions(ctx, userID, sessionID)
		warn("sessions", err)
	}
	if s.d.CloseSockets != nil {
		s.d.CloseSockets(ctx, uid)
	}
	// A room joined while the deletion ran (the socket was still open).
	if s.d.LeaveRoom != nil {
		warn("room", s.d.LeaveRoom(ctx, uid))
	}

	// Recent players on both sides: every opponent's list loses the account.
	opponents, err := s.d.RDB.ZRange(ctx, social.RecentKey(userID), 0, -1).Result()
	warn("recent", err)
	pipe := s.d.RDB.Pipeline()
	for _, o := range opponents {
		if id, err := uuid.Parse(o); err == nil {
			pipe.ZRem(ctx, social.RecentKey(id), uid)
		}
	}
	now := s.d.Now()
	for w := 0; w < leaderboardWeeks; w++ {
		pipe.ZRem(ctx, progression.LeaderboardKey(progression.WeekKey(now.AddDate(0, 0, -7*w))), uid)
	}
	keys := []string{
		social.RecentKey(userID), social.PresenceKey(userID), social.BotRequestsKey(userID),
		"profile:" + uid, profile.NameChangesKey(userID),
		progression.SeatKey(userID), progression.SeatKey(userID) + ":lease", progression.EmotesKey(userID),
	}
	if s.d.Profiles != nil {
		keys = append(keys, "pubid:"+s.d.Profiles.PublicID(userID))
	}
	pipe.Del(ctx, keys...)
	_, err = pipe.Exec(ctx)
	warn("keys", err)
	if s.d.Limiter != nil {
		warn("rate_limits", s.d.Limiter.Forget(ctx, uid, s.d.UserRules...))
	}
}

// ------------------------------------------------------------------ HTTP

var errConfirm = httpapi.Errf(http.StatusBadRequest, "confirmation_required",
	`Send {"confirm":"DELETE"} to delete the account.`)

// Register adds DELETE /api/v1/account: human sessions only (bots 403), not
// version gated (deleting must always work, like logout), rate limited per
// account.
func (s *Service) Register(rt *httpapi.Router) {
	rule := ratelimit.AccountDeletePerUser
	rt.Handle("DELETE /api/v1/account", httpapi.Route{Auth: httpapi.AuthHuman, UserRule: &rule, MaxBody: 1 << 10},
		s.handleDelete)
}

func (s *Service) handleDelete(w http.ResponseWriter, r *http.Request) error {
	p, _ := httpapi.PrincipalFrom(r.Context())
	var body struct {
		Confirm string `json:"confirm"`
	}
	if err := httpapi.DecodeJSON(r, &body); err != nil || body.Confirm != ConfirmWord {
		metrics.AccountDeletions.WithLabelValues("bad_confirm").Inc()
		return errConfirm
	}
	// Not cancelled by a client that hangs up mid-deletion.
	e, err := s.Delete(context.WithoutCancel(r.Context()), p.UserID, p.SessionID)
	switch {
	case errors.Is(err, ErrNotFound):
		// A concurrent request deleted it first: this session is dead too.
		metrics.AccountDeletions.WithLabelValues("already_deleted").Inc()
		return httpapi.ErrUnauthorized
	case err != nil:
		metrics.AccountDeletions.WithLabelValues("error").Inc()
		return err
	}
	metrics.AccountDeletions.WithLabelValues("deleted").Inc()
	// Row counts only: no account, public or provider id is logged.
	s.d.Log.Info("account deleted", "identities", e.Identities, "friendships", e.Friendships,
		"inventory", e.Inventory, "reports_filed", e.ReportsFiled, "reports_against", e.ReportsAgainst)
	w.WriteHeader(http.StatusNoContent)
	return nil
}
