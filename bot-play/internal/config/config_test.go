package config

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"os"
	"path/filepath"
	"strings"
	"syscall"
	"testing"
	"time"
)

const profilesYAML = `
profiles:
  balanced:
    think_time_ms: {min: 10, max: 20}
    weights: {enter_from_base: 1, capture_opponent: 2, reach_safe_square: 1, progress_toward_home: 1, complete_home: 1, escape_danger: 1, avoid_danger: 1, random_jitter: 0}
  advanced:
    think_time_ms: {min: 5, max: 10}
    weights: {capture_opponent: 5}
`

func TestShippedConfigsValidate(t *testing.T) {
	prof := filepath.Join("..", "..", "configs", "profiles.yaml")
	files, _ := filepath.Glob(filepath.Join("..", "..", "configs", "environments", "*.yaml"))
	files = append(files, filepath.Join("..", "..", "configs", "config.example.yaml"), filepath.Join("..", "..", "configs", "loadtest.example.yaml"))
	if len(files) < 5 {
		t.Fatalf("expected shipped config files, got %v", files)
	}
	for _, f := range files {
		snap, err := LoadFiles(f, prof)
		if err != nil {
			t.Errorf("%s: %v", f, err)
			continue
		}
		if strings.Contains(f, "production") {
			if snap.Config.Loadtest.Enabled || snap.Config.IsLoadtest() {
				t.Errorf("production config enables load tests")
			}
		}
	}
}

func TestDefaultsAndEmptyFile(t *testing.T) {
	c, err := Parse(nil)
	if err != nil {
		t.Fatalf("empty file must yield valid defaults: %v", err)
	}
	if c.Bots.MaxBotsPerRoom != 3 || c.Metrics.ListenAddr != "127.0.0.1:9091" || !c.Bots.Games[GameSnakes] || c.Bots.PublicMatchmaking.PerGame[GameLudo] {
		t.Fatalf("unexpected defaults: %+v", c.Bots)
	}
	if got := c.Connection.AssignmentWait(); got != 20*time.Second {
		t.Fatalf("assignment wait = %v", got)
	}
}

func TestValidationRejectsBadConfigs(t *testing.T) {
	cases := map[string]string{
		"think min > max":           "bots: {think_time: {min_ms: 500, max_ms: 100}}",
		"max_bots_per_room 0":       "bots: {max_bots_per_room: 0}",
		"max_bots_per_room 4":       "bots: {max_bots_per_room: 4}",
		"target > max":              "bots: {target_active_bots: 200, max_concurrent_bots: 100}",
		"bad http url":              "connection: {backend_http_url: 'localhost:8080'}",
		"bad ws scheme":             "connection: {backend_ws_url: 'http://localhost/api/v1/ws'}",
		"credentials in url":        "connection: {backend_http_url: 'http://u:p@localhost/api/v1'}",
		"unknown key":               "bots: {service_key: abc}",
		"unknown top-level key":     "secrets: {key: abc}",
		"unknown mode":              "bots: {modes: [practice, chaos]}",
		"loadtest combined":         "bots: {modes: [practice, loadtest]}\nloadtest: {enabled: true}",
		"loadtest mode w/o enabled": "bots: {modes: [loadtest]}",
		"production cap":            "app: {environment: production}\nconnection: {backend_http_url: 'https://x/api/v1', backend_ws_url: 'wss://x/api/v1/ws'}\nbots: {max_concurrent_bots: 501, target_active_bots: 10}",
		"production loadtest":       "app: {environment: production}\nconnection: {backend_http_url: 'https://x/api/v1', backend_ws_url: 'wss://x/api/v1/ws'}\nloadtest: {enabled: true}",
		"production insecure url":   "app: {environment: production}",
		"bad environment":           "app: {environment: staging}",
		"per_game_max unknown game": "bots: {per_game_max: {chess: 3}}",
		"games unknown":             "bots: {games: {chess: true}}",
		"max wait <= fill after":    "bots: {public_matchmaking: {fill_after_seconds: 20, maximum_wait_seconds: 20}}",
		"capacity mix 5":            "loadtest: {capacity_mix: {5: 1}}",
		"game mix all zero":         "loadtest: {game_mix: {ludo: 0}}",
		"shutdown policy":           "bots: {shutdown: {policy: maybe}}",
		"disconnect probability":    "bots: {behavior: {disconnect_probability: 0.5}}",
		"actions per second 0":      "limits: {max_actions_per_second_per_bot: 0}",
		"metrics addr":              "metrics: {listen_addr: 'nope'}",
		"backoff max < base":        "connection: {reconnect_backoff_base_ms: 1000, reconnect_backoff_max_ms: 500}",
		"loadtest target > max":     "bots: {modes: [loadtest], max_concurrent_bots: 10, target_active_bots: 5}\nloadtest: {enabled: true, target_connections: 11}",
		"bad host pattern":          "loadtest: {allowed_hosts: ['http://x']}",
		"names pool entry too long": "bots: {identity: {names_pool: ['abcdefghijklmnopq']}}",
		"min humans 0":              "bots: {public_matchmaking: {minimum_humans: 0}}",
		"chat cap 11":               "bots: {chat: {max_per_match: 11}}",
		"chat cap negative":         "bots: {chat: {max_per_match: -1}}",
		"chat interval < 3 s":       "bots: {chat: {min_interval_ms: 2999}}",
		"chat delay min > max":      "bots: {chat: {reaction_delay_ms: {min: 3000, max: 1000}}}",
		"chat delay too long":       "bots: {chat: {reaction_delay_ms: {min: 0, max: 15001}}}",
		"chat probability > 1":      "bots: {chat: {probability: {win: 1.5}}}",
		"chat probability < 0":      "bots: {chat: {probability: {six: -0.1}}}",
		"chat emote share > 1":      "bots: {chat: {emote_share: 2}}",
		"chat unknown trigger":      "bots: {chat: {probability: {sneeze: 0.5}}}",
		"chat unknown key":          "bots: {chat: {spam: true}}",
	}
	for name, y := range cases {
		t.Run(name, func(t *testing.T) {
			if _, err := Parse([]byte(y)); err == nil {
				t.Fatalf("expected validation error for %q", y)
			}
		})
	}
}

