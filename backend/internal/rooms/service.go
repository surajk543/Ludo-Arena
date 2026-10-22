package rooms

import (
	"context"
	"crypto/rand"
	"encoding/binary"
	"encoding/json"
	"errors"
	"hash/fnv"
	"log/slog"
	mrand "math/rand/v2"
	"strconv"
	"sync"
	"time"

	"github.com/google/uuid"
	"github.com/redis/go-redis/v9"

	"ludoarena/internal/apppolicy"
	"ludoarena/internal/auth"
	"ludoarena/internal/config"
	"ludoarena/internal/gameevents"
	"ludoarena/internal/notify"
	"ludoarena/internal/playerinfo"
	"ludoarena/internal/profile"
	"ludoarena/internal/protocol"
	"ludoarena/internal/ratelimit"
	"ludoarena/internal/wallet"
)

// Dice produces server-side die values (1..6).
type Dice interface{ Roll() int }

// CryptoDice uses crypto/rand with rejection sampling (unbiased).
type CryptoDice struct{}

// Roll implements Dice.
func (CryptoDice) Roll() int {
	var b [1]byte
	for {
		if _, err := rand.Read(b[:]); err != nil {
			panic(err)
		}
		if b[0] < 252 { // 252 = 6*42: reject the biased tail
			return int(b[0]%6) + 1
		}
	}
}

// SeededDice is deterministic (tests and load tests in non-production only).
type SeededDice struct {
	mu sync.Mutex
	r  *mrand.Rand
}

// NewSeededDice returns deterministic dice.
func NewSeededDice(seed int64) *SeededDice {
	return &SeededDice{r: mrand.New(mrand.NewPCG(uint64(seed), uint64(seed)^0x9e3779b97f4a7c15))}
}

// Roll implements Dice.
func (d *SeededDice) Roll() int {
	d.mu.Lock()
	defer d.mu.Unlock()
	return d.r.IntN(6) + 1
}

// Deps wires the room service.
type Deps struct {
	RDB         *redis.Client
	Wallets     *wallet.Store
	Profiles    *profile.Service
	Progression playerinfo.Provider
	// Pictures picks profile pictures for bot personas (nil: bots wear none).
	Pictures playerinfo.PictureSource
	// Catalog lists the cosmetics bot personas may show (nil: starter look).
	Catalog   playerinfo.CatalogSource
	Recorder  gameevents.Recorder
	Inviter   gameevents.Inviter
	Inventory gameevents.Inventory
	Policy    *apppolicy.Store
	BotAuth   *auth.BotAuth
	Limiter   *ratelimit.Limiter
	Notifier  *notify.Publisher
	Log       *slog.Logger
	Game      config.GameConfig
	Bots      config.BotConfig
	Env       string
	FullSnaps bool // benchmark: attach a full snapshot to every delta event
	Dice      Dice
	Now       func() time.Time
	// StatsInterval is how often the live-game gauges are refreshed
	// (GAME_STATS_INTERVAL; default 15 s). See stats.go.
	StatsInterval time.Duration
}

// Service is the room engine.
type Service struct {
	Deps
	st       store
	locks    [256]sync.Mutex
	instance string // random per process: owner id of the game-stats lease
}

// New returns a Service.
func New(d Deps) *Service {
	if d.Dice == nil {
		d.Dice = CryptoDice{}
	}
	if d.Now == nil {
		d.Now = time.Now
	}
	if d.Progression == nil {
		d.Progression = playerinfo.StarterProvider{}
	}
	return &Service{Deps: d, st: store{rdb: d.RDB}, instance: uuid.NewString()}
}

func (s *Service) nowMs() int64 { return s.Now().UnixMilli() }

func (s *Service) lock(roomID string) *sync.Mutex {
	h := fnv.New32a()
	h.Write([]byte(roomID))
	return &s.locks[h.Sum32()%uint32(len(s.locks))]
}

// mutation collects the effects of one room change.
type mutation struct {
	s       *Service
	r       *Room
	msgs    []json.RawMessage
	ops     []sideOp
	guards  []guard
	extraTo []string
	after   []func(context.Context)
	ttl     time.Duration
	write   bool // state changed (even without events)
}

// emitV appends a versioned event; build receives the new v.
func (m *mutation) emitV(t string, build func(v int64) any) {
	m.r.V++
	m.write = true
	m.msgs = append(m.msgs, protocol.Encode(t, "", build(m.r.V)))
}

// emitSnapshot appends a versioned full-snapshot event.
func (m *mutation) emitSnapshot(t, reason string) {
	m.r.V++
	m.write = true
	v := m.r.View()
	payload := map[string]any{"room": v}
	if reason != "" {
		payload["reason"] = reason
	}
	m.msgs = append(m.msgs, protocol.Encode(t, "", payload))
}

// emit appends a non-versioned room message (chat, etc.).
func (m *mutation) emit(t string, payload any) {
	m.msgs = append(m.msgs, protocol.Encode(t, "", payload))
}

func (m *mutation) op(o sideOp)                  { m.ops = append(m.ops, o); m.write = true }
func (m *mutation) then(f func(context.Context)) { m.after = append(m.after, f) }

func (m *mutation) schedule(kind, arg string, at int64) {
	m.op(sideOp{Op: "zadd", K: schedKey, V: kind + "|" + m.r.ID + "|" + arg, S: float64(at)})
}

