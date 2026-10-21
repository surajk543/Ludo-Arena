// Package fakebackend is an in-process fake of the Ludo Royale backend for
// bot-play tests. It implements the bot service REST endpoints
// (docs/rest-api.md → "Bot service") and the `ludo-royale.v1` WebSocket
// protocol (docs/websocket-protocol.md) with a tiny authoritative Ludo and
// Snakes & Ladders engine (backend/docs/game-rules.md), written
// independently of bot-play's own code (its own hash, legality and reducer).
//
// Simplifications (documented so the real backend is the reference):
//   - assignment rooms start when every bot seat is taken AND connected;
//   - "human" seats are played by the fake itself after HumanDelay;
//   - rematch only records answers.
package fakebackend

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"
)

// Options configures the fake.
type Options struct {
	ServiceKey           string
	ControllerTTL        time.Duration // default 15m
	TurnTimeout          time.Duration // default 2s: server auto-acts for a bot after this
	HumanDelay           time.Duration // default 1ms: fake humans act after this
	LobbyFillDeadline    time.Duration // load-test matchmaking lobby deadline (default 300ms)
	CompressionThreshold int           // default 64 bytes
	AllowLoadtest        bool
	PublicFillEnabled    bool
	// FillReturnsAssignments selects the documented fill response
	// ({"assignments":[...]}); by default the fake behaves like the backend
	// implementation: {"requested": n} with assignments delivered through
	// the GET /bot/assignments long-poll.
	FillReturnsAssignments bool
	// OmitPublicFillFlag drops "publicFillEnabled" from GET /bot/lobbies
	// (the documented response has no such field).
	OmitPublicFillFlag bool
	MaxBotsPerRoom     int // BOT_MAX_PER_ROOM (default 3)
	Seed               uint64
}

// Envelope is a server -> client message (hooks may mutate P).
type Envelope struct {
	T string         `json:"t"`
	R string         `json:"r,omitempty"`
	P map[string]any `json:"p,omitempty"`
}

// Hook can drop, duplicate, reorder or mutate outbound messages per uid.
type Hook func(uid string, env Envelope) []Envelope

// CommandHook can reject a game command before it is executed by returning
// an error code (e.g. "rate_limited", "stale_state"); "" lets it through.
type CommandHook func(uid, msgType string) (code string, retry bool)

// RecordedRequest is a REST request seen by the fake.
type RecordedRequest struct {
	Method string
	Path   string
	Header http.Header
	Body   string
}

// Server is the fake backend.
type Server struct {
	*httptest.Server
	opts Options

	mu          sync.Mutex
	ctlTokens   map[string]time.Time
	sessions    map[string]*session // by access token
	byUID       map[string]*session
	assignments map[string]*assignment
	queue       []*assignment // not yet handed out
	queueCh     chan struct{}
	rooms       map[string]*room
	conns       map[string]*wsConn
	seenIDs     map[string]bool // uid|id de-dup
	hook        Hook
	cmdHook     CommandHook
	seq         int
	dice        *diceSource

	requests     []RecordedRequest
	handshakes   []http.Header
	clientMsgs   map[string][]string
	syncCount    map[string]int
	fills        []FillRecord
	revoked      []string
	sessionBodys []map[string]any

	maintenance atomic.Bool
	closed      atomic.Bool
}

// FillRecord is one POST /bot/lobbies/{id}/fill.
type FillRecord struct {
	RoomID string
	Count  int
	Status int
}

type session struct {
	token     string
	uid       string
	name      string
	loadtest  bool
	roomID    string
	expiresAt time.Time
}

type assignment struct {
	ID        string `json:"id"`
	RoomID    string `json:"roomId"`
	Game      string `json:"game"`
	Variant   string `json:"variant"`
	Kind      string `json:"kind"`
	ExpiresAt int64  `json:"expiresAt"`
	used      bool
}

