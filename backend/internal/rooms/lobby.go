package rooms

import (
	"context"
	"crypto/rand"
	"errors"
	"math"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/google/uuid"

	"ludoarena/internal/auth"
	"ludoarena/internal/metrics"
	"ludoarena/internal/playerinfo"
	"ludoarena/internal/protocol"
	"ludoarena/internal/ratelimit"
)

// Caller identifies who issued a command.
type Caller struct {
	UserID   string
	Bot      bool
	LoadTest bool
	BotRoom  string
	BotName  string // display name of a bot session (from its token)
	Epoch    int64
}

// CallerFrom builds a Caller from an authenticated principal.
func CallerFrom(p auth.Principal, epoch int64) Caller {
	return Caller{UserID: p.UserID.String(), Bot: p.IsBot(), LoadTest: p.LoadTest, BotRoom: p.RoomID,
		BotName: p.BotName, Epoch: epoch}
}

func validGame(game, variant string, capacity int) error {
	switch game {
	case GameLudo:
		if variant != "classic" && variant != "quick" {
			return protocol.ErrBadRequest
		}
	case GameSnakes:
		if variant != "classic" {
			return protocol.ErrBadRequest
		}
	default:
		return protocol.ErrBadRequest
	}
	if capacity < 2 || capacity > 4 {
		return protocol.ErrBadRequest
	}
	return nil
}

// EntryFee is the live coin entry fee for a new room (or public rematch room)
// of game. Precedence: the app-policy file's "entryFees" (hot-reloaded) >
// ENTRY_FEE_* > built-in default. A room stores the fee it was created with
// (Room.EntryFee) for all of its rounds, so a policy change never alters rooms
// that already exist. Practice and load-test games stay free; bots pay it like
// people (startGame).
func (s *Service) EntryFee(game string) int64 {
	fallback := s.Game.EntryFeeLudo
	if game == GameSnakes {
		fallback = s.Game.EntryFeeSnakes
	}
	if s.Policy == nil {
		return fallback
	}
	return s.Policy.EntryFee(game, fallback)
}

// EntryFees returns the live entry fee of every game (GET /app/config).
func (s *Service) EntryFees() map[string]int64 {
	return map[string]int64{GameLudo: s.EntryFee(GameLudo), GameSnakes: s.EntryFee(GameSnakes)}
}

// playerFor builds a seat for a human from profile + progression data.
func (s *Service) playerFor(ctx context.Context, userID string) Player {
	uid := parseUUID(userID)
	prof := s.Profiles.Get(ctx, uid)
	sum, err := playerinfo.SeatSummary(ctx, s.Progression, uid) // Redis-cached (progression/cache.go)
	if err != nil {
		sum = playerinfo.Starter()
	}
	cos := map[string]string{}
	for _, slot := range []string{"dice", "token", "frame", "trail", "victory"} {
		cos[slot] = sum.Loadout[slot]
	}
	return Player{UserID: userID, UID: prof.UID, Name: prof.Name, Avatar: prof.Avatar, Level: sum.Level,
		Title: sum.Title, Cosmetics: cos, Picture: sum.Picture, JoinedAt: s.nowMs()}
}

// ensureFree makes sure the user is not seated in another active room. A
// stale pointer (room gone, finished, or player already left) is cleared;
// finished rooms are left automatically (declining the rematch).
func (s *Service) ensureFree(ctx context.Context, userID string) error {
	roomID := s.ActiveRoom(ctx, userID)
	if roomID == "" {
		return nil
	}
	r, _, err := s.st.load(ctx, roomID)
	if errors.Is(err, errNoRoom) {
		s.RDB.Del(ctx, userRoomKey(userID))
		return nil
	}
	if err != nil {
		return err
	}
	seat := r.SeatOf(userID)
	switch {
	case seat < 0 || r.Status == StatusClosed:
		s.clearStalePointer(ctx, userID, roomID)
		return nil
	case r.Status == StatusFinished, r.Players[seat].Forfeited:
		if err := s.Leave(ctx, Caller{UserID: userID}, roomID); err != nil && !errors.Is(err, protocol.ErrNotInRoom) {
			return err
		}
		s.clearStalePointer(ctx, userID, roomID)
		return nil
	}
	return protocol.ErrAlreadyInRoom
}

func (s *Service) clearStalePointer(ctx context.Context, userID, roomID string) {
	if cur, _ := s.RDB.Get(ctx, userRoomKey(userID)).Result(); cur == roomID {
		s.RDB.Del(ctx, userRoomKey(userID))
	}
}

