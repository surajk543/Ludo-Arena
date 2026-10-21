package rooms

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"hash/fnv"
	mrand "math/rand/v2"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/google/uuid"

	"ludoroyale/internal/auth"
	"ludoroyale/internal/config"
	"ludoroyale/internal/httpapi"
	"ludoroyale/internal/metrics"
	"ludoroyale/internal/playerinfo"
	"ludoroyale/internal/profile"
	"ludoroyale/internal/protocol"
	"ludoroyale/internal/ratelimit"
)

// assignment is a pending bot seat handed to bot-play.
type assignment struct {
	ID        string `json:"id"`
	RoomID    string `json:"roomId"`
	Game      string `json:"game"`
	Variant   string `json:"variant"`
	Kind      string `json:"kind"` // practice | private | public_fill
	ExpiresAt int64  `json:"expiresAt"`
}

func newAssignmentID() string {
	b := make([]byte, 12)
	_, _ = rand.Read(b)
	return "a_" + hex.EncodeToString(b)
}

// requestBots creates count assignments for the mutated room (atomic with it).
func (s *Service) requestBots(m *mutation, kind string, count int) {
	r := m.r
	exp := s.nowMs() + s.Bots.AssignmentTTL.Milliseconds()
	for i := 0; i < count; i++ {
		a := assignment{ID: newAssignmentID(), RoomID: r.ID, Game: r.Game, Variant: r.Variant, Kind: kind, ExpiresAt: exp}
		raw, _ := json.Marshal(a)
		m.op(sideOp{Op: "set", K: botAssignPrefix + a.ID, V: string(raw), TTL: s.Bots.AssignmentTTL.Milliseconds()})
		m.op(sideOp{Op: "rpush", K: botQueueKey, V: a.ID})
		m.schedule("botexp", a.ID, exp+1000)
		metrics.BotAssignments.WithLabelValues(kind, "created").Inc()
	}
	r.PendingBots += count
	r.BotRequested = s.nowMs()
}

// PracticeStart creates a practice room: the caller plus 1–3 bots.
func (s *Service) PracticeStart(ctx context.Context, c Caller, game, variant string, bots int) (*Room, error) {
	if c.Bot {
		return nil, protocol.ErrBotsNotAllowed
	}
	if bots < 1 || bots > 3 {
		return nil, protocol.ErrBadRequest
	}
	if err := validGame(game, variant, bots+1); err != nil {
		return nil, err
	}
	if s.BotAuth == nil || !s.BotAuth.Enabled() {
		return nil, protocol.ErrBotsUnavailable
	}
	if err := s.ensureFree(ctx, c.UserID); err != nil {
		return nil, err
	}
	me := seatConnected(s.playerFor(ctx, c.UserID), c)
	now := s.nowMs()
	r := &Room{ID: newRoomID(), Game: game, Variant: variant, Mode: ModePractice, Capacity: bots + 1,
		Status: StatusLobby, HostSeat: 0, AllowBots: true, EntryFee: 0, Round: 1, CreatedAt: now,
		Players: []Player{me}}
	room, err := s.create(ctx, r, func(m *mutation) error {
		m.setPointer(c.UserID)
		s.requestBots(m, "practice", bots)
		m.schedule("practice", "1", now+s.Game.PracticeBotWait.Milliseconds())
		m.emitSnapshot(protocol.TRoomUpdated, "created")
		return nil
	})
	if err == nil {
		metrics.PracticeGames.WithLabelValues(game).Inc()
	}
	return room, err
}

// handlePracticeDeadline starts a practice room with the bots that arrived,
// or closes it when none did.
func (s *Service) handlePracticeDeadline(ctx context.Context, roomID string, round int) error {
	var start bool
	var human string
	_, err := s.mutate(ctx, roomID, func(m *mutation) error {
		r := m.r
		if r.Status != StatusLobby || r.Mode != ModePractice || r.Round != round {
			return errNoop
		}
		if r.Bots() >= 1 {
			start = true
			r.PendingBots = 0
			return nil
		}
		for _, p := range r.Players {
			if !p.Bot {
				human = p.UserID
			}
		}
		s.closeRoom(m, "bots_unavailable")
		return nil
	})
	if err != nil {
		return err
	}
	if start {
		return s.startGame(ctx, roomID)
	}
	if human != "" {
		s.notifyUser(ctx, human, protocol.TError, protocol.ErrBotsUnavailable)
	}
	return nil
}

