package fakebackend

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/coder/websocket"
)

type wsConn struct {
	uid  string
	ws   *websocket.Conn
	out  chan []byte
	done chan struct{}
	once sync.Once
}

func (c *wsConn) send(env Envelope) {
	b, err := json.Marshal(env)
	if err != nil {
		return
	}
	select {
	case <-c.done:
		return
	default:
	}
	select {
	case c.out <- b:
	default:
		c.closeWith(4508, "slow consumer")
	}
}

func (c *wsConn) closeWith(code int, reason string) {
	c.once.Do(func() {
		close(c.done)
		go func() { _ = c.ws.Close(websocket.StatusCode(code), reason) }()
	})
}

func (c *wsConn) closeNow() {
	c.once.Do(func() {
		close(c.done)
		_ = c.ws.CloseNow()
	})
}

func (c *wsConn) writeLoop() {
	for {
		select {
		case <-c.done:
			return
		case b := <-c.out:
			ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
			err := c.ws.Write(ctx, websocket.MessageText, b)
			cancel()
			if err != nil {
				c.closeNow()
				return
			}
		}
	}
}

func (s *Server) handleWS(w http.ResponseWriter, r *http.Request) {
	if s.maintenance.Load() {
		writeErr(w, http.StatusServiceUnavailable, "maintenance", "maintenance in progress")
		return
	}
	tok, _ := strings.CutPrefix(r.Header.Get("Authorization"), "Bearer ")
	s.mu.Lock()
	sess := s.sessions[tok]
	s.handshakes = append(s.handshakes, r.Header.Clone())
	s.mu.Unlock()
	if sess == nil || time.Now().After(sess.expiresAt) {
		writeErr(w, http.StatusUnauthorized, "unauthorized", "invalid bot token")
		return
	}
	if r.Header.Get("X-App-Platform") != "bot" {
		writeErr(w, http.StatusBadRequest, "bad_request", "X-App-Platform: bot required for bot tokens")
		return
	}
	if r.Header.Get("X-App-Version") == "" || r.Header.Get("X-App-Build") == "" {
		writeErr(w, http.StatusBadRequest, "client_version_required", "version headers required")
		return
	}
	if !strings.Contains(r.Header.Get("Sec-WebSocket-Protocol"), "ludo-arena.v1") {
		writeErr(w, http.StatusBadRequest, "bad_request", "subprotocol ludo-arena.v1 required")
		return
	}
	offered := strings.Contains(strings.ToLower(r.Header.Get("Sec-WebSocket-Extensions")), "permessage-deflate")
	ws, err := websocket.Accept(w, r, &websocket.AcceptOptions{
		Subprotocols:         []string{"ludo-arena.v1"},
		CompressionMode:      websocket.CompressionNoContextTakeover,
		CompressionThreshold: s.opts.CompressionThreshold,
	})
	if err != nil {
		return
	}
	ws.SetReadLimit(4096)
	c := &wsConn{uid: sess.uid, ws: ws, out: make(chan []byte, 256), done: make(chan struct{})}
	go c.writeLoop()

	compression := "none"
	if offered {
		compression = "permessage-deflate; client_no_context_takeover; server_no_context_takeover"
	}
	s.mu.Lock()
	old := s.conns[sess.uid]
	s.conns[sess.uid] = c
	c.send(Envelope{T: "connection.ready", P: map[string]any{"uid": sess.uid, "protocol": 1, "serverTime": time.Now().UnixMilli(),
		"activeRoomId": sess.roomID, "compression": compression, "heartbeatSec": 20}})
	if rm := s.rooms[sess.roomID]; rm != nil && rm.member(sess.uid) != nil {
		// Like the backend: push the active room's state right after ready.
		s.deliverLocked(sess.uid, Envelope{T: "game.state", P: map[string]any{"room": rm.snapshot()}})
		if p := rm.member(sess.uid); !p.connected {
			p.connected = true
			if rm.status == "playing" {
				s.emitLocked(rm, "player.connected", map[string]any{"seat": p.seat}, false, "", "")
			}
		}
	}
	s.mu.Unlock()
	if old != nil {
		old.closeWith(4409, "replaced")
	}

	ctx := r.Context()
	for {
		_, data, err := ws.Read(ctx)
		if err != nil {
			break
		}
		s.onClientMessage(c, sess, data)
	}
	s.mu.Lock()
	if s.conns[sess.uid] == c {
		delete(s.conns, sess.uid)
		if rm := s.rooms[sess.roomID]; rm != nil {
			if p := rm.member(sess.uid); p != nil && p.connected {
				p.connected = false
				if rm.status == "playing" {
					s.emitLocked(rm, "player.disconnected", map[string]any{"seat": p.seat}, false, "", "")
				}
			}
		}
	}
	s.mu.Unlock()
	c.closeNow()
}