func TestValidationAcceptsGoodConfigs(t *testing.T) {
	good := []string{
		"bots: {modes: [practice, public_fill], max_bots_per_room: 1}",
		"app: {environment: preproduction}", // alias
		"app: {environment: preprod}\nbots: {modes: [loadtest], max_concurrent_bots: 5000, target_active_bots: 1}\nloadtest: {enabled: true, target_connections: 5000}",
		"app: {environment: production}\nconnection: {backend_http_url: 'https://x/api/v1', backend_ws_url: 'wss://x/api/v1/ws'}\nbots: {max_concurrent_bots: 500, target_active_bots: 500}",
		"bots: {enabled: false, modes: []}",
		"bots: {chat: {enabled: false}}",
		"bots: {chat: {max_per_match: 0, min_interval_ms: 3000, probability: {win: 1, loss: 0}, emote_share: 0}}",
	}
	for _, y := range good {
		if _, err := Parse([]byte(y)); err != nil {
			t.Errorf("%q: %v", y, err)
		}
	}
}

// bots.chat defaults: on, sparing, never faster than the server allows; a
// partial override keeps the other defaults.
func TestChatDefaultsAndPartialOverride(t *testing.T) {
	c, err := Parse(nil)
	if err != nil {
		t.Fatal(err)
	}
	ch := c.Bots.Chat
	if !ch.Enabled || ch.InLoadtest || ch.MaxPerMatch != 3 || ch.MinIntervalMS < MinChatIntervalMS ||
		ch.ReactionDelayMS.Min > ch.ReactionDelayMS.Max || ch.Probability.Win <= 0 || ch.Probability.Win > 0.5 {
		t.Fatalf("chat defaults: %+v", ch)
	}
	c, err = Parse([]byte("bots: {chat: {probability: {win: 0.9}}}"))
	if err != nil {
		t.Fatal(err)
	}
	if c.Bots.Chat.Probability.Win != 0.9 || c.Bots.Chat.Probability.Loss != Default().Bots.Chat.Probability.Loss ||
		c.Bots.Chat.MaxPerMatch != 3 {
		t.Fatalf("partial override lost defaults: %+v", c.Bots.Chat)
	}
}

