package tests

import (
	"context"
	cryptorand "crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"hash/fnv"
	"net/http"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/coder/websocket"
)

// msg is a decoded server envelope.
type msg struct {
	T string          `json:"t"`
	R string          `json:"r"`
	P json.RawMessage `json:"p"`
}

// roomState is the client-side reconstruction of a room (mirrors the Flutter
// reducer contract in docs/websocket-protocol.md §3 and §6).
type roomState struct {
	ID       string `json:"id"`
	V        int64  `json:"v"`
	Game     string `json:"game"`
	Variant  string `json:"variant"`
	Mode     string `json:"mode"`
	Code     string `json:"code"`
	Status   string `json:"status"`
	Round    int    `json:"round"`
	EntryFee int64  `json:"entryFee"`
	Pot      int64  `json:"pot"`
	Players  []struct {
		Seat    int    `json:"seat"`
		UID     string `json:"uid"`
		Name    string `json:"name"`
		Avatar  int    `json:"avatar"`
		Level   int    `json:"level"`
		Picture *struct {
			ID string `json:"id"`
		} `json:"picture"`
		Title      string            `json:"title"`
		Cosmetics  map[string]string `json:"cosmetics"`
		Connected  bool              `json:"connected"`
		Forfeited  bool              `json:"forfeited"`
		ForfeitWhy string            `json:"forfeitWhy"`
		Strikes    int               `json:"strikes"`
	} `json:"players"`
	HostSeat      int   `json:"hostSeat"`
	PendingBots   int   `json:"pendingBots"`
	ComputerSeats []int `json:"computerSeats"`
	Turn          struct {
		Seat      int    `json:"seat"`
		Phase     string `json:"phase"`
		TurnSeq   int    `json:"turnSeq"`
		Deadline  int64  `json:"deadline"`
		Dice      int    `json:"dice"`
		Legal     []int  `json:"legal"`
		SixStreak int    `json:"sixStreak"`
	} `json:"turn"`
	Board struct {
		Tokens    [][]int `json:"tokens"`
		Positions []int   `json:"positions"`
	} `json:"board"`
	Result *struct {
		WinnerSeat int   `json:"winnerSeat"`
		Payout     int64 `json:"payout"`
	} `json:"result"`
	Rematch *struct {
		Open     bool  `json:"open"`
		Accepted []int `json:"accepted"`
	} `json:"rematch"`
	H uint32 `json:"h"`
}

