// Package client is the REST client for the backend's bot service endpoints
// (docs/rest-api.md → "Bot service"). It never calls wallet, progression,
// collection, social or account endpoints.
package client

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"ludoroyale/botplay/internal/config"
)

// Assignment kinds.
const (
	KindPractice   = "practice"
	KindPrivate    = "private"
	KindPublicFill = "public_fill"
	KindLoadtest   = "loadtest" // local only: load-test bots have no assignment
)

// Assignment is a bot seat the backend wants filled.
type Assignment struct {
	ID        string `json:"id"`
	RoomID    string `json:"roomId"`
	Game      string `json:"game"`
	Variant   string `json:"variant"`
	Kind      string `json:"kind"`
	ExpiresAt int64  `json:"expiresAt"` // unix ms
}

// Lobby is an open public lobby as reported by GET /bot/lobbies.
type Lobby struct {
	RoomID      string `json:"roomId"`
	Game        string `json:"game"`
	Variant     string `json:"variant"`
	Capacity    int    `json:"capacity"`
	Humans      int    `json:"humans"`
	Bots        int    `json:"bots"`
	PendingBots int    `json:"pendingBots"`
	WaitingMS   int64  `json:"waitingMs"`
}

// SessionRequest is the POST /bot/sessions body. It intentionally has no
// "bot" flag: the backend derives bot status from the session itself.
type SessionRequest struct {
	AssignmentID string `json:"assignmentId,omitempty"`
	Mode         string `json:"mode,omitempty"` // "loadtest" for load-test sessions
	Name         string `json:"name"`
	Profile      string `json:"profile,omitempty"`
}

// Session is a bot session (access token scoped to one assignment or to the
// load-test pool, <= 2 h). UID is the bot's public id, in the same format as
// a person's ("u_" + 12 characters).
type Session struct {
	AccessToken config.Secret `json:"-"`
	ExpiresAt   int64         `json:"expiresAt"`
	UID         string        `json:"uid"`
	RoomID      string        `json:"roomId"`
	// Emotes are the emote ids this bot may send with chat.emote (empty when
	// the backend sent none: the bot then sends no emotes).
	Emotes []string `json:"emotes"`
}

// APIError is a non-2xx backend response.
type APIError struct {
	Status     int
	Code       string
	Message    string
	RetryAfter time.Duration
}

func (e *APIError) Error() string {
	return fmt.Sprintf("backend %d %s: %s", e.Status, e.Code, e.Message)
}

// Retryable reports whether the same request may succeed later.
func (e *APIError) Retryable() bool {
	return e.Status == http.StatusTooManyRequests || e.Status == http.StatusServiceUnavailable || e.Status >= 500
}

// IsMaintenance reports whether err is the backend's maintenance response.
func IsMaintenance(err error) bool {
	var ae *APIError
	return errors.As(err, &ae) && (ae.Status == http.StatusServiceUnavailable && (ae.Code == "maintenance" || ae.Code == ""))
}

// IsStatus reports whether err is an APIError with the given HTTP status.
func IsStatus(err error, status int) bool {
	var ae *APIError
	return errors.As(err, &ae) && ae.Status == status
}

// RetryAfter returns the server-requested delay, if any.
func RetryAfter(err error) time.Duration {
	var ae *APIError
	if errors.As(err, &ae) {
		return ae.RetryAfter
	}
	return 0
}

// Options configures a Client.
type Options struct {
	BaseURL        string        // e.g. http://localhost:8080/api/v1
	ServiceKey     config.Secret // BOT_SERVICE_KEY
	RequestTimeout time.Duration
	UserAgent      string
	HTTPClient     *http.Client // optional
	OnToken        func(ok bool)
}

// Client talks to the bot service endpoints with a cached controller token.
type Client struct {
	base    string
	key     config.Secret
	timeout time.Duration
	ua      string
	hc      *http.Client
	onToken func(ok bool)

	refreshMu sync.Mutex // serializes token fetches
	mu        sync.Mutex // guards the cached token fields
	token     config.Secret
	expiresAt time.Time
	issuedAt  time.Time

	lastOK atomic.Int64 // unix nanos of last successful backend response
}

// New creates a client.
func New(o Options) (*Client, error) {
	u, err := url.Parse(o.BaseURL)
	if err != nil || u.Host == "" {
		return nil, fmt.Errorf("client: invalid base URL %q", o.BaseURL)
	}
	hc := o.HTTPClient
	if hc == nil {
		hc = &http.Client{Transport: http.DefaultTransport.(*http.Transport).Clone()}
	}
	if o.RequestTimeout <= 0 {
		o.RequestTimeout = 5 * time.Second
	}
	return &Client{
		base: strings.TrimRight(o.BaseURL, "/"), key: o.ServiceKey, timeout: o.RequestTimeout,
		ua: o.UserAgent, hc: hc, onToken: o.OnToken,
	}, nil
}

