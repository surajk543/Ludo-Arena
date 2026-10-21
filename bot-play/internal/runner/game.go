package runner

import (
	"context"
	"encoding/json"
	"strconv"
	"time"

	"ludoroyale/botplay/internal/chatter"
	"ludoroyale/botplay/internal/client"
	"ludoroyale/botplay/internal/config"
	"ludoroyale/botplay/internal/connection"
	"ludoroyale/botplay/internal/matchmaking"
	"ludoroyale/botplay/internal/profiles"
	"ludoroyale/botplay/internal/snakes_ladders"
)

const (
	leaveAckTimeout   = 3 * time.Second
	maxSyncFailures   = 3
	rematchGrace      = 5 * time.Second
	sessionRenewAhead = 10 * time.Minute
	// stallGrace: when the server's turn deadline passed this long ago and
	// no newer event arrived, an event was probably lost (e.g. the last one
	// of a turn or game); request a sync once for that state version.
	stallGrace = 2 * time.Second
)

type turnKey struct {
	seq   int
	phase string
}

type pendingAction struct {
	typ    string // "roll" | "move"
	id     string
	key    turnKey
	sentAt time.Time
}

// gameState is the per-bot game loop state, owned by the bot goroutine.
type gameState struct {
	roomID       string
	state        connection.RoomState
	mySeat       int
	msgSeq       uint64 // message ids stay unique across reconnects (server de-dup)
	serverOffset time.Duration
	ready        bool
	reconnected  bool
	minDelay     time.Duration

	syncPending  bool
	syncID       string
	syncSentAt   time.Time
	syncFailures int
	verifyResync bool
	verifyPrevV  int64

	hasActed      bool
	actedKey      turnKey
	pending       *pendingAction
	thinkKey      turnKey
	thinkAt       time.Time
	throttleUntil time.Time
	throttleLevel int

	wantLeave       bool
	leaveID         string
	leaveDeadline   time.Time
	cancelID        string
	rematchID       string
	done            bool
	dropNow         bool
	readyDeadline   time.Time
	lobbyDeadline   time.Time
	rematchDeadline time.Time

	malformed map[string]bool // ids of deliberately malformed messages (load test)

	joinAt     time.Time
	joinID     string
	joinSentAt time.Time
	searching  bool

	stallSyncV   int64  // state version a stall sync was already sent for
	countedGame  string // roomID/round already counted as started
	finishedGame string // roomID/round already handled as finished

	// Quick-chat / emote reactions (chat.go).
	chat           chatter.State
	chatPending    *pendingChat
	chatIDs        map[string]string // message id -> kind of sent chat messages
	leaveAfterChat bool              // leave the finished room once the pending reaction is sent
}

type serveResult struct {
	done bool
	info connection.CloseInfo
}

// serve runs the game loop on one connection until it ends or the bot is
// done. All state mutation happens on this goroutine.
func (b *Bot) serve(ctx context.Context, conn *connection.Conn, reconnect bool) serveResult {
	g := &b.g
	cfg := b.svc.store.Config()
	g.ready = false
	g.reconnected = reconnect
	g.syncPending = false
	g.pending = nil
	g.thinkAt = time.Time{}
	g.leaveID = ""
	g.cancelID = ""
	g.dropNow = false
	g.readyDeadline = time.Now().Add(cfg.Connection.ConnectTimeout())

	wake := time.NewTimer(time.Hour)
	defer wake.Stop()
	for {
		if g.done {
			conn.Close(connection.CloseNormal, "bye")
			return serveResult{done: true}
		}
		if g.dropNow {
			g.dropNow = false
			conn.Abort(connection.CloseLocal, "simulated disconnect")
			return serveResult{info: conn.Info()}
		}
		b.resetWake(wake)
		select {
		case <-ctx.Done():
			conn.Abort(connection.CloseLocal, "hard stop")
			return serveResult{done: true}
		case <-conn.Done():
			return serveResult{info: conn.Info()}
		case msg := <-conn.Recv():
			b.handle(conn, msg)
		case <-b.retireCh:
			b.onRetire(conn)
		case <-b.churnCh:
			b.log.Debug("churn: dropping connection")
			conn.Abort(connection.CloseLocal, "churn")
			return serveResult{info: conn.Info()}
		case <-wake.C:
			b.onTick(conn)
		}
		b.maybeAct(conn)
	}
}

