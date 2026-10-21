package social

import (
	"context"
	"encoding/json"
	"errors"
	"sort"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/redis/go-redis/v9"

	"ludoroyale/internal/metrics"
	"ludoroyale/internal/progression"
)

// Friend requests to bots.
//
// Bots must be indistinguishable from people in the app, so "Add friend" on
// a bot's player pod behaves like a request to a person who never answers:
// the same checks and limits, the same 201 response, and the request is
// listed under outgoing — until it quietly lapses after BotRequestTTL. Bots
// are not accounts, so these requests live in Redis (BotRequestsKey), never
// in progression.friendships, and are never accepted.

// DefaultBotRequestTTL is how long a request to a bot stays pending.
const DefaultBotRequestTTL = 72 * time.Hour

// BotProfile is a bot seat's public profile as the room shows it.
type BotProfile struct {
	UID    string
	Name   string
	Avatar int
	Level  int
	Title  string
}

// BotLookup returns the live bot with public id uid as seen by me (wired to
// rooms.FindBotSeat), or ErrUnknownPlayer.
type BotLookup func(ctx context.Context, me uuid.UUID, uid string) (BotProfile, error)

// BotRequestsKey is the HASH of an account's pending requests to bots:
// field = the bot's public id, value = JSON botRequest.
func BotRequestsKey(userID uuid.UUID) string { return "botfr:" + userID.String() }

// botRequest is the stored profile of the requested bot and when it was sent.
type botRequest struct {
	Name   string `json:"name"`
	Avatar int    `json:"avatar"`
	Level  int    `json:"level"`
	Title  string `json:"title"`
	At     int64  `json:"at"` // unix ms
}

type pendingBot struct {
	uid string
	req botRequest
}

func (p pendingBot) friend() Friend {
	return Friend{UID: p.uid, Name: p.req.Name, Avatar: p.req.Avatar, Level: max(p.req.Level, 1), Title: p.req.Title,
		Status: StatusOutgoing}
}

// liveBotRequests splits raw hash entries into live requests (newest first)
// and fields to delete (lapsed at now - ttl, or unreadable).
func liveBotRequests(raw map[string]string, now time.Time, ttl time.Duration) (live []pendingBot, stale []string) {
	cutoff := now.Add(-ttl).UnixMilli()
	for uid, v := range raw {
		var r botRequest
		if err := json.Unmarshal([]byte(v), &r); err != nil || r.At <= cutoff {
			stale = append(stale, uid)
			continue
		}
		live = append(live, pendingBot{uid: uid, req: r})
	}
	sort.Slice(live, func(i, j int) bool {
		if live[i].req.At != live[j].req.At {
			return live[i].req.At > live[j].req.At
		}
		return live[i].uid < live[j].uid
	})
	sort.Strings(stale)
	return live, stale
}

// botRequests returns my live requests to bots, newest first, and deletes
// lapsed ones.
func (s *Service) botRequests(ctx context.Context, me uuid.UUID) ([]pendingBot, error) {
	key := BotRequestsKey(me)
	raw, err := s.rdb.HGetAll(ctx, key).Result()
	if err != nil && !errors.Is(err, redis.Nil) {
		return nil, err
	}
	live, stale := liveBotRequests(raw, s.opts.Now(), s.opts.BotRequestTTL)
	if len(stale) > 0 {
		_ = s.rdb.HDel(ctx, key, stale...).Err()
	}
	return live, nil
}

// datedFriend is a person's pending request with its creation time.
type datedFriend struct {
	at time.Time
	f  Friend
}

// mergeOutgoing lists people's and bots' pending requests together, newest
// first.
func mergeOutgoing(people []datedFriend, bots []pendingBot) []Friend {
	all := make([]datedFriend, 0, len(people)+len(bots))
	all = append(all, people...)
	for _, b := range bots {
		all = append(all, datedFriend{at: time.UnixMilli(b.req.At), f: b.friend()})
	}
	sort.SliceStable(all, func(i, j int) bool { return all[i].at.After(all[j].at) })
	out := make([]Friend, len(all))
	for i, d := range all {
		out[i] = d.f
	}
	return out
}

// requestBot sends a request to the bot uid: the checks of a request to a
// person with no relationship yet (friend cap, pending-request cap counted
// over people and bots), under my account lock like every friend change.
// Repeating a pending request returns it again.
func (s *Service) requestBot(ctx context.Context, me uuid.UUID, uid string) (Friend, error) {
	if s.opts.Bots == nil {
		return Friend{}, ErrUnknownPlayer
	}
	bot, err := s.opts.Bots(ctx, me, uid)
	if err != nil {
		return Friend{}, err
	}
	tx, err := s.pool.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		return Friend{}, err
	}
	defer tx.Rollback(ctx) //nolint:errcheck
	if err := s.prog.LockAccountsTx(ctx, tx, me); err != nil {
		if errors.Is(err, progression.ErrUnknownUser) {
			return Friend{}, ErrUnknownPlayer
		}
		return Friend{}, err
	}
	pending, err := s.botRequests(ctx, me)
	if err != nil {
		return Friend{}, err
	}
	for _, p := range pending {
		if p.uid == bot.UID {
			return p.friend(), nil
		}
	}
	if err := s.checkFriendLimit(ctx, tx, me); err != nil {
		metrics.FriendRequests.WithLabelValues("rejected").Inc()
		return Friend{}, err
	}
	if n, err := countPending(ctx, tx, me, true); err != nil {
		return Friend{}, err
	} else if n+len(pending) >= s.opts.MaxOutgoing {
		metrics.FriendRequests.WithLabelValues("rejected").Inc()
		return Friend{}, ErrFriendLimit
	}
	p := pendingBot{uid: bot.UID, req: botRequest{Name: bot.Name, Avatar: bot.Avatar, Level: bot.Level, Title: bot.Title,
		At: s.opts.Now().UnixMilli()}}
	raw, err := json.Marshal(p.req)
	if err != nil {
		return Friend{}, err
	}
	key := BotRequestsKey(me)
	pipe := s.rdb.TxPipeline()
	pipe.HSet(ctx, key, p.uid, raw)
	pipe.Expire(ctx, key, s.opts.BotRequestTTL)
	if _, err := pipe.Exec(ctx); err != nil {
		return Friend{}, err
	}
	if err := tx.Commit(ctx); err != nil {
		return Friend{}, err
	}
	metrics.FriendRequests.WithLabelValues("sent_to_bot").Inc()
	return p.friend(), nil
}

// cancelBotRequest removes my request to the bot uid. found is false when
// there is none.
func (s *Service) cancelBotRequest(ctx context.Context, me uuid.UUID, uid string) (found bool, err error) {
	n, err := s.rdb.HDel(ctx, BotRequestsKey(me), strings.ToLower(strings.TrimSpace(uid))).Result()
	if err != nil {
		return false, err
	}
	if n > 0 {
		metrics.FriendRequests.WithLabelValues("cancelled").Inc()
	}
	return n > 0, nil
}

// isBot reports whether uid is a live bot that me can see.
func (s *Service) isBot(ctx context.Context, me uuid.UUID, uid string) bool {
	if s.opts.Bots == nil {
		return false
	}
	_, err := s.opts.Bots(ctx, me, strings.ToLower(strings.TrimSpace(uid)))
	return err == nil
}
