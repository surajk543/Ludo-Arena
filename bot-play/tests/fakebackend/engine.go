package fakebackend

import (
	"math/rand/v2"
	"strconv"
	"strings"
	"time"
)

// Independent implementation of backend/docs/game-rules.md for the fake.

var colourTable = map[int][]string{
	2: {"red", "yellow"},
	3: {"red", "green", "yellow"},
	4: {"red", "green", "yellow", "blue"},
}
var colourIdx = map[string]int{"red": 0, "green": 1, "yellow": 2, "blue": 3}
var safeSquares = map[int]bool{0: true, 13: true, 26: true, 39: true, 8: true, 21: true, 34: true, 47: true}
var snakeMap = map[int]int{16: 6, 47: 26, 49: 11, 56: 53, 62: 19, 64: 60, 87: 24, 93: 73, 95: 75, 98: 78}
var ladderMap = map[int]int{1: 38, 4: 14, 9: 31, 21: 42, 28: 84, 36: 44, 51: 67, 71: 91, 80: 100}

type diceSource struct{ r *rand.Rand }

func newDice(seed uint64) *diceSource { return &diceSource{r: rand.New(rand.NewPCG(seed, seed*31+7))} }
func (d *diceSource) next() int       { return 1 + d.r.IntN(6) }

type player struct {
	seat      int
	uid       string
	name      string
	bot       bool
	human     bool // played by the fake
	connected bool
	forfeited bool
	left      bool // removed from the roster (left a lobby)
	gone      bool // no longer receives room events (left the room)
	strikes   int
	colour    string
	// forfeitWhy is "left" or "timeouts" once forfeited.
	forfeitWhy string
}

// maxStrikes mirrors the backend's MAX_STRIKES default: consecutive missed
// turns that forfeit a player (reason "timeouts").
const maxStrikes = 5

type room struct {
	s            *Server
	id           string
	game         string
	variant      string
	mode         string
	capacity     int
	status       string
	round        int
	v            int64
	players      []*player
	createdAt    time.Time
	fillDeadline time.Time
	pendingBots  int
	loadtest     bool

	turnSeat  int
	turnSeq   int
	phase     string
	deadline  int64
	dice      int
	legal     []int
	sixStreak int
	tokens    [][]int
	positions []int
	result    map[string]any
	rematch   map[string]any

	script    []int
	scriptIdx int
	timer     *time.Timer
	timerGen  int

	startTokens [][]int
	startPos    []int

	botRolls, botMoves, autos int
}

func (s *Server) newRoomLocked(game, variant, mode string, capacity int) *room {
	rm := &room{s: s, id: s.nextIDLocked("r_"), game: game, variant: variant, mode: mode, capacity: capacity,
		status: "lobby", round: 1, v: 1, createdAt: time.Now(), turnSeat: 0, phase: "none", legal: []int{}}
	s.rooms[rm.id] = rm
	return rm
}

func (rm *room) seat(p *player) {
	p.seat = len(rm.players)
	rm.players = append(rm.players, p)
}

func (rm *room) member(uid string) *player {
	for _, p := range rm.players {
		if p.uid == uid && !p.left && !p.gone {
			return p
		}
	}
	return nil
}

func (rm *room) counts() (humans, bots int) {
	for _, p := range rm.players {
		if p.left {
			continue
		}
		if p.bot {
			bots++
		} else {
			humans++
		}
	}
	return
}

func (rm *room) full() bool {
	h, b := rm.counts()
	return h+b >= rm.capacity
}

func (rm *room) stopTimer() {
	if rm.timer != nil {
		rm.timer.Stop()
		rm.timer = nil
	}
	rm.timerGen++
}

func (rm *room) nextDice() int {
	if len(rm.script) > 0 {
		v := rm.script[rm.scriptIdx%len(rm.script)]
		rm.scriptIdx++
		return v
	}
	return rm.s.dice.next()
}

// canonical / hash: independent of bot-play's implementation.
func (rm *room) canonical() string {
	var b strings.Builder
	if rm.game == "snakes_ladders" {
		b.WriteString("S|" + strconv.Itoa(rm.turnSeq) + "|" + strconv.Itoa(rm.turnSeat) + "|")
		for i, p := range rm.positions {
			if i > 0 {
				b.WriteByte(',')
			}
			b.WriteString(strconv.Itoa(p))
		}
		return b.String()
	}
	b.WriteString("L|" + strconv.Itoa(rm.turnSeq) + "|" + strconv.Itoa(rm.turnSeat) + "|")
	for i, seat := range rm.tokens {
		if i > 0 {
			b.WriteByte(';')
		}
		for j, t := range seat {
			if j > 0 {
				b.WriteByte(',')
			}
			b.WriteString(strconv.Itoa(t))
		}
	}
	return b.String()
}