func (b *Bot) resetWake(t *time.Timer) {
	g := &b.g
	next := time.Time{}
	consider := func(ts time.Time) {
		if !ts.IsZero() && (next.IsZero() || ts.Before(next)) {
			next = ts
		}
	}
	if !g.ready {
		consider(g.readyDeadline)
	}
	consider(g.thinkAt)
	if g.pending != nil {
		consider(g.pending.sentAt.Add(b.confirmTimeout()))
	}
	if g.syncPending {
		consider(g.syncSentAt.Add(b.confirmTimeout()))
	}
	consider(g.lobbyDeadline)
	consider(g.leaveDeadline)
	consider(g.rematchDeadline)
	consider(g.joinAt)
	if at, ok := b.stallAt(); ok {
		consider(at)
	}
	if g.chatPending != nil {
		consider(g.chatPending.at)
	}
	d := time.Hour
	if !next.IsZero() {
		d = max(time.Until(next), 0)
	}
	t.Reset(d)
}

// stallAt returns when a playing room with no new events should be resynced.
func (b *Bot) stallAt() (time.Time, bool) {
	g := &b.g
	r := g.state.Room()
	if r == nil || r.Status != connection.StatusPlaying || r.Turn.Deadline <= 0 || g.syncPending || g.stallSyncV == r.V {
		return time.Time{}, false
	}
	return b.serverToLocal(r.Turn.Deadline).Add(stallGrace), true
}

func (b *Bot) confirmTimeout() time.Duration {
	return b.svc.store.Config().Connection.ActionConfirmTimeout()
}

// nextID returns a message id unique for this bot's account for longer than
// the server's 2-minute de-duplication window: a random per-bot prefix
// (later sessions of the same persona reuse the account) and a counter that
// keeps growing across reconnects.
func (b *Bot) nextID() string {
	b.g.msgSeq++
	return "m" + b.idPrefix + "." + strconv.FormatUint(b.g.msgSeq, 10)
}

func (b *Bot) send(conn *connection.Conn, t string, p any, metricType string) string {
	id := b.nextID()
	if err := conn.Send(connection.Outbound{T: t, ID: id, P: p}); err != nil {
		b.log.Debug("send failed", "type", t, "error", err.Error())
		return id
	}
	if metricType != "" {
		b.svc.m.RecordAction(metricType)
	}
	return id
}

func (b *Bot) handle(conn *connection.Conn, msg connection.Inbound) {
	switch msg.T {
	case connection.TReady:
		b.onReady(conn, msg)
	case connection.TAck:
		if b.chatReply(msg.R, false) {
			return
		}
		if msg.R != "" && msg.R == b.g.leaveID {
			b.afterLeave()
		}
	case connection.TError:
		b.onError(conn, msg)
	case connection.TMatchmakingStatus:
		b.onMatchmaking(conn, msg)
	case connection.TRoomUpdated, connection.TGameStarted, connection.TGameState:
		b.onSnapshot(conn, msg)
	default:
		if connection.IsVersionedDelta(msg.T) {
			b.onDelta(conn, msg)
		}
		// Everything else (wallet, progression, chat, social, unknown types)
		// is ignored, as the protocol requires for unknown types.
	}
}

func (b *Bot) onReady(conn *connection.Conn, msg connection.Inbound) {
	g := &b.g
	var p connection.Ready
	_ = json.Unmarshal(msg.P, &p)
	g.ready = true
	g.readyDeadline = time.Time{}
	if p.ServerTime > 0 {
		g.serverOffset = time.UnixMilli(p.ServerTime).Sub(msg.At)
	}
	if g.reconnected {
		b.svc.m.RecordReconnect(true)
		g.verifyResync = true
		g.verifyPrevV = g.state.V()
	}
	b.log.Debug("connection ready", "compression", p.Compression, "active_room_id", p.ActiveRoomID, "reconnect", g.reconnected)
	if g.wantLeave {
		b.leave(conn)
		return
	}
	if g.roomID == "" && p.ActiveRoomID != "" {
		g.roomID = p.ActiveRoomID
	}
	if b.kind == client.KindLoadtest && g.roomID == "" && !g.searching {
		b.scheduleJoin(false)
		return
	}
	reason := "connect"
	if g.reconnected {
		reason = "reconnect"
	}
	b.requestSync(conn, reason)
}

func (b *Bot) requestSync(conn *connection.Conn, reason string) {
	g := &b.g
	if !g.ready {
		return
	}
	if g.syncPending && time.Since(g.syncSentAt) < b.confirmTimeout() {
		return
	}
	var p any
	if g.roomID != "" {
		p = connection.RoomRef{RoomID: g.roomID}
	}
	g.syncID = b.send(conn, connection.TRequestSync, p, "sync")
	g.syncPending = true
	g.syncSentAt = time.Now()
	b.svc.m.RecordResync(reason)
	if reason != "connect" && reason != "reconnect" {
		b.log.Debug("requesting state sync", "reason", reason, "local_v", g.state.V())
	}
}