func errEnv(reqID, code, msg string, retry bool) Envelope {
	return Envelope{T: "error", R: reqID, P: map[string]any{"code": code, "msg": msg, "retry": retry}}
}

func (s *Server) onClientMessage(c *wsConn, sess *session, data []byte) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.clientMsgs[sess.uid] = append(s.clientMsgs[sess.uid], string(data))
	var env struct {
		T  string          `json:"t"`
		ID *string         `json:"id"`
		P  json.RawMessage `json:"p"`
	}
	if err := json.Unmarshal(data, &env); err != nil || env.T == "" {
		c.send(errEnv("", "bad_request", "malformed message", false))
		return
	}
	if env.T == "ping" {
		c.send(Envelope{T: "pong", P: map[string]any{"ts": time.Now().UnixMilli()}})
		return
	}
	if env.ID == nil || *env.ID == "" || len(*env.ID) > 64 {
		c.send(errEnv("", "bad_request", "id required", false))
		return
	}
	id := *env.ID
	key := sess.uid + "|" + id
	if s.seenIDs[key] {
		c.send(Envelope{T: "ack", R: id, P: map[string]any{"dup": true}})
		return
	}
	s.seenIDs[key] = true
	// Backend allowlist: assignment bots may roll, move, sync, leave and
	// chat (quick chat + emotes); load-test bots may also use matchmaking
	// and rematch.
	allowed := map[string]bool{"game.roll_dice": true, "game.make_move": true, "game.request_sync": true, "room.leave": true,
		"chat.quick": true, "chat.emote": true}
	if sess.loadtest {
		allowed["matchmaking.join"], allowed["matchmaking.cancel"], allowed["game.rematch"] = true, true, true
	}
	if !allowed[env.T] {
		c.send(errEnv(id, "bad_request", "command not allowed for bots", false))
		return
	}
	rm := s.rooms[sess.roomID]
	switch env.T {
	case "game.request_sync":
		s.syncCount[sess.uid]++
		var p struct {
			RoomID string `json:"roomId"`
		}
		if !strictDecode(env.P, &p) {
			c.send(errEnv(id, "bad_request", "invalid payload", false))
			return
		}
		if rm == nil || rm.member(sess.uid) == nil || (p.RoomID != "" && p.RoomID != rm.id) {
			c.send(errEnv(id, "not_in_room", "not in a room", false))
			return
		}
		s.deliverLocked(sess.uid, Envelope{T: "game.state", R: id, P: map[string]any{"room": rm.snapshot()}})
	case "game.roll_dice", "game.make_move":
		var roll struct {
			RoomID  string `json:"roomId"`
			TurnSeq int    `json:"turnSeq"`
		}
		var p struct {
			RoomID  string `json:"roomId"`
			TurnSeq int    `json:"turnSeq"`
			Token   *int   `json:"token"`
		}
		ok := false
		if env.T == "game.roll_dice" {
			ok = strictDecode(env.P, &roll)
			p.RoomID, p.TurnSeq = roll.RoomID, roll.TurnSeq
		} else {
			ok = strictDecode(env.P, &p)
		}
		if !ok || len(p.RoomID) < 3 || len(p.RoomID) > 32 {
			c.send(errEnv(id, "bad_request", "invalid payload", false))
			return
		}
		if rm == nil || rm.id != p.RoomID || rm.member(sess.uid) == nil {
			c.send(errEnv(id, "not_in_room", "not in that room", false))
			return
		}
		pl := rm.member(sess.uid)
		if s.cmdHook != nil {
			if code, retry := s.cmdHook(sess.uid, env.T); code != "" {
				c.send(errEnv(id, code, "rejected by test hook", retry))
				if code == "stale_state" {
					s.deliverLocked(sess.uid, Envelope{T: "game.state", P: map[string]any{"room": rm.snapshot()}})
				}
				return
			}
		}
		switch {
		case rm.status != "playing":
			c.send(errEnv(id, "invalid_phase", "game not running", false))
		case rm.turnSeat != pl.seat:
			c.send(errEnv(id, "not_your_turn", "not your turn", false))
		case p.TurnSeq != rm.turnSeq:
			c.send(errEnv(id, "stale_state", "stale turnSeq", false))
			s.deliverLocked(sess.uid, Envelope{T: "game.state", P: map[string]any{"room": rm.snapshot()}})
		case env.T == "game.roll_dice" && rm.phase != "awaiting_roll":
			c.send(errEnv(id, "invalid_phase", "not awaiting roll", false))
		case env.T == "game.roll_dice" && rm.game == "snakes_ladders" && rm.dice != 0:
			c.send(errEnv(id, "invalid_phase", "already rolled", false))
		case env.T == "game.roll_dice":
			s.rollLocked(rm, pl.seat, false, "", "")
			c.send(Envelope{T: "ack", R: id, P: map[string]any{}})
		case rm.phase != "awaiting_move" || rm.game != "ludo":
			c.send(errEnv(id, "invalid_phase", "not awaiting move", false))
		case p.Token == nil || !contains(rm.legal, *p.Token):
			c.send(errEnv(id, "illegal_move", "token not legal", false))
		default:
			s.moveLocked(rm, pl.seat, *p.Token, false, sess.uid, "")
			c.send(Envelope{T: "ack", R: id, P: map[string]any{}})
		}
	case "room.leave":
		var p struct {
			RoomID string `json:"roomId"`
		}
		if !strictDecode(env.P, &p) {
			c.send(errEnv(id, "bad_request", "invalid payload", false))
			return
		}
		if rm != nil {
			s.leaveLocked(rm, sess.uid)
			c.send(Envelope{T: "ack", R: id, P: map[string]any{}})
			return
		}
		c.send(errEnv(id, "not_in_room", "not in a room", false))
	case "game.rematch":
		c.send(Envelope{T: "ack", R: id, P: map[string]any{}})
	case "chat.quick", "chat.emote":
		s.chatLocked(c, sess, rm, env.T, env.P, id)
	case "matchmaking.join":
		var p struct {
			Game     string `json:"game"`
			Variant  string `json:"variant"`
			Capacity int    `json:"capacity"`
		}
		if !strictDecode(env.P, &p) || p.Capacity < 2 || p.Capacity > 4 {
			c.send(errEnv(id, "bad_request", "invalid payload", false))
			return
		}
		if !sess.loadtest {
			c.send(errEnv(id, "bad_request", "assignment bots cannot use matchmaking", false))
			return
		}
		if rm != nil && rm.member(sess.uid) != nil && (rm.status == "lobby" || rm.status == "playing") {
			c.send(errEnv(id, "already_in_room", "already in a room", false))
			return
		}
		s.joinMatchmakingLocked(sess, p.Game, p.Variant, p.Capacity, id)
	case "matchmaking.cancel":
		if rm == nil || rm.member(sess.uid) == nil {
			c.send(errEnv(id, "not_in_room", "not searching", false))
			return
		}
		if rm.status != "lobby" {
			c.send(errEnv(id, "room_in_progress", "game already started", false))
			return
		}
		s.leaveLocked(rm, sess.uid)
		c.send(Envelope{T: "matchmaking.status", R: id, P: map[string]any{"status": "cancelled", "game": rm.game,
			"variant": rm.variant, "capacity": rm.capacity, "roomId": rm.id}})
	}
}