func (m *mutation) setPointer(userID string) {
	m.guards = append(m.guards, guard{K: userRoomKey(userID), Eq: m.r.ID})
	m.op(sideOp{Op: "set", K: userRoomKey(userID), V: m.r.ID, TTL: (6 * time.Hour).Milliseconds()})
}

func (m *mutation) clearPointer(userID string) {
	m.op(sideOp{Op: "delif", K: userRoomKey(userID), V: m.r.ID})
}

// fullSnap attaches the full snapshot to a delta payload in benchmark mode.
func (m *mutation) fullSnap() *View {
	if !m.s.FullSnaps {
		return nil
	}
	v := m.r.View()
	return &v
}

// ttlFor returns the Redis TTL for the room's status.
func (s *Service) ttlFor(r *Room) time.Duration {
	switch r.Status {
	case StatusLobby:
		return s.Game.LobbyTTL
	case StatusPlaying:
		return 3 * time.Hour
	case StatusFinished:
		return s.Game.FinishedTTL + s.Game.RematchWindow
	}
	return 2 * time.Minute
}

var errNoop = errors.New("noop")

// mutate loads the room, applies fn to a fresh copy and commits atomically,
// retrying on concurrent modification. fn may return errNoop to skip writing.
func (s *Service) mutate(ctx context.Context, roomID string, fn func(m *mutation) error) (*Room, error) {
	r, after, err := s.mutateLocked(ctx, roomID, fn)
	// Post-commit actions run without the room lock: they may mutate this or
	// another room (which could share a lock stripe).
	for _, f := range after {
		f(ctx)
	}
	return r, err
}

func (s *Service) mutateLocked(ctx context.Context, roomID string, fn func(m *mutation) error) (*Room, []func(context.Context), error) {
	l := s.lock(roomID)
	l.Lock()
	defer l.Unlock()
	for attempt := 0; attempt < 8; attempt++ {
		r, rev, err := s.st.load(ctx, roomID)
		if errors.Is(err, errNoRoom) {
			return nil, nil, protocol.ErrRoomNotFound
		}
		if err != nil {
			return nil, nil, err
		}
		m := &mutation{s: s, r: r}
		if err := fn(m); err != nil {
			if errors.Is(err, errNoop) {
				return r, m.after, nil
			}
			return r, m.after, err
		}
		if !m.write && len(m.msgs) == 0 {
			return r, m.after, nil
		}
		if err := s.commit(ctx, m, rev); err != nil {
			if errors.Is(err, errConflict) {
				time.Sleep(time.Duration(mrand.IntN(5)+1) * time.Millisecond)
				continue
			}
			if errors.Is(err, errGuard) {
				return r, nil, protocol.ErrAlreadyInRoom
			}
			return r, nil, err
		}
		return m.r, m.after, nil
	}
	return nil, nil, protocol.ErrInternal
}

// create commits a brand-new room.
func (s *Service) create(ctx context.Context, r *Room, fn func(m *mutation) error) (*Room, error) {
	m := &mutation{s: s, r: r, write: true}
	if err := fn(m); err != nil {
		return nil, err
	}
	if err := s.commit(ctx, m, "0"); err != nil {
		if errors.Is(err, errGuard) {
			return nil, protocol.ErrAlreadyInRoom
		}
		return nil, err
	}
	for _, f := range m.after {
		f(ctx)
	}
	return m.r, nil
}

func (s *Service) commit(ctx context.Context, m *mutation, rev string) error {
	ttl := m.ttl
	if ttl == 0 {
		ttl = s.ttlFor(m.r)
	}
	if m.r.Code != "" && m.r.Status != StatusClosed {
		m.ops = append(m.ops, sideOp{Op: "set", K: codeKey(m.r.Code), V: m.r.ID, TTL: ttl.Milliseconds()})
	}
	var b *Batch
	if len(m.msgs) > 0 {
		to := append(m.r.MemberIDs(), m.extraTo...)
		b = &Batch{Room: m.r.ID, To: to, Msgs: m.msgs}
	}
	return s.st.commit(ctx, m.r, rev, ttl, m.guards, m.ops, b)
}

// Snapshot returns the current view of a room for a member, or an error.
func (s *Service) Snapshot(ctx context.Context, userID, roomID string) (*View, error) {
	r, _, err := s.st.load(ctx, roomID)
	if errors.Is(err, errNoRoom) {
		return nil, protocol.ErrRoomNotFound
	}
	if err != nil {
		return nil, err
	}
	if r.SeatOf(userID) < 0 {
		return nil, protocol.ErrNotInRoom
	}
	v := r.View()
	return &v, nil
}

// ActiveRoom returns the user's current room id ("" if none).
func (s *Service) ActiveRoom(ctx context.Context, userID string) string {
	id, err := s.RDB.Get(ctx, userRoomKey(userID)).Result()
	if err != nil {
		return ""
	}
	return id
}

// notifyUser sends a message to one user (any instance).
func (s *Service) notifyUser(ctx context.Context, userID, t string, payload any) {
	if s.Notifier != nil {
		s.Notifier.Send(ctx, userID, protocol.Encode(t, "", payload))
	}
}

func newRoomID() string {
	var b [9]byte
	_, _ = rand.Read(b[:])
	return "r_" + strconv.FormatUint(binary.BigEndian.Uint64(b[:8]), 36) + strconv.Itoa(int(b[8])%10)
}

func parseUUID(s string) uuid.UUID {
	id, err := uuid.Parse(s)
	if err != nil {
		return uuid.Nil
	}
	return id
}
