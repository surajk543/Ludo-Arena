package tests

import (
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"os"
	"path/filepath"
	"testing"
	"time"

	"ludoroyale/botplay/internal/client"
	"ludoroyale/botplay/internal/config"
	"ludoroyale/botplay/internal/metrics"
	"ludoroyale/botplay/internal/runner"
	"ludoroyale/botplay/tests/fakebackend"
)

func loadtestConfig(c *config.Config, report string) {
	c.Bots.Modes = []string{config.ModeLoadtest}
	c.Bots.MaxConcurrentBots = 8
	c.Bots.TargetActiveBots = 8 // unused in loadtest mode (loadtest.target_connections applies)
	c.Bots.LobbyWaitTimeoutSeconds = 10
	c.Loadtest.Enabled = true
	c.Loadtest.TargetConnections = 6
	c.Loadtest.RampPerSecond = 50
	c.Loadtest.DurationSeconds = 8
	c.Loadtest.GameMix = map[string]float64{config.GameSnakes: 1}
	c.Loadtest.CapacityMix = map[int]float64{2: 1}
	c.Loadtest.ReportPath = report
}

func guardReason(err error) string {
	var ge *config.GuardError
	if errors.As(err, &ge) {
		return ge.Reason
	}
	if err == nil {
		return "<nil>"
	}
	return err.Error()
}

// runOnce runs a service built from cfg until it returns (or times out).
func runOnce(t *testing.T, f *fakebackend.Server, mutate func(*config.Config), ack bool) error {
	t.Helper()
	c := testConfig(f)
	mutate(c)
	if err := c.Validate(); err != nil {
		return err
	}
	ps, err := config.LoadFiles(writeTemp(t, c), filepath.Join("..", "configs", "profiles.yaml"))
	if err != nil {
		return err
	}
	cl, _ := client.New(client.Options{BaseURL: f.HTTPURL(), ServiceKey: config.NewSecret(testServiceKey)})
	svc := runner.New(runner.Options{Store: config.NewStore(ps), Client: cl, Metrics: metrics.New(),
		Logger: slog.New(slog.NewTextHandler(&syncBuffer{}, nil)), LoadtestAcknowledged: ack})
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	return svc.Run(ctx)
}

func writeTemp(t *testing.T, c *config.Config) string {
	p := filepath.Join(t.TempDir(), "c.yaml")
	writeConfig(t, p, c)
	return p
}

// Every load-test refusal path: no CLI acknowledgement, host not allowed,
// forbidden host, production environment, disabled, and the backend's own
// refusal (APP_ENV=production / BOT_LOADTEST_ENABLED=false).
func TestLoadtestGuardRefusals(t *testing.T) {
	t.Parallel()
	f := newFake(t, fakebackend.Options{AllowLoadtest: false})
	report := filepath.Join(t.TempDir(), "r.json")
	base := func(c *config.Config) { loadtestConfig(c, report) }

	if r := guardReason(runOnce(t, f, base, false)); r != config.GuardNoAck {
		t.Errorf("no ack: %s", r)
	}
	if r := guardReason(runOnce(t, f, func(c *config.Config) { base(c); c.Loadtest.AllowedHosts = []string{"preprod.example"} }, true)); r != config.GuardHostNotAllowed {
		t.Errorf("host not allowed: %s", r)
	}
	if r := guardReason(runOnce(t, f, func(c *config.Config) { base(c); c.Loadtest.ForbiddenHosts = []string{"127.0.0.1"} }, true)); r != config.GuardForbiddenHost {
		t.Errorf("forbidden host: %s", r)
	}
	if err := runOnce(t, f, func(c *config.Config) { base(c); c.App.Environment = config.EnvProduction }, true); err == nil {
		t.Error("production load test must be rejected")
	}
	if err := runOnce(t, f, func(c *config.Config) { base(c); c.Loadtest.Enabled = false }, true); err == nil {
		t.Error("loadtest mode without loadtest.enabled must be rejected")
	}
	start := time.Now()
	err := runOnce(t, f, base, true)
	if r := guardReason(err); r != config.GuardBackendRefused {
		t.Fatalf("backend refusal: %v", err)
	}
	if time.Since(start) > 15*time.Second {
		t.Fatal("backend refusal should stop the run promptly")
	}
	for _, b := range f.SessionBodies() {
		if b["mode"] != "loadtest" {
			t.Fatalf("unexpected session body %v", b)
		}
	}
}

