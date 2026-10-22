package connection

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/coder/websocket"

	"ludoarena/botplay/internal/config"
)

// ErrQueueFull is returned when the bounded outbound queue is full.
var ErrQueueFull = errors.New("connection: outbound queue full")

// ErrClosed is returned when sending on a closed connection.
var ErrClosed = errors.New("connection: closed")

// DialOptions configures one WebSocket connection.
type DialOptions struct {
	URL            string
	Token          config.Secret // bot session access token
	Version, Build string        // X-App-Version / X-App-Build (bot-play's own)
	Reconnect      bool          // adds X-Reconnect: 1
	ConnectTimeout time.Duration
	QueueSize      int
	PingInterval   time.Duration
	PongTimeout    time.Duration
	ReadLimit      int64
	WriteTimeout   time.Duration
	SlowReadDelay  time.Duration // load-test slow-reader simulation (0 = off)
	Compression    string        // no_context_takeover (default) | context_takeover | disabled
	OnBytes        func(n int)   // payload bytes received after decompression
	HTTPClient     *http.Client
}

// Handshake describes what the upgrade negotiated.
type Handshake struct {
	Compression bool   // permessage-deflate negotiated
	Extensions  string // raw Sec-WebSocket-Extensions response header
}

// DialError is a rejected upgrade (no WebSocket was created) or a network
// failure before the upgrade.
type DialError struct {
	Status     int // HTTP status; 0 for network errors
	Code       string
	Message    string
	RetryAfter time.Duration
	Err        error
}

func (e *DialError) Error() string {
	if e.Status == 0 {
		return "connection: dial: " + e.Err.Error()
	}
	return fmt.Sprintf("connection: upgrade rejected: %d %s %s", e.Status, e.Code, e.Message)
}

func (e *DialError) Unwrap() error { return e.Err }

// CloseInfo describes why a connection ended.
type CloseInfo struct {
	Code   int // WebSocket close code, or a negative local code (see Close* constants)
	Reason string
	Local  bool // closed by this process
}

// Conn is one bot WebSocket connection with a reader goroutine, a writer
// goroutine (which also sends heartbeats) and a bounded outbound queue.
type Conn struct {
	ws    *websocket.Conn
	opts  DialOptions
	out   chan []byte
	in    chan Inbound
	done  chan struct{}
	ctx   context.Context
	stop  context.CancelFunc
	once  sync.Once
	info  CloseInfo
	pong  atomic.Int64 // unix nanos of last pong
	wg    sync.WaitGroup
	slowR atomic.Int64 // slow read delay (nanos)
}

// Dial upgrades a connection with the bot headers and permessage-deflate
// (no context takeover) offered.
func Dial(ctx context.Context, o DialOptions) (*Conn, Handshake, error) {
	if o.QueueSize <= 0 {
		o.QueueSize = 64
	}
	if o.PingInterval <= 0 {
		o.PingInterval = 15 * time.Second
	}
	if o.PongTimeout <= 0 {
		o.PongTimeout = 10 * time.Second
	}
	if o.WriteTimeout <= 0 {
		o.WriteTimeout = 10 * time.Second
	}
	if o.ReadLimit <= 0 {
		o.ReadLimit = 1 << 20
	}
	h := http.Header{}
	h.Set("Authorization", "Bearer "+o.Token.Reveal())
	h.Set("X-App-Platform", "bot")
	h.Set("X-App-Version", o.Version)
	h.Set("X-App-Build", o.Build)
	if o.Reconnect {
		h.Set("X-Reconnect", "1")
	}
	dctx := ctx
	if o.ConnectTimeout > 0 {
		var cancel context.CancelFunc
		dctx, cancel = context.WithTimeout(ctx, o.ConnectTimeout)
		defer cancel()
	}
	ws, resp, err := websocket.Dial(dctx, o.URL, &websocket.DialOptions{
		HTTPClient:      o.HTTPClient,
		HTTPHeader:      h,
		Subprotocols:    []string{Subprotocol},
		CompressionMode: compressionMode(o.Compression),
	})
	if err != nil {
		return nil, Handshake{}, dialError(resp, err)
	}
	if ws.Subprotocol() != Subprotocol {
		ws.Close(websocket.StatusProtocolError, "subprotocol not negotiated")
		return nil, Handshake{}, &DialError{Status: 0, Err: fmt.Errorf("server did not select subprotocol %s", Subprotocol)}
	}
	ws.SetReadLimit(o.ReadLimit)
	hs := Handshake{}
	if resp != nil {
		hs.Extensions = resp.Header.Get("Sec-WebSocket-Extensions")
		hs.Compression = strings.Contains(strings.ToLower(hs.Extensions), "permessage-deflate")
	}
	cctx, cancel := context.WithCancel(context.Background())
	c := &Conn{
		ws: ws, opts: o, ctx: cctx, stop: cancel,
		out:  make(chan []byte, o.QueueSize),
		in:   make(chan Inbound, 32),
		done: make(chan struct{}),
	}
	c.slowR.Store(int64(o.SlowReadDelay))
	c.pong.Store(time.Now().UnixNano())
	c.wg.Add(2)
	go c.readLoop()
	go c.writeLoop()
	return c, hs, nil
}