func fnv32a(s string) uint32 {
	h := uint32(2166136261)
	for i := 0; i < len(s); i++ {
		h ^= uint32(s[i])
		h *= 16777619
	}
	return h
}

func (rm *room) hash() uint32 { return fnv32a(rm.canonical()) }

func (rm *room) snapshot() map[string]any {
	players := make([]map[string]any, 0, len(rm.players))
	for _, p := range rm.players {
		if p.left {
			continue
		}
		players = append(players, map[string]any{
			"seat": p.seat, "uid": p.uid, "name": p.name, "avatar": 1, "level": 1, "title": "title_rookie",
			"cosmetics": map[string]any{"dice": "dice_classic"}, "color": p.colour,
			"connected": p.connected, "bot": p.bot, "forfeited": p.forfeited, "strikes": p.strikes,
		})
		if p.forfeited {
			players[len(players)-1]["forfeitWhy"] = p.forfeitWhy
		}
	}
	board := map[string]any{}
	if rm.game == "snakes_ladders" {
		if rm.positions != nil {
			board["positions"] = append([]int(nil), rm.positions...)
		}
	} else if rm.tokens != nil {
		cp := make([][]int, len(rm.tokens))
		for i := range rm.tokens {
			cp[i] = append([]int(nil), rm.tokens[i]...)
		}
		board["tokens"] = cp
	}
	hostSeat := -1
	if rm.mode != "public" {
		hostSeat = 0
	}
	snap := map[string]any{
		"id": rm.id, "v": rm.v, "game": rm.game, "variant": rm.variant, "mode": rm.mode, "allowBots": rm.mode != "public",
		"capacity": rm.capacity, "status": rm.status, "hostSeat": hostSeat, "entryFee": 0, "pot": 0, "round": rm.round,
		"fillDeadline": rm.fillDeadline.UnixMilli(), "players": players,
		"turn": map[string]any{"seat": rm.turnSeat, "phase": rm.phase, "turnSeq": rm.turnSeq, "deadline": rm.deadline,
			"dice": rm.dice, "legal": append([]int{}, rm.legal...), "sixStreak": rm.sixStreak},
		"board": board,
	}
	if rm.result != nil {
		snap["result"] = rm.result
		snap["rematch"] = rm.rematch
	}
	if rm.status == "playing" || rm.status == "finished" {
		snap["h"] = rm.hash()
	}
	return snap
}

func (rm *room) info() RoomInfo {
	ri := RoomInfo{ID: rm.id, Status: rm.status, Game: rm.game, Mode: rm.mode, V: rm.v, Winner: -1,
		Finished: rm.status == "finished", Moves: rm.botMoves, Rolls: rm.botRolls, Autos: rm.autos}
	if rm.result != nil {
		ri.Winner, _ = rm.result["winnerSeat"].(int)
	}
	for _, p := range rm.players {
		if p.left {
			continue
		}
		ri.Players = append(ri.Players, PlayerInfo{Seat: p.seat, UID: p.uid, Name: p.name, Bot: p.bot, Connected: p.connected, Forfeited: p.forfeited})
	}
	return ri
}

// --- events -----------------------------------------------------------------

// emitLocked bumps v, attaches roomId/v (and h) and delivers to members.
// reply maps uid -> client message id for the actor's copy.
func (s *Server) emitLocked(rm *room, t string, p map[string]any, withHash bool, replyUID, replyID string) {
	rm.v++
	p["roomId"] = rm.id
	p["v"] = rm.v
	if withHash {
		p["h"] = rm.hash()
	}
	for _, pl := range rm.players {
		if pl.left || pl.gone || pl.human {
			continue
		}
		env := Envelope{T: t, P: clonePayload(p)}
		if pl.uid == replyUID {
			env.R = replyID
		}
		s.deliverLocked(pl.uid, env)
	}
}

func clonePayload(p map[string]any) map[string]any {
	out := make(map[string]any, len(p))
	for k, v := range p {
		out[k] = v
	}
	return out
}

func (s *Server) broadcastSnapshotLocked(rm *room, t, reason string) {
	for _, pl := range rm.players {
		if pl.left || pl.gone || pl.human {
			continue
		}
		p := map[string]any{"room": rm.snapshot()}
		if reason != "" {
			p["reason"] = reason
		}
		s.deliverLocked(pl.uid, Envelope{T: t, P: p})
	}
}