func TestProfileChattiness(t *testing.T) {
	snap, err := LoadBytes(nil, []byte("profiles: {balanced: {think_time_ms: {min: 1, max: 2}, chattiness: 0}, advanced: {think_time_ms: {min: 1, max: 2}}}"))
	if err != nil {
		t.Fatal(err)
	}
	b, _ := snap.Profiles.Get("balanced")
	a, _ := snap.Profiles.Get("advanced")
	if b.ChatMultiplier() != 0 || a.ChatMultiplier() != 1 {
		t.Fatalf("chattiness: balanced %v advanced %v", b.ChatMultiplier(), a.ChatMultiplier())
	}
	for _, bad := range []string{"-1", "5.5"} {
		if _, err := LoadBytes(nil, []byte("profiles: {balanced: {chattiness: "+bad+"}}")); err == nil {
			t.Fatalf("chattiness %s accepted", bad)
		}
	}
}

func TestProfilesMustExist(t *testing.T) {
	_, err := LoadBytes([]byte("bots: {behavior: {default_profile: ghost}}"), []byte(profilesYAML))
	if err == nil || !strings.Contains(err.Error(), "ghost") {
		t.Fatalf("want missing profile error, got %v", err)
	}
	if _, err := LoadBytes([]byte("bots: {behavior: {default_profile: advanced}}"), []byte(profilesYAML)); err != nil {
		t.Fatal(err)
	}
	if _, err := LoadBytes(nil, []byte("profiles: {balanced: {think_time_ms: {min: 30, max: 10}}}")); err == nil {
		t.Fatal("profile think min > max must fail")
	}
	if _, err := LoadBytes(nil, []byte("profiles: {balanced: {weights: {capture_opponent: -1}}}")); err == nil {
		t.Fatal("negative weight must fail")
	}
	if _, err := LoadBytes(nil, []byte("profiles: {balanced: {weightz: {}}}")); err == nil {
		t.Fatal("unknown profile key must fail")
	}
}

func TestServiceKeyFromEnvOnly(t *testing.T) {
	t.Setenv(ServiceKeyEnv, "")
	if _, _, err := ServiceKeyFromEnv(); err == nil {
		t.Fatal("missing key must fail")
	}
	if _, _, err := ServiceKeyFrom("has space"); err == nil {
		t.Fatal("whitespace must fail")
	}
	if _, _, err := ServiceKeyFrom("short-key"); err == nil {
		t.Fatal("keys under 32 chars are rejected by the backend and must fail fast")
	}
	if _, _, err := ServiceKeyFrom(strings.Repeat("k", 257)); err == nil {
		t.Fatal("keys over 256 chars must fail")
	}
	k, warn, err := ServiceKeyFrom(strings.Repeat("k", 40))
	if err != nil || warn == "" || k.Reveal() != strings.Repeat("k", 40) {
		t.Fatalf("40-char key: %v %q", err, warn)
	}
	t.Setenv(ServiceKeyEnv, strings.Repeat("k", 64))
	k, warn, err = ServiceKeyFromEnv()
	if err != nil || warn != "" || k.Empty() {
		t.Fatalf("env key: %v %q", err, warn)
	}
}

func TestSecretNeverFormatsRaw(t *testing.T) {
	raw := "super-secret-value-123"
	s := NewSecret(raw)
	var buf bytes.Buffer
	log := slog.New(slog.NewJSONHandler(&buf, &slog.HandlerOptions{ReplaceAttr: RedactAttr}))
	log.Info("x", "k", s, "authorization", "Bearer "+raw, "access_token", raw, "controllerToken", raw)
	j, _ := json.Marshal(struct{ S Secret }{s})
	outs := []string{
		fmt.Sprint(s), fmt.Sprintf("%v %+v %#v %s %q", s, s, s, s, s), string(j), buf.String(),
		fmt.Sprintf("%v", struct{ S Secret }{s}),
	}
	for _, o := range outs {
		if strings.Contains(o, raw) {
			t.Fatalf("secret leaked: %s", o)
		}
	}
	// Non-sensitive keys are untouched (e.g. Ludo pieces are logged as "piece").
	buf.Reset()
	log.Info("x", "piece", 2, "turn_seq", 5)
	if !strings.Contains(buf.String(), `"piece":2`) {
		t.Fatalf("non-sensitive attr redacted: %s", buf.String())
	}
}