func (s *Service) checkFunds(ctx context.Context, c Caller, fee int64) error {
	if c.Bot || fee == 0 {
		return nil
	}
	w, err := s.Wallets.Get(ctx, parseUUID(c.UserID))
	if err != nil {
		return err
	}
	if w.Coins < fee {
		return protocol.ErrInsufficientFunds
	}
	return nil
}

// ---- public matchmaking ----

// MatchmakingJoin seats the caller in the best open public lobby or creates one.
func (s *Service) MatchmakingJoin(ctx context.Context, c Caller, game, variant string, capacity int) (*Room, error) {
	if err := validGame(game, variant, capacity); err != nil {
		return nil, err
	}
	if c.Bot && !c.LoadTest {
		return nil, protocol.ErrBotsNotAllowed
	}
	if !c.Bot {
		if ok, _ := s.Limiter.Allow(ctx, ratelimit.MatchmakePerUser, c.UserID); !ok {
			return nil, protocol.ErrRateLimited
		}
	}
	seat := s.seatAsync(ctx, c)
	if err := s.ensureFree(ctx, c.UserID); err != nil {
		return nil, err
	}
	pool := "live"
	if c.LoadTest {
		pool = "loadtest"
	}
	fee := s.EntryFee(game)
	if c.LoadTest {
		fee = 0
	}
	if err := s.checkFunds(ctx, c, fee); err != nil {
		return nil, err
	}
	me := <-seat
	me.MatchmakeAt = s.nowMs()

	key := openKey(game, variant, capacity, pool)
	ids, err := s.RDB.ZRange(ctx, key, 0, 19).Result()
	if err != nil {
		return nil, err
	}
	for _, id := range s.rankCandidates(ctx, ids, me.Level) {
		var full bool
		r, err := s.mutate(ctx, id, func(m *mutation) error {
			r := m.r
			if r.Status != StatusLobby || r.Mode != ModePublic || len(r.Players) >= r.Capacity || r.LoadTest != c.LoadTest {
				return errSkip
			}
			if r.SeatOf(c.UserID) >= 0 {
				return nil
			}
			if r.EntryFee != fee {
				// Opened before an entry-fee change: the caller was checked
				// (and shown) the current fee, so only join lobbies at it.
				return errSkip
			}
			r.Players = append(r.Players, me)
			m.setPointer(c.UserID)
			full = len(r.Players) == r.Capacity
			m.emitSnapshot(protocol.TRoomUpdated, "joined")
			return nil
		})
		if errors.Is(err, errSkip) || errors.Is(err, protocol.ErrRoomNotFound) {
			if errors.Is(err, protocol.ErrRoomNotFound) {
				s.RDB.ZRem(ctx, key, id)
			}
			continue
		}
		if err != nil {
			return nil, err
		}
		if full {
			if err := s.startGame(ctx, id); err != nil {
				s.Log.Warn("start after fill failed", "error", err.Error())
			}
		}
		return r, nil
	}

	now := s.nowMs()
	r := &Room{ID: newRoomID(), Game: game, Variant: variant, Mode: ModePublic, Capacity: capacity,
		Status: StatusLobby, HostSeat: -1, EntryFee: fee, Round: 1, CreatedAt: now, LoadTest: c.LoadTest,
		FillDeadline: now + s.Game.FillTimeout.Milliseconds(), Players: []Player{me}}
	return s.create(ctx, r, func(m *mutation) error {
		m.setPointer(c.UserID)
		m.op(sideOp{Op: "zadd", K: key, V: r.ID, S: float64(now)})
		m.schedule("fill", "1", r.FillDeadline)
		m.emitSnapshot(protocol.TRoomUpdated, "created")
		return nil
	})
}

var errSkip = errors.New("skip candidate")

// rankCandidates orders open lobbies by closeness of average level, then age.
func (s *Service) rankCandidates(ctx context.Context, ids []string, level int) []string {
	type cand struct {
		id   string
		dist float64
		age  int64
	}
	var cs []cand
	for i, id := range ids {
		r, _, err := s.st.load(ctx, id)
		if err != nil || r.Status != StatusLobby || len(r.Players) >= r.Capacity {
			continue
		}
		sum := 0
		for _, p := range r.Players {
			sum += p.Level
		}
		avg := float64(sum) / math.Max(1, float64(len(r.Players)))
		cs = append(cs, cand{id: id, dist: math.Abs(avg - float64(level)), age: int64(i)})
	}
	sort.SliceStable(cs, func(a, b int) bool {
		// Level bands of 5 so close levels don't starve older lobbies.
		da, db := math.Floor(cs[a].dist/5), math.Floor(cs[b].dist/5)
		if da != db {
			return da < db
		}
		return cs[a].age < cs[b].age
	})
	out := make([]string, len(cs))
	for i, c := range cs {
		out[i] = c.id
	}
	return out
}

