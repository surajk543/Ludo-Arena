package websocket

import (
	"context"
	"encoding/json"
	"errors"
	"sync"
	"sync/atomic"
	"time"

	ws "github.com/coder/websocket"

	"ludoarena/internal/apppolicy"
	"ludoarena/internal/auth"
	"ludoarena/internal/metrics"
	"ludoarena/internal/protocol"
	"ludoarena/internal/rooms"
)

type conn struct {
	g           *Gateway
	id          string
	userID      string
	principal   auth.Principal
	client      apppolicy.Client
	ws          *ws.Conn
	counter     *wireCounter
	out         chan []byte
	wake        chan struct{}
	resync      atomic.Bool // queued deltas were dropped: send a fresh snapshot
	walletMsg   atomic.Bool // a wallet.updated was queued since the last write
	walletLost  atomic.Bool // a wallet.updated was dropped on overflow
	epoch       int64
	actor       string
	compression string
	locale      string
	rate        *bucket
	ctx         context.Context
	cancel      context.CancelFunc
	closeOnce   sync.Once

	mu        sync.Mutex
	overflows []time.Time
	invalid   []time.Time
	limited   []time.Time
}

// enqueue queues a pre-encoded message without blocking. When the queue is
// full, the queued messages are discarded and replaced by one authoritative
// snapshot (plus a wallet refresh if a wallet update was lost). Repeated
// overflow closes the connection (4508); the client reconnects and resyncs.
func (c *conn) enqueue(msg []byte) {
	metrics.WSQueueDepth.Observe(float64(len(c.out)))
	select {
	case c.out <- msg:
		return
	default:
	}
	metrics.WSSlowClients.WithLabelValues("overflow").Inc()
	dropped := 0
	for {
		select {
		case <-c.out:
			dropped++
			continue
		default:
		}
		break
	}
	if c.walletMsg.Swap(false) {
		c.walletLost.Store(true)
	}
	c.resync.Store(true)
	select {
	case c.wake <- struct{}{}:
	default:
	}
	c.mu.Lock()
	now := time.Now()
	c.overflows = recent(append(c.overflows, now), now, time.Minute)
	n := len(c.overflows)
	c.mu.Unlock()
	if n >= 3 {
		metrics.WSSlowClients.WithLabelValues("disconnect").Inc()
		c.close(CloseSlowConsumer, "slow consumer")
	}
}

func recent(ts []time.Time, now time.Time, window time.Duration) []time.Time {
	i := 0
	for i < len(ts) && now.Sub(ts[i]) > window {
		i++
	}
	return ts[i:]
}

// close sends the close frame (with code) before tearing down the context,
// so clients receive the documented close code.
func (c *conn) close(code ws.StatusCode, reason string) {
	c.closeOnce.Do(func() {
		go func() {
			_ = c.ws.Close(code, reason)
			if c.cancel != nil {
				c.cancel()
			}
		}()
	})
}

// writeLoop is the single writer for this connection.
func (c *conn) writeLoop() {
	for {
		select {
		case <-c.ctx.Done():
			return
		case msg := <-c.out:
			if !c.write(msg) {
				return
			}
		case <-c.wake:
		}
		if c.resync.Swap(false) {
			if !c.writeResync() {
				return
			}
		}
	}
}

func (c *conn) write(msg []byte) bool {
	ctx, cancel := context.WithTimeout(c.ctx, c.g.cfg.WriteTimeout)
	start := time.Now()
	err := c.ws.Write(ctx, ws.MessageText, msg)
	cancel()
	if err != nil {
		if errors.Is(err, context.DeadlineExceeded) {
			metrics.WSSlowClients.WithLabelValues("write_timeout").Inc()
			c.close(CloseSlowConsumer, "write timeout")
		} else {
			c.close(ws.StatusGoingAway, "write failed")
		}
		return false
	}
	metrics.WSWriteSeconds.Observe(time.Since(start).Seconds())
	metrics.WSPayloadBytesSent.Add(float64(len(msg)))
	metrics.WSMsgsSent.WithLabelValues(msgType(msg)).Inc()
	return true
}

