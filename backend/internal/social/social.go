// Package social owns friends (friend codes = public player ids), friend
// requests, recent opponents, private-room invites and the weekly friends
// leaderboard.
//
// Storage: friendships live in PostgreSQL (progression.friendships, created by
// migrations/003_progression.sql; this package is the only writer).
// Progression reads the same table inside its match transaction for the
// friend XP bonus. Recent opponents, invites, the weekly XP leaderboard and
// pending requests to bots (bots.go) are ephemeral Redis data (lost on a
// Redis wipe without affecting anything durable). Responses never contain
// account ids, emails or provider ids of other players: only public uid,
// display name, avatar, level and title.
//
// Dependency: social uses *progression.Service for summaries (level, title),
// durable public-id resolution and per-account row locks, and registers
// itself with progression (OnMatch) to receive finished matches.
package social

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"errors"
	"log/slog"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/redis/go-redis/v9"

	"ludoroyale/internal/gameevents"
	"ludoroyale/internal/metrics"
	"ludoroyale/internal/profile"
	"ludoroyale/internal/progression"
	"ludoroyale/internal/ratelimit"
)

// Friend statuses.
const (
	StatusFriend   = "friend"
	StatusIncoming = "incoming"
	StatusOutgoing = "outgoing"
	StatusNone     = "none"
)

// WebSocket message types.
const (
	MsgInvite        = "social.invite"
	MsgFriendRequest = "social.friend_request"
)

// Limits.
var (
	InvitePerUser        = ratelimit.Rule{Name: "invite_user", Limit: 10, Window: time.Minute}
	FriendRequestPerHour = ratelimit.Rule{Name: "friend_request_user", Limit: 60, Window: time.Hour}
)

const (
	recentLimit = 20
	recentTTL   = 14 * 24 * time.Hour
)

// Errors.
var (
	ErrUnknownPlayer     = errors.New("unknown player")
	ErrSelf              = errors.New("cannot befriend yourself")
	ErrAlreadyFriends    = errors.New("already friends")
	ErrFriendLimit       = errors.New("friend limit reached")
	ErrNoRequest         = errors.New("no pending friend request")
	ErrInviteRateLimited = errors.New("too many invites")
)

// DefaultMaxFriends is the accepted-friend cap when Options.MaxFriends is
// unset (FRIENDS_MAX in production wiring).
const DefaultMaxFriends = 20

// Options configure the service.
type Options struct {
	// MaxFriends caps accepted friends per account (default 20). A new
	// friendship (request, auto-accept or accept) is refused when EITHER
	// side already has MaxFriends; accounts above the cap keep their friends.
	MaxFriends  int
	MaxOutgoing int              // pending requests sent per account, to people and bots (default 100)
	MaxIncoming int              // pending requests received per account (default 100)
	Now         func() time.Time // default time.Now
	// Bots finds a bot seat by public id so that a request to a bot looks
	// like one to a person who never answers (nil: bot codes are unknown).
	Bots BotLookup
	// BotRequestTTL is how long a request to a bot stays pending (default
	// DefaultBotRequestTTL).
	BotRequestTTL time.Duration
}

// Service implements the social features and gameevents.Inviter.
type Service struct {
	pool     *pgxpool.Pool
	rdb      *redis.Client
	profiles *profile.Service
	prog     *progression.Service
	notifier gameevents.Notifier
	log      *slog.Logger
	limiter  *ratelimit.Limiter
	opts     Options
}

var _ gameevents.Inviter = (*Service)(nil)

// New returns the social service and subscribes it to finished matches
// recorded by prog (recent opponents). notifier may be nil.
func New(pool *pgxpool.Pool, rdb *redis.Client, profiles *profile.Service, prog *progression.Service,
	notifier gameevents.Notifier, log *slog.Logger, opts Options) *Service {
	if opts.MaxFriends <= 0 {
		opts.MaxFriends = DefaultMaxFriends
	}
	if opts.MaxOutgoing <= 0 {
		opts.MaxOutgoing = 100
	}
	if opts.MaxIncoming <= 0 {
		opts.MaxIncoming = 100
	}
	if opts.Now == nil {
		opts.Now = time.Now
	}
	if opts.BotRequestTTL <= 0 {
		opts.BotRequestTTL = DefaultBotRequestTTL
	}
	if log == nil {
		log = slog.Default()
	}
	s := &Service{pool: pool, rdb: rdb, profiles: profiles, prog: prog, notifier: notifier, log: log,
		limiter: ratelimit.New(rdb, log, false), opts: opts}
	prog.OnMatch(s.recordOpponents)
	return s
}