func (s *Service) newSeat(ctx context.Context, c Caller) Player {
	var p Player
	if c.Bot {
		// Load-test bots (matchmaking.join): a fresh, unremembered persona
		// look on the session's own id; the uid has the people's format.
		rng, items, o := newRNG(), s.catalogItems(), s.wardrobe()
		look := newPersona(rng, items, o)
		look.nextMatch(rng, items, o)
		look.ID = parseUUID(c.UserID)
		p = s.botSeat(look, s.Profiles.PublicID(look.ID), botName(c.BotName, c.UserID))
	} else {
		p = s.playerFor(ctx, c.UserID)
	}
	return seatConnected(p, c)
}

// seatAsync builds the caller's seat (Redis profile + cached progression
// summary; PostgreSQL only on a cache miss) concurrently with the join's
// other checks. Receive from the channel where the seat is needed; an
// abandoned result is simply dropped (buffered).
func (s *Service) seatAsync(ctx context.Context, c Caller) <-chan Player {
	ch := make(chan Player, 1)
	go func() { ch <- s.newSeat(ctx, c) }()
	return ch
}

// seatConnected marks a seat taken over a live connection as connected.
func seatConnected(p Player, c Caller) Player {
	if c.Epoch > 0 {
		p.Connected, p.ConnEpoch = true, c.Epoch
	}
	return p
}

// MatchmakingCancel removes the caller from their public lobby.
func (s *Service) MatchmakingCancel(ctx context.Context, c Caller) error {
	roomID := s.ActiveRoom(ctx, c.UserID)
	if roomID == "" {
		return nil
	}
	_, err := s.mutate(ctx, roomID, func(m *mutation) error {
		seat := m.r.SeatOf(c.UserID)
		if seat < 0 || m.r.Mode != ModePublic {
			return errNoop
		}
		if m.r.Status != StatusLobby {
			return protocol.ErrRoomInProgress
		}
		s.removeSeat(m, seat)
		if m.r.Status == StatusLobby {
			m.emitSnapshot(protocol.TRoomUpdated, "left")
		}
		return nil
	})
	if err == nil && !c.Bot {
		metrics.MatchmakingResults.WithLabelValues("cancelled").Inc()
	}
	return err
}

// handleFill starts or times out a public lobby at its fill deadline.
func (s *Service) handleFill(ctx context.Context, roomID string) error {
	var start bool
	var lonely []string
	_, err := s.mutate(ctx, roomID, func(m *mutation) error {
		r := m.r
		if r.Status != StatusLobby || r.Mode != ModePublic {
			return errNoop
		}
		now := s.nowMs()
		if now < r.FillDeadline-50 {
			m.schedule("fill", "1", r.FillDeadline)
			return nil
		}
		if s.Policy != nil && s.Policy.GlobalMaintenanceActive() {
			r.FillDeadline = now + s.Game.FillTimeout.Milliseconds()
			m.schedule("fill", "1", r.FillDeadline)
			return nil
		}
		if r.PendingBots > 0 && r.Extra["fillExtended"] == 0 {
			if r.Extra == nil {
				r.Extra = map[string]int64{}
			}
			r.Extra["fillExtended"] = 1
			r.FillDeadline = now + s.Bots.AssignmentTTL.Milliseconds() + 5000
			m.schedule("fill", "1", r.FillDeadline)
			m.emitSnapshot(protocol.TRoomUpdated, "waiting_for_bots")
			return nil
		}
		if len(r.Players) >= 2 {
			start = true
			return errNoop
		}
		for _, p := range r.Players {
			lonely = append(lonely, p.UserID)
		}
		s.closeRoom(m, "timeout")
		return nil
	})
	if err != nil {
		return err
	}
	if start {
		return s.startGame(ctx, roomID)
	}
	for _, u := range lonely {
		metrics.MatchmakingResults.WithLabelValues("timeout").Inc()
		s.notifyUser(ctx, u, protocol.TMatchmakingStatus, map[string]any{"status": "timeout", "roomId": roomID})
	}
	return nil
}

