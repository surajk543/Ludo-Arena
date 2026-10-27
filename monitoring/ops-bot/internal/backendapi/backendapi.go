// Package backendapi reads the backend's operator API (/api/v1/admin/ops/*):
// the online human players and the top players by minutes per game. These
// are per-user lists, which never belong in Prometheus labels.
//
// The operator key (BACKEND_ADMIN_KEY) is a secret. It is only sent in the
// X-Admin-Key header and never appears in errors or logs. The backend
// answers these routes on the private network only (nginx returns 404 for
// /api/v1/admin/ publicly).
package backendapi

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"
)

const (
	keyHeader       = "X-Admin-Key"
	maxResponseBody = 8 << 20
)

// Activities of an online player (OnlineUser.Activity).
const (
	ActivityLudo    = "ludo"
	ActivitySnakes  = "snakes_ladders"
	ActivityWaiting = "waiting" // seated in a room that has not started
	ActivityLobby   = "lobby"   // online, not in a live room
)

// Client calls one backend. It is safe for concurrent use.
type Client struct {
	BaseURL string // e.g. http://127.0.0.1:8080
	Key     string // operator key (secret)
	HTTP    *http.Client
}

// New returns a client with a bounded HTTP timeout (each call is also bound
// by its context).
func New(baseURL, key string) *Client {
	return &Client{BaseURL: strings.TrimRight(baseURL, "/"), Key: key, HTTP: &http.Client{Timeout: 20 * time.Second}}
}

// OnlineUser is one online human player.
type OnlineUser struct {
	UID         string     `json:"uid"`    // public id shown in the app ("u_…")
	UserID      string     `json:"userId"` // account id
	Name        string     `json:"name"`
	CreatedAt   *time.Time `json:"createdAt"`
	OnlineSince time.Time  `json:"onlineSince"`
	Activity    string     `json:"activity"`
	Game        string     `json:"game"` // "" in the lobby
	Mode        string     `json:"mode"` // public|private|practice, "" in the lobby
}

// Online is GET /api/v1/admin/ops/online: Total and Counts cover every
// online human, Users the first `limit` (playing first, longest online first).
type Online struct {
	At     time.Time      `json:"at"`
	Total  int            `json:"total"`
	Counts map[string]int `json:"counts"`
	Users  []OnlineUser   `json:"users"`
}

// HourSeconds is the play of one UTC hour.
type HourSeconds struct {
	Hour    time.Time `json:"hour"`
	Seconds int64     `json:"seconds"`
}

// PlayerSeconds is one player's play in the window.
type PlayerSeconds struct {
	UID       string     `json:"uid"`
	UserID    string     `json:"userId"`
	Name      string     `json:"name"`
	CreatedAt *time.Time `json:"createdAt"`
	Seconds   int64      `json:"seconds"`
}

// GamePlaytime is one game's play in the window.
type GamePlaytime struct {
	Game    string          `json:"game"`
	Seconds int64           `json:"seconds"`
	Players int             `json:"players"`
	Hourly  []HourSeconds   `json:"hourly"`
	Top     []PlayerSeconds `json:"top"`
}

// Playtime is GET /api/v1/admin/ops/playtime: active play (the daily
// playtime rules: foreground, not idle) of human players per game.
type Playtime struct {
	From  time.Time      `json:"from"`
	To    time.Time      `json:"to"`
	Hours int            `json:"hours"`
	Games []GamePlaytime `json:"games"`
}

// Game returns the entry of game (zero value when missing).
func (p Playtime) Game(game string) GamePlaytime {
	for _, g := range p.Games {
		if g.Game == game {
			return g
		}
	}
	return GamePlaytime{Game: game}
}

// Error is an unsuccessful answer. It never contains the operator key.
type Error struct {
	Path       string
	StatusCode int
	Code       string
}

func (e *Error) Error() string {
	switch e.StatusCode {
	case http.StatusNotFound:
		return fmt.Sprintf("backend %s: 404 (operator API disabled: set ADMIN_API_KEY_SHA256 on the backend)", e.Path)
	case http.StatusUnauthorized:
		return fmt.Sprintf("backend %s: 401 (BACKEND_ADMIN_KEY does not match ADMIN_API_KEY_SHA256)", e.Path)
	}
	if e.Code != "" {
		return fmt.Sprintf("backend %s: %d %s", e.Path, e.StatusCode, e.Code)
	}
	return fmt.Sprintf("backend %s: %d %s", e.Path, e.StatusCode, http.StatusText(e.StatusCode))
}

// Online lists the online human players (limit 1–500).
func (c *Client) Online(ctx context.Context, limit int) (Online, error) {
	var out Online
	err := c.get(ctx, "/api/v1/admin/ops/online", url.Values{"limit": {strconv.Itoa(limit)}}, &out)
	return out, err
}

// Playtime returns the top players by active play per game over the last
// hours (1–24), limit players per game (1–500).
func (c *Client) Playtime(ctx context.Context, hours, limit int) (Playtime, error) {
	var out Playtime
	err := c.get(ctx, "/api/v1/admin/ops/playtime", url.Values{"hours": {strconv.Itoa(hours)}, "limit": {strconv.Itoa(limit)}}, &out)
	return out, err
}

func (c *Client) get(ctx context.Context, path string, q url.Values, v any) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, c.BaseURL+path+"?"+q.Encode(), nil)
	if err != nil {
		return fmt.Errorf("backend %s: %w", path, err)
	}
	req.Header.Set(keyHeader, c.Key)
	req.Header.Set("Accept", "application/json")
	hc := c.HTTP
	if hc == nil {
		hc = http.DefaultClient
	}
	resp, err := hc.Do(req)
	if err != nil {
		var ue *url.Error
		if errors.As(err, &ue) {
			err = ue.Err // the URL holds no secret, but keep messages short
		}
		return fmt.Errorf("backend %s: %w", path, err)
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(io.LimitReader(resp.Body, maxResponseBody))
	if err != nil {
		return fmt.Errorf("backend %s: read: %w", path, err)
	}
	if resp.StatusCode != http.StatusOK {
		var env struct {
			Error struct {
				Code string `json:"code"`
			} `json:"error"`
		}
		_ = json.Unmarshal(body, &env)
		return &Error{Path: path, StatusCode: resp.StatusCode, Code: env.Error.Code}
	}
	if err := json.Unmarshal(body, v); err != nil {
		return fmt.Errorf("backend %s: decode: %w", path, err)
	}
	return nil
}