func roomGoneCode(code string) bool {
	return code == "not_in_room" || code == "room_not_found" || code == "room_closed"
}

func (b *Bot) onError(conn *connection.Conn, msg connection.Inbound) {
	g := &b.g
	var p connection.ErrorPayload
	_ = json.Unmarshal(msg.P, &p)
	if b.chatReply(msg.R, true) {
		// A refused chat message (rate limit, emote) is never retried and
		// never slows down game actions.
		b.log.Debug("chat message refused", "code", p.Code)
		return
	}
	b.svc.m.RecordError(p.Code)
	b.log.Debug("server error", "code", p.Code, "msg", p.Msg, "retry", p.Retry, "reply_to", msg.R)
	r := msg.R
	if r != "" && g.malformed[r] {
		delete(g.malformed, r) // expected rejection of an injected message
		return
	}
	switch {
	case r != "" && r == g.leaveID:
		b.afterLeave()
		return
	case r != "" && r == g.rematchID:
		// The backend may not accept game.rematch from bots: leave now.
		g.rematchID = ""
		g.rematchDeadline = time.Time{}
		b.leave(conn)
		return
	case r != "" && r == g.cancelID:
		g.cancelID = ""
		if roomGoneCode(p.Code) {
			b.afterLeave()
			return
		}
		// Cancel failed because the lobby already started: play the game
		// (a retiring bot exits after it).
		g.leaveDeadline = time.Time{}
		return
	case r != "" && r == g.syncID && g.syncPending:
		g.syncPending = false
		if roomGoneCode(p.Code) {
			if g.verifyResync {
				g.verifyResync = false
				b.svc.m.RecordResyncVerification("room_gone")
			}
			b.roomGone("sync: " + p.Code)
			return
		}
	case r != "" && r == g.joinID:
		g.joinID = ""
		g.searching = false
		if p.Code == "already_in_room" {
			b.requestSync(conn, "already_in_room")
			return
		}
		b.throttle()
		b.scheduleJoin(true)
		return
	case r != "" && g.pending != nil && r == g.pending.id:
		g.pending = nil
	}
	switch p.Code {
	case "stale_state", "invalid_phase", "illegal_move":
		b.requestSync(conn, p.Code)
	case "not_your_turn":
		// Wait for the server's next turn event.
	case "rate_limited":
		b.throttle()
		if p.Retry {
			g.hasActed = false
		}
	case "maintenance":
		b.svc.noteMaintenance()
	case "not_in_room", "room_not_found", "room_closed":
		b.roomGone(p.Code)
	case "unauthorized":
		b.log.Warn("server reports bot session unauthorized; exiting")
		g.done = true
	}
}

// throttle slows a bot down after rate_limited (exponential, jittered).
func (b *Bot) throttle() {
	g := &b.g
	g.throttleLevel++
	d := client.Backoff{Base: 500 * time.Millisecond, Max: 10 * time.Second}.Ceiling(g.throttleLevel)
	g.throttleUntil = time.Now().Add(d/2 + client.FullJitter(d/2))
}

func (b *Bot) onMatchmaking(conn *connection.Conn, msg connection.Inbound) {
	g := &b.g
	var p connection.MatchmakingStatus
	_ = json.Unmarshal(msg.P, &p)
	if g.joinID != "" && msg.R == g.joinID {
		b.svc.m.ObserveLatency("join", time.Since(g.joinSentAt))
		g.joinID = ""
	}
	switch p.Status {
	case "searching":
		g.searching = true
		if p.RoomID != "" && g.roomID != p.RoomID {
			g.roomID = p.RoomID
			b.svc.m.RoomJoins.WithLabelValues(client.KindLoadtest).Inc()
		}
		if g.lobbyDeadline.IsZero() {
			g.lobbyDeadline = time.Now().Add(b.svc.store.Config().Bots.LobbyWaitTimeout())
		}
	case "cancelled":
		b.afterLeave()
	case "timeout":
		b.log.Debug("matchmaking timed out")
		b.roomGone("matchmaking_timeout")
	}
}