// ---- private rooms ----

const codeAlphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789" // 32 symbols, no I/O/0/1

func newCode() string {
	b := make([]byte, 6)
	_, _ = rand.Read(b)
	for i := range b {
		b[i] = codeAlphabet[int(b[i])%len(codeAlphabet)] // 256 % 32 == 0: unbiased
	}
	return string(b)
}

// NormalizeCode upper-cases and validates a room code.
func NormalizeCode(code string) (string, bool) {
	code = strings.ToUpper(strings.TrimSpace(code))
	if len(code) != 6 {
		return "", false
	}
	for _, r := range code {
		if !strings.ContainsRune(codeAlphabet, r) {
			return "", false
		}
	}
	return code, true
}

// CreatePrivate creates a private room with a fresh code; caller is host.
func (s *Service) CreatePrivate(ctx context.Context, c Caller, game, variant string, capacity int) (*Room, error) {
	if c.Bot {
		return nil, protocol.ErrBotsNotAllowed
	}
	if err := validGame(game, variant, capacity); err != nil {
		return nil, err
	}
	seat := s.seatAsync(ctx, c)
	if err := s.ensureFree(ctx, c.UserID); err != nil {
		return nil, err
	}
	fee := s.EntryFee(game)
	if err := s.checkFunds(ctx, c, fee); err != nil {
		return nil, err
	}
	me := <-seat
	now := s.nowMs()
	for attempt := 0; attempt < 5; attempt++ {
		code := newCode()
		r := &Room{ID: newRoomID(), Game: game, Variant: variant, Mode: ModePrivate, Code: code,
			Capacity: capacity, Status: StatusLobby, HostSeat: 0, EntryFee: fee, Round: 1, CreatedAt: now,
			Players: []Player{me}}
		ok, err := s.RDB.SetNX(ctx, codeKey(code), r.ID, s.Game.LobbyTTL).Result()
		if err != nil {
			return nil, err
		}
		if !ok {
			continue // code collision; try another
		}
		room, err := s.create(ctx, r, func(m *mutation) error {
			m.setPointer(c.UserID)
			m.emitSnapshot(protocol.TRoomUpdated, "created")
			return nil
		})
		if err != nil {
			s.RDB.Del(ctx, codeKey(code))
			return nil, err
		}
		metrics.PrivateRooms.WithLabelValues(game).Inc()
		return room, nil
	}
	return nil, protocol.ErrInternal
}

// PreviewCode returns public info about a private room (REST join-with-code).
func (s *Service) PreviewCode(ctx context.Context, code string) (*Room, error) {
	code, ok := NormalizeCode(code)
	if !ok {
		return nil, protocol.ErrInvalidCode
	}
	id, err := s.RDB.Get(ctx, codeKey(code)).Result()
	if err != nil {
		return nil, protocol.ErrInvalidCode
	}
	r, _, err := s.st.load(ctx, id)
	if err != nil || r.Mode != ModePrivate || r.Code != code || r.Status == StatusClosed {
		return nil, protocol.ErrInvalidCode
	}
	return r, nil
}

// JoinByCode seats the caller in a private lobby.
func (s *Service) JoinByCode(ctx context.Context, c Caller, code string) (*Room, error) {
	if c.Bot {
		return nil, protocol.ErrBotsNotAllowed
	}
	if ok, _ := s.Limiter.Allow(ctx, ratelimit.RoomCodePerUser, c.UserID); !ok {
		return nil, protocol.ErrRateLimited
	}
	preview, err := s.PreviewCode(ctx, code)
	if err != nil {
		return nil, err
	}
	if preview.SeatOf(c.UserID) >= 0 {
		return preview, nil // idempotent re-join
	}
	switch preview.Status {
	case StatusPlaying, StatusFinished:
		return nil, protocol.ErrRoomInProgress
	}
	if len(preview.Players) >= preview.Capacity {
		return nil, protocol.ErrRoomFull
	}
	seat := s.seatAsync(ctx, c)
	if err := s.ensureFree(ctx, c.UserID); err != nil {
		return nil, err
	}
	if err := s.checkFunds(ctx, c, preview.EntryFee); err != nil {
		return nil, err
	}
	me := <-seat
	return s.mutate(ctx, preview.ID, func(m *mutation) error {
		r := m.r
		if r.SeatOf(c.UserID) >= 0 {
			return errNoop
		}
		if r.Status != StatusLobby {
			return protocol.ErrRoomInProgress
		}
		if len(r.Players)+r.PendingBots >= r.Capacity {
			return protocol.ErrRoomFull
		}
		r.Players = append(r.Players, me)
		m.setPointer(c.UserID)
		m.emitSnapshot(protocol.TRoomUpdated, "joined")
		return nil
	})
}