// AllowBots toggles bot seats in a private lobby (host only).
func (s *Service) AllowBots(ctx context.Context, c Caller, roomID string, allow bool) error {
	_, err := s.mutate(ctx, roomID, func(m *mutation) error {
		r := m.r
		if err := s.hostLobby(r, c.UserID, ModePrivate); err != nil {
			return err
		}
		if r.AllowBots == allow {
			return errNoop
		}
		if !allow && (r.Bots() > 0 || r.PendingBots > 0) {
			return protocol.ErrInvalidPhase
		}
		r.AllowBots = allow
		m.emitSnapshot(protocol.TRoomUpdated, "settings")
		return nil
	})
	return err
}

// AddBot requests one bot seat in a private lobby (host only).
func (s *Service) AddBot(ctx context.Context, c Caller, roomID string) error {
	if s.BotAuth == nil || !s.BotAuth.Enabled() {
		return protocol.ErrBotsUnavailable
	}
	_, err := s.mutate(ctx, roomID, func(m *mutation) error {
		r := m.r
		if err := s.hostLobby(r, c.UserID, ModePrivate); err != nil {
			return err
		}
		if !r.AllowBots {
			return protocol.ErrBotsNotAllowed
		}
		if len(r.Players)+r.PendingBots >= r.Capacity {
			return protocol.ErrRoomFull
		}
		if r.Bots()+r.PendingBots >= s.Bots.MaxPerRoom {
			return protocol.ErrRoomFull
		}
		s.requestBots(m, "private", 1)
		m.emitSnapshot(protocol.TRoomUpdated, "bot_requested")
		return nil
	})
	return err
}

// RemoveBot removes a bot seat from a private lobby (host only).
func (s *Service) RemoveBot(ctx context.Context, c Caller, roomID string, seat int) error {
	var revoke []string
	_, err := s.mutate(ctx, roomID, func(m *mutation) error {
		r := m.r
		if err := s.hostLobby(r, c.UserID, ModePrivate); err != nil {
			return err
		}
		if seat < 0 || seat >= len(r.Players) || !r.Players[seat].Bot {
			return protocol.ErrBadRequest
		}
		revoke = s.removeSeat(m, seat)
		m.emitSnapshot(protocol.TRoomUpdated, "left")
		return nil
	})
	for _, sid := range revoke {
		_ = s.BotAuth.Revoke(ctx, sid)
	}
	return err
}

func (s *Service) hostLobby(r *Room, userID, mode string) error {
	seat := r.SeatOf(userID)
	switch {
	case seat < 0:
		return protocol.ErrNotInRoom
	case r.Mode != mode:
		return protocol.ErrInvalidPhase
	case seat != r.HostSeat:
		return protocol.ErrNotHost
	case r.Status != StatusLobby:
		return protocol.ErrRoomInProgress
	}
	return nil
}

// handleBotExpiry releases a seat whose assignment was never claimed.
func (s *Service) handleBotExpiry(ctx context.Context, roomID, asgID string) error {
	n, err := s.RDB.Del(ctx, botAssignPrefix+asgID).Result()
	if err != nil || n == 0 {
		return err // claimed (or already expired and handled)
	}
	metrics.BotAssignments.WithLabelValues("any", "expired").Inc()
	_, err = s.mutate(ctx, roomID, func(m *mutation) error {
		if m.r.PendingBots <= 0 || m.r.Status != StatusLobby {
			return errNoop
		}
		m.r.PendingBots--
		m.emitSnapshot(protocol.TRoomUpdated, "bot_unavailable")
		return nil
	})
	if errors.Is(err, protocol.ErrRoomNotFound) {
		return nil
	}
	return err
}

