// Package websocket is the realtime gateway: authenticated WebSocket
// connections with negotiated permessage-deflate, bounded per-connection
// outbound queues with snapshot coalescing, heartbeats, rate limits, and
// Redis pub/sub fan-out of room and user events across instances.
package websocket

import (
	"bufio"
	"bytes"
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"log/slog"
	"net"
	"net/http"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	ws "github.com/coder/websocket"
	"github.com/google/uuid"
	"github.com/redis/go-redis/v9"

	"ludoroyale/internal/apppolicy"
	"ludoroyale/internal/auth"
	"ludoroyale/internal/config"
	"ludoroyale/internal/httpapi"
	"ludoroyale/internal/metrics"
	"ludoroyale/internal/notify"
	"ludoroyale/internal/protocol"
	"ludoroyale/internal/ratelimit"
	"ludoroyale/internal/rooms"
)

// Custom close codes (docs/websocket-protocol.md §1).
const (
	CloseProtocol      ws.StatusCode = 4400
	CloseUnauthorized  ws.StatusCode = 4401
	CloseReplaced      ws.StatusCode = 4409
	CloseUpdate        ws.StatusCode = 4426
	CloseRateLimited   ws.StatusCode = 4429
	CloseMaintenance   ws.StatusCode = 4503
	CloseSlowConsumer  ws.StatusCode = 4508
	presenceTTL                      = 60 * time.Second
	sessionCheckPeriod               = 60 * time.Second
	policyCheckPeriod                = 10 * time.Second
)

// Gateway accepts and manages WebSocket connections.
type Gateway struct {
	cfg      config.WSConfig
	log      *slog.Logger
	auth     *auth.Service
	policy   *apppolicy.Store
	limiter  *ratelimit.Limiter
	rooms    *rooms.Service
	rdb      *redis.Client
	proxyHop int

	// OnHumanConnect is called once per accepted human connection (analytics).
	OnHumanConnect func(ctx context.Context, userID uuid.UUID)

	mu    sync.RWMutex
	conns map[string]*conn // userID -> live connection on this instance
	count atomic.Int64
	ctx   context.Context
}

// New returns a Gateway; call Run to start pub/sub fan-out.
func New(cfg config.WSConfig, log *slog.Logger, a *auth.Service, p *apppolicy.Store,
	l *ratelimit.Limiter, r *rooms.Service, rdb *redis.Client, proxyHops int) *Gateway {
	return &Gateway{cfg: cfg, log: log, auth: a, policy: p, limiter: l, rooms: r, rdb: rdb,
		proxyHop: proxyHops, conns: map[string]*conn{}, ctx: context.Background()}
}

func newConnID() string {
	b := make([]byte, 8)
	_, _ = rand.Read(b)
	return hex.EncodeToString(b)
}

func (g *Gateway) compressionMode() ws.CompressionMode {
	switch g.cfg.CompressionMode {
	case "context_takeover":
		return ws.CompressionContextTakeover
	case "no_context_takeover":
		return ws.CompressionNoContextTakeover
	}
	return ws.CompressionDisabled
}

func rejectJSON(w http.ResponseWriter, status int, code, msg string, details any) {
	body := map[string]any{"code": code, "message": msg}
	if details != nil {
		body["details"] = details
	}
	httpapi.WriteJSON(w, status, map[string]any{"error": body})
}