// New starts a fake backend.
func New(o Options) *Server {
	if o.ControllerTTL == 0 {
		o.ControllerTTL = 15 * time.Minute
	}
	if o.TurnTimeout == 0 {
		o.TurnTimeout = 2 * time.Second
	}
	if o.HumanDelay == 0 {
		o.HumanDelay = time.Millisecond
	}
	if o.LobbyFillDeadline == 0 {
		o.LobbyFillDeadline = 300 * time.Millisecond
	}
	if o.CompressionThreshold == 0 {
		o.CompressionThreshold = 64
	}
	if o.MaxBotsPerRoom == 0 {
		o.MaxBotsPerRoom = 3
	}
	if o.Seed == 0 {
		o.Seed = 42
	}
	s := &Server{
		opts: o, ctlTokens: map[string]time.Time{}, sessions: map[string]*session{}, byUID: map[string]*session{},
		assignments: map[string]*assignment{}, queueCh: make(chan struct{}, 1), rooms: map[string]*room{},
		conns: map[string]*wsConn{}, seenIDs: map[string]bool{}, clientMsgs: map[string][]string{},
		syncCount: map[string]int{}, dice: newDice(o.Seed),
	}
	mux := http.NewServeMux()
	mux.HandleFunc("POST /api/v1/bot/controller/token", s.handleControllerToken)
	mux.HandleFunc("GET /api/v1/bot/assignments", s.handleAssignments)
	mux.HandleFunc("GET /api/v1/bot/lobbies", s.handleLobbies)
	mux.HandleFunc("POST /api/v1/bot/lobbies/{roomId}/fill", s.handleFill)
	mux.HandleFunc("POST /api/v1/bot/sessions", s.handleCreateSession)
	mux.HandleFunc("DELETE /api/v1/bot/sessions/{uid}", s.handleRevoke)
	mux.HandleFunc("GET /api/v1/ws", s.handleWS)
	s.Server = httptest.NewServer(s.record(mux))
	return s
}

// Close shuts the fake down.
func (s *Server) Close() {
	s.closed.Store(true)
	s.mu.Lock()
	for _, r := range s.rooms {
		r.stopTimer()
	}
	conns := make([]*wsConn, 0, len(s.conns))
	for _, c := range s.conns {
		conns = append(conns, c)
	}
	s.mu.Unlock()
	for _, c := range conns {
		c.closeNow()
	}
	s.Server.CloseClientConnections()
	s.Server.Close()
}

// HTTPURL is the REST base URL (…/api/v1).
func (s *Server) HTTPURL() string { return s.URL + "/api/v1" }

// WSURL is the WebSocket URL.
func (s *Server) WSURL() string { return "ws" + strings.TrimPrefix(s.URL, "http") + "/api/v1/ws" }

func (s *Server) record(h http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var body []byte
		if r.Body != nil && r.URL.Path != "/api/v1/ws" {
			body, _ = io.ReadAll(io.LimitReader(r.Body, 1<<20))
			r.Body = io.NopCloser(strings.NewReader(string(body)))
		}
		s.mu.Lock()
		s.requests = append(s.requests, RecordedRequest{Method: r.Method, Path: r.URL.Path, Header: r.Header.Clone(), Body: string(body)})
		s.mu.Unlock()
		if s.maintenance.Load() && r.URL.Path == "/api/v1/bot/assignments" {
			writeJSON(w, http.StatusOK, map[string]any{"assignments": []any{}, "maintenance": true})
			return
		}
		if s.maintenance.Load() && r.URL.Path != "/api/v1/ws" && !strings.HasPrefix(r.URL.Path, "/api/v1/bot/controller") {
			writeErr(w, http.StatusServiceUnavailable, "maintenance", "maintenance in progress")
			return
		}
		h.ServeHTTP(w, r)
	})
}

func writeJSON(w http.ResponseWriter, code int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	_ = json.NewEncoder(w).Encode(v)
}

func writeErr(w http.ResponseWriter, code int, ecode, msg string) {
	writeJSON(w, code, map[string]any{"error": map[string]any{"code": ecode, "message": msg, "details": map[string]any{}}})
}

func randToken(prefix string) string {
	b := make([]byte, 12)
	_, _ = rand.Read(b)
	return prefix + hex.EncodeToString(b)
}

func (s *Server) nextIDLocked(prefix string) string {
	s.seq++
	return prefix + strconv.Itoa(s.seq)
}

// --- REST ---------------------------------------------------------------

func (s *Server) handleControllerToken(w http.ResponseWriter, r *http.Request) {
	if r.Header.Get("Authorization") != "Bot-Service "+s.opts.ServiceKey {
		writeErr(w, http.StatusUnauthorized, "unauthorized", "invalid service key")
		return
	}
	s.mu.Lock()
	tok := randToken("ct_")
	exp := time.Now().Add(s.opts.ControllerTTL)
	s.ctlTokens[tok] = exp
	s.mu.Unlock()
	writeJSON(w, http.StatusOK, map[string]any{"token": tok, "expiresAt": exp.UnixMilli()})
}