// msgType extracts "t" cheaply for metrics (envelopes start with {"t":"...").
func msgType(msg []byte) string {
	const prefix = `{"t":"`
	if len(msg) > len(prefix) && string(msg[:len(prefix)]) == prefix {
		for i := len(prefix); i < len(msg) && i < 40; i++ {
			if msg[i] == '"' {
				return string(msg[len(prefix):i])
			}
		}
	}
	return "other"
}

func (c *conn) writeResync() bool {
	ctx, cancel := context.WithTimeout(c.ctx, 5*time.Second)
	defer cancel()
	if roomID := c.g.rooms.ActiveRoom(ctx, c.userID); roomID != "" {
		if v, err := c.g.rooms.Snapshot(ctx, c.userID, roomID); err == nil {
			metrics.WSResyncs.WithLabelValues("overflow").Inc()
			if !c.write(protocol.Encode(protocol.TGameState, "", map[string]any{"room": v})) {
				return false
			}
		}
	}
	if c.walletLost.Swap(false) && !c.principal.IsBot() {
		if w, err := c.g.rooms.Wallets.Get(ctx, c.principal.UserID); err == nil {
			return c.write(protocol.Encode(protocol.TWalletUpdated, "", map[string]any{
				"coins": w.Coins, "diamonds": w.Diamonds, "delta": map[string]int64{"coins": 0, "diamonds": 0}, "reason": "resync"}))
		}
	}
	return true
}

// heartbeat pings the client, re-checks the session and the app policy.
func (c *conn) heartbeat() {
	ping := time.NewTicker(c.g.cfg.PingInterval)
	sess := time.NewTicker(sessionCheckPeriod)
	pol := time.NewTicker(policyCheckPeriod)
	defer ping.Stop()
	defer sess.Stop()
	defer pol.Stop()
	for {
		select {
		case <-c.ctx.Done():
			return
		case <-ping.C:
			ctx, cancel := context.WithTimeout(c.ctx, c.g.cfg.PongTimeout)
			err := c.ws.Ping(ctx)
			cancel()
			if err != nil {
				c.close(ws.StatusGoingAway, "ping timeout")
				return
			}
			c.g.rdb.Expire(c.ctx, "presence:"+c.userID, presenceTTL)
		case <-sess.C:
			switch err := c.g.auth.CheckSession(c.ctx, c.principal.SessionID); {
			case errors.Is(err, auth.ErrSessionReplaced):
				c.close(CloseUnauthorized, "session replaced")
				return
			case errors.Is(err, auth.ErrRevoked):
				c.close(CloseUnauthorized, "session revoked")
				return
			}
		case <-pol.C:
			if code, msg := c.policyBlock(); code != 0 {
				c.enqueue(protocol.Encode(protocol.TError, "", msg))
				time.Sleep(100 * time.Millisecond)
				c.close(code, msg.Code)
				return
			}
		}
	}
}

// policyBlock evaluates the current app policy for this connection.
func (c *conn) policyBlock() (ws.StatusCode, *protocol.Error) {
	if c.principal.IsBot() {
		if c.g.policy.GlobalMaintenanceActive() {
			return CloseMaintenance, protocol.ErrMaintenance
		}
		return 0, nil
	}
	d := c.g.policy.Evaluate(c.client, c.locale)
	switch d.Mode {
	case apppolicy.ModeMaintenance:
		return CloseMaintenance, protocol.ErrMaintenance
	case apppolicy.ModeForceUpdate:
		return CloseUpdate, protocol.ErrUpdateRequired
	}
	return 0, nil
}