// Friend is the API Friend object (never contains account ids).
type Friend struct {
	UID    string `json:"uid"`
	Name   string `json:"name"`
	Avatar int    `json:"avatar"`
	Level  int    `json:"level"`
	Title  string `json:"title"`
	Online bool   `json:"online"`
	Status string `json:"status"`
}

// FriendsView is the GET /friends response.
type FriendsView struct {
	Friends  []Friend `json:"friends"`
	Incoming []Friend `json:"incoming"`
	Outgoing []Friend `json:"outgoing"`
	// OnlineCount is the number of accepted friends online now.
	OnlineCount int `json:"onlineCount"`
	// FriendCount is the number of accepted friends (len(Friends)).
	FriendCount int `json:"friendCount"`
	// MaxFriends is the accepted-friend cap (FRIENDS_MAX).
	MaxFriends int `json:"maxFriends"`
}

// MaxFriends returns the configured accepted-friend cap.
func (s *Service) MaxFriends() int { return s.opts.MaxFriends }

func (s *Service) notify(ctx context.Context, userID uuid.UUID, msgType string, payload any) {
	if s.notifier != nil {
		s.notifier.NotifyUser(ctx, userID, msgType, payload)
	}
}

// PresenceKey is set (with a TTL) by the WebSocket gateway while a user is
// connected; social only checks that it exists.
func PresenceKey(userID uuid.UUID) string { return "presence:" + userID.String() }

// RecentKey is the ZSET of recent human opponents (score = unix ms).
func RecentKey(userID uuid.UUID) string { return "recent:" + userID.String() }

// existingAccounts reports which ids are accounts (have a wallet row).
func existingAccounts(ctx context.Context, q querier, ids []uuid.UUID) (map[uuid.UUID]bool, error) {
	rows, err := q.Query(ctx, `SELECT user_id FROM wallet.wallets WHERE user_id = ANY($1)`, ids)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make(map[uuid.UUID]bool, len(ids))
	for rows.Next() {
		var id uuid.UUID
		if err := rows.Scan(&id); err != nil {
			return nil, err
		}
		out[id] = true
	}
	return out, rows.Err()
}

// ------------------------------------------------------------ relationships

func order(a, b uuid.UUID) (uuid.UUID, uuid.UUID) {
	if strings.Compare(a.String(), b.String()) < 0 {
		return a, b
	}
	return b, a
}

type relation struct {
	other   uuid.UUID
	status  string
	created time.Time
}

type querier interface {
	Query(ctx context.Context, sql string, args ...any) (pgx.Rows, error)
	QueryRow(ctx context.Context, sql string, args ...any) pgx.Row
}

// relations lists every friendship row involving me, from my perspective.
func relations(ctx context.Context, q querier, me uuid.UUID) ([]relation, error) {
	rows, err := q.Query(ctx, `
		SELECT CASE WHEN user_lo = $1 THEN user_hi ELSE user_lo END, status, requested_by, created_at
		  FROM progression.friendships WHERE user_lo = $1 OR user_hi = $1`, me)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []relation
	for rows.Next() {
		var r relation
		var status string
		var by uuid.UUID
		if err := rows.Scan(&r.other, &status, &by, &r.created); err != nil {
			return nil, err
		}
		switch {
		case status == "accepted":
			r.status = StatusFriend
		case by == me:
			r.status = StatusOutgoing
		default:
			r.status = StatusIncoming
		}
		out = append(out, r)
	}
	return out, rows.Err()
}

// pairStatus returns the relationship row between me and other.
func pairStatus(ctx context.Context, q querier, me, other uuid.UUID) (string, error) {
	lo, hi := order(me, other)
	var status string
	var by uuid.UUID
	err := q.QueryRow(ctx, `SELECT status, requested_by FROM progression.friendships WHERE user_lo = $1 AND user_hi = $2`,
		lo, hi).Scan(&status, &by)
	switch {
	case errors.Is(err, pgx.ErrNoRows):
		return StatusNone, nil
	case err != nil:
		return "", err
	case status == "accepted":
		return StatusFriend, nil
	case by == me:
		return StatusOutgoing, nil
	}
	return StatusIncoming, nil
}