// Load test: ramps to target, never exceeds max_concurrent, plays games via
// matchmaking.join, survives churn / malformed messages / slow readers,
// scales down on reload and writes the JSON report.
func TestLoadtestPopulationChurnAndReport(t *testing.T) {
	t.Parallel()
	f := newFake(t, fakebackend.Options{AllowLoadtest: true, LobbyFillDeadline: 200 * time.Millisecond})
	report := filepath.Join(t.TempDir(), "report.json")
	h := newHarness(t, f, func(c *config.Config) {
		loadtestConfig(c, report)
		c.Loadtest.ChurnPerMinute = 120
		c.Loadtest.MalformedMessageRate = 0.05
		c.Loadtest.SlowReaderFraction = 0.3
		c.Loadtest.SlowReaderDelayMS = 2
	})
	stop := make(chan struct{})
	defer close(stop)
	peak := watchPeak(h, stop)
	h.start()
	waitFor(t, 5*time.Second, "ramp to target", func() bool { return h.svc.Count() == 6 })
	waitFor(t, 10*time.Second, "games finished", func() bool {
		return h.metricValue("games_finished_total", map[string]string{"game": "snakes_ladders"}) >= 3
	})
	if err := h.reload(func(c *config.Config) { c.Loadtest.TargetConnections = 2 }); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		if t.Failed() {
			t.Logf("fake rooms:\n%s", f.DebugRooms())
		}
	})
	waitFor(t, 10*time.Second, "scale down", func() bool { return h.svc.Count() <= 2 })
	if peak.Load() > 8 {
		t.Fatalf("peak %d > max_concurrent 8", peak.Load())
	}
	select {
	case err := <-h.done:
		h.done <- err
		if err != nil {
			t.Fatalf("run: %v", err)
		}
	case <-time.After(30 * time.Second):
		t.Fatal("load test did not end after duration_seconds")
	}
	b, err := os.ReadFile(report)
	if err != nil {
		t.Fatalf("report: %v", err)
	}
	var r metrics.Report
	if err := json.Unmarshal(b, &r); err != nil {
		t.Fatal(err)
	}
	if r.PeakConnections < 6 || r.PeakConnections > 8 || r.TargetConnections != 6 || r.SuccessfulSessions < 6 {
		t.Fatalf("population in report: %+v", r)
	}
	if r.GamesFinished["snakes_ladders"] < 3 || r.GamesStarted["snakes_ladders"] < r.GamesFinished["snakes_ladders"] {
		t.Fatalf("games: %+v / %+v", r.GamesStarted, r.GamesFinished)
	}
	if r.HashMismatches != 0 {
		t.Fatalf("hash mismatches: %d", r.HashMismatches)
	}
	if r.ActionsTotal == 0 || r.ActionsPerSecond <= 0 || r.LatencyMS["roll"].Count == 0 || r.LatencyMS["roll"].P99 < r.LatencyMS["roll"].P50 {
		t.Fatalf("actions/latency: %+v %+v", r.ActionsByType, r.LatencyMS)
	}
	if r.ReconnectAttempts == 0 || r.ReconnectRate <= 0 {
		t.Fatalf("churn reconnects: attempts=%d rate=%v", r.ReconnectAttempts, r.ReconnectRate)
	}
	if r.BytesReceived == 0 || r.Compression["negotiated"] == 0 || r.DurationSeconds < 8 {
		t.Fatalf("bytes/compression/duration: %+v", r)
	}
	sent := 0
	for _, n := range r.MalformedSent {
		sent += int(n)
	}
	if sent == 0 || r.ErrorsByCode["bad_request"]+r.ErrorsByCode["unknown_type"] == 0 {
		t.Fatalf("malformed injection not exercised: sent=%v errors=%v", r.MalformedSent, r.ErrorsByCode)
	}
	if h.metricValue("matchmaking_join_attempts_total", nil) == 0 {
		t.Fatal("no matchmaking joins")
	}
	if len(f.Revoked()) < 6 {
		t.Fatalf("sessions not revoked: %d", len(f.Revoked()))
	}
}