func (b *Bot) onSnapshot(conn *connection.Conn, msg connection.Inbound) {
	g := &b.g
	var p connection.RoomPayload
	if err := json.Unmarshal(msg.P, &p); err != nil || p.Room == nil {
		return
	}
	r := p.Room
	uid := b.session.UID
	if g.roomID != "" && r.ID != g.roomID {
		if !(b.kind == client.KindLoadtest && g.searching && r.SeatOf(uid) >= 0) {
			b.svc.m.EventsIgnored.WithLabelValues("other_room").Inc()
			return
		}
	}
	if g.roomID == "" {
		if r.SeatOf(uid) < 0 {
			b.svc.m.EventsIgnored.WithLabelValues("other_room").Inc()
			return
		}
	}
	// Any game.state answers a pending sync (the backend also pushes one
	// unsolicited after connection.ready and after stale_state).
	isSyncReply := msg.T == connection.TGameState && g.syncPending
	out := g.state.ApplySnapshot(r)
	if isSyncReply {
		g.syncPending = false
		g.syncFailures = 0
		if msg.R == g.syncID {
			b.svc.m.ObserveLatency("sync", time.Since(g.syncSentAt))
		}
	}
	if out == connection.Duplicate {
		b.svc.m.EventsIgnored.WithLabelValues("stale_snapshot").Inc()
		return
	}
	g.roomID = r.ID
	// A snapshot supersedes anything in flight.
	g.pending = nil
	if isSyncReply || msg.T == connection.TGameState {
		g.hasActed = false
	}
	if match, ok := connection.VerifySnapshotHash(r); ok && !match {
		b.svc.m.RecordHashMismatch()
		b.log.Warn("snapshot hash differs from local computation (check canonical hash rules)", "v", r.V)
	}
	if g.verifyResync && msg.T == connection.TGameState {
		g.verifyResync = false
		match, hashed := connection.VerifySnapshotHash(r)
		if r.V >= g.verifyPrevV && (!hashed || match) {
			b.svc.m.RecordResyncVerification("verified")
		} else {
			b.svc.m.RecordResyncVerification("failed")
			b.log.Warn("resync after reconnect did not verify", "v", r.V, "previous_v", g.verifyPrevV)
		}
	}
	b.afterStateChange(conn)
}

func (b *Bot) onDelta(conn *connection.Conn, msg connection.Inbound) {
	g := &b.g
	out, err := g.state.ApplyDelta(msg.T, msg.P)
	switch out {
	case connection.Applied:
		b.onApplied(conn, msg)
	case connection.HashMismatch:
		b.svc.m.RecordHashMismatch()
		b.log.Warn("state hash mismatch; resyncing", "type", msg.T, "v", g.state.V())
		b.onApplied(conn, msg)
		b.requestSync(conn, "hash_mismatch")
	case connection.Duplicate:
		b.svc.m.EventsIgnored.WithLabelValues("duplicate").Inc()
	case connection.OtherRoom:
		b.svc.m.EventsIgnored.WithLabelValues("other_room").Inc()
	case connection.Gap:
		b.svc.m.EventsIgnored.WithLabelValues("gap").Inc()
		b.requestSync(conn, "gap")
	case connection.NoState:
		b.svc.m.EventsIgnored.WithLabelValues("no_state").Inc()
		b.requestSync(conn, "no_state")
	case connection.Invalid:
		b.log.Warn("undecodable event; resyncing", "type", msg.T, "error", errString(err))
		b.requestSync(conn, "invalid")
	}
}

func errString(err error) string {
	if err == nil {
		return ""
	}
	return err.Error()
}

func (b *Bot) onApplied(conn *connection.Conn, msg connection.Inbound) {
	g := &b.g
	switch msg.T {
	case connection.TDiceResult:
		var p connection.DiceResult
		_ = json.Unmarshal(msg.P, &p)
		if p.Seat == g.mySeat && g.pending != nil && g.pending.typ == "roll" {
			b.svc.m.ObserveLatency("roll", time.Since(g.pending.sentAt))
			g.pending = nil
			g.throttleLevel = 0
		}
		b.reactToDice(p)
	case connection.TMoveApplied:
		var p connection.MoveApplied
		_ = json.Unmarshal(msg.P, &p)
		if p.Seat == g.mySeat && g.pending != nil && g.pending.typ == "move" {
			b.svc.m.ObserveLatency("move", time.Since(g.pending.sentAt))
			g.pending = nil
			g.throttleLevel = 0
		}
		if r := g.state.Room(); r != nil && r.Game == "snakes_ladders" && p.Seat == g.mySeat {
			if exp := snakes_ladders.ExpectedDestination(p.From, r.Turn.Dice); exp != p.To {
				b.log.Debug("server destination differs from documented board (server wins)", "from", p.From, "dice", r.Turn.Dice, "to", p.To)
			}
		}
		b.reactToMove(p)
	case connection.TTurnChanged:
		g.pending = nil // the server moved on (e.g. voided roll / no legal move)
	}
	b.afterStateChange(conn)
}

func gameKeyOf(r *connection.Room) string {
	if k := config.GameKey(r.Game, r.Variant); k != "" {
		return k
	}
	return gameNone
}