// AreFriends reports whether two accounts are accepted friends.
func (s *Service) AreFriends(ctx context.Context, a, b uuid.UUID) (bool, error) {
	st, err := pairStatus(ctx, s.pool, a, b)
	return st == StatusFriend, err
}

// FriendIDs returns the accepted friends of an account.
func (s *Service) FriendIDs(ctx context.Context, me uuid.UUID) ([]uuid.UUID, error) {
	rels, err := relations(ctx, s.pool, me)
	if err != nil {
		return nil, err
	}
	var out []uuid.UUID
	for _, r := range rels {
		if r.status == StatusFriend {
			out = append(out, r.other)
		}
	}
	return out, nil
}

// views renders public Friend objects. Presence is only revealed to friends.
func (s *Service) views(ctx context.Context, ids []uuid.UUID, status map[uuid.UUID]string) ([]Friend, error) {
	if len(ids) == 0 {
		return []Friend{}, nil
	}
	profs := s.profiles.GetMany(ctx, ids)
	sums, err := s.prog.Summaries(ctx, ids)
	if err != nil {
		return nil, err
	}
	online := make(map[uuid.UUID]bool, len(ids))
	pipe := s.rdb.Pipeline()
	cmds := map[uuid.UUID]*redis.IntCmd{}
	for _, id := range ids {
		if status[id] == StatusFriend {
			cmds[id] = pipe.Exists(ctx, PresenceKey(id))
		}
	}
	if len(cmds) > 0 {
		if _, err := pipe.Exec(ctx); err != nil && !errors.Is(err, redis.Nil) {
			s.log.Warn("presence lookup failed", "error", err.Error())
		}
		for id, c := range cmds {
			online[id] = c.Val() == 1
		}
	}
	out := make([]Friend, 0, len(ids))
	for _, id := range ids {
		p, sum := profs[id], sums[id]
		st := status[id]
		if st == "" {
			st = StatusNone
		}
		out = append(out, Friend{UID: p.UID, Name: p.Name, Avatar: p.Avatar, Level: sum.Level, Title: sum.Title,
			Online: online[id], Status: st})
	}
	return out, nil
}

func (s *Service) view(ctx context.Context, id uuid.UUID, status string) (Friend, error) {
	v, err := s.views(ctx, []uuid.UUID{id}, map[uuid.UUID]string{id: status})
	if err != nil {
		return Friend{}, err
	}
	return v[0], nil
}

// Friends lists accepted friends (online first, then by name) and pending
// requests (newest first).
func (s *Service) Friends(ctx context.Context, me uuid.UUID) (FriendsView, error) {
	rels, err := relations(ctx, s.pool, me)
	if err != nil {
		return FriendsView{}, err
	}
	sort.Slice(rels, func(i, j int) bool { return rels[i].created.After(rels[j].created) })
	ids := make([]uuid.UUID, len(rels))
	status := make(map[uuid.UUID]string, len(rels))
	for i, r := range rels {
		ids[i] = r.other
		status[r.other] = r.status
	}
	all, err := s.views(ctx, ids, status)
	if err != nil {
		return FriendsView{}, err
	}
	bots, err := s.botRequests(ctx, me)
	if err != nil {
		return FriendsView{}, err
	}
	out := FriendsView{Friends: []Friend{}, Incoming: []Friend{}, MaxFriends: s.opts.MaxFriends}
	var outgoing []datedFriend
	for i, f := range all { // views keeps the order of ids (= rels)
		switch f.Status {
		case StatusFriend:
			out.Friends = append(out.Friends, f)
			if f.Online {
				out.OnlineCount++
			}
		case StatusIncoming:
			out.Incoming = append(out.Incoming, f)
		case StatusOutgoing:
			outgoing = append(outgoing, datedFriend{at: rels[i].created, f: f})
		}
	}
	out.Outgoing = mergeOutgoing(outgoing, bots)
	sort.SliceStable(out.Friends, func(i, j int) bool {
		a, b := out.Friends[i], out.Friends[j]
		if a.Online != b.Online {
			return a.Online
		}
		return strings.ToLower(a.Name) < strings.ToLower(b.Name)
	})
	out.FriendCount = len(out.Friends)
	return out, nil
}