// StartPrivate lets the host start a private lobby.
func (s *Service) StartPrivate(ctx context.Context, c Caller, roomID string) error {
	r, _, err := s.st.load(ctx, roomID)
	if err != nil {
		return protocol.ErrRoomNotFound
	}
	seat := r.SeatOf(c.UserID)
	switch {
	case seat < 0:
		return protocol.ErrNotInRoom
	case r.Mode != ModePrivate:
		return protocol.ErrInvalidPhase
	case seat != r.HostSeat:
		return protocol.ErrNotHost
	case r.Status != StatusLobby:
		return protocol.ErrRoomInProgress
	case len(r.Players) < 2:
		return protocol.ErrNotEnoughPlayers
	case r.PendingBots > 0:
		return protocol.ErrPlayersNotReady
	}
	for _, p := range r.Players {
		if !p.Connected {
			return protocol.ErrPlayersNotReady
		}
	}
	return s.startGame(ctx, roomID)
}

// ---- leaving / closing ----

// Leave handles room.leave for any status.
func (s *Service) Leave(ctx context.Context, c Caller, roomID string) error {
	var revokeBots []string
	_, err := s.mutate(ctx, roomID, func(m *mutation) error {
		r := m.r
		seat := r.SeatOf(c.UserID)
		if seat < 0 {
			return protocol.ErrNotInRoom
		}
		switch r.Status {
		case StatusLobby:
			revokeBots = append(revokeBots, s.removeSeat(m, seat)...)
			if r.Status == StatusLobby {
				m.emitSnapshot(protocol.TRoomUpdated, "left")
			}
		case StatusPlaying:
			m.extraTo = append(m.extraTo, c.UserID)
			if p := &r.Players[seat]; p.Forfeited {
				// Already out (missed turns): leaving now only stops the
				// room's events for this user (MemberIDs skips "left").
				p.ForfeitWhy = "left"
				m.write = true
			} else if err := s.forfeit(m, seat, "left"); err != nil {
				return err
			}
			m.clearPointer(c.UserID)
		case StatusFinished:
			p := &r.Players[seat]
			if p.ForfeitWhy == "left" {
				return errNoop
			}
			p.ForfeitWhy = "left"
			if r.Rematch != nil && r.Rematch.Open && !containsInt(r.Rematch.Declined, seat) && !containsInt(r.Rematch.Accepted, seat) {
				r.Rematch.Declined = append(r.Rematch.Declined, seat)
				m.emitV(protocol.TRoomRematch, func(v int64) any {
					return map[string]any{"roomId": r.ID, "v": v, "rematch": r.Rematch}
				})
				if s.rematchDecided(r) {
					m.then(func(ctx context.Context) { _ = s.resolveRematch(ctx, r.ID, r.Round) })
				}
			}
			m.write = true
			m.clearPointer(c.UserID)
		default:
			m.clearPointer(c.UserID)
		}
		return nil
	})
	for _, sid := range revokeBots {
		_ = s.BotAuth.Revoke(ctx, sid)
	}
	return err
}

// LeaveActive takes userID out of its active room exactly like room.leave (a
// lobby seat is released, a game in progress is forfeited and continues for
// the others, a finished room's rematch is declined) and clears a stale
// pointer. Used by account deletion; a no-op without an active room.
func (s *Service) LeaveActive(ctx context.Context, userID string) error {
	roomID := s.ActiveRoom(ctx, userID)
	if roomID == "" {
		return nil
	}
	err := s.Leave(ctx, Caller{UserID: userID}, roomID)
	if err != nil && !errors.Is(err, protocol.ErrNotInRoom) && !errors.Is(err, protocol.ErrRoomNotFound) {
		return err
	}
	s.clearStalePointer(ctx, userID, roomID)
	return nil
}