func (s *Server) emitRoomUpdatedLocked(rm *room, reason string) {
	rm.v++
	s.broadcastSnapshotLocked(rm, "room.updated", reason)
	s.maybeStartLocked(rm)
}

func (s *Server) deliverLocked(uid string, env Envelope) {
	c := s.conns[uid]
	if c == nil {
		return
	}
	envs := []Envelope{env}
	if s.hook != nil {
		envs = s.hook(uid, env)
	}
	for _, e := range envs {
		c.send(e)
	}
}

func (s *Server) maybeStartLocked(rm *room) {
	if rm.status != "lobby" {
		return
	}
	// Like the backend: a room starts as soon as it is full (bots may still
	// be connecting; they receive the state on connect).
	humans, bots := rm.counts()
	if humans+bots == rm.capacity {
		s.startLocked(rm)
	}
}

func (s *Server) startLocked(rm *room) {
	rm.stopTimer()
	var active []*player
	for _, p := range rm.players {
		if !p.left {
			active = append(active, p)
		}
	}
	rm.players = active
	n := len(active)
	cols := colourTable[n]
	for i, p := range active {
		p.seat = i
		if i < len(cols) {
			p.colour = cols[i]
		}
	}
	rm.status = "playing"
	if rm.game == "snakes_ladders" {
		rm.positions = make([]int, n)
		copy(rm.positions, rm.startPos)
	} else {
		rm.tokens = make([][]int, n)
		for i := range rm.tokens {
			rm.tokens[i] = []int{-1, -1, -1, -1}
			if i < len(rm.startTokens) {
				copy(rm.tokens[i], rm.startTokens[i])
			}
		}
	}
	rm.turnSeat, rm.turnSeq, rm.phase, rm.dice, rm.legal, rm.sixStreak = 0, 1, "awaiting_roll", 0, []int{}, 0
	rm.deadline = time.Now().Add(s.opts.TurnTimeout).UnixMilli()
	rm.v++
	s.broadcastSnapshotLocked(rm, "game.started", "")
	s.scheduleTurnLocked(rm)
}

func (s *Server) scheduleTurnLocked(rm *room) {
	rm.stopTimer()
	if rm.status != "playing" {
		return
	}
	p := rm.players[rm.turnSeat]
	delay := s.opts.TurnTimeout
	if p.human {
		delay = s.opts.HumanDelay
	}
	gen := rm.timerGen
	rm.timer = time.AfterFunc(delay, func() {
		s.mu.Lock()
		defer s.mu.Unlock()
		if s.closed.Load() || gen != rm.timerGen || rm.status != "playing" {
			return
		}
		s.autoActLocked(rm, p)
	})
}

func (s *Server) autoActLocked(rm *room, p *player) {
	auto := !p.human
	if auto {
		rm.autos++
		p.strikes++
		if p.strikes >= maxStrikes {
			s.forfeitLocked(rm, p.seat, "timeouts")
			return
		}
	}
	switch rm.phase {
	case "awaiting_roll":
		s.rollLocked(rm, p.seat, auto, "", "")
	case "awaiting_move":
		best := rm.legal[0]
		for _, t := range rm.legal {
			if rm.tokens[p.seat][t] > rm.tokens[p.seat][best] {
				best = t
			}
		}
		s.moveLocked(rm, p.seat, best, auto, "", "")
	}
}

func (rm *room) resetDeadline() {
	rm.deadline = time.Now().Add(rm.s.opts.TurnTimeout).UnixMilli()
}

func ludoLegal(tokens []int, dice int) []int {
	out := []int{}
	seen := map[int]bool{}
	for i, p := range tokens {
		if seen[p] {
			continue // identical progress -> only the lowest index is listed
		}
		ok := false
		switch {
		case p == -1:
			ok = dice == 6
		case p >= 0 && p < 56:
			ok = p+dice <= 56
		}
		if ok {
			seen[p] = true
			out = append(out, i)
		}
	}
	return out
}

