// Package progtest provides test fixtures for the progression, social and
// analytics packages: the test PostgreSQL database (migrated), Redis DB 14, a
// real auth service + httpapi.Router, accounts, a controllable clock and a
// recording Notifier. It is imported by tests only.
//
// Environment: TEST_DATABASE_URL (default
// postgres://ludo@127.0.0.1:5440/ludo_royale_test?sslmode=disable),
// TEST_REDIS_ADDR (default 127.0.0.1:6390), TEST_REDIS_DB (default 14).
// Tests are skipped when the services are unreachable.
package progtest

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"runtime"
	"strconv"
	"sync"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/redis/go-redis/v9"

	"ludoroyale/internal/apppolicy"
	"ludoroyale/internal/auth"
	"ludoroyale/internal/httpapi"
	"ludoroyale/internal/identity"
	"ludoroyale/internal/postgres"
	"ludoroyale/internal/profile"
	"ludoroyale/internal/ratelimit"
)

// Welcome grant used for test accounts.
const (
	WelcomeCoins    = 1_000_000
	WelcomeDiamonds = 50
)

// Env holds shared fixtures.
type Env struct {
	Pool     *pgxpool.Pool
	RDB      *redis.Client
	Profiles *profile.Service
	IDs      *identity.Store
	Auth     *auth.Service
	Signer   *auth.Signer
	Sessions *auth.Sessions
	Policy   *apppolicy.Store
	Log      *slog.Logger
	// BackendDir is the absolute path of the backend module.
	BackendDir string
}

var (
	once    sync.Once
	shared  *Env
	initErr string
)