func (b *Bot) afterStateChange(conn *connection.Conn) {
	g := &b.g
	r := g.state.Room()
	if r == nil {
		return
	}
	g.mySeat = r.SeatOf(b.session.UID)
	if g.mySeat < 0 {
		if r.Status == connection.StatusLobby || r.Status == connection.StatusPlaying {
			b.roomGone("not_seated")
		}
		return
	}
	me := r.Player(g.mySeat)
	gameID := r.ID + "/" + strconv.Itoa(r.Round)
	switch r.Status {
	case connection.StatusLobby:
		g.rematchDeadline = time.Time{}
		if g.lobbyDeadline.IsZero() {
			g.lobbyDeadline = time.Now().Add(b.svc.store.Config().Bots.LobbyWaitTimeout())
		}
		if b.kind == client.KindLoadtest && b.RetireMode() != RetireNone {
			b.leaveOrDone(conn)
		}
	case connection.StatusPlaying:
		g.lobbyDeadline = time.Time{}
		g.rematchDeadline = time.Time{}
		g.searching = false
		if g.countedGame != gameID {
			g.countedGame = gameID
			b.inGame.Store(true)
			b.svc.m.RecordGameStarted(gameKeyOf(r))
			b.log.Info("game started", append(b.roomAttr(r), "seat", g.mySeat, "players", len(r.Players), "round", r.Round)...)
			if r.Turn.TurnSeq <= 1 {
				b.react(chatter.GameStart) // not when joining a game already under way
			}
		}
		if me != nil && me.Forfeited {
			b.log.Warn("this bot was forfeited; leaving", b.roomAttr(r)...)
			b.leave(conn)
		}
	case connection.StatusFinished:
		b.onFinished(conn, r)
	case connection.StatusClosed:
		b.roomGone("room_closed")
	}
}

func (b *Bot) onFinished(conn *connection.Conn, r *connection.Room) {
	g := &b.g
	gameID := r.ID + "/" + strconv.Itoa(r.Round)
	if g.finishedGame == gameID {
		if !g.rematchDeadline.IsZero() && r.Rematch != nil && !r.Rematch.Open {
			b.leave(conn) // rematch window closed without a new round
		}
		return
	}
	g.finishedGame = gameID
	g.lobbyDeadline = time.Time{}
	g.thinkAt = time.Time{}
	played := g.countedGame == gameID
	if played {
		b.svc.m.RecordGameFinished(gameKeyOf(r))
	}
	b.inGame.Store(false)
	winner := -1
	if r.Result != nil {
		winner = r.Result.WinnerSeat
	}
	b.log.Info("game finished", append(b.roomAttr(r), "seat", g.mySeat, "winner_seat", winner)...)
	switch {
	case winner >= 0 && winner == g.mySeat:
		b.react(chatter.Win)
	case winner >= 0 && played:
		b.react(chatter.Loss)
	}
	cfg := b.svc.store.Config()
	if cfg.Bots.AcceptRematch && (b.kind == client.KindPractice || b.kind == client.KindPrivate) &&
		r.Rematch != nil && r.Rematch.Open && b.RetireMode() == RetireNone && cfg.Bots.Enabled && !b.svc.stopping.Load() {
		g.rematchID = b.send(conn, connection.TRematch, connection.RematchAnswer{RoomID: r.ID, Accept: true}, "rematch")
		g.rematchDeadline = b.serverToLocal(r.Rematch.Deadline).Add(rematchGrace)
		return
	}
	// Default: decline by leaving (room.leave in a finished room counts as
	// a declined rematch) — after the pending "gg", like a person.
	if g.chatPending != nil && g.chatPending.match == gameID {
		g.leaveAfterChat = true
		return
	}
	b.leave(conn)
}

// roomAttr adds room_id for load-test bots (assignment bots' loggers already
// carry it).
func (b *Bot) roomAttr(r *connection.Room) []any {
	if b.assignment != nil {
		return nil
	}
	return []any{"room_id", r.ID}
}

func (b *Bot) serverToLocal(ms int64) time.Time {
	if ms <= 0 {
		return time.Now()
	}
	return time.UnixMilli(ms).Add(-b.g.serverOffset)
}

func (b *Bot) remaining(deadline int64) (time.Duration, bool) {
	if deadline <= 0 {
		return 0, false
	}
	return time.Until(b.serverToLocal(deadline)), true
}

// roomGone handles the bot's room ending or becoming unreachable.
func (b *Bot) roomGone(reason string) {
	b.log.Info("room gone", "reason", reason)
	if b.kind != client.KindLoadtest {
		b.g.done = true
		return
	}
	b.resetRoom()
	if b.shouldStopLoadtest() {
		b.g.done = true
		return
	}
	b.scheduleJoin(true)
}