func (s *Server) rollLocked(rm *room, seat int, auto bool, uid, reqID string) {
	value := rm.nextDice()
	p := rm.players[seat]
	if !auto && !p.human {
		p.strikes = 0
		rm.botRolls++
	}
	rm.dice = value
	base := func(phase string, legal []int, voided bool) map[string]any {
		m := map[string]any{"seat": seat, "value": value, "turnSeq": rm.turnSeq, "phase": phase, "deadline": rm.deadline,
			"legal": legal, "sixStreak": rm.sixStreak, "strikes": p.strikes}
		if voided {
			m["voided"] = true
		}
		if auto {
			m["auto"] = true
		}
		return m
	}
	if rm.game == "snakes_ladders" {
		// Phase stays awaiting_roll; the move is applied as part of the roll.
		s.emitLocked(rm, "game.dice_result", base("awaiting_roll", []int{}, false), true, uid, reqID)
		from := rm.positions[seat]
		to := from + value
		if to > 100 {
			s.passTurnLocked(rm)
			return
		}
		mv := map[string]any{"seat": seat, "token": 0, "from": from, "to": to, "captures": []any{}}
		if t, ok := snakeMap[to]; ok {
			mv["landing"], mv["transition"], mv["to"] = to, map[string]any{"kind": "snake", "from": to, "to": t}, t
			to = t
		} else if t, ok := ladderMap[to]; ok {
			mv["landing"], mv["transition"], mv["to"] = to, map[string]any{"kind": "ladder", "from": to, "to": t}, t
			to = t
		}
		rm.positions[seat] = to
		s.emitLocked(rm, "game.move_applied", mv, true, "", "")
		if to == 100 {
			s.finishLocked(rm, seat, "completed")
			return
		}
		s.passTurnLocked(rm)
		return
	}
	if value == 6 {
		rm.sixStreak++
	}
	// Voided third six / no legal move: phase and turnSeq unchanged (hash of
	// the state before the roll), then the turn passes.
	if value == 6 && rm.sixStreak >= 3 {
		s.emitLocked(rm, "game.dice_result", base("awaiting_roll", []int{}, true), true, uid, reqID)
		s.passTurnLocked(rm)
		return
	}
	legal := ludoLegal(rm.tokens[seat], value)
	switch len(legal) {
	case 0:
		s.emitLocked(rm, "game.dice_result", base("awaiting_roll", []int{}, false), true, uid, reqID)
		s.passTurnLocked(rm)
	case 1:
		// Announced as awaiting_move with the single token, then applied by
		// the server itself.
		rm.phase, rm.legal = "awaiting_move", legal
		rm.turnSeq++
		s.emitLocked(rm, "game.dice_result", base("awaiting_move", legal, false), true, uid, reqID)
		s.moveLocked(rm, seat, legal[0], false, "", "")
	default:
		rm.phase, rm.legal = "awaiting_move", legal
		rm.turnSeq++
		rm.resetDeadline()
		s.emitLocked(rm, "game.dice_result", base("awaiting_move", legal, false), true, uid, reqID)
		s.scheduleTurnLocked(rm)
	}
}

func (s *Server) moveLocked(rm *room, seat, token int, auto bool, uid, reqID string) {
	p := rm.players[seat]
	if uid != "" && !auto {
		p.strikes = 0
		rm.botMoves++
	}
	from := rm.tokens[seat][token]
	to := from + rm.dice
	if from == -1 {
		to = 0
	}
	rm.tokens[seat][token] = to
	captures := []any{}
	if to >= 0 && to <= 50 {
		abs := (13*colourIdx[p.colour] + to) % 52
		if !safeSquares[abs] {
			for _, o := range rm.players {
				if o.seat == seat || o.forfeited {
					continue
				}
				for t, op := range rm.tokens[o.seat] {
					if op >= 0 && op <= 50 && (13*colourIdx[o.colour]+op)%52 == abs {
						rm.tokens[o.seat][t] = -1
						captures = append(captures, map[string]any{"seat": o.seat, "token": t})
					}
				}
			}
		}
	}
	rm.legal = []int{}
	mv := map[string]any{"seat": seat, "token": token, "from": from, "to": to, "captures": captures}
	if to == 56 {
		mv["home"] = true
	}
	if auto {
		mv["auto"] = true
	}
	s.emitLocked(rm, "game.move_applied", mv, true, uid, reqID)
	done := true
	for _, t := range rm.tokens[seat] {
		if t != 56 {
			done = false
		}
	}
	if done {
		s.finishLocked(rm, seat, "completed")
		return
	}
	if rm.dice == 6 || len(captures) > 0 || to == 56 {
		rm.turnSeq++
		rm.phase, rm.dice = "awaiting_roll", 0
		rm.resetDeadline()
		s.emitLocked(rm, "game.turn_changed", map[string]any{"seat": seat, "turnSeq": rm.turnSeq, "phase": rm.phase,
			"deadline": rm.deadline, "sixStreak": rm.sixStreak}, true, "", "")
		s.scheduleTurnLocked(rm)
		return
	}
	s.passTurnLocked(rm)
}