const defaultLT = "loadtest: {enabled: true, allowed_hosts: [localhost, '*.preprod.example'], forbidden_hosts: [api.example, '*.prod.example']}"

// loadtestCfg builds a load-test config; extra may override app/connection
// and (when it contains "loadtest:") the loadtest block.
func loadtestCfg(t *testing.T, extra string) *Config {
	t.Helper()
	lt := defaultLT
	if strings.Contains(extra, "loadtest:") {
		lt = ""
	}
	c, err := Parse([]byte("bots: {modes: [loadtest]}\n" + lt + "\n" + extra))
	if err != nil {
		t.Fatal(err)
	}
	return c
}

func TestLoadtestGuard(t *testing.T) {
	c := loadtestCfg(t, "")
	if err := CheckLoadtestGuard(c, true); err != nil {
		t.Fatalf("valid guard refused: %v", err)
	}
	reason := func(err error) string {
		if ge, ok := err.(*GuardError); ok {
			return ge.Reason
		}
		return fmt.Sprint(err)
	}
	if r := reason(CheckLoadtestGuard(c, false)); r != GuardNoAck {
		t.Errorf("no ack: %s", r)
	}
	prod := *c
	prod.App.Environment = EnvProduction // validation forbids this; the guard must too
	if r := reason(CheckLoadtestGuard(&prod, true)); r != GuardEnvironment {
		t.Errorf("production: %s", r)
	}
	off := *c
	off.Loadtest.Enabled = false
	if r := reason(CheckLoadtestGuard(&off, true)); r != GuardDisabled {
		t.Errorf("disabled: %s", r)
	}
	forb := loadtestCfg(t, "connection: {backend_http_url: 'https://api.example/api/v1', backend_ws_url: 'wss://api.example/api/v1/ws'}\nloadtest: {enabled: true, allowed_hosts: [api.example], forbidden_hosts: [api.example]}")
	if r := reason(CheckLoadtestGuard(forb, true)); r != GuardForbiddenHost {
		t.Errorf("forbidden host: %s", r)
	}
	wild := loadtestCfg(t, "connection: {backend_http_url: 'https://eu.prod.example/api/v1', backend_ws_url: 'wss://eu.prod.example/api/v1/ws'}\nloadtest: {enabled: true, allowed_hosts: ['*.example'], forbidden_hosts: ['*.prod.example']}")
	if r := reason(CheckLoadtestGuard(wild, true)); r != GuardForbiddenHost {
		t.Errorf("wildcard forbidden host: %s", r)
	}
	na := loadtestCfg(t, "connection: {backend_http_url: 'http://10.0.0.5:8080/api/v1', backend_ws_url: 'ws://10.0.0.5:8080/api/v1/ws'}")
	if r := reason(CheckLoadtestGuard(na, true)); r != GuardHostNotAllowed {
		t.Errorf("not allowed host: %s", r)
	}
	mixed := loadtestCfg(t, "connection: {backend_http_url: 'http://localhost:8080/api/v1', backend_ws_url: 'ws://evil.example/api/v1/ws'}")
	if r := reason(CheckLoadtestGuard(mixed, true)); r != GuardHostNotAllowed {
		t.Errorf("ws host must also be allowed: %s", r)
	}
	pre := loadtestCfg(t, "app: {environment: preprod}\nconnection: {backend_http_url: 'https://lt.preprod.example/api/v1', backend_ws_url: 'wss://lt.preprod.example/api/v1/ws'}")
	if err := CheckLoadtestGuard(pre, true); err != nil {
		t.Errorf("preprod allowed host refused: %v", err)
	}
	if HostMatches("*.example", "example") || !HostMatches("*.example", "a.b.example") || !HostMatches("LocalHost", "localhost") {
		t.Error("HostMatches semantics")
	}
}

func writeFile(t *testing.T, path, content string) {
	t.Helper()
	if err := os.WriteFile(path, []byte(content), 0o600); err != nil {
		t.Fatal(err)
	}
}

