// Package tests contains end-to-end integration tests that run the fully
// wired backend (internal/server) against real PostgreSQL and Redis.
//
// They are skipped unless TEST_DATABASE_URL and TEST_REDIS_ADDR are set, e.g.
//
//	TEST_DATABASE_URL=postgres://ludo@127.0.0.1:5440/ludo_royale_test?sslmode=disable \
//	TEST_REDIS_ADDR=127.0.0.1:6390 go test -race ./tests/...
package tests

import (
	"bytes"
	"context"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"math/big"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/jackc/pgx/v5"
	"github.com/redis/go-redis/v9"

	"ludoroyale/internal/assets/r2test"
	"ludoroyale/internal/config"
	"ludoroyale/internal/postgres"
	"ludoroyale/internal/redisstore"
	"ludoroyale/internal/rooms"
	"ludoroyale/internal/server"
)

const (
	googleAud  = "test-web-client.apps.googleusercontent.com"
	botKey     = "test-bot-service-key-0123456789abcdef0123456789"
	redisDB    = 13
	appVersion = "1.0.0"
	// Fake R2 bucket (internal/assets/r2test); never a real account.
	testR2Account = "0123456789abcdef0123456789abcdef"
	testR2Bucket  = "ludo-royale"
	testR2KeyID   = "AKIDE2ETEST"
	testR2Secret  = "e2e-fake-r2-secret"
)

// runID makes provider subjects unique per test run (the test database
// persists between runs).
var runID = fmt.Sprint(time.Now().UnixNano())

func sub(name string) string { return name + "-" + runID }

// fakeOIDC is a local JWKS server that signs provider-style ID tokens.
type fakeOIDC struct {
	srv *httptest.Server
	key *rsa.PrivateKey
	kid string
}

func newFakeOIDC(t *testing.T) *fakeOIDC {
	key, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatal(err)
	}
	f := &fakeOIDC{key: key, kid: "test-key-1"}
	f.srv = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		n := base64.RawURLEncoding.EncodeToString(key.N.Bytes())
		e := base64.RawURLEncoding.EncodeToString(big.NewInt(int64(key.E)).Bytes())
		_ = json.NewEncoder(w).Encode(map[string]any{"keys": []map[string]string{
			{"kty": "RSA", "kid": f.kid, "alg": "RS256", "use": "sig", "n": n, "e": e}}})
	}))
	t.Cleanup(f.srv.Close)
	return f
}

func (f *fakeOIDC) googleToken(t *testing.T, sub, aud string, exp time.Duration) string {
	claims := jwt.MapClaims{"iss": "https://accounts.google.com", "aud": aud, "sub": sub,
		"iat": time.Now().Unix(), "exp": time.Now().Add(exp).Unix(), "given_name": "Tester"}
	tok := jwt.NewWithClaims(jwt.SigningMethodRS256, claims)
	tok.Header["kid"] = f.kid
	s, err := tok.SignedString(f.key)
	if err != nil {
		t.Fatal(err)
	}
	return s
}

// env is a running backend for one test.
type env struct {
	t      *testing.T
	app    *server.App
	srv    *httptest.Server
	rdb    *redis.Client
	oidc   *fakeOIDC
	policy string // policy file path
	flag   string // maintenance flag path
	cancel context.CancelFunc
}

type envOpts struct {
	dice        rooms.Dice
	queue       int
	turnTimeout time.Duration
	fill        time.Duration
	compression string
	// proxyHops sets TRUSTED_PROXY_HOPS so a test can present distinct
	// client IPs (X-Forwarded-For) to the per-IP rate limits.
	proxyHops int
	// pgTracer, when set, traces every PostgreSQL query of the app's pool
	// (query counting in hotpath_test.go).
	pgTracer pgx.QueryTracer
	// r2, when set, configures the four R2_* variables and R2_ENDPOINT for
	// this fake bucket (profile-picture signing). Without it R2 is
	// unconfigured, whatever the shell environment holds.
	r2 *r2test.Server
	// botPictureShare sets BOT_PICTURE_SHARE ("" = default 0.3).
	botPictureShare string
}

