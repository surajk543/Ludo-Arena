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
//	sess:{sid}      hash {uid, cur, actor}  TTL = refresh TTL (sliding)
//	rt:{sha256}     sid                     TTL = refresh TTL
//
// Each refresh rotates the token. Presenting a token that is no longer the
// family's current token (reuse after rotation, i.e. likely theft) revokes the
// whole family. Old token hashes stay as tombstones until they expire so reuse
// is detected. Access tokens are checked against sess:{sid} on every use, so
// logout and revocation take effect immediately.
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

// Create starts a new session family and returns (sid, refreshToken).
func (s *Sessions) Create(ctx context.Context, userID uuid.UUID, actor string) (string, string, error) {
	sid := randomID(16)
	rt := NewSecret("rt_")
	h := HashSecret(rt)
	pipe := s.rdb.TxPipeline()
	pipe.HSet(ctx, "sess:"+sid, "uid", userID.String(), "cur", h, "actor", actor)
	pipe.PExpire(ctx, "sess:"+sid, s.ttl)
	pipe.Set(ctx, "rt:"+h, sid, s.ttl)
	if _, err := pipe.Exec(ctx); err != nil {
		return "", "", err
	}
	return sid, rt, nil
}

// rotate: KEYS[1]=rt:{old}  ARGV[1]=old hash ARGV[2]=new hash ARGV[3]=ttl ms
// returns {status, sid, uid, actor}; status 1 ok, 0 invalid, -1 reused.
var rotate = redis.NewScript(`
local sid = redis.call('GET', KEYS[1])
if not sid then return {0, '', '', ''} end
local skey = 'sess:' .. sid
local cur = redis.call('HGET', skey, 'cur')
if not cur then return {0, '', '', ''} end
if cur ~= ARGV[1] then
  redis.call('DEL', skey)
  return {-1, sid, '', ''}
end
local uid = redis.call('HGET', skey, 'uid')
local actor = redis.call('HGET', skey, 'actor')
redis.call('HSET', skey, 'cur', ARGV[2])
redis.call('PEXPIRE', skey, ARGV[3])
redis.call('SET', 'rt:' .. ARGV[2], sid, 'PX', ARGV[3])
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
	}
	uid, err := uuid.Parse(res[2].(string))
	if err != nil {
		return "", uuid.Nil, "", "", ErrRefreshInvalid
	}
	return res[1].(string), uid, res[3].(string), newRefresh, nil
}

// Active reports whether the session family still exists.
func (s *Sessions) Active(ctx context.Context, sid string) (bool, error) {
	n, err := s.rdb.Exists(ctx, "sess:"+sid).Result()
	return n == 1, err
}

// Revoke ends a session family.
func (s *Sessions) Revoke(ctx context.Context, sid string) error {
	return s.rdb.Del(ctx, "sess:"+sid).Err()
}

// CreateBot stores a bot session (no refresh token; short TTL).
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
