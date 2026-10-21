package auth

import (
	"context"
	"errors"
	"time"

	"github.com/google/uuid"
	"github.com/redis/go-redis/v9"
)

// Sessions stores refresh-token families in Redis.
//
//	sess:{sid}       hash {uid, cur, actor}  TTL = refresh TTL (sliding)
//	rt:{sha256}      sid                     TTL = refresh TTL
//	usess:{userId}   sid                     TTL = refresh TTL (sliding)  humans only
//	sessrep:{sid}    newer sid               TTL = refresh TTL
//
// Each refresh rotates the token. Presenting a token that is no longer the
// family's current token (reuse after rotation, i.e. likely theft) revokes the
// whole family. Old token hashes stay as tombstones until they expire so reuse
// is detected. Access tokens are checked against sess:{sid} on every use, so
// logout and revocation take effect immediately.
//
// An account has at most one live human session: usess:{userId} points at it.
// A new human sign-in atomically replaces the pointer and deletes the previous
// session, leaving a sessrep:{oldSid} tombstone so the old device is told
// "session_replaced" (signed in on another device) rather than a generic
// revocation. Bot sessions never touch the pointer.
type Sessions struct {
	rdb *redis.Client
	ttl time.Duration
}

// NewSessions returns a Sessions store.
func NewSessions(rdb *redis.Client, ttl time.Duration) *Sessions {
	return &Sessions{rdb: rdb, ttl: ttl}
}

// Errors.
var (
	ErrRefreshInvalid = errors.New("refresh token invalid or expired")
	ErrRefreshReused  = errors.New("refresh token reused; session revoked")
)

// createHuman: KEYS[1]=sess:{sid} KEYS[2]=rt:{hash} KEYS[3]=usess:{uid}
// ARGV[1]=sid ARGV[2]=uid ARGV[3]=hash ARGV[4]=ttl ms
// Creates the session, makes it the account's current human session and
// revokes the previous one (tombstoned). Returns the replaced sid or an
// empty string.
var createHuman = redis.NewScript(`
redis.call('HSET', KEYS[1], 'uid', ARGV[2], 'cur', ARGV[3], 'actor', 'human')
redis.call('PEXPIRE', KEYS[1], ARGV[4])
redis.call('SET', KEYS[2], ARGV[1], 'PX', ARGV[4])
local old = redis.call('GET', KEYS[3])
redis.call('SET', KEYS[3], ARGV[1], 'PX', ARGV[4])
if old and old ~= ARGV[1] and redis.call('DEL', 'sess:' .. old) == 1 then
  redis.call('SET', 'sessrep:' .. old, ARGV[1], 'PX', ARGV[4])
  return old
end
return ''`)

// CreateHuman starts a new human session family for the account and returns
// (sid, refreshToken, replacedSid). replacedSid is the account's previous
// live human session, revoked by this sign-in ("" if there was none).
func (s *Sessions) CreateHuman(ctx context.Context, userID uuid.UUID) (sid, refresh, replaced string, err error) {
	sid = randomID(16)
	refresh = NewSecret("rt_")
	h := HashSecret(refresh)
	replaced, err = createHuman.Run(ctx, s.rdb,
		[]string{"sess:" + sid, "rt:" + h, "usess:" + userID.String()},
		sid, userID.String(), h, s.ttl.Milliseconds()).Text()
	if err != nil {
		return "", "", "", err
	}
	return sid, refresh, replaced, nil
}

// rotate: KEYS[1]=rt:{old}  ARGV[1]=old hash ARGV[2]=new hash ARGV[3]=ttl ms
// returns {status, sid, uid, actor}; status 1 ok, 0 invalid, -1 reused,
// -2 replaced by a newer sign-in.
//
// A human session slides the account pointer with it; a live session whose
// account has no pointer (created before the pointer existed) adopts it.
var rotate = redis.NewScript(`
local sid = redis.call('GET', KEYS[1])
if not sid then return {0, '', '', ''} end
local skey = 'sess:' .. sid
local cur = redis.call('HGET', skey, 'cur')
if not cur then
  if redis.call('EXISTS', 'sessrep:' .. sid) == 1 then return {-2, sid, '', ''} end
  return {0, '', '', ''}
end
local uid = redis.call('HGET', skey, 'uid')
local actor = redis.call('HGET', skey, 'actor')
if cur ~= ARGV[1] then
  redis.call('DEL', skey)
  if actor == 'human' and redis.call('GET', 'usess:' .. uid) == sid then
    redis.call('DEL', 'usess:' .. uid)
  end
  return {-1, sid, '', ''}
end
redis.call('HSET', skey, 'cur', ARGV[2])
redis.call('PEXPIRE', skey, ARGV[3])
redis.call('SET', 'rt:' .. ARGV[2], sid, 'PX', ARGV[3])
if actor == 'human' then
  local p = redis.call('GET', 'usess:' .. uid)
  if (not p) or p == sid then redis.call('SET', 'usess:' .. uid, sid, 'PX', ARGV[3]) end
end
return {1, sid, uid, actor}`)