func env(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

// BackendDir returns the backend module directory.
func BackendDir() string {
	_, file, _, _ := runtime.Caller(0)
	return filepath.Clean(filepath.Join(filepath.Dir(file), "..", "..", ".."))
}

// Setup returns the shared environment or skips the test.
func Setup(t testing.TB) *Env {
	t.Helper()
	once.Do(func() {
		ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
		defer cancel()
		log := slog.New(slog.NewTextHandler(io.Discard, nil))
		if os.Getenv("TEST_VERBOSE_LOG") != "" {
			log = slog.New(slog.NewTextHandler(os.Stderr, &slog.HandlerOptions{Level: slog.LevelDebug}))
		}
		pool, err := postgres.Open(ctx, env("TEST_DATABASE_URL", "postgres://ludo@127.0.0.1:5440/ludo_royale_test?sslmode=disable"), 40)
		if err != nil {
			initErr = "postgres unavailable: " + err.Error()
			return
		}
		if err := postgres.Migrate(ctx, pool); err != nil {
			initErr = "migrate: " + err.Error()
			return
		}
		db, _ := strconv.Atoi(env("TEST_REDIS_DB", "14"))
		rdb := redis.NewClient(&redis.Options{Addr: env("TEST_REDIS_ADDR", "127.0.0.1:6390"), DB: db, PoolSize: 64})
		if err := rdb.Ping(ctx).Err(); err != nil {
			initErr = "redis unavailable: " + err.Error()
			return
		}
		dir := BackendDir()
		policy, err := apppolicy.NewStore(filepath.Join(dir, "config", "app-policy.development.json"), "", "development", log)
		if err != nil {
			initErr = "app policy: " + err.Error()
			return
		}
		profiles := profile.New(rdb, []byte("test-public-id-key-0123456789abcdef"))
		ids := identity.NewStore(pool, identity.Welcome{Coins: WelcomeCoins, Diamonds: WelcomeDiamonds})
		signer := auth.NewSigner([]byte("test-jwt-signing-key-0123456789abcdef"), "ludo-royale-test")
		sessions := auth.NewSessions(rdb, time.Hour)
		a := auth.NewService(signer, sessions, ids, profiles, nil, 15*time.Minute, time.Hour)
		shared = &Env{Pool: pool, RDB: rdb, Profiles: profiles, IDs: ids, Auth: a, Signer: signer, Sessions: sessions,
			Policy: policy, Log: log, BackendDir: dir}
	})
	if shared == nil {
		t.Skip("progtest: " + initErr)
	}
	return shared
}

// CatalogPath / MissionsPath return the repository config files.
func (e *Env) CatalogPath() string  { return filepath.Join(e.BackendDir, "config", "catalog.json") }
func (e *Env) MissionsPath() string { return filepath.Join(e.BackendDir, "config", "missions.json") }

// cleanup deletes accounts created by a test (progression rows cascade).
func (e *Env) cleanup(t testing.TB, id uuid.UUID) {
	t.Cleanup(func() {
		ctx := context.Background()
		_, _ = e.Pool.Exec(ctx, `DELETE FROM identity.auth_identities WHERE user_id = $1`, id)
		_, _ = e.Pool.Exec(ctx, `DELETE FROM wallet.wallets WHERE user_id = $1`, id)
		_ = e.RDB.Del(ctx, "profile:"+id.String(), "pubid:"+e.Profiles.PublicID(id), "recent:"+id.String(),
			"presence:"+id.String()).Err()
	})
}

// NewAccount creates an account (wallet with the welcome grant + guest
// identity) and its Redis display profile.
func (e *Env) NewAccount(t testing.TB) uuid.UUID {
	t.Helper()
	ctx := context.Background()
	acct, err := e.IDs.FindOrCreate(ctx, identity.Guest, "test-"+uuid.NewString())
	if err != nil {
		t.Fatalf("create account: %v", err)
	}
	if _, err := e.Profiles.Save(ctx, acct.UserID, ""); err != nil {
		t.Fatalf("save profile: %v", err)
	}
	e.cleanup(t, acct.UserID)
	return acct.UserID
}

// SetDiamonds sets the account's diamond balance (tests that buy Shop items,
// which cost more than the welcome grant).
func (e *Env) SetDiamonds(t testing.TB, id uuid.UUID, diamonds int64) {
	t.Helper()
	if _, err := e.Pool.Exec(context.Background(),
		`UPDATE wallet.wallets SET diamonds = $2 WHERE user_id = $1`, id, diamonds); err != nil {
		t.Fatalf("set diamonds: %v", err)
	}
}

// Guest creates a guest through the real auth service and returns its access
// token.
func (e *Env) Guest(t testing.TB) (uuid.UUID, string) {
	t.Helper()
	res, err := e.Auth.CreateGuest(context.Background())
	if err != nil {
		t.Fatalf("create guest: %v", err)
	}
	e.cleanup(t, res.UserID)
	return res.UserID, res.AccessToken
}

// BotToken issues a bot player session token (scoped to a room), as the bot
// service would receive it.
func (e *Env) BotToken(t testing.TB) string {
	t.Helper()
	sid, err := e.Sessions.CreateBot(context.Background(), uuid.New(), time.Hour, map[string]any{"room": "r_test"})
	if err != nil {
		t.Fatal(err)
	}
	c := auth.Claims{Kind: auth.KindBot, SessionID: sid, Actor: auth.ActorBot, RoomID: "r_test", BotName: "Bot"}
	c.Subject = uuid.NewString()
	tok, _, err := e.Signer.Sign(c, time.Hour)
	if err != nil {
		t.Fatal(err)
	}
	return tok
}

// Router returns a real httpapi.Router (rate limits enabled) and a running
// test server for it; register routes on the router before sending requests.
func (e *Env) Router(t testing.TB) (*httpapi.Router, *httptest.Server) {
	t.Helper()
	rt := httpapi.NewRouter(e.Log, e.Auth, e.Policy, ratelimit.New(e.RDB, e.Log, false), 0)
	srv := httptest.NewServer(rt.Mux())
	t.Cleanup(srv.Close)
	return rt, srv
}

// Response is a decoded HTTP response.
type Response struct {
	Status int
	Header http.Header
	Body   []byte
}

// JSON decodes the body into v.
func (r Response) JSON(t testing.TB, v any) {
	t.Helper()
	if err := json.Unmarshal(r.Body, v); err != nil {
		t.Fatalf("decode %s: %v", r.Body, err)
	}
}

// ErrorCode returns error.code of an error body.
func (r Response) ErrorCode() string {
	var e struct {
		Error struct {
			Code string `json:"code"`
		} `json:"error"`
	}
	_ = json.Unmarshal(r.Body, &e)
	return e.Error.Code
}

// Do performs an API request with the app headers and optional bearer token.
func Do(t testing.TB, srv *httptest.Server, method, path, token string, body any, headers map[string]string) Response {
	t.Helper()
	var rd io.Reader
	if body != nil {
		raw, err := json.Marshal(body)
		if err != nil {
			t.Fatal(err)
		}
		rd = bytes.NewReader(raw)
	}
	req, err := http.NewRequest(method, srv.URL+path, rd)
	if err != nil {
		t.Fatal(err)
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-App-Platform", "android")
	req.Header.Set("X-App-Version", "1.0.0")
	req.Header.Set("X-App-Build", "1")
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	for k, v := range headers {
		req.Header.Set(k, v)
	}
	resp, err := srv.Client().Do(req)
	if err != nil {
		t.Fatalf("%s %s: %v", method, path, err)
	}
	defer resp.Body.Close()
	raw, _ := io.ReadAll(resp.Body)
	return Response{Status: resp.StatusCode, Header: resp.Header, Body: raw}
}

// Clock is a controllable clock.
type Clock struct {
	mu sync.Mutex
	t  time.Time
}

// NewClock returns a clock set to t.
func NewClock(t time.Time) *Clock { return &Clock{t: t} }

// Now returns the current fake time.
func (c *Clock) Now() time.Time {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.t
}

// Set changes the time.
func (c *Clock) Set(t time.Time) {
	c.mu.Lock()
	c.t = t
	c.mu.Unlock()
}

// Message is one captured notification.
type Message struct {
	UserID  uuid.UUID
	Type    string
	Payload any
}

// Notifier records NotifyUser calls (implements gameevents.Notifier).
type Notifier struct {
	mu   sync.Mutex
	msgs []Message
}

// NotifyUser implements gameevents.Notifier.
func (n *Notifier) NotifyUser(_ context.Context, userID uuid.UUID, msgType string, payload any) {
	n.mu.Lock()
	n.msgs = append(n.msgs, Message{UserID: userID, Type: msgType, Payload: payload})
	n.mu.Unlock()
}

// For returns the messages of a type sent to a user.
func (n *Notifier) For(userID uuid.UUID, msgType string) []Message {
	n.mu.Lock()
	defer n.mu.Unlock()
	var out []Message
	for _, m := range n.msgs {
		if m.UserID == userID && m.Type == msgType {
			out = append(out, m)
		}
	}
	return out
}

// PayloadMap round-trips a payload through JSON (what the client receives).
func PayloadMap(t testing.TB, p any) map[string]any {
	t.Helper()
	raw, err := json.Marshal(p)
	if err != nil {
		t.Fatal(err)
	}
	var m map[string]any
	if err := json.Unmarshal(raw, &m); err != nil {
		t.Fatal(err)
	}
	return m
}