func (b *Bot) shouldStopLoadtest() bool {
	cfg := b.svc.store.Config()
	return b.RetireMode() != RetireNone || !cfg.Bots.Enabled || b.svc.stopping.Load()
}

func (b *Bot) resetRoom() {
	g := &b.g
	g.state.Reset()
	g.roomID = ""
	g.mySeat = -1
	g.searching = false
	g.joinID = ""
	g.lobbyDeadline = time.Time{}
	g.rematchDeadline = time.Time{}
	g.pending = nil
	g.thinkAt = time.Time{}
	g.hasActed = false
	g.wantLeave = false
	g.leaveID = ""
	g.leaveDeadline = time.Time{}
	g.cancelID = ""
	g.chatPending = nil
	g.leaveAfterChat = false
	b.inGame.Store(false)
	b.svc.setGame(b, gameNone)
}

// leave sends room.leave (re-sent after a reconnect until acknowledged).
func (b *Bot) leave(conn *connection.Conn) {
	g := &b.g
	g.wantLeave = true
	g.thinkAt = time.Time{}
	if !g.ready || g.leaveID != "" {
		return
	}
	if g.roomID == "" {
		b.afterLeave()
		return
	}
	g.leaveID = b.send(conn, connection.TRoomLeave, connection.RoomRef{RoomID: g.roomID}, "leave")
	g.leaveDeadline = time.Now().Add(leaveAckTimeout)
}

// leaveOrDone leaves whatever the bot is in (cancelling load-test
// matchmaking when still searching) or finishes when it is in nothing.
func (b *Bot) leaveOrDone(conn *connection.Conn) {
	g := &b.g
	r := g.state.Room()
	switch {
	case b.kind == client.KindLoadtest && (g.searching || (r != nil && r.Status == connection.StatusLobby)):
		if g.ready && g.cancelID == "" {
			g.cancelID = b.send(conn, connection.TMatchmakingCancel, struct{}{}, "cancel")
			g.leaveDeadline = time.Now().Add(leaveAckTimeout)
		}
	case g.roomID == "" && !g.searching:
		g.done = true
	default:
		b.leave(conn)
	}
}

func (b *Bot) afterLeave() {
	g := &b.g
	g.wantLeave = false
	g.leaveID = ""
	g.leaveDeadline = time.Time{}
	g.cancelID = ""
	if b.kind != client.KindLoadtest {
		g.done = true
		return
	}
	b.resetRoom()
	if b.shouldStopLoadtest() {
		g.done = true
		return
	}
	b.scheduleJoin(false)
}

func (b *Bot) onRetire(conn *connection.Conn) {
	g := &b.g
	mode := b.RetireMode()
	r := g.state.Room()
	b.log.Info("retire requested", "mode", mode.String())
	switch mode {
	case RetireNow:
		b.leaveOrDone(conn)
	case RetireAfterGame:
		switch {
		case b.kind == client.KindLoadtest && (r == nil || r.Status != connection.StatusPlaying):
			b.leaveOrDone(conn)
		case r != nil && (r.Status == connection.StatusFinished || r.Status == connection.StatusClosed):
			b.leave(conn)
		case r == nil && g.roomID == "":
			g.done = true
		}
		// Seated assignment bots (lobby or playing) finish their game.
	}
}

func (b *Bot) onTick(conn *connection.Conn) {
	g := &b.g
	now := time.Now()
	if !g.ready && !g.readyDeadline.IsZero() && now.After(g.readyDeadline) {
		b.log.Warn("no connection.ready within connect timeout")
		conn.Abort(connection.CloseHandshakeError, "no connection.ready")
		return
	}
	if !g.thinkAt.IsZero() && !now.Before(g.thinkAt) {
		b.fireAction(conn)
	}
	if g.chatPending != nil && !now.Before(g.chatPending.at) {
		b.fireChat(conn)
	}
	if g.pending != nil && now.Sub(g.pending.sentAt) >= b.confirmTimeout() {
		b.log.Debug("action not confirmed in time; resyncing", "action", g.pending.typ)
		g.pending = nil
		b.requestSync(conn, "action_timeout")
	}
	if g.syncPending && now.Sub(g.syncSentAt) >= b.confirmTimeout() {
		g.syncFailures++
		g.syncPending = false
		if g.syncFailures >= maxSyncFailures {
			b.log.Warn("state sync not answered; reconnecting")
			g.syncFailures = 0
			conn.Abort(connection.CloseHandshakeError, "sync timeout")
			return
		}
		b.requestSync(conn, "sync_timeout")
	}
	if !g.lobbyDeadline.IsZero() && now.After(g.lobbyDeadline) {
		g.lobbyDeadline = time.Time{}
		b.log.Info("lobby did not start in time; leaving")
		if b.kind == client.KindLoadtest {
			b.leaveOrDone(conn)
		} else {
			b.leave(conn)
		}
	}
	if !g.leaveDeadline.IsZero() && now.After(g.leaveDeadline) {
		b.log.Debug("leave not acknowledged in time; continuing")
		b.afterLeave()
	}
	if !g.rematchDeadline.IsZero() && now.After(g.rematchDeadline) {
		g.rematchDeadline = time.Time{}
		if r := g.state.Room(); r != nil && r.Status == connection.StatusFinished {
			b.leave(conn)
		}
	}
	if !g.joinAt.IsZero() && !now.Before(g.joinAt) {
		b.doJoin(conn)
	}
	if at, ok := b.stallAt(); ok && !now.Before(at) && g.ready {
		g.stallSyncV = g.state.V()
		b.requestSync(conn, "stalled")
	}
}