// claimAssignment seats a bot for an assignment (called by bot-play).
func (s *Service) claimAssignment(ctx context.Context, asgID, name, profileName string) (auth.BotSession, *Room, string, error) {
	raw, err := s.RDB.GetDel(ctx, botAssignPrefix+asgID).Result()
	if err != nil {
		return auth.BotSession{}, nil, "", httpapi.Errf(http.StatusNotFound, "assignment_not_found", "Assignment expired or already claimed.")
	}
	var a assignment
	if err := json.Unmarshal([]byte(raw), &a); err != nil {
		return auth.BotSession{}, nil, "", err
	}
	display := botName(name, asgID)
	sess, err := s.BotAuth.IssueBot(ctx, a.RoomID, false, display, profileName, s.Bots.SessionTTL)
	if err != nil {
		return auth.BotSession{}, nil, "", err
	}
	uid := "b_" + strings.ReplaceAll(sess.BotID.String(), "-", "")[:10]
	var start bool
	room, err := s.mutate(ctx, a.RoomID, func(m *mutation) error {
		r := m.r
		if r.Status != StatusLobby || len(r.Players) >= r.Capacity {
			return httpapi.Errf(http.StatusConflict, "room_unavailable", "The room no longer needs a bot.")
		}
		if r.PendingBots > 0 {
			r.PendingBots--
		}
		// Seated like a brand-new player (starter title and cosmetics) so the
		// seat looks the same as a human's in the app.
		starter := playerinfo.Starter()
		cos := map[string]string{}
		for _, slot := range []string{"dice", "token", "frame", "trail", "victory"} {
			cos[slot] = starter.Loadout[slot]
		}
		r.Players = append(r.Players, Player{UserID: sess.BotID.String(), UID: uid, Name: display,
			Avatar: int(sess.BotID[15]) % 12, Level: starter.Level, Title: starter.Title, Cosmetics: cos,
			Picture: s.botPicture(), Bot: true, BotProfile: profile.SanitizeName(profileName),
			BotSID: sess.SessionID, JoinedAt: s.nowMs()})
		m.setPointer(sess.BotID.String())
		full := len(r.Players) == r.Capacity
		start = full && (r.Mode == ModePractice || r.Mode == ModePublic)
		m.emitSnapshot(protocol.TRoomUpdated, "joined")
		return nil
	})
	if err != nil {
		_ = s.BotAuth.Revoke(ctx, sess.SessionID)
		return auth.BotSession{}, nil, "", err
	}
	_ = s.RDB.Set(ctx, "botsess:"+uid, sess.SessionID+"|"+sess.BotID.String()+"|"+a.RoomID, s.Bots.SessionTTL).Err()
	metrics.BotAssignments.WithLabelValues(a.Kind, "claimed").Inc()
	metrics.BotSessions.WithLabelValues(a.Kind).Inc()
	if start {
		go func() {
			if err := s.startGame(context.WithoutCancel(ctx), a.RoomID); err != nil {
				s.Log.Warn("start after bot fill failed", "error", err.Error())
			}
		}()
	}
	return sess, room, uid, nil
}

// botPicture returns the profile picture of a new bot seat: with probability
// BOT_PICTURE_SHARE a random active catalogue picture (no wallet, no
// ownership: bots only look like players who bought one), else nil.
func (s *Service) botPicture() *playerinfo.Picture {
	if s.Pictures == nil || s.Bots.PictureShare <= 0 || mrand.Float64() >= s.Bots.PictureShare {
		return nil
	}
	return s.Pictures.RandomPicture()
}

// neutralBotNames are fallback display names for bots whose requested name
// is empty (common Indian, Indonesian and Arabic first names).
var neutralBotNames = []string{
	"Aarav", "Priya", "Rohan", "Ananya", "Vikram", "Kavya", "Arjun", "Isha",
	"Rizky", "Putri", "Budi", "Sari", "Dewi", "Agus",
	"Omar", "Layla", "Yusuf", "Amira", "Karim", "Noor",
}

// botName returns a bot's display name. Names carry no bot label: a leading
// "Bot" word (any case, followed by a space, "-", "_", ":" or "." — e.g.
// bot-play's display_name_prefix) is stripped, and an empty result falls
// back to a neutral first name chosen from seed. Bots stay identifiable to
// the server and clients through players[].bot and actorType, never the name.
func botName(name, seed string) string {
	name = profile.SanitizeName(name)
	for {
		rest, ok := stripBotWord(name)
		if !ok {
			break
		}
		name = rest
	}
	if name == "" {
		h := fnv.New32a()
		h.Write([]byte(seed))
		name = neutralBotNames[h.Sum32()%uint32(len(neutralBotNames))]
	}
	if r := []rune(name); len(r) > 20 {
		name = strings.TrimSpace(string(r[:20]))
	}
	return name
}

// stripBotWord removes one leading "bot" label word from name.
func stripBotWord(name string) (string, bool) {
	if len(name) < 3 || !strings.EqualFold(name[:3], "bot") {
		return name, false
	}
	rest := name[3:]
	if rest == "" {
		return "", true
	}
	if !strings.ContainsRune(" -_:.", rune(rest[0])) {
		return name, false // e.g. "Botan"
	}
	return strings.TrimLeft(rest, " -_:."), true
}