func (s *Server) controllerOK(w http.ResponseWriter, r *http.Request) bool {
	tok, ok := strings.CutPrefix(r.Header.Get("Authorization"), "Bearer ")
	s.mu.Lock()
	exp, found := s.ctlTokens[tok]
	s.mu.Unlock()
	if !ok || !found || time.Now().After(exp) {
		writeErr(w, http.StatusUnauthorized, "unauthorized", "controller token required")
		return false
	}
	return true
}

func (s *Server) handleAssignments(w http.ResponseWriter, r *http.Request) {
	if !s.controllerOK(w, r) {
		return
	}
	wait, _ := strconv.Atoi(r.URL.Query().Get("wait"))
	deadline := time.Now().Add(time.Duration(wait) * time.Second)
	for {
		s.mu.Lock()
		if len(s.queue) > 0 {
			out := s.queue
			s.queue = nil
			s.mu.Unlock()
			writeJSON(w, http.StatusOK, map[string]any{"assignments": out})
			return
		}
		s.mu.Unlock()
		rem := time.Until(deadline)
		if rem <= 0 {
			writeJSON(w, http.StatusOK, map[string]any{"assignments": []any{}})
			return
		}
		t := time.NewTimer(rem)
		select {
		case <-r.Context().Done():
			t.Stop()
			return
		case <-s.queueCh:
		case <-t.C:
		}
		t.Stop()
	}
}

func (s *Server) enqueueLocked(a *assignment) {
	s.assignments[a.ID] = a
	s.queue = append(s.queue, a)
	select {
	case s.queueCh <- struct{}{}:
	default:
	}
}

func (s *Server) handleLobbies(w http.ResponseWriter, r *http.Request) {
	if !s.controllerOK(w, r) {
		return
	}
	s.mu.Lock()
	out := []map[string]any{}
	for _, rm := range s.rooms {
		if rm.mode != "public" || rm.status != "lobby" || rm.loadtest {
			continue
		}
		humans, bots := rm.counts()
		out = append(out, map[string]any{
			"roomId": rm.id, "game": rm.game, "variant": rm.variant, "capacity": rm.capacity,
			"humans": humans, "bots": bots, "pendingBots": rm.pendingBots,
			"waitingMs": time.Since(rm.createdAt).Milliseconds(),
		})
	}
	resp := map[string]any{"lobbies": out}
	if !s.opts.OmitPublicFillFlag {
		resp["publicFillEnabled"] = s.opts.PublicFillEnabled
	}
	s.mu.Unlock()
	writeJSON(w, http.StatusOK, resp)
}

func (s *Server) handleFill(w http.ResponseWriter, r *http.Request) {
	if !s.controllerOK(w, r) {
		return
	}
	roomID := r.PathValue("roomId")
	var body struct {
		Count int `json:"count"`
	}
	_ = json.NewDecoder(r.Body).Decode(&body)
	s.mu.Lock()
	defer s.mu.Unlock()
	rec := FillRecord{RoomID: roomID, Count: body.Count}
	defer func() { s.fills = append(s.fills, rec) }()
	if !s.opts.PublicFillEnabled {
		rec.Status = http.StatusForbidden
		writeErr(w, http.StatusForbidden, "public_fill_disabled", "Public bot fill is disabled on this server.")
		return
	}
	if body.Count < 1 || body.Count > 3 {
		rec.Status = http.StatusBadRequest
		writeErr(w, http.StatusBadRequest, "bad_request", "count must be 1..3")
		return
	}
	rm := s.rooms[roomID]
	conflict := func(code string) {
		rec.Status = http.StatusConflict
		writeErr(w, http.StatusConflict, code, "fill refused")
	}
	if rm == nil || rm.status != "lobby" || rm.mode != "public" || rm.loadtest {
		conflict("lobby_changed")
		return
	}
	humans, bots := rm.counts()
	free := rm.capacity - humans - bots - rm.pendingBots
	switch {
	case rm.pendingBots > 0:
		conflict("bots_pending")
		return
	case humans == 0:
		conflict("lobby_changed")
		return
	case body.Count > free || bots+body.Count > s.opts.MaxBotsPerRoom:
		conflict("capacity")
		return
	}
	out := []*assignment{}
	for i := 0; i < body.Count; i++ {
		a := &assignment{ID: s.nextIDLocked("as_"), RoomID: rm.id, Game: rm.game, Variant: rm.variant, Kind: "public_fill",
			ExpiresAt: time.Now().Add(30 * time.Second).UnixMilli()}
		if s.opts.FillReturnsAssignments {
			s.assignments[a.ID] = a
		} else {
			s.enqueueLocked(a)
		}
		out = append(out, a)
	}
	rm.pendingBots += body.Count
	rec.Status = http.StatusOK
	if s.opts.FillReturnsAssignments {
		writeJSON(w, http.StatusOK, map[string]any{"assignments": out})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"requested": body.Count})
}