// ServeHTTP upgrades GET /api/v1/ws.
func (g *Gateway) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	tok, ok := strings.CutPrefix(r.Header.Get("Authorization"), "Bearer ")
	if !ok {
		metrics.WSConnects.WithLabelValues("unauthorized").Inc()
		rejectJSON(w, http.StatusUnauthorized, "unauthorized", "Authentication required.", nil)
		return
	}
	p, err := g.auth.Authenticate(ctx, strings.TrimSpace(tok))
	if err != nil || (p.Kind != auth.KindAccess && p.Kind != auth.KindBot) {
		metrics.WSConnects.WithLabelValues("unauthorized").Inc()
		rejectJSON(w, http.StatusUnauthorized, "unauthorized", "Authentication required.", nil)
		return
	}

	var client apppolicy.Client
	if p.IsBot() {
		if r.Header.Get("X-App-Platform") != "bot" {
			rejectJSON(w, http.StatusBadRequest, "client_version_required", "Bots must send X-App-Platform: bot.", nil)
			return
		}
		if g.policy.GlobalMaintenanceActive() {
			metrics.WSConnects.WithLabelValues("maintenance").Inc()
			rejectJSON(w, http.StatusServiceUnavailable, "maintenance", "Maintenance in progress.", nil)
			return
		}
	} else {
		client, err = apppolicy.ParseClient(r.Header.Get("X-App-Platform"), r.Header.Get("X-App-Version"), r.Header.Get("X-App-Build"))
		if err != nil {
			rejectJSON(w, http.StatusBadRequest, "client_version_required", "X-App-Platform, X-App-Version and X-App-Build are required.", nil)
			return
		}
		if apiErr := httpapi.PolicyError(g.policy.Evaluate(client, httpapi.Locale(r)), "ws_connect"); apiErr != nil {
			metrics.WSConnects.WithLabelValues(apiErr.Code).Inc()
			rejectJSON(w, apiErr.Status, apiErr.Code, apiErr.Message, apiErr.Details)
			return
		}
	}
	if !offersSubprotocol(r) {
		rejectJSON(w, http.StatusBadRequest, "bad_request", "Sec-WebSocket-Protocol "+protocol.Subprotocol+" is required.", nil)
		return
	}
	if ok, retry := g.limiter.Allow(ctx, ratelimit.WSConnectPerUser, p.UserID.String()); !ok {
		metrics.WSConnects.WithLabelValues("rate_limited").Inc()
		w.Header().Set("Retry-After", retry.String())
		rejectJSON(w, http.StatusTooManyRequests, "rate_limited", "Too many connection attempts.", nil)
		return
	}
	if g.count.Load() >= int64(g.cfg.MaxConnections) {
		metrics.WSConnects.WithLabelValues("overloaded").Inc()
		rejectJSON(w, http.StatusServiceUnavailable, "overloaded", "Server is at capacity. Please retry.", nil)
		return
	}

	counter := &wireCounter{}
	c, err := ws.Accept(&hijackCounter{ResponseWriter: w, counter: counter}, r, &ws.AcceptOptions{
		Subprotocols:         []string{protocol.Subprotocol},
		CompressionMode:      g.compressionMode(),
		CompressionThreshold: g.cfg.CompressionThreshold,
		// Mobile apps send no Origin header; browsers are not a supported client.
		InsecureSkipVerify: true,
	})
	if err != nil {
		metrics.WSConnects.WithLabelValues("accept_error").Inc()
		return
	}
	negotiated := w.Header().Get("Sec-WebSocket-Extensions")
	mode := "none"
	if strings.Contains(negotiated, "permessage-deflate") {
		mode = "no_context_takeover"
		if !strings.Contains(negotiated, "server_no_context_takeover") {
			mode = "context_takeover"
		}
	}
	metrics.WSCompression.WithLabelValues(mode).Inc()
	metrics.WSConnects.WithLabelValues("ok").Inc()
	c.SetReadLimit(g.cfg.ReadLimit)

	actor := "human"
	if p.IsBot() {
		actor = "bot"
	}
	if r.Header.Get("X-Reconnect") == "1" {
		metrics.WSReconnects.WithLabelValues(actor).Inc()
	}
	cn := &conn{
		g: g, id: newConnID(), userID: p.UserID.String(), principal: p, client: client, ws: c,
		counter: counter, out: make(chan []byte, g.cfg.OutboundQueue), wake: make(chan struct{}, 1),
		epoch: time.Now().UnixNano(), actor: actor, compression: negotiated, locale: httpapi.Locale(r),
		rate: newBucket(g.cfg.MsgRatePerSec, g.cfg.MsgBurst),
	}
	g.serve(cn)
}