// removeSeat removes a lobby seat, compacting seats and transferring host.
// It closes the room when no humans remain. Returns bot session ids to revoke.
func (s *Service) removeSeat(m *mutation, seat int) []string {
	r := m.r
	removed := r.Players[seat]
	r.Players = append(r.Players[:seat], r.Players[seat+1:]...)
	m.clearPointer(removed.UserID)
	m.extraTo = append(m.extraTo, removed.UserID)
	var revoke []string
	if removed.Bot && removed.BotSID != "" {
		revoke = append(revoke, removed.BotSID)
	}
	if r.HostSeat >= 0 {
		switch {
		case seat == r.HostSeat:
			r.HostSeat = 0
		case seat < r.HostSeat:
			r.HostSeat--
		}
	}
	if r.Humans() == 0 {
		for _, p := range r.Players {
			if p.Bot && p.BotSID != "" {
				revoke = append(revoke, p.BotSID)
			}
		}
		s.closeRoom(m, "empty")
	}
	return revoke
}

// closeRoom marks a room closed and releases its code, open-list entry and
// every player's pointer.
func (s *Service) closeRoom(m *mutation, reason string) {
	r := m.r
	r.Status = StatusClosed
	if r.Mode == ModePublic {
		m.op(sideOp{Op: "zrem", K: openKey(r.Game, r.Variant, r.Capacity, poolOf(r)), V: r.ID})
	}
	if r.Code != "" {
		m.op(sideOp{Op: "delif", K: codeKey(r.Code), V: r.ID})
	}
	for _, p := range r.Players {
		m.clearPointer(p.UserID)
	}
	m.emitSnapshot(protocol.TRoomUpdated, reason)
}

// ---- presence ----

// Presence updates a member's connection status (called by the gateway).
func (s *Service) Presence(ctx context.Context, userID string, connected bool, epoch int64) {
	roomID := s.ActiveRoom(ctx, userID)
	if roomID == "" {
		return
	}
	_, err := s.mutate(ctx, roomID, func(m *mutation) error {
		r := m.r
		seat := r.SeatOf(userID)
		if seat < 0 || r.Status == StatusClosed {
			return errNoop
		}
		p := &r.Players[seat]
		if !connected && p.ConnEpoch != epoch {
			return errNoop // a newer connection already replaced this one
		}
		if connected && epoch < p.ConnEpoch {
			return errNoop
		}
		if p.Connected == connected && p.ConnEpoch == epoch {
			return errNoop
		}
		p.Connected, p.ConnEpoch = connected, epoch
		t := protocol.TPlayerConnected
		if !connected {
			t = protocol.TPlayerDisconn
		}
		m.emitV(t, func(v int64) any { return seatP{RoomID: r.ID, V: v, Seat: seat} })
		if !connected {
			switch r.Status {
			case StatusLobby:
				m.schedule("lobbykick", userID+":"+strconv.FormatInt(epoch, 10),
					s.nowMs()+s.Game.LobbyDisconnectGrace.Milliseconds())
			case StatusPlaying:
				// Shorten the disconnected player's current turn.
				if turnSeat, seq, _, _, _, _ := r.turnInfo(); turnSeat == seat {
					short := s.nowMs() + s.Game.TurnTimeoutDisconnected.Milliseconds()
					if short < r.Deadline {
						r.Deadline = short
						m.schedule("turn", strconv.Itoa(seq), short)
					}
				}
			}
		}
		return nil
	})
	if err != nil && !errors.Is(err, protocol.ErrRoomNotFound) {
		s.Log.Warn("presence update failed", "error", err.Error())
	}
}

// handleLobbyKick removes a lobby player who stayed disconnected.
func (s *Service) handleLobbyKick(ctx context.Context, roomID, arg string) error {
	userID, epochStr, _ := strings.Cut(arg, ":")
	epoch, _ := strconv.ParseInt(epochStr, 10, 64)
	var revoke []string
	_, err := s.mutate(ctx, roomID, func(m *mutation) error {
		r := m.r
		seat := r.SeatOf(userID)
		if seat < 0 || r.Status != StatusLobby || r.Players[seat].Connected || r.Players[seat].ConnEpoch != epoch {
			return errNoop
		}
		revoke = s.removeSeat(m, seat)
		if r.Status == StatusLobby {
			m.emitSnapshot(protocol.TRoomUpdated, "left")
		}
		return nil
	})
	for _, sid := range revoke {
		_ = s.BotAuth.Revoke(ctx, sid)
	}
	return err
}

func containsInt(xs []int, v int) bool {
	for _, x := range xs {
		if x == v {
			return true
		}
	}
	return false
}

// userUUID parses a member id for wallet operations.
func userUUID(id string) uuid.UUID { return parseUUID(id) }

var _ = time.Second