// currentProfile resolves bots.behavior.default_profile at each decision
// point, so profile/weight changes apply to the next decision.
func (b *Bot) currentProfile() *profiles.Profile {
	snap := b.svc.store.Load()
	p, _ := snap.Profiles.Get(snap.Config.Bots.Behavior.DefaultProfile)
	return p
}

func (b *Bot) thinkOverride(cfg *config.Config) *config.RangeMS {
	if b.kind == client.KindLoadtest {
		r := cfg.Loadtest.ThinkTimeMS
		return &r
	}
	return nil
}

func (b *Bot) cancelThink() { b.g.thinkAt = time.Time{} }

// maybeAct schedules a roll or move when it is this bot's turn. The bot
// acts at most once per (turnSeq, phase) and only on server state.
func (b *Bot) maybeAct(conn *connection.Conn) {
	g := &b.g
	if g.pending != nil {
		return
	}
	if !g.ready || g.wantLeave || g.syncPending || g.done || b.RetireMode() == RetireNow {
		b.cancelThink()
		return
	}
	r := g.state.Room()
	if r == nil || r.Status != connection.StatusPlaying || g.mySeat < 0 {
		b.cancelThink()
		return
	}
	t := r.Turn
	me := r.Player(g.mySeat)
	if t.Seat != g.mySeat || me == nil || me.Forfeited {
		b.cancelThink()
		return
	}
	key := turnKey{seq: t.TurnSeq, phase: t.Phase}
	if g.hasActed && g.actedKey == key {
		return
	}
	switch t.Phase {
	case connection.PhaseAwaitingRoll:
		if t.Dice != 0 {
			return // already rolled this turn (e.g. snakes: move applied as part of the roll)
		}
	case connection.PhaseAwaitingMove:
		// With exactly one legal token the server applies the move itself
		// (game-rules.md: "If exactly one legal move exists, the server
		// applies it automatically"); only choose when there is a choice.
		if len(t.Legal) < 2 {
			return
		}
	default:
		b.cancelThink()
		return
	}
	if !g.thinkAt.IsZero() && g.thinkKey == key {
		return
	}
	cfg := b.svc.store.Config()
	rem, has := b.remaining(t.Deadline)
	d := b.strat.ThinkDelay(b.currentProfile(), cfg.Bots.ThinkTime, b.thinkOverride(cfg), rem, has)
	g.thinkKey = key
	g.thinkAt = time.Now().Add(d)
}

func (b *Bot) fireAction(conn *connection.Conn) {
	g := &b.g
	key := g.thinkKey
	g.thinkAt = time.Time{}
	r := g.state.Room()
	if r == nil || r.Status != connection.StatusPlaying || r.Turn.Seat != g.mySeat ||
		r.Turn.TurnSeq != key.seq || r.Turn.Phase != key.phase || g.pending != nil || g.syncPending || !g.ready {
		return // state moved on; maybeAct reschedules if needed
	}
	now := time.Now()
	if now.Before(g.throttleUntil) {
		g.thinkKey, g.thinkAt = key, g.throttleUntil
		return
	}
	if !b.actLim.Allow() {
		lim := float64(b.actLim.Limit())
		g.thinkKey, g.thinkAt = key, now.Add(time.Duration(float64(time.Second)/max(lim, 0.1)))
		return
	}
	cfg := b.svc.store.Config()
	if cfg.Bots.Behavior.DisconnectSimulationEnabled && b.strat.Float64() < cfg.Bots.Behavior.DisconnectProbability {
		b.log.Info("simulating a disconnect")
		g.dropNow = true
		return
	}
	if b.kind == client.KindLoadtest && cfg.Loadtest.MalformedMessageRate > 0 && b.strat.Float64() < cfg.Loadtest.MalformedMessageRate {
		b.sendMalformed(conn)
	}
	switch key.phase {
	case connection.PhaseAwaitingRoll:
		id := b.send(conn, connection.TRollDice, connection.RollDice{RoomID: r.ID, TurnSeq: key.seq}, "roll")
		g.pending = &pendingAction{typ: "roll", id: id, key: key, sentAt: time.Now()}
		b.log.Debug("roll", "turn_seq", key.seq)
	case connection.PhaseAwaitingMove:
		piece, _, ok := b.strat.ChooseLudoMove(r, g.mySeat, b.currentProfile())
		if !ok {
			return
		}
		id := b.send(conn, connection.TMakeMove, connection.MakeMove{RoomID: r.ID, TurnSeq: key.seq, Token: piece}, "move")
		g.pending = &pendingAction{typ: "move", id: id, key: key, sentAt: time.Now()}
		b.log.Debug("move", "turn_seq", key.seq, "piece", piece, "dice", r.Turn.Dice, "legal", r.Turn.Legal)
	}
	g.actedKey = key
	g.hasActed = true
}