func offersSubprotocol(r *http.Request) bool {
	for _, h := range r.Header.Values("Sec-WebSocket-Protocol") {
		for _, p := range strings.Split(h, ",") {
			if strings.TrimSpace(p) == protocol.Subprotocol {
				return true
			}
		}
	}
	return false
}

// serve runs the connection until it closes.
func (g *Gateway) serve(c *conn) {
	ctx, cancel := context.WithCancel(g.ctx)
	c.ctx, c.cancel = ctx, cancel
	defer cancel()

	g.register(c)
	metrics.WSConnections.WithLabelValues(c.actor).Inc()
	g.count.Add(1)
	defer func() {
		g.unregister(c)
		g.count.Add(-1)
		metrics.WSConnections.WithLabelValues(c.actor).Dec()
		bg, cancelBG := context.WithTimeout(context.Background(), 5*time.Second)
		g.rooms.Presence(bg, c.userID, false, c.epoch)
		cancelBG()
	}()

	go c.writeLoop()
	go c.heartbeat()

	uid := c.userID
	if !c.principal.IsBot() {
		uid = g.rooms.Profiles.PublicID(c.principal.UserID)
	}
	compression := c.compression
	if compression == "" {
		compression = "none"
	}
	activeRoom := g.rooms.ActiveRoom(ctx, c.userID)
	c.enqueue(protocol.Encode(protocol.TReady, "", map[string]any{
		"uid": uid, "protocol": protocol.Version, "serverTime": time.Now().UnixMilli(),
		"activeRoomId": activeRoom, "compression": compression,
		"heartbeatSec": int(g.cfg.PingInterval.Seconds()),
	}))
	g.rooms.Presence(ctx, c.userID, true, c.epoch)
	if !c.principal.IsBot() && g.OnHumanConnect != nil {
		g.OnHumanConnect(ctx, c.principal.UserID)
	}
	if activeRoom != "" {
		if v, err := g.rooms.Snapshot(ctx, c.userID, activeRoom); err == nil {
			metrics.WSResyncs.WithLabelValues("connect").Inc()
			c.enqueue(protocol.Encode(protocol.TGameState, "", map[string]any{"room": v}))
		}
	}
	c.readLoop()
}

func (g *Gateway) register(c *conn) {
	g.mu.Lock()
	old := g.conns[c.userID]
	g.conns[c.userID] = c
	g.mu.Unlock()
	if old != nil {
		old.close(CloseReplaced, "session replaced by a newer connection")
	}
	ctx := context.Background()
	// Kick connections of this user on other instances. A struct (not a map)
	// keeps "ctl" as the first key, which route() relies on to tell control
	// messages apart from client envelopes.
	ctl, _ := json.Marshal(controlMsg{Ctl: "kick", Conn: c.id})
	g.rdb.Publish(ctx, notify.UserChannel(c.userID), ctl)
	g.rdb.Set(ctx, "presence:"+c.userID, c.id, presenceTTL)
}

// controlMsg is an instance-to-instance message on a user channel; it is
// never forwarded to clients.
type controlMsg struct {
	Ctl  string `json:"ctl"`
	Conn string `json:"conn"`
}

func (g *Gateway) unregister(c *conn) {
	g.mu.Lock()
	if g.conns[c.userID] == c {
		delete(g.conns, c.userID)
	}
	g.mu.Unlock()
	ctx := context.Background()
	if cur, _ := g.rdb.Get(ctx, "presence:"+c.userID).Result(); cur == c.id {
		g.rdb.Del(ctx, "presence:"+c.userID)
	}
}

func (g *Gateway) local(userID string) *conn {
	g.mu.RLock()
	defer g.mu.RUnlock()
	return g.conns[userID]
}

// Run consumes room and user events from Redis and fans them out to local
// connections. It blocks until ctx is cancelled, then closes every connection
// with 1001 (going away) so clients reconnect elsewhere.
func (g *Gateway) Run(ctx context.Context) {
	g.ctx = ctx
	ps := g.rdb.PSubscribe(ctx, "ev:room:*", "ev:user:*")
	defer ps.Close()
	ch := ps.Channel(redis.WithChannelSize(8192))
	for {
		select {
		case <-ctx.Done():
			g.closeAll()
			return
		case msg, ok := <-ch:
			if !ok {
				return
			}
			g.route(msg)
		}
	}
}