func (s *Service) resolve(ctx context.Context, uid string) (uuid.UUID, error) {
	// Public ids are lowercase; accept codes typed in any case.
	id, err := s.prog.ResolvePublicID(ctx, strings.ToLower(strings.TrimSpace(uid)))
	if errors.Is(err, progression.ErrUnknownPlayer) {
		return uuid.Nil, ErrUnknownPlayer
	}
	return id, err
}

// count helpers (inside a transaction that holds both account locks).
func countFriends(ctx context.Context, tx pgx.Tx, id uuid.UUID) (int, error) {
	var n int
	err := tx.QueryRow(ctx, `SELECT count(*) FROM progression.friendships
		WHERE status = 'accepted' AND (user_lo = $1 OR user_hi = $1)`, id).Scan(&n)
	return n, err
}

func countPending(ctx context.Context, tx pgx.Tx, id uuid.UUID, outgoing bool) (int, error) {
	cond := "requested_by = $1"
	if !outgoing {
		cond = "requested_by <> $1"
	}
	var n int
	err := tx.QueryRow(ctx, `SELECT count(*) FROM progression.friendships
		WHERE status = 'pending' AND (user_lo = $1 OR user_hi = $1) AND `+cond, id).Scan(&n)
	return n, err
}

// checkFriendLimit refuses a new friendship when any of ids already has
// MaxFriends accepted friends. Callers hold both accounts' row locks
// (LockAccountsTx), and every change that adds a friendship takes the same
// locks, so two transactions can never both pass for the last slot.
func (s *Service) checkFriendLimit(ctx context.Context, tx pgx.Tx, ids ...uuid.UUID) error {
	for _, id := range ids {
		n, err := countFriends(ctx, tx, id)
		if err != nil {
			return err
		}
		if n >= s.opts.MaxFriends {
			return ErrFriendLimit
		}
	}
	return nil
}

// Request sends a friend request by friend code (public uid). If the other
// player already requested me, the friendship is accepted immediately.
// Repeating a pending request is idempotent. A bot's code (a seat the
// caller can see) gets a request that is never answered (requestBot).
func (s *Service) Request(ctx context.Context, me uuid.UUID, friendCode string) (Friend, error) {
	target, err := s.resolve(ctx, friendCode)
	if errors.Is(err, ErrUnknownPlayer) {
		return s.requestBot(ctx, me, strings.ToLower(strings.TrimSpace(friendCode)))
	}
	if err != nil {
		return Friend{}, err
	}
	if target == me {
		metrics.FriendRequests.WithLabelValues("rejected").Inc()
		return Friend{}, ErrSelf
	}
	lo, hi := order(me, target)

	tx, err := s.pool.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		return Friend{}, err
	}
	defer tx.Rollback(ctx) //nolint:errcheck
	if err := s.prog.LockAccountsTx(ctx, tx, lo, hi); err != nil {
		if errors.Is(err, progression.ErrUnknownUser) {
			return Friend{}, ErrUnknownPlayer
		}
		return Friend{}, err
	}
	st, err := pairStatus(ctx, tx, me, target)
	if err != nil {
		return Friend{}, err
	}
	event := ""
	switch st {
	case StatusFriend:
		return Friend{}, ErrAlreadyFriends
	case StatusOutgoing:
		// Already requested: idempotent.
	case StatusIncoming:
		if err := s.checkFriendLimit(ctx, tx, me, target); err != nil {
			metrics.FriendRequests.WithLabelValues("rejected").Inc()
			return Friend{}, err
		}
		if _, err := tx.Exec(ctx, `UPDATE progression.friendships SET status = 'accepted' WHERE user_lo = $1 AND user_hi = $2`, lo, hi); err != nil {
			return Friend{}, err
		}
		st, event = StatusFriend, "auto_accepted"
	case StatusNone:
		// Either side at the cap: the request could never be accepted.
		if err := s.checkFriendLimit(ctx, tx, me, target); err != nil {
			metrics.FriendRequests.WithLabelValues("rejected").Inc()
			return Friend{}, err
		}
		// Pending requests to bots count toward the same cap.
		bots, err := s.botRequests(ctx, me)
		if err != nil {
			return Friend{}, err
		}
		if n, err := countPending(ctx, tx, me, true); err != nil {
			return Friend{}, err
		} else if n+len(bots) >= s.opts.MaxOutgoing {
			metrics.FriendRequests.WithLabelValues("rejected").Inc()
			return Friend{}, ErrFriendLimit
		}
		if n, err := countPending(ctx, tx, target, false); err != nil {
			return Friend{}, err
		} else if n >= s.opts.MaxIncoming {
			metrics.FriendRequests.WithLabelValues("rejected").Inc()
			return Friend{}, ErrFriendLimit
		}
		if _, err := tx.Exec(ctx, `INSERT INTO progression.friendships (user_lo, user_hi, status, requested_by)
			VALUES ($1, $2, 'pending', $3)`, lo, hi, me); err != nil {
			return Friend{}, err
		}
		st, event = StatusOutgoing, "sent"
	}
	if err := tx.Commit(ctx); err != nil {
		return Friend{}, err
	}
	if event != "" {
		metrics.FriendRequests.WithLabelValues(event).Inc()
	}
	if event == "sent" {
		p := s.profiles.Get(ctx, me)
		s.notify(ctx, target, MsgFriendRequest, map[string]any{"fromUid": p.UID, "fromName": p.Name})
	}
	return s.view(ctx, target, st)
}