// Load-test matchmaking.

func (b *Bot) scheduleJoin(afterError bool) {
	g := &b.g
	cfg := b.svc.store.Config()
	lo, hi := cfg.Loadtest.ThinkTimeMS.Min, cfg.Loadtest.ThinkTimeMS.Max
	d := time.Duration(lo) * time.Millisecond
	if hi > lo {
		d += time.Duration(b.strat.IntN(hi-lo+1)) * time.Millisecond
	}
	if afterError {
		d = max(d, time.Second)
	}
	if g.throttleUntil.After(time.Now().Add(d)) {
		d = time.Until(g.throttleUntil)
	}
	g.joinAt = time.Now().Add(d)
}

func (b *Bot) doJoin(conn *connection.Conn) {
	g := &b.g
	g.joinAt = time.Time{}
	if !g.ready {
		return
	}
	if b.shouldStopLoadtest() {
		g.done = true
		return
	}
	if b.session.ExpiresAt > 0 && time.Until(time.UnixMilli(b.session.ExpiresAt)) < sessionRenewAhead {
		b.log.Info("load-test session close to expiry; retiring (the controller starts a replacement)")
		g.done = true
		return
	}
	cfg := b.svc.store.Config()
	mix := matchmaking.NewMix(cfg.Loadtest.GameMix, cfg.Loadtest.CapacityMix, cfg.Bots.Games)
	choice, ok := mix.Pick(b.strat.Float64(), b.strat.Float64())
	if !ok {
		g.joinAt = time.Now().Add(5 * time.Second)
		return
	}
	if !b.svc.joinLim.Allow() {
		g.joinAt = time.Now().Add(50*time.Millisecond + client.FullJitter(200*time.Millisecond))
		return
	}
	if !b.svc.setGame(b, choice.GameKey) {
		g.joinAt = time.Now().Add(time.Second + client.FullJitter(time.Second))
		return
	}
	g.joinID = b.send(conn, connection.TMatchmakingJoin, connection.MatchmakingJoin{Game: choice.Game, Variant: choice.Variant, Capacity: choice.Capacity}, "join")
	g.joinSentAt = time.Now()
	g.searching = true
	g.lobbyDeadline = time.Now().Add(cfg.Bots.LobbyWaitTimeout())
	b.svc.m.MatchmakingJoinAttempts.Inc()
}

// sendMalformed injects one deliberately invalid message (load test only)
// to exercise server-side rejection.
func (b *Bot) sendMalformed(conn *connection.Conn) {
	kinds := []string{"invalid_json", "unknown_type", "missing_id", "bad_payload"}
	kind := kinds[b.strat.IntN(len(kinds))]
	id := b.nextID()
	if b.g.malformed == nil || len(b.g.malformed) > 256 {
		b.g.malformed = map[string]bool{}
	}
	b.g.malformed[id] = true
	var raw string
	switch kind {
	case "invalid_json":
		raw = `{"t":"game.roll_dice","id":"` + id + `","p":{`
	case "unknown_type":
		raw = `{"t":"loadtest.unknown","id":"` + id + `","p":{}}`
	case "missing_id":
		raw = `{"t":"loadtest.missing_id","p":{}}`
	case "bad_payload":
		raw = `{"t":"game.roll_dice","id":"` + id + `","p":{"roomId":12,"turnSeq":"x"}}`
	}
	if err := conn.SendRaw([]byte(raw)); err == nil {
		b.svc.m.RecordMalformed(kind)
	}
}