func (g *Gateway) route(msg *redis.Message) {
	switch {
	case strings.HasPrefix(msg.Channel, "ev:room:"):
		var b rooms.Batch
		if err := json.Unmarshal([]byte(msg.Payload), &b); err != nil {
			return
		}
		n := 0
		for _, uid := range b.To {
			if c := g.local(uid); c != nil {
				n++
				for _, m := range b.Msgs {
					c.enqueue(m)
				}
			}
		}
		metrics.WSBroadcastFanout.Observe(float64(n))
	case strings.HasPrefix(msg.Channel, "ev:user:"):
		uid := strings.TrimPrefix(msg.Channel, "ev:user:")
		c := g.local(uid)
		if c == nil {
			return
		}
		payload := []byte(msg.Payload)
		if !bytes.HasPrefix(payload, []byte(`{"t":`)) {
			// Not a client envelope: an instance control message.
			var ctl controlMsg
			if json.Unmarshal(payload, &ctl) == nil && ctl.Ctl == "kick" && ctl.Conn != c.id {
				c.close(CloseReplaced, "session replaced by a newer connection")
			}
			return
		}
		if bytes.Contains(payload[:min(len(payload), 40)], []byte(`"wallet.updated"`)) {
			c.walletMsg.Store(true)
		}
		c.enqueue(payload)
	}
}

func (g *Gateway) closeAll() {
	g.mu.RLock()
	all := make([]*conn, 0, len(g.conns))
	for _, c := range g.conns {
		all = append(all, c)
	}
	g.mu.RUnlock()
	for _, c := range all {
		c.close(ws.StatusGoingAway, "server shutting down")
	}
}

// ---- wire byte counting ----

type wireCounter struct{ read, written atomic.Int64 }

type countingConn struct {
	net.Conn
	c *wireCounter
}

func (cc *countingConn) Read(p []byte) (int, error) {
	n, err := cc.Conn.Read(p)
	if n > 0 {
		metrics.WSWireBytesReceived.Add(float64(n))
	}
	return n, err
}

func (cc *countingConn) Write(p []byte) (int, error) {
	n, err := cc.Conn.Write(p)
	if n > 0 {
		metrics.WSWireBytesSent.Add(float64(n))
	}
	return n, err
}

// hijackCounter wraps the hijacked connection so the bytes actually written
// to and read from the socket (WebSocket frames incl. headers, after
// compression) are measured.
type hijackCounter struct {
	http.ResponseWriter
	counter *wireCounter
}

func (h *hijackCounter) Hijack() (net.Conn, *bufio.ReadWriter, error) {
	hj, ok := h.ResponseWriter.(http.Hijacker)
	if !ok {
		return nil, nil, errors.New("hijack not supported")
	}
	nc, brw, err := hj.Hijack()
	if err != nil {
		return nil, nil, err
	}
	wrapped := &countingConn{Conn: nc, c: h.counter}
	// Preserve any bytes already buffered by the HTTP server.
	buffered, _ := brw.Reader.Peek(brw.Reader.Buffered())
	pre := append([]byte(nil), buffered...)
	reader := bufio.NewReaderSize(&prefixReader{prefix: pre, r: wrapped}, 4096)
	if len(pre) > 0 {
		// Pull the leftover bytes into the buffer so the WebSocket library,
		// which keeps only already-buffered bytes, does not drop them.
		_, _ = reader.Peek(len(pre))
	}
	return wrapped, bufio.NewReadWriter(reader, bufio.NewWriterSize(wrapped, 4096)), nil
}

type prefixReader struct {
	prefix []byte
	r      net.Conn
}

func (p *prefixReader) Read(b []byte) (int, error) {
	if len(p.prefix) > 0 {
		n := copy(b, p.prefix)
		p.prefix = p.prefix[n:]
		return n, nil
	}
	return p.r.Read(b)
}
