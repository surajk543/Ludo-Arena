package rooms

import (
	"context"
	"encoding/json"
	"errors"
	"strconv"
	"time"

	"github.com/redis/go-redis/v9"
)

// Redis keys (see docs/redis-keys.md).
func roomKey(id string) string      { return "room:" + id }
func userRoomKey(uid string) string { return "user:" + uid + ":room" }
func codeKey(code string) string    { return "roomcode:" + code }
func openKey(game, variant string, capacity int, pool string) string {
	return "mm:open:" + pool + ":" + game + ":" + variant + ":" + strconv.Itoa(capacity)
}

const (
	schedKey        = "sched"
	liveRoomsKey    = "idx:rooms:live" // live-room index (see stats.go)
	roomChanPrefix  = "ev:room:"
	userChanPrefix  = "ev:user:"
	botQueueKey     = "bot:assignments"
	botAssignPrefix = "botasg:"
)

// sideOp is an extra Redis write applied atomically with a room commit.
type sideOp struct {
	Op  string  `json:"op"` // set | del | delif | zadd | zrem | rpush
	K   string  `json:"k"`
	V   string  `json:"v,omitempty"`
	TTL int64   `json:"ttl,omitempty"` // ms (set only)
	S   float64 `json:"s,omitempty"`   // zadd score
}

// guard aborts the commit if key exists with a value other than Eq.
type guard struct {
	K  string `json:"k"`
	Eq string `json:"eq"`
}

// commitScript performs, atomically: optimistic revision check, guards,
// state write + TTL, side ops, the live-room index entry, and PUBLISH of the
// event batch. Because Redis executes scripts serially, events are published
// in commit order even when several backend instances mutate the same room.
//
// KEYS[1] room hash, KEYS[2] live-room index. ARGV[8] is the index op
// ('set' | 'del'), ARGV[9] the room id and ARGV[10] the room summary; the
// entry is stored as "{rev}|{summary}" so readers can verify it belongs to
// the room's current revision (stats.go).
var commitScript = redis.NewScript(`
local cur = redis.call('HGET', KEYS[1], 'rev')
if ARGV[1] == '0' then
  if cur then return -1 end
else
  if cur ~= ARGV[1] then return -1 end
end
local guards = cjson.decode(ARGV[4])
for _, g in ipairs(guards) do
  local v = redis.call('GET', g.k)
  if v and v ~= g.eq then return -2 end
end
local rev = tostring(tonumber(ARGV[1]) + 1)
redis.call('HSET', KEYS[1], 'rev', rev, 's', ARGV[2])
redis.call('PEXPIRE', KEYS[1], ARGV[3])
local ops = cjson.decode(ARGV[5])
for _, o in ipairs(ops) do
  if o.op == 'set' then
    if o.ttl and o.ttl > 0 then redis.call('SET', o.k, o.v, 'PX', o.ttl) else redis.call('SET', o.k, o.v) end
  elseif o.op == 'del' then
    redis.call('DEL', o.k)
  elseif o.op == 'delif' then
    if redis.call('GET', o.k) == o.v then redis.call('DEL', o.k) end
  elseif o.op == 'zadd' then
    redis.call('ZADD', o.k, o.s, o.v)
  elseif o.op == 'zrem' then
    redis.call('ZREM', o.k, o.v)
  elseif o.op == 'rpush' then
    redis.call('RPUSH', o.k, o.v)
  end
end
if ARGV[8] == 'set' then
  redis.call('HSET', KEYS[2], ARGV[9], rev .. '|' .. ARGV[10])
elseif ARGV[8] == 'del' then
  redis.call('HDEL', KEYS[2], ARGV[9])
end
if ARGV[7] ~= '' then redis.call('PUBLISH', ARGV[6], ARGV[7]) end
return tonumber(rev)`)

var (
	errConflict = errors.New("room revision conflict")
	errGuard    = errors.New("guard failed")
	errNoRoom   = errors.New("room not found")
)

// Batch is the internal pub/sub payload routed by the gateway.
type Batch struct {
	Room string            `json:"room"`
	To   []string          `json:"to"`   // internal user ids (never sent to clients)
	Msgs []json.RawMessage `json:"msgs"` // pre-encoded client envelopes, in order
	// Resync lists recipients whose queued deltas must be superseded by a
	// fresh snapshot (unused by the engine today; reserved).
}

type store struct{ rdb *redis.Client }

func (st *store) load(ctx context.Context, id string) (*Room, string, error) {
	vals, err := st.rdb.HMGet(ctx, roomKey(id), "rev", "s").Result()
	if err != nil {
		return nil, "", err
	}
	rev, _ := vals[0].(string)
	raw, _ := vals[1].(string)
	if rev == "" || raw == "" {
		return nil, "", errNoRoom
	}
	var r Room
	if err := json.Unmarshal([]byte(raw), &r); err != nil {
		return nil, "", err
	}
	return &r, rev, nil
}

// ErrRoomGone is returned by LoadRoom when the room no longer exists
// (finished rooms are kept for FINISHED_ROOM_TTL + the rematch window,
// closed rooms for 2 minutes).
var ErrRoomGone = errNoRoom

// LoadRoom reads a room's current state from Redis without a Service. It is
// read-only (player reports use it to verify seats) and returns ErrRoomGone
// when the room no longer exists.
func LoadRoom(ctx context.Context, rdb *redis.Client, roomID string) (*Room, error) {
	r, _, err := (&store{rdb: rdb}).load(ctx, roomID)
	return r, err
}

func (st *store) commit(ctx context.Context, r *Room, rev string, ttl time.Duration,
	guards []guard, ops []sideOp, b *Batch) error {
	raw, err := json.Marshal(r)
	if err != nil {
		return err
	}
	if guards == nil {
		guards = []guard{}
	}
	if ops == nil {
		ops = []sideOp{}
	}
	g, _ := json.Marshal(guards)
	o, _ := json.Marshal(ops)
	pub := ""
	if b != nil && len(b.Msgs) > 0 {
		pb, err := json.Marshal(b)
		if err != nil {
			return err
		}
		pub = string(pb)
	}
	if rev == "" {
		rev = "0"
	}
	idxOp, summary := liveEntry(r)
	res, err := commitScript.Run(ctx, st.rdb, []string{roomKey(r.ID), liveRoomsKey},
		rev, string(raw), ttl.Milliseconds(), string(g), string(o), roomChanPrefix+r.ID, pub,
		idxOp, r.ID, summary).Int64()
	if err != nil {
		return err
	}
	switch res {
	case -1:
		return errConflict
	case -2:
		return errGuard
	}
	return nil
}

func jsonMarshal(v any) ([]byte, error) { return json.Marshal(v) }