// LastSuccess returns when the backend last answered successfully.
func (c *Client) LastSuccess() time.Time {
	n := c.lastOK.Load()
	if n == 0 {
		return time.Time{}
	}
	return time.Unix(0, n)
}

// TokenValid reports whether a non-expired controller token is cached.
func (c *Client) TokenValid() bool {
	c.mu.Lock()
	defer c.mu.Unlock()
	return !c.token.Empty() && time.Now().Before(c.expiresAt)
}

// InvalidateToken drops the cached controller token.
func (c *Client) InvalidateToken() {
	c.mu.Lock()
	c.token = config.Secret{}
	c.mu.Unlock()
}

// ControllerToken returns a valid controller JWT, fetching a new one with
// the service key when the cached one is missing or close to expiry
// (refresh at 80% of its lifetime, and always >= 30 s before expiry).
func (c *Client) ControllerToken(ctx context.Context) (config.Secret, error) {
	if tok, ok := c.cachedToken(time.Now()); ok {
		return tok, nil
	}
	c.refreshMu.Lock()
	defer c.refreshMu.Unlock()
	now := time.Now()
	if tok, ok := c.cachedToken(now); ok { // refreshed by another caller
		return tok, nil
	}
	var out struct {
		Token     string `json:"token"`
		ExpiresAt int64  `json:"expiresAt"`
	}
	err := c.do(ctx, http.MethodPost, "/bot/controller/token", "Bot-Service "+c.key.Reveal(), nil, &out)
	if err == nil && (out.Token == "" || out.ExpiresAt <= 0) {
		err = errors.New("client: controller token response missing token or expiresAt")
	}
	if c.onToken != nil {
		c.onToken(err == nil)
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	if err != nil {
		if !c.token.Empty() && now.Before(c.expiresAt) {
			return c.token, nil // keep using the still-valid token; retry next call
		}
		return config.Secret{}, err
	}
	c.token = config.NewSecret(out.Token)
	c.issuedAt = now
	c.expiresAt = time.UnixMilli(out.ExpiresAt)
	if !c.expiresAt.After(now) { // clock skew guard: assume the documented 15 min
		c.expiresAt = now.Add(15 * time.Minute)
	}
	return c.token, nil
}

// cachedToken returns the cached token while it is before its refresh point.
func (c *Client) cachedToken(now time.Time) (config.Secret, bool) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.token.Empty() {
		return config.Secret{}, false
	}
	life := c.expiresAt.Sub(c.issuedAt)
	refreshAt := c.issuedAt.Add(life * 8 / 10)
	if hard := c.expiresAt.Add(-30 * time.Second); hard.Before(refreshAt) {
		refreshAt = hard
	}
	return c.token, now.Before(refreshAt)
}

// withController performs a controller-authenticated call, refreshing the
// token once on 401.
func (c *Client) withController(ctx context.Context, method, path string, body, out any) error {
	for attempt := 0; attempt < 2; attempt++ {
		tok, err := c.ControllerToken(ctx)
		if err != nil {
			return err
		}
		err = c.do(ctx, method, path, "Bearer "+tok.Reveal(), body, out)
		if attempt == 0 && IsStatus(err, http.StatusUnauthorized) {
			c.InvalidateToken()
			continue
		}
		return err
	}
	return nil
}

// Assignments long-polls for new assignments (each is handed out once).
func (c *Client) Assignments(ctx context.Context, wait time.Duration) ([]Assignment, error) {
	secs := int(wait / time.Second)
	if secs < 1 {
		secs = 1
	}
	ctx, cancel := context.WithTimeout(ctx, wait+c.timeout)
	defer cancel()
	var out struct {
		Assignments []Assignment `json:"assignments"`
		Maintenance bool         `json:"maintenance"`
	}
	err := c.withControllerNoTimeout(ctx, http.MethodGet, "/bot/assignments?wait="+strconv.Itoa(secs), nil, &out)
	if err == nil && out.Maintenance {
		// The backend answers 200 {"assignments":[],"maintenance":true}
		// during global maintenance; surface it like a 503.
		err = &APIError{Status: http.StatusServiceUnavailable, Code: "maintenance", Message: "backend maintenance"}
	}
	return out.Assignments, err
}

// LobbyList is the GET /bot/lobbies response.
type LobbyList struct {
	Lobbies []Lobby `json:"lobbies"`
	// PublicFillEnabled mirrors BOT_PUBLIC_FILL_ENABLED when the backend
	// reports it (nil when absent).
	PublicFillEnabled *bool `json:"publicFillEnabled,omitempty"`
}