// ---- REST endpoints for bot-play (docs/rest-api.md → Bot service) ----

// RegisterBotRoutes adds the bot service endpoints.
func (s *Service) RegisterBotRoutes(rt *httpapi.Router, env string) {
	ipRule := ratelimit.BotServicePerIP
	ctl := httpapi.Route{Auth: httpapi.AuthBotController, IPRule: &ipRule}

	rt.Handle("POST /api/v1/bot/controller/token", httpapi.Route{IPRule: &ipRule}, func(w http.ResponseWriter, r *http.Request) error {
		key, ok := strings.CutPrefix(r.Header.Get("Authorization"), "Bot-Service ")
		if !ok || !s.BotAuth.VerifyServiceKey(strings.TrimSpace(key)) {
			return httpapi.ErrUnauthorized
		}
		tok, exp, err := s.BotAuth.IssueController(r.Context())
		if err != nil {
			return err
		}
		httpapi.WriteJSON(w, http.StatusOK, map[string]any{"token": tok, "expiresAt": exp.UnixMilli()})
		return nil
	})

	rt.Handle("GET /api/v1/bot/assignments", ctl, func(w http.ResponseWriter, r *http.Request) error {
		wait := 20
		if v, err := strconv.Atoi(r.URL.Query().Get("wait")); err == nil && v >= 0 && v <= 25 {
			wait = v
		}
		out := []assignment{}
		if s.Policy != nil && s.Policy.GlobalMaintenanceActive() {
			httpapi.WriteJSON(w, http.StatusOK, map[string]any{"assignments": out, "maintenance": true})
			return nil
		}
		ctx := r.Context()
		first, err := s.RDB.BLPop(ctx, time.Duration(wait)*time.Second, botQueueKey).Result()
		if err == nil && len(first) == 2 {
			ids := []string{first[1]}
			if more, err := s.RDB.LPopCount(ctx, botQueueKey, 19).Result(); err == nil {
				ids = append(ids, more...)
			}
			for _, id := range ids {
				raw, err := s.RDB.Get(ctx, botAssignPrefix+id).Result()
				if err != nil {
					continue // expired
				}
				var a assignment
				if json.Unmarshal([]byte(raw), &a) == nil {
					out = append(out, a)
				}
			}
		}
		httpapi.WriteJSON(w, http.StatusOK, map[string]any{"assignments": out})
		return nil
	})

	rt.Handle("GET /api/v1/bot/lobbies", ctl, func(w http.ResponseWriter, r *http.Request) error {
		type lobby struct {
			RoomID      string `json:"roomId"`
			Game        string `json:"game"`
			Variant     string `json:"variant"`
			Capacity    int    `json:"capacity"`
			Humans      int    `json:"humans"`
			Bots        int    `json:"bots"`
			PendingBots int    `json:"pendingBots"`
			WaitingMs   int64  `json:"waitingMs"`
		}
		out := []lobby{}
		now := s.nowMs()
		for _, gv := range [][2]string{{GameLudo, "classic"}, {GameLudo, "quick"}, {GameSnakes, "classic"}} {
			for capacity := 2; capacity <= 4; capacity++ {
				ids, _ := s.RDB.ZRange(r.Context(), openKey(gv[0], gv[1], capacity, "live"), 0, 49).Result()
				for _, id := range ids {
					rm, _, err := s.st.load(r.Context(), id)
					if err != nil || rm.Status != StatusLobby {
						continue
					}
					out = append(out, lobby{RoomID: rm.ID, Game: rm.Game, Variant: rm.Variant, Capacity: rm.Capacity,
						Humans: rm.Humans(), Bots: rm.Bots(), PendingBots: rm.PendingBots, WaitingMs: now - rm.CreatedAt})
				}
			}
		}
		httpapi.WriteJSON(w, http.StatusOK, map[string]any{"lobbies": out, "publicFillEnabled": s.Bots.PublicFillEnabled})
		return nil
	})

	rt.Handle("POST /api/v1/bot/lobbies/{roomId}/fill", ctl, func(w http.ResponseWriter, r *http.Request) error {
		if !s.Bots.PublicFillEnabled {
			return httpapi.Errf(http.StatusForbidden, "public_fill_disabled", "Public bot fill is disabled on this server.")
		}
		var body struct {
			Count int `json:"count"`
		}
		if err := httpapi.DecodeJSON(r, &body); err != nil {
			return err
		}
		if body.Count < 1 || body.Count > 3 {
			return httpapi.ErrBadRequest
		}
		var created int
		_, err := s.mutate(r.Context(), r.PathValue("roomId"), func(m *mutation) error {
			rm := m.r
			free := rm.Capacity - len(rm.Players) - rm.PendingBots
			switch {
			case rm.Status != StatusLobby || rm.Mode != ModePublic || rm.LoadTest:
				return httpapi.Errf(http.StatusConflict, "lobby_changed", "The lobby is no longer open.")
			case rm.PendingBots > 0:
				return httpapi.Errf(http.StatusConflict, "bots_pending", "Bots are already on their way.")
			case rm.Humans() == 0:
				return httpapi.Errf(http.StatusConflict, "lobby_changed", "The lobby has no players.")
			case body.Count > free || rm.Bots()+body.Count > s.Bots.MaxPerRoom:
				return httpapi.Errf(http.StatusConflict, "capacity", "That many bots would exceed the room limit.")
			}
			s.requestBots(m, "public_fill", body.Count)
			created = body.Count
			m.emitSnapshot(protocol.TRoomUpdated, "bot_requested")
			return nil
		})
		if errors.Is(err, protocol.ErrRoomNotFound) {
			return httpapi.Errf(http.StatusConflict, "lobby_changed", "The lobby is no longer open.")
		}
		if err != nil {
			return err
		}
		httpapi.WriteJSON(w, http.StatusOK, map[string]any{"requested": created})
		return nil
	})

	rt.Handle("POST /api/v1/bot/sessions", ctl, func(w http.ResponseWriter, r *http.Request) error {
		var body struct {
			AssignmentID string `json:"assignmentId"`
			Mode         string `json:"mode"`
			Name         string `json:"name"`
			Profile      string `json:"profile"`
		}
		if err := httpapi.DecodeJSON(r, &body); err != nil {
			return err
		}
		if s.Policy != nil && s.Policy.GlobalMaintenanceActive() {
			return httpapi.Errf(http.StatusServiceUnavailable, "maintenance", "Maintenance in progress.")
		}
		if body.Mode == "loadtest" {
			if env == config.EnvProduction || !s.Bots.LoadTestEnabled {
				return httpapi.Errf(http.StatusForbidden, "loadtest_disabled", "Load-test sessions are not allowed on this server.")
			}
			sess, err := s.BotAuth.IssueBot(r.Context(), "", true, botName(body.Name, uuid.NewString()), body.Profile, s.Bots.SessionTTL)
			if err != nil {
				return err
			}
			metrics.BotSessions.WithLabelValues("loadtest").Inc()
			uid := "b_" + strings.ReplaceAll(sess.BotID.String(), "-", "")[:10]
			_ = s.RDB.Set(r.Context(), "botsess:"+uid, sess.SessionID+"|"+sess.BotID.String()+"|", s.Bots.SessionTTL).Err()
			httpapi.WriteJSON(w, http.StatusOK, map[string]any{"accessToken": sess.Token,
				"expiresAt": sess.ExpiresAt.UnixMilli(), "uid": uid, "roomId": ""})
			return nil
		}
		if body.AssignmentID == "" {
			return httpapi.ErrBadRequest
		}
		sess, room, uid, err := s.claimAssignment(r.Context(), body.AssignmentID, body.Name, body.Profile)
		if err != nil {
			return err
		}
		httpapi.WriteJSON(w, http.StatusOK, map[string]any{"accessToken": sess.Token,
			"expiresAt": sess.ExpiresAt.UnixMilli(), "uid": uid, "roomId": room.ID})
		return nil
	})

	rt.Handle("DELETE /api/v1/bot/sessions/{uid}", ctl, func(w http.ResponseWriter, r *http.Request) error {
		raw, err := s.RDB.GetDel(r.Context(), "botsess:"+r.PathValue("uid")).Result()
		if err == nil {
			parts := strings.SplitN(raw, "|", 3)
			if len(parts) == 3 {
				if parts[2] != "" {
					_ = s.Leave(r.Context(), Caller{UserID: parts[1], Bot: true}, parts[2])
				} else if roomID := s.ActiveRoom(r.Context(), parts[1]); roomID != "" {
					_ = s.Leave(r.Context(), Caller{UserID: parts[1], Bot: true}, roomID)
				}
				_ = s.BotAuth.Revoke(r.Context(), parts[0])
			}
		}
		w.WriteHeader(http.StatusNoContent)
		return nil
	})
}