// Accept accepts an incoming request from uid. Accepting an existing
// friendship is idempotent.
func (s *Service) Accept(ctx context.Context, me uuid.UUID, uid string) (Friend, error) {
	other, err := s.resolve(ctx, uid)
	if err != nil {
		return Friend{}, err
	}
	if other == me {
		return Friend{}, ErrNoRequest
	}
	lo, hi := order(me, other)
	tx, err := s.pool.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		return Friend{}, err
	}
	defer tx.Rollback(ctx) //nolint:errcheck
	if err := s.prog.LockAccountsTx(ctx, tx, lo, hi); err != nil {
		return Friend{}, err
	}
	st, err := pairStatus(ctx, tx, me, other)
	if err != nil {
		return Friend{}, err
	}
	switch st {
	case StatusFriend:
		return s.view(ctx, other, StatusFriend)
	case StatusIncoming:
	default:
		return Friend{}, ErrNoRequest
	}
	if err := s.checkFriendLimit(ctx, tx, me, other); err != nil {
		metrics.FriendRequests.WithLabelValues("rejected").Inc()
		return Friend{}, err
	}
	if _, err := tx.Exec(ctx, `UPDATE progression.friendships SET status = 'accepted' WHERE user_lo = $1 AND user_hi = $2`, lo, hi); err != nil {
		return Friend{}, err
	}
	if err := tx.Commit(ctx); err != nil {
		return Friend{}, err
	}
	metrics.FriendRequests.WithLabelValues("accepted").Inc()
	return s.view(ctx, other, StatusFriend)
}

// Remove deletes a friendship, declines an incoming request or cancels an
// outgoing one (to a person or a bot). Removing a non-existent relationship
// is a no-op.
func (s *Service) Remove(ctx context.Context, me uuid.UUID, uid string) error {
	if found, err := s.cancelBotRequest(ctx, me, uid); err != nil || found {
		return err
	}
	other, err := s.resolve(ctx, uid)
	if errors.Is(err, ErrUnknownPlayer) && s.isBot(ctx, me, uid) {
		return nil // a bot without a pending request: nothing to remove
	}
	if err != nil {
		return err
	}
	lo, hi := order(me, other)
	var status string
	var by uuid.UUID
	err = s.pool.QueryRow(ctx, `DELETE FROM progression.friendships WHERE user_lo = $1 AND user_hi = $2
		RETURNING status, requested_by`, lo, hi).Scan(&status, &by)
	switch {
	case errors.Is(err, pgx.ErrNoRows):
		return nil
	case err != nil:
		return err
	case status == "accepted":
		metrics.FriendRequests.WithLabelValues("removed").Inc()
	case by == me:
		metrics.FriendRequests.WithLabelValues("cancelled").Inc()
	default:
		metrics.FriendRequests.WithLabelValues("declined").Inc()
	}
	return nil
}

// ---------------------------------------------------------- recent players