// chatLimits mirror the backend's per-account quick-chat limits.
const (
	chatBurstWindow  = 3 * time.Second
	chatMinuteWindow = time.Minute
	chatPerMinute    = 10
)

// chatLocked implements chat.quick / chat.emote like the backend: known
// quick-chat ids, emotes the session may use, 1 per 3 s and 10 per minute
// per account; accepted messages are broadcast to the room.
func (s *Server) chatLocked(c *wsConn, sess *session, rm *room, t string, raw json.RawMessage, id string) {
	reject := func(code string, retry bool) {
		s.chatRejects[code]++
		c.send(errEnv(id, code, "chat refused", retry))
	}
	var p struct {
		RoomID string `json:"roomId"`
		Msg    string `json:"msg"`
		Emote  string `json:"emote"`
	}
	if !strictDecode(raw, &p) || len(p.RoomID) < 3 || len(p.RoomID) > 32 {
		reject("bad_request", false)
		return
	}
	value := p.Msg
	if t == "chat.emote" {
		value = p.Emote
		if p.Msg != "" || p.Emote == "" {
			reject("bad_request", false)
			return
		}
	} else if p.Emote != "" || !quickChatIDs[p.Msg] {
		reject("bad_request", false)
		return
	}
	if s.opts.RefuseChat != "" {
		reject(s.opts.RefuseChat, s.opts.RefuseChat == "rate_limited")
		return
	}
	now := time.Now()
	var recent []time.Time
	for _, at := range s.chatTimes[sess.uid] {
		if now.Sub(at) < chatMinuteWindow {
			recent = append(recent, at)
		}
	}
	s.chatTimes[sess.uid] = recent
	if len(recent) >= chatPerMinute || (len(recent) > 0 && now.Sub(recent[len(recent)-1]) < chatBurstWindow) {
		reject("rate_limited", true)
		return
	}
	if rm == nil || rm.id != p.RoomID || rm.member(sess.uid) == nil {
		reject("not_in_room", false)
		return
	}
	if t == "chat.emote" && !containsStr(sess.emotes, p.Emote) {
		reject("item_not_owned", false)
		return
	}
	s.chatTimes[sess.uid] = append(recent, now)
	s.chats = append(s.chats, ChatRecord{UID: sess.uid, RoomID: rm.id, Type: t, Value: value, At: now})
	c.send(Envelope{T: "ack", R: id, P: map[string]any{}})
	seat := rm.member(sess.uid).seat
	for _, pl := range rm.players {
		if pl.left || pl.gone || pl.human {
			continue
		}
		payload := map[string]any{"roomId": rm.id, "seat": seat}
		if t == "chat.emote" {
			payload["emote"] = value
		} else {
			payload["msg"] = value
		}
		s.deliverLocked(pl.uid, Envelope{T: t, P: payload})
	}
}

func containsStr(xs []string, v string) bool {
	for _, x := range xs {
		if x == v {
			return true
		}
	}
	return false
}

// strictDecode mirrors the backend's DisallowUnknownFields decoding.
func strictDecode(raw json.RawMessage, v any) bool {
	if len(raw) == 0 || string(raw) == "null" {
		raw = []byte("{}")
	}
	dec := json.NewDecoder(bytes.NewReader(raw))
	dec.DisallowUnknownFields()
	return dec.Decode(v) == nil
}

func contains(xs []int, v int) bool {
	for _, x := range xs {
		if x == v {
			return true
		}
	}
	return false
}