func TestReloadRollbackAndCompatibility(t *testing.T) {
	dir := t.TempDir()
	cfgPath, profPath := filepath.Join(dir, "c.yaml"), filepath.Join(dir, "p.yaml")
	writeFile(t, cfgPath, "app: {reload_poll_seconds: 1}\nbots: {target_active_bots: 10}")
	writeFile(t, profPath, profilesYAML)
	snap, err := LoadFiles(cfgPath, profPath)
	if err != nil {
		t.Fatal(err)
	}
	store := NewStore(snap)
	sub := store.Subscribe()
	var results []bool
	var logs bytes.Buffer
	w := &Watcher{ConfigPath: cfgPath, ProfilesPath: profPath, Store: store,
		Logger: slog.New(slog.NewTextHandler(&logs, nil)), OnResult: func(ok bool) { results = append(results, ok) }}

	writeFile(t, cfgPath, "app: {reload_poll_seconds: 1}\nbots: {target_active_bots: 20}")
	if err := w.Reload("test"); err != nil {
		t.Fatal(err)
	}
	if got := store.Config().Bots.TargetActiveBots; got != 20 || store.Load().Generation != 2 {
		t.Fatalf("reload not applied: %d gen %d", got, store.Load().Generation)
	}
	select {
	case s := <-sub:
		if s.Config.Bots.TargetActiveBots != 20 {
			t.Fatal("subscriber got wrong snapshot")
		}
	default:
		t.Fatal("subscriber not notified")
	}

	writeFile(t, cfgPath, "bots: {think_time: {min_ms: 9, max_ms: 1}}")
	if err := w.Reload("test"); err == nil {
		t.Fatal("invalid config accepted")
	}
	writeFile(t, profPath, "profiles: {}")
	if err := w.Reload("test"); err == nil {
		t.Fatal("invalid profiles accepted")
	}
	writeFile(t, profPath, profilesYAML)
	writeFile(t, cfgPath, "app: {environment: preprod}")
	if err := w.Reload("test"); err == nil || !strings.Contains(err.Error(), "restart required") {
		t.Fatalf("environment change must be rejected at runtime: %v", err)
	}
	if store.Config().Bots.TargetActiveBots != 20 || store.Load().Generation != 2 {
		t.Fatal("last valid config not kept")
	}
	if fmt.Sprint(results) != "[true false false false]" {
		t.Fatalf("results = %v", results)
	}
	if !strings.Contains(logs.String(), "keeping last valid configuration") {
		t.Fatalf("rollback not logged: %s", logs.String())
	}

	// mtime polling and SIGHUP.
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	hup := make(chan os.Signal, 1)
	writeFile(t, cfgPath, "app: {reload_poll_seconds: 1}\nbots: {target_active_bots: 20}")
	_ = w.Reload("reset")
	go w.Run(ctx, hup)
	time.Sleep(50 * time.Millisecond)
	writeFile(t, cfgPath, "app: {reload_poll_seconds: 1}\nbots: {target_active_bots: 30, max_concurrent_bots: 100}  ")
	deadline := time.Now().Add(5 * time.Second)
	for store.Config().Bots.TargetActiveBots != 30 && time.Now().Before(deadline) {
		time.Sleep(50 * time.Millisecond)
	}
	if store.Config().Bots.TargetActiveBots != 30 {
		t.Fatal("mtime change not picked up")
	}
	gen := store.Load().Generation
	hup <- syscall.SIGHUP
	deadline = time.Now().Add(3 * time.Second)
	for store.Load().Generation == gen && time.Now().Before(deadline) {
		time.Sleep(20 * time.Millisecond)
	}
	if store.Load().Generation == gen {
		t.Fatal("SIGHUP did not reload")
	}
}

func TestGameKeys(t *testing.T) {
	if GameKey("ludo", "classic") != GameLudo || GameKey("ludo", "quick") != GameLudoQuick || GameKey("snakes_ladders", "classic") != GameSnakes || GameKey("chess", "") != "" {
		t.Fatal("GameKey mapping")
	}
	for _, k := range GameKeys {
		g, v := GameVariant(k)
		if GameKey(g, v) != k {
			t.Fatalf("round trip %s", k)
		}
	}
	v, b := ClientVersion()
	if v == "" || b == "" {
		t.Fatal("client version")
	}
}