func (r *roomState) canonical() string {
	var b strings.Builder
	if r.Game == "ludo" {
		fmt.Fprintf(&b, "L|%d|%d|", r.Turn.TurnSeq, r.Turn.Seat)
		for i, seat := range r.Board.Tokens {
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
	} else {
		fmt.Fprintf(&b, "S|%d|%d|", r.Turn.TurnSeq, r.Turn.Seat)
		for i, p := range r.Board.Positions {
			if i > 0 {
				b.WriteByte(',')
			}
			b.WriteString(strconv.Itoa(p))
		}
	}
	return b.String()
}

func (r *roomState) hash() uint32 {
	h := fnv.New32a()
	h.Write([]byte(r.canonical()))
	return h.Sum32()
}

// client is a test WebSocket client.
type client struct {
	t      *testing.T
	name   string
	acct   account
	conn   *websocket.Conn
	ctx    context.Context
	stop   context.CancelFunc
	nextID atomic.Int64
	// idPrefix is random per connection (see send).
	idPrefix string

	mu        sync.Mutex
	room      *roomState
	all       []msg
	errors    []string
	replies   map[string]msg
	ready     map[string]any
	gaps      int
	hashMiss  int
	syncs     int
	closeCode websocket.StatusCode
	// closeReason is the server's close reason (e.g. "account deleted").
	closeReason string
	closed      chan struct{}
	notify      chan struct{}
}

func (e *env) dial(name string, acct account, headers map[string]string) (*client, *http.Response, error) {
	h := http.Header{}
	h.Set("Authorization", "Bearer "+acct.Token)
	h.Set("X-App-Platform", "android")
	h.Set("X-App-Version", appVersion)
	h.Set("X-App-Build", "1")
	for k, v := range headers {
		if v == "" {
			h.Del(k)
		} else {
			h.Set(k, v)
		}
	}
	ctx, cancel := context.WithCancel(context.Background())
	url := "ws" + strings.TrimPrefix(e.srv.URL, "http") + "/api/v1/ws"
	conn, res, err := websocket.Dial(ctx, url, &websocket.DialOptions{
		HTTPHeader: h, Subprotocols: []string{"ludo-arena.v1"},
		CompressionMode: websocket.CompressionNoContextTakeover,
	})
	if err != nil {
		cancel()
		return nil, res, err
	}
	conn.SetReadLimit(1 << 20)
	c := &client{t: e.t, name: name, acct: acct, conn: conn, ctx: ctx, stop: cancel, idPrefix: randomHex(4),
		replies: map[string]msg{}, closed: make(chan struct{}), notify: make(chan struct{}, 1)}
	go c.readLoop()
	e.t.Cleanup(c.close)
	waitFor(e.t, 5*time.Second, name+" connection.ready", func() bool {
		c.mu.Lock()
		defer c.mu.Unlock()
		return c.ready != nil
	})
	return c, res, nil
}

func (e *env) mustDial(name string, acct account) *client {
	e.t.Helper()
	c, _, err := e.dial(name, acct, nil)
	if err != nil {
		e.t.Fatalf("dial %s: %v", name, err)
	}
	return c
}

func (c *client) close() {
	c.stop()
	_ = c.conn.Close(websocket.StatusNormalClosure, "")
}

func (c *client) readLoop() {
	defer close(c.closed)
	for {
		_, data, err := c.conn.Read(c.ctx)
		if err != nil {
			c.mu.Lock()
			c.closeCode = websocket.CloseStatus(err)
			var ce websocket.CloseError
			if errors.As(err, &ce) {
				c.closeReason = ce.Reason
			}
			c.mu.Unlock()
			return
		}
		var m msg
		if err := json.Unmarshal(data, &m); err != nil || m.T == "" {
			// Every server frame must be a protocol envelope with a type
			// (regression: an internal control message once leaked here).
			c.t.Errorf("%s: invalid server frame %s", c.name, data)
			continue
		}
		// Bots are indistinguishable from people: no frame says which
		// seats are bots.
		var generic any
		if json.Unmarshal(data, &generic) == nil && hasJSONKey(generic, "bot") {
			c.t.Errorf("%s: frame marks a bot: %s", c.name, data)
		}
		c.mu.Lock()
		c.apply(m)
		c.mu.Unlock()
		select {
		case c.notify <- struct{}{}:
		default:
		}
	}
}

// apply implements the reconciliation rules (called with mu held).
func (c *client) apply(m msg) {
	c.all = append(c.all, m)
	if m.R != "" {
		c.replies[m.R] = m
	}
	switch m.T {
	case "connection.ready":
		_ = json.Unmarshal(m.P, &c.ready)
		return
	case "error":
		var e struct{ Code string }
		_ = json.Unmarshal(m.P, &e)
		c.errors = append(c.errors, e.Code)
		return
	case "room.updated", "game.started", "game.state":
		var p struct {
			Room *roomState `json:"room"`
		}
		if err := json.Unmarshal(m.P, &p); err != nil {
			c.t.Errorf("%s: snapshot decode: %v", c.name, err)
			return
		}
		if p.Room == nil {
			return
		}
		if c.room == nil || c.room.ID != p.Room.ID || p.Room.V >= c.room.V {
			c.room = p.Room
			if c.room.Status != "lobby" && c.room.Board.Tokens != nil || c.room.Board.Positions != nil {
				if c.room.hash() != c.room.H {
					c.t.Errorf("%s: snapshot hash mismatch %s", c.name, c.room.canonical())
				}
			}
		}
		return
	}
	var hdr struct {
		RoomID string `json:"roomId"`
		V      int64  `json:"v"`
		H      uint32 `json:"h"`
	}
	_ = json.Unmarshal(m.P, &hdr)
	if hdr.V == 0 || c.room == nil || hdr.RoomID != c.room.ID {
		return
	}
	if hdr.V <= c.room.V {
		return // duplicate / old
	}
	if hdr.V > c.room.V+1 {
		c.gaps++
		c.requestSyncLocked()
		return
	}
	r := c.room
	r.V = hdr.V
	switch m.T {
	case "game.dice_result":
		var p struct {
			Seat, Value, TurnSeq, SixStreak, Strikes int
			Phase                                    string
			Deadline                                 int64
			Legal                                    []int
		}
		_ = json.Unmarshal(m.P, &p)
		r.Turn.Dice, r.Turn.TurnSeq, r.Turn.Phase, r.Turn.Deadline = p.Value, p.TurnSeq, p.Phase, p.Deadline
		r.Turn.Legal, r.Turn.SixStreak = p.Legal, p.SixStreak
		if p.Seat < len(r.Players) {
			r.Players[p.Seat].Strikes = p.Strikes
		}
	case "game.move_applied":
		var p struct {
			Seat, Token, To int
			Captures        []struct{ Seat, Token int }
		}
		_ = json.Unmarshal(m.P, &p)
		if r.Game == "ludo" {
			r.Board.Tokens[p.Seat][p.Token] = p.To
			for _, cp := range p.Captures {
				r.Board.Tokens[cp.Seat][cp.Token] = -1
			}
		} else {
			r.Board.Positions[p.Seat] = p.To
		}
		r.Turn.Legal = nil
	case "game.turn_changed":
		var p struct {
			Seat, TurnSeq, SixStreak int
			Phase                    string
			Deadline                 int64
		}
		_ = json.Unmarshal(m.P, &p)
		r.Turn.Seat, r.Turn.TurnSeq, r.Turn.Phase, r.Turn.Deadline, r.Turn.SixStreak = p.Seat, p.TurnSeq, p.Phase, p.Deadline, p.SixStreak
		r.Turn.Dice, r.Turn.Legal = 0, nil
	case "player.connected", "player.disconnected":
		var p struct{ Seat int }
		_ = json.Unmarshal(m.P, &p)
		r.Players[p.Seat].Connected = m.T == "player.connected"
	case "player.forfeited":
		var p struct {
			Seat, Strikes int
			Reason        string
		}
		_ = json.Unmarshal(m.P, &p)
		r.Players[p.Seat].Forfeited = true
		r.Players[p.Seat].ForfeitWhy, r.Players[p.Seat].Strikes = p.Reason, p.Strikes
		if r.Game == "ludo" {
			for i := range r.Board.Tokens[p.Seat] {
				r.Board.Tokens[p.Seat][i] = -1
			}
		}
	case "game.finished":
		var p struct {
			Result *struct {
				WinnerSeat int   `json:"winnerSeat"`
				Payout     int64 `json:"payout"`
			} `json:"result"`
		}
		_ = json.Unmarshal(m.P, &p)
		r.Status, r.Result, r.Turn.Phase = "finished", p.Result, "finished"
		return
	case "room.rematch":
		return
	}
	if hdr.H != 0 && r.hash() != hdr.H {
		c.hashMiss++
		c.t.Errorf("%s: hash mismatch after %s v=%d local=%s", c.name, m.T, hdr.V, r.canonical())
		c.requestSyncLocked()
	}
}

func (c *client) requestSyncLocked() {
	c.syncs++
	go c.send("game.request_sync", map[string]any{"roomId": c.room.ID})
}

// hasJSONKey reports whether decoded JSON v contains key at any depth.
func hasJSONKey(v any, key string) bool {
	switch x := v.(type) {
	case map[string]any:
		for k, e := range x {
			if k == key || hasJSONKey(e, key) {
				return true
			}
		}
	case []any:
		for _, e := range x {
			if hasJSONKey(e, key) {
				return true
			}
		}
	}
	return false
}

func randomHex(n int) string {
	b := make([]byte, n)
	_, _ = cryptorand.Read(b)
	return hex.EncodeToString(b)
}

// send writes a command and returns its id. The random per-connection
// prefix keeps ids unique per user across connections, as the server
// requires (a bot persona's user id outlives its session).
func (c *client) send(t string, payload any) string {
	id := fmt.Sprintf("%s-%s-%d", c.name, c.idPrefix, c.nextID.Add(1))
	raw, _ := json.Marshal(map[string]any{"t": t, "id": id, "p": payload})
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	_ = c.conn.Write(ctx, websocket.MessageText, raw)
	return id
}

// call sends a command and waits for its reply.
func (c *client) call(t string, payload any) msg {
	c.t.Helper()
	id := c.send(t, payload)
	var out msg
	waitFor(c.t, 5*time.Second, c.name+" reply to "+t, func() bool {
		c.mu.Lock()
		defer c.mu.Unlock()
		m, ok := c.replies[id]
		out = m
		return ok
	})
	return out
}

// snapshot returns a deep copy (the reader goroutine mutates c.room in place).
func (c *client) snapshot() *roomState {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.room == nil {
		return nil
	}
	raw, _ := json.Marshal(c.room)
	var cp roomState
	_ = json.Unmarshal(raw, &cp)
	return &cp
}

func (c *client) seat() int {
	r := c.snapshot()
	if r == nil {
		return -1
	}
	return seatIn(r, c.acct.UID)
}

func seatIn(r *roomState, uid string) int {
	for _, p := range r.Players {
		if p.UID == uid {
			return p.Seat
		}
	}
	return -1
}

func (c *client) count(t string) int {
	c.mu.Lock()
	defer c.mu.Unlock()
	n := 0
	for _, m := range c.all {
		if m.T == t {
			n++
		}
	}
	return n
}

func (c *client) hasError(code string) bool {
	c.mu.Lock()
	defer c.mu.Unlock()
	for _, e := range c.errors {
		if e == code {
			return true
		}
	}
	return false
}

// playUntilFinished acts whenever it is this client's turn.
func (c *client) playUntilFinished(timeout time.Duration) {
	c.t.Helper()
	deadline := time.After(timeout)
	acted := ""
	for {
		r := c.snapshot()
		if r != nil && r.Status == "finished" {
			return
		}
		mySeat := -1
		if r != nil {
			mySeat = seatIn(r, c.acct.UID)
		}
		if r != nil && r.Status == "playing" && mySeat >= 0 && r.Turn.Seat == mySeat {
			key := fmt.Sprintf("%d/%s", r.Turn.TurnSeq, r.Turn.Phase)
			if key != acted {
				acted = key
				switch r.Turn.Phase {
				case "awaiting_roll":
					c.send("game.roll_dice", map[string]any{"roomId": r.ID, "turnSeq": r.Turn.TurnSeq})
				case "awaiting_move":
					if len(r.Turn.Legal) > 0 {
						c.send("game.make_move", map[string]any{"roomId": r.ID, "turnSeq": r.Turn.TurnSeq, "token": r.Turn.Legal[len(r.Turn.Legal)-1]})
					}
				}
			}
		}
		select {
		case <-deadline:
			c.t.Fatalf("%s: game did not finish (state %+v)", c.name, r)
		case <-c.closed:
			return
		case <-c.notify:
		case <-time.After(200 * time.Millisecond):
		}
	}
}