// recordOpponents stores each human's human opponents (idempotent: a ZSET
// member is re-scored, never duplicated). Players whose account no longer
// exists (deleted while the match ran) are left out, so a deleted account
// never reappears in anyone's recent players.
func (s *Service) recordOpponents(ctx context.Context, rec gameevents.MatchRecord) {
	humans := rec.Humans()
	if len(humans) < 2 {
		return
	}
	ids := make([]uuid.UUID, len(humans))
	for i, h := range humans {
		ids[i] = h.UserID
	}
	if live, err := existingAccounts(ctx, s.pool, ids); err == nil {
		kept := humans[:0:0]
		for _, h := range humans {
			if live[h.UserID] {
				kept = append(kept, h)
			}
		}
		if humans = kept; len(humans) < 2 {
			return
		}
	} else {
		s.log.Warn("recent opponents: account check failed", "error", err.Error())
	}
	at := rec.FinishedAt
	if at.IsZero() {
		at = s.opts.Now()
	}
	score := float64(at.UnixMilli())
	cutoff := strconv.FormatInt(at.Add(-recentTTL).UnixMilli(), 10)
	pipe := s.rdb.Pipeline()
	for _, h := range humans {
		key := RecentKey(h.UserID)
		var members []redis.Z
		for _, o := range humans {
			if o.UserID != h.UserID {
				members = append(members, redis.Z{Score: score, Member: o.UserID.String()})
			}
		}
		if len(members) == 0 {
			continue
		}
		pipe.ZAdd(ctx, key, members...)
		pipe.ZRemRangeByScore(ctx, key, "-inf", "("+cutoff)
		pipe.ZRemRangeByRank(ctx, key, 0, -(recentLimit + 1))
		pipe.Expire(ctx, key, recentTTL)
	}
	if _, err := pipe.Exec(ctx); err != nil {
		s.log.Warn("recent opponents update failed", "error", err.Error())
	}
}

// Recent returns up to 20 human opponents of the last 14 days, newest first.
func (s *Service) Recent(ctx context.Context, me uuid.UUID) ([]Friend, error) {
	minScore := strconv.FormatInt(s.opts.Now().Add(-recentTTL).UnixMilli(), 10)
	raw, err := s.rdb.ZRevRangeByScore(ctx, RecentKey(me), &redis.ZRangeBy{
		Max: "+inf", Min: minScore, Count: recentLimit}).Result()
	if err != nil && !errors.Is(err, redis.Nil) {
		return nil, err
	}
	var ids []uuid.UUID
	for _, r := range raw {
		if id, err := uuid.Parse(r); err == nil && id != me {
			ids = append(ids, id)
		}
	}
	if len(ids) == 0 {
		return []Friend{}, nil
	}
	// Deleted accounts are dropped (and forgotten), never shown.
	live, err := existingAccounts(ctx, s.pool, ids)
	if err != nil {
		return nil, err
	}
	kept := ids[:0]
	var gone []any
	for _, id := range ids {
		if live[id] {
			kept = append(kept, id)
		} else {
			gone = append(gone, id.String())
		}
	}
	if len(gone) > 0 {
		_ = s.rdb.ZRem(ctx, RecentKey(me), gone...).Err()
	}
	if ids = kept; len(ids) == 0 {
		return []Friend{}, nil
	}
	rels, err := relations(ctx, s.pool, me)
	if err != nil {
		return nil, err
	}
	status := map[uuid.UUID]string{}
	for _, r := range rels {
		status[r.other] = r.status
	}
	return s.views(ctx, ids, status)
}

// ------------------------------------------------------------- leaderboard

// LeaderboardEntry is one row of the friends leaderboard.
type LeaderboardEntry struct {
	UID      string `json:"uid"`
	Name     string `json:"name"`
	Avatar   int    `json:"avatar"`
	Level    int    `json:"level"`
	WeeklyXP int64  `json:"weeklyXp"`
	Rank     int    `json:"rank"`
	IsMe     bool   `json:"isMe"`
}

// Leaderboard is the GET /leaderboards/friends response.
type Leaderboard struct {
	PeriodKey string             `json:"periodKey"`
	Entries   []LeaderboardEntry `json:"entries"`
}