// botName mirrors the backend: a visible "Bot" label, at most 20 runes.
func botName(name string) string {
	name = strings.TrimSpace(name)
	if name == "" {
		name = "Bot"
	}
	if !strings.HasPrefix(strings.ToLower(name), "bot") {
		name = "Bot " + name
	}
	if r := []rune(name); len(r) > 20 {
		name = string(r[:20])
	}
	return name
}

func (s *Server) handleCreateSession(w http.ResponseWriter, r *http.Request) {
	if !s.controllerOK(w, r) {
		return
	}
	raw, _ := io.ReadAll(r.Body)
	var body map[string]any
	if err := json.Unmarshal(raw, &body); err != nil {
		writeErr(w, http.StatusBadRequest, "bad_request", "invalid json")
		return
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	s.sessionBodys = append(s.sessionBodys, body)
	name, _ := body["name"].(string)
	name = botName(name)
	sess := &session{token: randToken("bt_"), uid: s.nextIDLocked("u_bot"), name: name, expiresAt: time.Now().Add(2 * time.Hour)}
	if mode, _ := body["mode"].(string); mode == "loadtest" {
		if !s.opts.AllowLoadtest {
			writeErr(w, http.StatusForbidden, "loadtest_disabled", "Load-test sessions are not allowed on this server.")
			return
		}
		sess.loadtest = true
	} else {
		id, _ := body["assignmentId"].(string)
		a := s.assignments[id]
		if a == nil || a.used || time.Now().UnixMilli() > a.ExpiresAt {
			writeErr(w, http.StatusNotFound, "assignment_not_found", "Assignment expired or already claimed.")
			return
		}
		rm := s.rooms[a.RoomID]
		if rm == nil || rm.status != "lobby" || rm.full() {
			writeErr(w, http.StatusConflict, "room_unavailable", "The room no longer needs a bot.")
			return
		}
		a.used = true
		if a.Kind == "public_fill" && rm.pendingBots > 0 {
			rm.pendingBots--
		}
		sess.roomID = rm.id
		rm.seat(&player{uid: sess.uid, name: name, bot: true})
		s.emitRoomUpdatedLocked(rm, "joined")
	}
	s.sessions[sess.token] = sess
	s.byUID[sess.uid] = sess
	writeJSON(w, http.StatusOK, map[string]any{"accessToken": sess.token, "expiresAt": sess.expiresAt.UnixMilli(), "uid": sess.uid, "roomId": sess.roomID})
}

func (s *Server) handleRevoke(w http.ResponseWriter, r *http.Request) {
	if !s.controllerOK(w, r) {
		return
	}
	uid := r.PathValue("uid")
	s.mu.Lock()
	sess := s.byUID[uid]
	if sess == nil {
		s.mu.Unlock()
		writeErr(w, http.StatusNotFound, "not_found", "no such session")
		return
	}
	s.revoked = append(s.revoked, uid)
	delete(s.byUID, uid)
	delete(s.sessions, sess.token)
	if sess.roomID != "" {
		if rm := s.rooms[sess.roomID]; rm != nil {
			s.leaveLocked(rm, uid)
		}
	}
	c := s.conns[uid]
	s.mu.Unlock()
	if c != nil {
		c.closeWith(4401, "session revoked")
	}
	w.WriteHeader(http.StatusNoContent)
}

// --- test controls ------------------------------------------------------

// SetHook installs an outbound message hook (nil removes it).
func (s *Server) SetHook(h Hook) {
	s.mu.Lock()
	s.hook = h
	s.mu.Unlock()
}

// SetCommandHook installs a command rejection hook (nil removes it).
func (s *Server) SetCommandHook(h CommandHook) {
	s.mu.Lock()
	s.cmdHook = h
	s.mu.Unlock()
}

// SetMaintenance toggles maintenance: REST and upgrades answer 503 and live
// connections are closed with 4503.
func (s *Server) SetMaintenance(on bool) {
	s.maintenance.Store(on)
	if !on {
		return
	}
	s.mu.Lock()
	conns := make([]*wsConn, 0, len(s.conns))
	for _, c := range s.conns {
		conns = append(conns, c)
	}
	s.mu.Unlock()
	for _, c := range conns {
		c.send(Envelope{T: "error", P: map[string]any{"code": "maintenance", "msg": "maintenance", "retry": true}})
		c.closeWith(4503, "maintenance")
	}
}

// SetPublicFill toggles BOT_PUBLIC_FILL_ENABLED.
func (s *Server) SetPublicFill(on bool) {
	s.mu.Lock()
	s.opts.PublicFillEnabled = on
	s.mu.Unlock()
}

// DropConnection abruptly drops a bot's connection (network failure).
func (s *Server) DropConnection(uid string) bool {
	s.mu.Lock()
	c := s.conns[uid]
	s.mu.Unlock()
	if c == nil {
		return false
	}
	c.closeNow()
	return true
}

// CloseConnection closes a bot's connection with a close code.
func (s *Server) CloseConnection(uid string, code int) bool {
	s.mu.Lock()
	c := s.conns[uid]
	s.mu.Unlock()
	if c == nil {
		return false
	}
	c.closeWith(code, "test close")
	return true
}

// Requests returns recorded REST requests.
func (s *Server) Requests() []RecordedRequest {
	s.mu.Lock()
	defer s.mu.Unlock()
	return append([]RecordedRequest(nil), s.requests...)
}

// Handshakes returns recorded WebSocket handshake headers.
func (s *Server) Handshakes() []http.Header {
	s.mu.Lock()
	defer s.mu.Unlock()
	return append([]http.Header(nil), s.handshakes...)
}

// ClientMessages returns raw messages received from a uid ("" = all).
func (s *Server) ClientMessages(uid string) []string {
	s.mu.Lock()
	defer s.mu.Unlock()
	if uid != "" {
		return append([]string(nil), s.clientMsgs[uid]...)
	}
	var out []string
	for _, m := range s.clientMsgs {
		out = append(out, m...)
	}
	return out
}

// SyncCount returns how many game.request_sync a uid sent.
func (s *Server) SyncCount(uid string) int {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.syncCount[uid]
}

// Fills returns recorded fill requests.
func (s *Server) Fills() []FillRecord {
	s.mu.Lock()
	defer s.mu.Unlock()
	return append([]FillRecord(nil), s.fills...)
}

// Revoked returns revoked session uids.
func (s *Server) Revoked() []string {
	s.mu.Lock()
	defer s.mu.Unlock()
	return append([]string(nil), s.revoked...)
}

// SessionBodies returns POST /bot/sessions bodies.
func (s *Server) SessionBodies() []map[string]any {
	s.mu.Lock()
	defer s.mu.Unlock()
	return append([]map[string]any(nil), s.sessionBodys...)
}

// ConnectedUIDs returns uids with a live WebSocket.
func (s *Server) ConnectedUIDs() []string {
	s.mu.Lock()
	defer s.mu.Unlock()
	out := make([]string, 0, len(s.conns))
	for uid := range s.conns {
		out = append(out, uid)
	}
	return out
}

// RoomInfo is a test view of a room.
type RoomInfo struct {
	ID       string
	Status   string
	Game     string
	Mode     string
	V        int64
	Players  []PlayerInfo
	Winner   int
	Finished bool
	Moves    int // bot-submitted moves applied
	Rolls    int // bot-submitted rolls applied
	Autos    int // server auto actions for bot seats (timeouts)
}

// PlayerInfo is a test view of a seat.
type PlayerInfo struct {
	Seat      int
	UID       string
	Name      string
	Bot       bool
	Connected bool
	Forfeited bool
}

// Room returns a snapshot of a room.
func (s *Server) Room(id string) (RoomInfo, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	rm := s.rooms[id]
	if rm == nil {
		return RoomInfo{}, false
	}
	return rm.info(), true
}

// Rooms returns all rooms.
func (s *Server) Rooms() []RoomInfo {
	s.mu.Lock()
	defer s.mu.Unlock()
	out := make([]RoomInfo, 0, len(s.rooms))
	for _, rm := range s.rooms {
		out = append(out, rm.info())
	}
	return out
}

// RoomSetup customizes a test room.
type RoomSetup struct {
	Game        string // "ludo" | "snakes_ladders"
	Variant     string
	Kind        string // "practice" | "private"
	Humans      int    // server-driven human seats (default 1)
	Bots        int
	StartTokens [][]int // ludo: per seat (after compaction) initial progress
	StartPos    []int   // snakes: per seat initial square
	Dice        []int   // scripted dice for this room (cycled); empty = seeded RNG
	ExpiresIn   time.Duration
}

// StartPractice creates a practice/private room with humans and queues bot
// assignments (handed out via GET /bot/assignments). It returns the room id.
func (s *Server) StartPractice(rs RoomSetup) string {
	if rs.Humans == 0 {
		rs.Humans = 1
	}
	if rs.Kind == "" {
		rs.Kind = "practice"
	}
	if rs.Variant == "" {
		rs.Variant = "classic"
	}
	if rs.ExpiresIn == 0 {
		rs.ExpiresIn = 30 * time.Second
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	mode := "practice"
	if rs.Kind == "private" {
		mode = "private"
	}
	rm := s.newRoomLocked(rs.Game, rs.Variant, mode, rs.Humans+rs.Bots)
	rm.startTokens, rm.startPos = rs.StartTokens, rs.StartPos
	if len(rs.Dice) > 0 {
		rm.script = append([]int(nil), rs.Dice...)
	}
	for i := 0; i < rs.Humans; i++ {
		rm.seat(&player{uid: s.nextIDLocked("u_h"), name: fmt.Sprintf("Human%d", i+1), human: true, connected: true})
	}
	for i := 0; i < rs.Bots; i++ {
		s.enqueueLocked(&assignment{ID: s.nextIDLocked("as_"), RoomID: rm.id, Game: rm.game, Variant: rm.variant,
			Kind: rs.Kind, ExpiresAt: time.Now().Add(rs.ExpiresIn).UnixMilli()})
	}
	return rm.id
}

// LobbySetup creates an open public lobby for fill tests.
type LobbySetup struct {
	Game     string
	Variant  string
	Capacity int
	Humans   int
	Waited   time.Duration // pretend the lobby was created this long ago
	Dice     []int
}

// AddLobby creates a public lobby with human seats.
func (s *Server) AddLobby(ls LobbySetup) string {
	if ls.Variant == "" {
		ls.Variant = "classic"
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	rm := s.newRoomLocked(ls.Game, ls.Variant, "public", ls.Capacity)
	rm.createdAt = time.Now().Add(-ls.Waited)
	if len(ls.Dice) > 0 {
		rm.script = append([]int(nil), ls.Dice...)
	}
	for i := 0; i < ls.Humans; i++ {
		rm.seat(&player{uid: s.nextIDLocked("u_h"), name: fmt.Sprintf("Human%d", i+1), human: true, connected: true})
	}
	return rm.id
}

// AssignmentCount returns how many assignments exist (all kinds).
func (s *Server) AssignmentCount() int {
	s.mu.Lock()
	defer s.mu.Unlock()
	return len(s.assignments)
}

// DebugRooms describes every room (for test failure output).
func (s *Server) DebugRooms() string {
	s.mu.Lock()
	defer s.mu.Unlock()
	var b strings.Builder
	for _, rm := range s.rooms {
		fmt.Fprintf(&b, "%s game=%s status=%s v=%d seat=%d phase=%s seq=%d dice=%d timer=%v players=[", rm.id, rm.game, rm.status, rm.v, rm.turnSeat, rm.phase, rm.turnSeq, rm.dice, rm.timer != nil)
		for _, p := range rm.players {
			_, live := s.conns[p.uid]
			fmt.Fprintf(&b, "{%s bot=%v conn=%v live=%v forf=%v left=%v gone=%v strikes=%d} ", p.uid, p.bot, p.connected, live, p.forfeited, p.left, p.gone, p.strikes)
		}
		b.WriteString("]\n")
	}
	return b.String()
}