func newEnv(t *testing.T, o envOpts) *env {
	t.Helper()
	dbURL, redisAddr := os.Getenv("TEST_DATABASE_URL"), os.Getenv("TEST_REDIS_ADDR")
	if dbURL == "" || redisAddr == "" {
		t.Skip("TEST_DATABASE_URL and TEST_REDIS_ADDR not set")
	}
	ctx, cancel := context.WithCancel(context.Background())
	oidc := newFakeOIDC(t)
	dir := t.TempDir()
	policyPath := filepath.Join(dir, "policy.json")
	writeFile(t, policyPath, policyJSON("1.0.0", 1, "1.0.0", 1, false))
	sum := sha256.Sum256([]byte(botKey))
	if o.compression == "" {
		o.compression = "no_context_takeover"
	}
	envVars := map[string]string{
		"APP_ENV": "development", "DATABASE_URL": dbURL, "REDIS_ADDR": redisAddr,
		"REDIS_DB": fmt.Sprint(redisDB), "JWT_SIGNING_KEY": strings.Repeat("k", 40),
		"PUBLIC_ID_KEY": strings.Repeat("p", 40), "GOOGLE_CLIENT_IDS": googleAud,
		"GOOGLE_JWKS_URL": oidc.srv.URL, "APP_POLICY_FILE": policyPath,
		"APP_MAINTENANCE_FLAG_FILE": filepath.Join(dir, "MAINTENANCE"), "APP_POLICY_POLL_SECONDS": "1s",
		"BOT_SERVICE_KEY_SHA256": hex.EncodeToString(sum[:]), "BOT_LOADTEST_ENABLED": "true",
		"BOT_PUBLIC_FILL_ENABLED": "true", "WS_COMPRESSION": o.compression,
		"WS_COMPRESSION_THRESHOLD": "256", "LOG_LEVEL": "error",
		"CATALOG_FILE": "../config/catalog.json", "MISSIONS_FILE": "../config/missions.json",
		// Never pick up a real bucket from the shell.
		"R2_ACCOUNT_ID": "", "R2_BUCKET": "", "R2_ACCESS_KEY_ID": "", "R2_SECRET_ACCESS_KEY": "",
		"R2_ENDPOINT": "", "ASSET_URL_TTL": "", "BOT_PICTURE_SHARE": o.botPictureShare,
	}
	if o.r2 != nil {
		envVars["R2_ACCOUNT_ID"], envVars["R2_BUCKET"] = testR2Account, o.r2.Bucket
		envVars["R2_ACCESS_KEY_ID"], envVars["R2_SECRET_ACCESS_KEY"] = o.r2.AccessKeyID, o.r2.Secret
		envVars["R2_ENDPOINT"] = o.r2.URL
	}
	if o.queue > 0 {
		envVars["WS_OUTBOUND_QUEUE"] = fmt.Sprint(o.queue)
	}
	if o.turnTimeout > 0 {
		envVars["TURN_SECONDS"] = o.turnTimeout.String()
		envVars["TURN_SECONDS_DISCONNECTED"] = o.turnTimeout.String()
	}
	if o.fill > 0 {
		envVars["MATCHMAKING_FILL_SECONDS"] = o.fill.String()
	}
	if o.proxyHops > 0 {
		envVars["TRUSTED_PROXY_HOPS"] = fmt.Sprint(o.proxyHops)
	}
	for k, v := range envVars {
		if _, preset := os.LookupEnv(k); preset && k == "PROGRESSION_MIN_MATCH_DURATION" {
			continue
		}
		t.Setenv(k, v)
	}
	cfg, err := config.Load()
	if err != nil {
		t.Fatal(err)
	}
	cfg.WS.MsgRatePerSec, cfg.WS.MsgBurst = 200, 400 // tests drive games quickly
	log := slog.New(slog.NewTextHandler(io.Discard, nil))
	pg, err := openPG(ctx, dbURL, o.pgTracer)
	if err != nil {
		t.Fatal(err)
	}
	if err := postgres.Migrate(ctx, pg); err != nil {
		t.Fatal(err)
	}
	rdb, err := redisstore.Open(ctx, redisAddr, "", redisDB, false)
	if err != nil {
		t.Fatal(err)
	}
	if err := rdb.FlushDB(ctx).Err(); err != nil {
		t.Fatal(err)
	}
	core := server.NewCore(cfg, log, pg, rdb)
	ext, err := server.DefaultExtensions(ctx, core)
	if err != nil {
		t.Fatal(err)
	}
	app, err := server.New(ctx, core, ext, o.dice)
	if err != nil {
		t.Fatal(err)
	}
	app.Start(ctx)
	srv := httptest.NewServer(app.Handler())
	e := &env{t: t, app: app, srv: srv, rdb: rdb, oidc: oidc, policy: policyPath,
		flag: filepath.Join(dir, "MAINTENANCE"), cancel: cancel}
	t.Cleanup(func() {
		cancel()
		srv.CloseClientConnections()
		srv.Close()
		time.Sleep(50 * time.Millisecond)
		pg.Close()
		_ = rdb.Close()
	})
	time.Sleep(50 * time.Millisecond) // let the pub/sub subscription start
	return e
}