// FriendsLeaderboard ranks me and my accepted friends by this ISO week's XP
// (standard competition ranking: equal XP share a rank).
func (s *Service) FriendsLeaderboard(ctx context.Context, me uuid.UUID) (Leaderboard, error) {
	week := progression.WeekKey(s.opts.Now())
	friends, err := s.FriendIDs(ctx, me)
	if err != nil {
		return Leaderboard{}, err
	}
	ids := append([]uuid.UUID{me}, friends...)
	key := progression.LeaderboardKey(week)
	pipe := s.rdb.Pipeline()
	cmds := make([]*redis.FloatCmd, len(ids))
	for i, id := range ids {
		cmds[i] = pipe.ZScore(ctx, key, id.String())
	}
	if _, err := pipe.Exec(ctx); err != nil && !errors.Is(err, redis.Nil) {
		return Leaderboard{}, err
	}
	profs := s.profiles.GetMany(ctx, ids)
	sums, err := s.prog.Summaries(ctx, ids)
	if err != nil {
		return Leaderboard{}, err
	}
	entries := make([]LeaderboardEntry, len(ids))
	for i, id := range ids {
		p := profs[id]
		entries[i] = LeaderboardEntry{UID: p.UID, Name: p.Name, Avatar: p.Avatar, Level: sums[id].Level,
			WeeklyXP: int64(cmds[i].Val()), IsMe: id == me}
	}
	sort.SliceStable(entries, func(i, j int) bool {
		a, b := entries[i], entries[j]
		if a.WeeklyXP != b.WeeklyXP {
			return a.WeeklyXP > b.WeeklyXP
		}
		if strings.ToLower(a.Name) != strings.ToLower(b.Name) {
			return strings.ToLower(a.Name) < strings.ToLower(b.Name)
		}
		return a.UID < b.UID
	})
	for i := range entries {
		if i > 0 && entries[i].WeeklyXP == entries[i-1].WeeklyXP {
			entries[i].Rank = entries[i-1].Rank
		} else {
			entries[i].Rank = i + 1
		}
	}
	return Leaderboard{PeriodKey: week, Entries: entries}, nil
}

// ------------------------------------------------------------------ invites

// SendInvite implements gameevents.Inviter: it pushes `social.invite` to an
// accepted friend. Unknown uids and non-friends both return
// gameevents.ErrNotFriends (no account enumeration); more than 10 invites per
// minute per sender return ErrInviteRateLimited.
func (s *Service) SendInvite(ctx context.Context, from uuid.UUID, friendUID string, inv gameevents.Invite) error {
	if ok, _ := s.limiter.Allow(ctx, InvitePerUser, from.String()); !ok {
		metrics.InvitesSent.WithLabelValues("rate_limited").Inc()
		return ErrInviteRateLimited
	}
	to, err := s.resolve(ctx, friendUID)
	if errors.Is(err, ErrUnknownPlayer) || (err == nil && to == from) {
		metrics.InvitesSent.WithLabelValues("not_friends").Inc()
		return gameevents.ErrNotFriends
	}
	if err != nil {
		metrics.InvitesSent.WithLabelValues("error").Inc()
		return err
	}
	ok, err := s.AreFriends(ctx, from, to)
	if err != nil {
		metrics.InvitesSent.WithLabelValues("error").Inc()
		return err
	}
	if !ok {
		metrics.InvitesSent.WithLabelValues("not_friends").Inc()
		return gameevents.ErrNotFriends
	}
	now := s.opts.Now()
	exp := inv.ExpiresAt
	if exp.IsZero() {
		exp = now.Add(5 * time.Minute)
	}
	ttl := exp.Sub(now)
	if ttl < 10*time.Second {
		ttl = 10 * time.Second
	} else if ttl > 30*time.Minute {
		ttl = 30 * time.Minute
	}
	// One invite id per (sender, friend, room) while it is valid, so repeated
	// taps re-deliver the same invite instead of stacking new ones.
	inviteID := "inv_" + randomHex(8)
	pairKey := "invite:" + from.String() + ":" + to.String() + ":" + inv.RoomID
	if set, err := s.rdb.SetNX(ctx, pairKey, inviteID, ttl).Result(); err == nil && !set {
		if existing, err := s.rdb.Get(ctx, pairKey).Result(); err == nil && existing != "" {
			inviteID = existing
		}
	}
	p := s.profiles.Get(ctx, from)
	s.notify(ctx, to, MsgInvite, map[string]any{
		"inviteId": inviteID, "fromUid": p.UID, "fromName": p.Name, "roomId": inv.RoomID,
		"code": inv.Code, "game": inv.Game, "expiresAt": exp.UnixMilli(),
	})
	metrics.InvitesSent.WithLabelValues("sent").Inc()
	return nil
}

func randomHex(n int) string {
	b := make([]byte, n)
	_, _ = rand.Read(b)
	return hex.EncodeToString(b)
}