func (s *Server) passTurnLocked(rm *room) {
	n := len(rm.players)
	next := rm.turnSeat
	for i := 0; i < n; i++ {
		next = (next + 1) % n
		if !rm.players[next].forfeited {
			break
		}
	}
	rm.turnSeat = next
	rm.turnSeq++
	rm.phase, rm.dice, rm.legal, rm.sixStreak = "awaiting_roll", 0, []int{}, 0
	rm.resetDeadline()
	s.emitLocked(rm, "game.turn_changed", map[string]any{"seat": next, "turnSeq": rm.turnSeq, "phase": rm.phase,
		"deadline": rm.deadline, "sixStreak": 0}, true, "", "")
	s.scheduleTurnLocked(rm)
}

func (s *Server) finishLocked(rm *room, winner int, reason string) {
	rm.stopTimer()
	rm.status = "finished"
	rm.phase = "finished"
	placements := []int{winner}
	for _, p := range rm.players {
		if p.seat != winner {
			placements = append(placements, p.seat)
		}
	}
	rm.result = map[string]any{"winnerSeat": winner, "reason": reason, "placements": placements, "payout": 0}
	rm.rematch = map[string]any{"open": true, "deadline": time.Now().Add(30 * time.Second).UnixMilli(), "accepted": []int{}, "declined": []int{}}
	s.emitLocked(rm, "game.finished", map[string]any{"result": rm.result, "rematch": rm.rematch}, false, "", "")
}

func (s *Server) forfeitLocked(rm *room, seat int, reason string) {
	p := rm.players[seat]
	if p.forfeited {
		return
	}
	p.forfeited = true
	if rm.tokens != nil {
		for i := range rm.tokens[seat] {
			rm.tokens[seat][i] = -1
		}
	}
	p.forfeitWhy = reason
	s.emitLocked(rm, "player.forfeited", map[string]any{"seat": seat, "reason": reason, "strikes": p.strikes}, true, "", "")
	var remaining []*player
	for _, o := range rm.players {
		if !o.forfeited {
			remaining = append(remaining, o)
		}
	}
	if len(remaining) == 1 {
		s.finishLocked(rm, remaining[0].seat, "forfeit")
		return
	}
	if rm.turnSeat == seat && rm.status == "playing" {
		s.passTurnLocked(rm)
	}
}

// leaveLocked implements room.leave semantics.
func (s *Server) leaveLocked(rm *room, uid string) {
	p := rm.member(uid)
	if p == nil {
		return
	}
	if sess := s.byUID[uid]; sess != nil {
		sess.roomID = ""
	}
	p.gone = true
	switch rm.status {
	case "lobby":
		p.left = true
		var keep []*player
		for _, o := range rm.players {
			if !o.left {
				o.seat = len(keep)
				keep = append(keep, o)
			}
		}
		rm.players = append(keep, p) // keep the leaver (marked left) for history
		s.emitRoomUpdatedLocked(rm, "left")
	case "playing":
		s.forfeitLocked(rm, p.seat, "left")
	}
}

// --- load-test matchmaking ----------------------------------------------------

func (s *Server) joinMatchmakingLocked(sess *session, game, variant string, capacity int, reqID string) {
	var rm *room
	for _, r := range s.rooms {
		if r.loadtest && r.status == "lobby" && r.game == game && r.variant == variant && r.capacity == capacity {
			if h, b := r.counts(); h+b < capacity {
				rm = r
				break
			}
		}
	}
	if rm == nil {
		rm = s.newRoomLocked(game, variant, "public", capacity)
		rm.loadtest = true
		rm.fillDeadline = time.Now().Add(s.opts.LobbyFillDeadline)
		gen := rm.timerGen
		lobby := rm
		rm.timer = time.AfterFunc(s.opts.LobbyFillDeadline, func() {
			s.mu.Lock()
			defer s.mu.Unlock()
			if s.closed.Load() || gen != lobby.timerGen || lobby.status != "lobby" {
				return
			}
			h, b := lobby.counts()
			if h+b >= 2 {
				s.startLocked(lobby)
				return
			}
			lobby.status = "closed"
			for _, p := range lobby.players {
				if p.left {
					continue
				}
				if ss := s.byUID[p.uid]; ss != nil {
					ss.roomID = ""
				}
				s.deliverLocked(p.uid, Envelope{T: "matchmaking.status", P: map[string]any{"status": "timeout",
					"game": lobby.game, "variant": lobby.variant, "capacity": lobby.capacity, "roomId": lobby.id}})
			}
		})
	}
	rm.seat(&player{uid: sess.uid, name: sess.name, bot: true, connected: true})
	sess.roomID = rm.id
	s.deliverLocked(sess.uid, Envelope{T: "matchmaking.status", R: reqID, P: map[string]any{"status": "searching",
		"game": game, "variant": variant, "capacity": capacity, "roomId": rm.id}})
	s.emitRoomUpdatedLocked(rm, "joined")
}