func writeFile(t *testing.T, path, body string) {
	t.Helper()
	if err := os.WriteFile(path, []byte(body), 0o600); err != nil {
		t.Fatal(err)
	}
}

func policyJSON(min string, minBuild int, latest string, latestBuild int, maintenance bool) string {
	plat := fmt.Sprintf(`{"minimumSupportedVersion":%q,"minimumSupportedBuild":%d,"latestVersion":%q,"latestBuild":%d,
		"storeUrl":"","forceUpdateTitle":"","forceUpdateMessage":"","optionalUpdateTitle":"","optionalUpdateMessage":"",
		"optionalUpdateReminderHours":24,"securityCritical":false,"maintenance":{"enabled":false,"message":""}}`,
		min, minBuild, latest, latestBuild)
	return fmt.Sprintf(`{"configVersion":%d,"environment":"development","maintenance":{"enabled":%t,"message":"m","windows":[]},
		"platforms":{"android":%s,"ios":%s}}`, time.Now().UnixNano()%1000000+1, maintenance, plat, plat)
}

// ---- REST helpers ----

type resp struct {
	Status int
	Body   map[string]any
	Raw    []byte
	Header http.Header
}

func (e *env) do(method, path, token string, body any, headers ...string) resp {
	e.t.Helper()
	var rd io.Reader
	if body != nil {
		b, _ := json.Marshal(body)
		rd = bytes.NewReader(b)
	}
	req, _ := http.NewRequest(method, e.srv.URL+path, rd)
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-App-Platform", "android")
	req.Header.Set("X-App-Version", appVersion)
	req.Header.Set("X-App-Build", "1")
	for i := 0; i+1 < len(headers); i += 2 {
		req.Header.Set(headers[i], headers[i+1])
	}
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	res, err := http.DefaultClient.Do(req)
	if err != nil {
		e.t.Fatal(err)
	}
	defer res.Body.Close()
	raw, _ := io.ReadAll(res.Body)
	out := resp{Status: res.StatusCode, Raw: raw, Header: res.Header}
	_ = json.Unmarshal(raw, &out.Body)
	return out
}

type account struct {
	Token, Refresh, UserID, UID, GuestSecret string
	Coins, Diamonds                          int64
}

func parseAuth(t *testing.T, r resp) account {
	t.Helper()
	if r.Status != 200 && r.Status != 201 {
		t.Fatalf("auth failed: %d %s", r.Status, r.Raw)
	}
	user := r.Body["user"].(map[string]any)
	w := r.Body["wallet"].(map[string]any)
	gs, _ := r.Body["guestSecret"].(string)
	return account{Token: r.Body["accessToken"].(string), Refresh: r.Body["refreshToken"].(string),
		UserID: user["id"].(string), UID: user["uid"].(string), GuestSecret: gs,
		Coins: int64(w["coins"].(float64)), Diamonds: int64(w["diamonds"].(float64))}
}

func (e *env) guest() account {
	return parseAuth(e.t, e.do("POST", "/api/v1/auth/guest", "", map[string]any{}))
}

func (e *env) coins(token string) int64 {
	r := e.do("GET", "/api/v1/wallet", token, nil)
	if r.Status != 200 {
		e.t.Fatalf("wallet: %d %s", r.Status, r.Raw)
	}
	return int64(r.Body["coins"].(float64))
}

// waitFor polls cond until true or timeout.
func waitFor(t *testing.T, timeout time.Duration, what string, cond func() bool) {
	t.Helper()
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		if cond() {
			return
		}
		time.Sleep(20 * time.Millisecond)
	}
	t.Fatalf("timed out waiting for %s", what)
}

var _ sync.Mutex