func dialError(resp *http.Response, err error) error {
	de := &DialError{Err: err}
	if resp == nil || resp.StatusCode == http.StatusSwitchingProtocols {
		return de
	}
	de.Status = resp.StatusCode
	if ra := resp.Header.Get("Retry-After"); ra != "" {
		if s, e := strconv.Atoi(ra); e == nil && s >= 0 {
			de.RetryAfter = time.Duration(s) * time.Second
		}
	}
	if resp.Body != nil {
		b, _ := io.ReadAll(io.LimitReader(resp.Body, 1024))
		var eb struct {
			Error struct {
				Code    string `json:"code"`
				Message string `json:"message"`
			} `json:"error"`
		}
		if json.Unmarshal(b, &eb) == nil {
			de.Code, de.Message = eb.Error.Code, eb.Error.Message
		}
	}
	return de
}

// Recv returns the inbound message channel. It is never closed; select on
// Done as well.
func (c *Conn) Recv() <-chan Inbound { return c.in }

// Done is closed when the connection has ended.
func (c *Conn) Done() <-chan struct{} { return c.done }

// Info returns why the connection ended (valid after Done is closed).
func (c *Conn) Info() CloseInfo {
	<-c.done
	return c.info
}

// Send marshals and enqueues a message without blocking.
func (c *Conn) Send(m Outbound) error {
	b, err := json.Marshal(m)
	if err != nil {
		return err
	}
	return c.SendRaw(b)
}

// SendRaw enqueues raw bytes without blocking (used for malformed-message
// injection in load tests).
func (c *Conn) SendRaw(b []byte) error {
	select {
	case <-c.done:
		return ErrClosed
	default:
	}
	select {
	case c.out <- b:
		return nil
	default:
		c.finish(CloseInfo{Code: CloseQueueOverflow, Reason: "outbound queue full", Local: true}, true)
		return ErrQueueFull
	}
}

// Close performs a graceful close handshake with the given code.
func (c *Conn) Close(code int, reason string) {
	c.finishWith(CloseInfo{Code: CloseLocal, Reason: reason, Local: true}, func() {
		_ = c.ws.Close(websocket.StatusCode(code), reason)
	})
	c.wg.Wait()
}

// Abort drops the connection without a close handshake (network failure
// simulation, protocol timeouts and hard shutdown). code is a local Close*
// code recorded in Info.
func (c *Conn) Abort(code int, reason string) {
	c.finish(CloseInfo{Code: code, Reason: reason, Local: true}, true)
	c.wg.Wait()
}

// SetSlowRead changes the slow-reader delay.
func (c *Conn) SetSlowRead(d time.Duration) { c.slowR.Store(int64(d)) }

func (c *Conn) finish(info CloseInfo, closeNow bool) {
	c.finishWith(info, func() {
		if closeNow {
			_ = c.ws.CloseNow()
		}
	})
}

func (c *Conn) finishWith(info CloseInfo, closer func()) {
	c.once.Do(func() {
		c.info = info
		close(c.done)
		closer()
		c.stop()
	})
}

func (c *Conn) readLoop() {
	defer c.wg.Done()
	for {
		_, data, err := c.ws.Read(c.ctx)
		if err != nil {
			// No close frame (EOF, reset, timeout) is reported as 1006.
			info := CloseInfo{Code: CloseAbnormal, Reason: err.Error()}
			var ce websocket.CloseError
			if errors.As(err, &ce) {
				info = CloseInfo{Code: int(ce.Code), Reason: ce.Reason}
			}
			c.finish(info, true)
			return
		}
		if c.opts.OnBytes != nil {
			c.opts.OnBytes(len(data))
		}
		if d := time.Duration(c.slowR.Load()); d > 0 {
			t := time.NewTimer(d)
			select {
			case <-t.C:
			case <-c.done:
				t.Stop()
				return
			}
		}
		var msg Inbound
		if err := json.Unmarshal(data, &msg); err != nil || msg.T == "" {
			continue // ignore undecodable frames; unknown types are handled by the bot
		}
		msg.Size = len(data)
		msg.At = time.Now()
		if msg.T == TPong {
			c.pong.Store(time.Now().UnixNano())
			continue
		}
		select {
		case c.in <- msg:
		case <-c.done:
			return
		}
	}
}

func (c *Conn) writeLoop() {
	defer c.wg.Done()
	ping := time.NewTicker(c.opts.PingInterval)
	defer ping.Stop()
	var pongTimer *time.Timer
	var pongC <-chan time.Time
	var pingSent int64
	defer func() {
		if pongTimer != nil {
			pongTimer.Stop()
		}
	}()
	pingMsg := []byte(`{"t":"ping"}`)
	for {
		select {
		case <-c.done:
			return
		case b := <-c.out:
			if err := c.write(b); err != nil {
				c.finish(CloseInfo{Code: CloseWriteError, Reason: err.Error()}, true)
				return
			}
		case <-ping.C:
			if err := c.write(pingMsg); err != nil {
				c.finish(CloseInfo{Code: CloseWriteError, Reason: err.Error()}, true)
				return
			}
			if pongC == nil {
				pingSent = time.Now().UnixNano()
				pongTimer = time.NewTimer(c.opts.PongTimeout)
				pongC = pongTimer.C
			}
		case <-pongC:
			pongC = nil
			if c.pong.Load() < pingSent {
				c.finish(CloseInfo{Code: ClosePongTimeout, Reason: "no pong within timeout", Local: true}, true)
				return
			}
		}
	}
}

func (c *Conn) write(b []byte) error {
	ctx, cancel := context.WithTimeout(c.ctx, c.opts.WriteTimeout)
	defer cancel()
	return c.ws.Write(ctx, websocket.MessageText, b)
}

// compressionMode maps the configured offer to the library mode.
func compressionMode(mode string) websocket.CompressionMode {
	switch mode {
	case "context_takeover":
		return websocket.CompressionContextTakeover
	case "disabled":
		return websocket.CompressionDisabled
	}
	return websocket.CompressionNoContextTakeover
}