// Lobbies lists open public lobbies.
func (c *Client) Lobbies(ctx context.Context) (LobbyList, error) {
	var out LobbyList
	err := c.withController(ctx, http.MethodGet, "/bot/lobbies", nil, &out)
	return out, err
}

// FillResult is the POST /bot/lobbies/{roomId}/fill response. The documented
// contract returns the created assignments; a backend may instead return only
// {"requested": n} and deliver the assignments through GET /bot/assignments.
// bot-play serves them either way.
type FillResult struct {
	Assignments []Assignment `json:"assignments"`
	Requested   int          `json:"requested"`
}

// Fill requests count bot seats for a public lobby.
func (c *Client) Fill(ctx context.Context, roomID string, count int) (FillResult, error) {
	var out FillResult
	err := c.withController(ctx, http.MethodPost, "/bot/lobbies/"+url.PathEscape(roomID)+"/fill", map[string]int{"count": count}, &out)
	return out, err
}

// CreateSession creates a bot session (assignment or load-test).
func (c *Client) CreateSession(ctx context.Context, req SessionRequest) (*Session, error) {
	var out struct {
		AccessToken string   `json:"accessToken"`
		ExpiresAt   int64    `json:"expiresAt"`
		UID         string   `json:"uid"`
		RoomID      string   `json:"roomId"`
		Emotes      []string `json:"emotes"`
	}
	if err := c.withController(ctx, http.MethodPost, "/bot/sessions", req, &out); err != nil {
		return nil, err
	}
	if out.AccessToken == "" || out.UID == "" {
		return nil, errors.New("client: session response missing accessToken or uid")
	}
	return &Session{AccessToken: config.NewSecret(out.AccessToken), ExpiresAt: out.ExpiresAt, UID: out.UID,
		RoomID: out.RoomID, Emotes: out.Emotes}, nil
}

// RevokeSession revokes a bot session (the bot leaves its room). 404 is
// treated as already revoked.
func (c *Client) RevokeSession(ctx context.Context, uid string) error {
	err := c.withController(ctx, http.MethodDelete, "/bot/sessions/"+url.PathEscape(uid), nil, nil)
	if IsStatus(err, http.StatusNotFound) {
		return nil
	}
	return err
}

// Ping performs a cheap authenticated call to confirm reachability.
func (c *Client) Ping(ctx context.Context) error {
	_, err := c.Lobbies(ctx)
	return err
}

func (c *Client) withControllerNoTimeout(ctx context.Context, method, path string, body, out any) error {
	return c.withController(context.WithValue(ctx, noTimeoutKey{}, true), method, path, body, out)
}

type noTimeoutKey struct{}

func (c *Client) do(ctx context.Context, method, path, auth string, body, out any) error {
	if ctx.Value(noTimeoutKey{}) == nil {
		var cancel context.CancelFunc
		ctx, cancel = context.WithTimeout(ctx, c.timeout)
		defer cancel()
	}
	var rd io.Reader
	if body != nil {
		b, err := json.Marshal(body)
		if err != nil {
			return err
		}
		rd = bytes.NewReader(b)
	}
	req, err := http.NewRequestWithContext(ctx, method, c.base+path, rd)
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", auth)
	req.Header.Set("Accept", "application/json")
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	if c.ua != "" {
		req.Header.Set("User-Agent", c.ua)
	}
	resp, err := c.hc.Do(req)
	if err != nil {
		return fmt.Errorf("client: %s %s: %w", method, redactPath(path), err)
	}
	defer resp.Body.Close()
	data, _ := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if resp.StatusCode < 200 || resp.StatusCode > 299 {
		ae := &APIError{Status: resp.StatusCode}
		var eb struct {
			Error struct {
				Code    string `json:"code"`
				Message string `json:"message"`
			} `json:"error"`
		}
		if json.Unmarshal(data, &eb) == nil {
			ae.Code, ae.Message = eb.Error.Code, eb.Error.Message
		}
		if ra := resp.Header.Get("Retry-After"); ra != "" {
			if s, err := strconv.Atoi(ra); err == nil && s >= 0 {
				ae.RetryAfter = time.Duration(s) * time.Second
			}
		}
		if resp.StatusCode < 500 && resp.StatusCode != http.StatusTooManyRequests {
			c.lastOK.Store(time.Now().UnixNano()) // the backend is reachable
		}
		return ae
	}
	c.lastOK.Store(time.Now().UnixNano())
	if out == nil || len(bytes.TrimSpace(data)) == 0 {
		return nil
	}
	if err := json.Unmarshal(data, out); err != nil {
		return fmt.Errorf("client: decode %s: %w", redactPath(path), err)
	}
	return nil
}

// redactPath strips query strings from paths used in error messages.
func redactPath(p string) string {
	if i := strings.IndexByte(p, '?'); i >= 0 {
		return p[:i]
	}
	return p
}