// readLoop processes client messages sequentially (per-connection ordering).
func (c *conn) readLoop() {
	caller := rooms.CallerFrom(c.principal, c.epoch)
	for {
		typ, data, err := c.ws.Read(c.ctx)
		if err != nil {
			if ws.CloseStatus(err) == -1 && !errors.Is(err, context.Canceled) {
				// Oversized frames, protocol errors and dead TCP connections.
				var ce ws.CloseError
				if !errors.As(err, &ce) {
					metrics.WSMsgsRejected.WithLabelValues("read_error").Inc()
				}
			}
			c.close(ws.StatusGoingAway, "read failed")
			return
		}
		metrics.WSPayloadBytesReceived.Add(float64(len(data)))
		if typ != ws.MessageText {
			metrics.WSMsgsRejected.WithLabelValues("binary").Inc()
			c.close(ws.StatusUnsupportedData, "text frames only")
			return
		}
		var in protocol.Inbound
		if err := json.Unmarshal(data, &in); err != nil || in.T == "" {
			c.reject("malformed", "", protocol.ErrBadRequest)
			continue
		}
		if in.T == protocol.TPing {
			c.enqueue(protocol.Encode(protocol.TPong, in.ID, map[string]any{"ts": time.Now().UnixMilli()}))
			continue
		}
		label := in.T
		if !protocol.KnownClientTypes[in.T] {
			c.reject("unknown_type", in.ID, protocol.ErrUnknownType)
			continue
		}
		if len(in.ID) < 1 || len(in.ID) > 64 {
			c.reject("bad_id", "", protocol.ErrBadRequest)
			continue
		}
		if !c.rate.allow() {
			metrics.WSMsgsRejected.WithLabelValues("rate_limited").Inc()
			c.enqueue(protocol.Encode(protocol.TError, in.ID, protocol.ErrRateLimited))
			c.mu.Lock()
			now := time.Now()
			c.limited = recent(append(c.limited, now), now, time.Minute)
			n := len(c.limited)
			c.mu.Unlock()
			if n > 50 {
				c.close(CloseRateLimited, "rate limit abuse")
				return
			}
			continue
		}
		if code, perr := c.policyBlock(); code != 0 {
			c.enqueue(protocol.Encode(protocol.TError, in.ID, perr))
			time.Sleep(100 * time.Millisecond)
			c.close(code, perr.Code)
			return
		}
		metrics.WSMsgsReceived.WithLabelValues(label).Inc()
		// De-duplicate retried commands (same id within 2 minutes).
		first, err := c.g.rdb.SetNX(c.ctx, "dedup:"+c.userID+":"+in.ID, 1, 2*time.Minute).Result()
		if err == nil && !first {
			c.enqueue(protocol.Encode(protocol.TAck, in.ID, map[string]any{"dup": true}))
			continue
		}
		start := time.Now()
		ctx, cancel := context.WithTimeout(c.ctx, 5*time.Second)
		replies := c.g.rooms.Dispatch(ctx, caller, in)
		cancel()
		metrics.WSProcessSeconds.WithLabelValues(label).Observe(time.Since(start).Seconds())
		for _, r := range replies {
			c.enqueue(r)
		}
	}
}

func (c *conn) reject(reason, id string, perr *protocol.Error) {
	metrics.WSMsgsRejected.WithLabelValues(reason).Inc()
	c.enqueue(protocol.Encode(protocol.TError, id, perr))
	c.mu.Lock()
	now := time.Now()
	c.invalid = recent(append(c.invalid, now), now, time.Minute)
	n := len(c.invalid)
	c.mu.Unlock()
	if n > 20 {
		c.close(CloseProtocol, "too many invalid messages")
	}
}

// bucket is a small token bucket (per connection; no locking needed beyond
// the reader goroutine, which is its only user).
type bucket struct {
	rate   float64
	burst  float64
	tokens float64
	last   time.Time
}

func newBucket(rate float64, burst int) *bucket {
	return &bucket{rate: rate, burst: float64(burst), tokens: float64(burst), last: time.Now()}
}

func (b *bucket) allow() bool {
	now := time.Now()
	b.tokens = min(b.burst, b.tokens+now.Sub(b.last).Seconds()*b.rate)
	b.last = now
	if b.tokens < 1 {
		return false
	}
	b.tokens--
	return true
}