// Rotate exchanges a refresh token for a new one in the same family.
func (s *Sessions) Rotate(ctx context.Context, refresh string) (sid string, userID uuid.UUID, actor, newRefresh string, err error) {
	if len(refresh) < 16 || len(refresh) > 128 {
		return "", uuid.Nil, "", "", ErrRefreshInvalid
	}
	old := HashSecret(refresh)
	newRefresh = NewSecret("rt_")
	res, err := rotate.Run(ctx, s.rdb, []string{"rt:" + old}, old, HashSecret(newRefresh), s.ttl.Milliseconds()).Slice()
	if err != nil {
		return "", uuid.Nil, "", "", err
	}
	switch res[0].(int64) {
	case 0:
		return "", uuid.Nil, "", "", ErrRefreshInvalid
	case -1:
		return "", uuid.Nil, "", "", ErrRefreshReused
	case -2:
		return "", uuid.Nil, "", "", ErrSessionReplaced
	}
	uid, err := uuid.Parse(res[2].(string))
	if err != nil {
		return "", uuid.Nil, "", "", ErrRefreshInvalid
	}
	return res[1].(string), uid, res[3].(string), newRefresh, nil
}

// Check reports whether the session family is live: nil, ErrSessionReplaced
// (revoked by a newer sign-in of the same account), ErrRevoked, or a Redis
// error. The common (live) case costs one EXISTS.
func (s *Sessions) Check(ctx context.Context, sid string) error {
	n, err := s.rdb.Exists(ctx, "sess:"+sid).Result()
	if err != nil {
		return err
	}
	if n == 1 {
		return nil
	}
	if n, err = s.rdb.Exists(ctx, "sessrep:"+sid).Result(); err != nil {
		return err
	}
	if n == 1 {
		return ErrSessionReplaced
	}
	return ErrRevoked
}

// endHuman: KEYS[1]=sess:{sid} KEYS[2]=usess:{uid} ARGV[1]=sid
var endHuman = redis.NewScript(`
redis.call('DEL', KEYS[1])
if redis.call('GET', KEYS[2]) == ARGV[1] then redis.call('DEL', KEYS[2]) end
return 1`)

// EndHuman ends a human session (logout): the family is deleted and the
// account pointer cleared if it still names this session. No tombstone is
// written, so the session reads as plainly revoked.
func (s *Sessions) EndHuman(ctx context.Context, userID uuid.UUID, sid string) error {
	return endHuman.Run(ctx, s.rdb, []string{"sess:" + sid, "usess:" + userID.String()}, sid).Err()
}

// endByRefresh: KEYS[1]=rt:{hash} ARGV[1]=hash
// Ends the human session only if hash is its CURRENT refresh token (an old,
// rotated token never revokes and never counts as reuse here). Returns 1 if a
// session was ended.
var endByRefresh = redis.NewScript(`
local sid = redis.call('GET', KEYS[1])
if not sid then return 0 end
local skey = 'sess:' .. sid
if redis.call('HGET', skey, 'cur') ~= ARGV[1] then return 0 end
if redis.call('HGET', skey, 'actor') ~= 'human' then return 0 end
local uid = redis.call('HGET', skey, 'uid')
redis.call('DEL', skey)
if redis.call('GET', 'usess:' .. uid) == sid then redis.call('DEL', 'usess:' .. uid) end
return 1`)

// EndByRefresh ends the human session whose current refresh token is
// refresh (logout without a valid access token). Unknown, malformed or
// rotated tokens are a silent no-op. No tombstone is written.
func (s *Sessions) EndByRefresh(ctx context.Context, refresh string) error {
	if len(refresh) < 16 || len(refresh) > 128 {
		return nil
	}
	h := HashSecret(refresh)
	return endByRefresh.Run(ctx, s.rdb, []string{"rt:" + h}, h).Err()
}

// Revoke ends a session family (bot and controller sessions).
func (s *Sessions) Revoke(ctx context.Context, sid string) error {
	return s.rdb.Del(ctx, "sess:"+sid).Err()
}

// CreateBot stores a bot session (no refresh token; short TTL). Bot sessions
// are independent of each other and of the per-account human session pointer.
func (s *Sessions) CreateBot(ctx context.Context, botID uuid.UUID, ttl time.Duration, meta map[string]any) (string, error) {
	sid := randomID(16)
	fields := []any{"uid", botID.String(), "actor", ActorBot}
	for k, v := range meta {
		fields = append(fields, k, v)
	}
	pipe := s.rdb.TxPipeline()
	pipe.HSet(ctx, "sess:"+sid, fields...)
	pipe.PExpire(ctx, "sess:"+sid, ttl)
	_, err := pipe.Exec(ctx)
	return sid, err
}
