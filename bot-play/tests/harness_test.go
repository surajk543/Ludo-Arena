package tests

import (
	"bytes"
	"context"
	"log/slog"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	dto "github.com/prometheus/client_model/go"
	"go.yaml.in/yaml/v3"

	"ludoarena/botplay/internal/client"
	"ludoarena/botplay/internal/config"
	"ludoarena/botplay/internal/metrics"
	"ludoarena/botplay/internal/runner"
	"ludoarena/botplay/tests/fakebackend"
)

const testServiceKey = "test-service-key-0123456789abcdefghijklmnop"

// syncBuffer is a goroutine-safe log sink.
type syncBuffer struct {
	mu  sync.Mutex
	buf bytes.Buffer
}

func (b *syncBuffer) Write(p []byte) (int, error) {
	b.mu.Lock()
	defer b.mu.Unlock()
	return b.buf.Write(p)
}

func (b *syncBuffer) String() string {
	b.mu.Lock()
	defer b.mu.Unlock()
	return b.buf.String()
}

type harness struct {
	t       *testing.T
	fake    *fakebackend.Server
	dir     string
	cfgPath string
	prof    string
	store   *config.Store
	m       *metrics.Metrics
	svc     *runner.Service
	logs    *syncBuffer
	watcher *config.Watcher
	cancel  context.CancelFunc
	done    chan error
	ack     bool
}

// testConfig returns fast, deterministic settings pointing at the fake.
func testConfig(f *fakebackend.Server) *config.Config {
	c := config.Default()
	c.App.ReloadPollSeconds = 0
	c.App.LogLevel = "debug"
	c.Connection.BackendHTTPURL = f.HTTPURL()
	c.Connection.BackendWSURL = f.WSURL()
	c.Connection.ConnectTimeoutMS = 2000
	c.Connection.RequestTimeoutMS = 2000
	c.Connection.AssignmentWaitSeconds = 1
	c.Connection.ReconnectBackoffBaseMS = 20
	c.Connection.ReconnectBackoffMaxMS = 200
	c.Connection.ReconnectResetSeconds = 1
	c.Connection.MaintenanceBackoffSeconds = 1
	c.Connection.ActionConfirmTimeoutMS = 1500
	c.Bots.Modes = []string{config.ModePractice}
	c.Bots.TargetActiveBots = 10
	c.Bots.MaxConcurrentBots = 10
	c.Bots.MaxRoomJoinsPerSecond = 100
	c.Bots.MaxConnectionAttemptsPerSecond = 100
	c.Bots.LobbyWaitTimeoutSeconds = 30
	c.Bots.ThinkTime = config.ThinkTimeConfig{MinMS: 0, MaxMS: 3, Randomize: true}
	c.Bots.Behavior.RandomSeed = 7
	c.Bots.Shutdown.GracefulTimeoutSeconds = 10
	c.Limits.MaxActionsPerSecondPerBot = 20
	c.Limits.MaxReconnectAttemptsPerMinute = 120
	c.Loadtest.AllowedHosts = []string{"127.0.0.1", "localhost"}
	c.Loadtest.ThinkTimeMS = config.RangeMS{Min: 0, Max: 3}
	c.Metrics.Enabled = false
	return c
}

func newFake(t *testing.T, o fakebackend.Options) *fakebackend.Server {
	t.Helper()
	if o.ServiceKey == "" {
		o.ServiceKey = testServiceKey
	}
	f := fakebackend.New(o)
	t.Cleanup(f.Close)
	return f
}

func writeConfig(t *testing.T, path string, c *config.Config) {
	t.Helper()
	b, err := yaml.Marshal(c)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, b, 0o600); err != nil {
		t.Fatal(err)
	}
}

// newHarness builds (but does not start) a service against the fake.
func newHarness(t *testing.T, f *fakebackend.Server, mutate func(*config.Config)) *harness {
	t.Helper()
	dir := t.TempDir()
	h := &harness{t: t, fake: f, dir: dir, cfgPath: filepath.Join(dir, "config.yaml"), prof: filepath.Join(dir, "profiles.yaml"), logs: &syncBuffer{}, ack: true}
	c := testConfig(f)
	if mutate != nil {
		mutate(c)
	}
	writeConfig(t, h.cfgPath, c)
	pb, err := os.ReadFile(filepath.Join("..", "configs", "profiles.yaml"))
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(h.prof, pb, 0o600); err != nil {
		t.Fatal(err)
	}
	snap, err := config.LoadFiles(h.cfgPath, h.prof)
	if err != nil {
		t.Fatalf("config: %v", err)
	}
	h.store = config.NewStore(snap)
	h.m = metrics.New()
	logger := slog.New(slog.NewJSONHandler(h.logs, &slog.HandlerOptions{Level: slog.LevelDebug, ReplaceAttr: config.RedactAttr}))
	cl, err := client.New(client.Options{BaseURL: f.HTTPURL(), ServiceKey: config.NewSecret(testServiceKey), RequestTimeout: 2 * time.Second, UserAgent: "bot-play/test"})
	if err != nil {
		t.Fatal(err)
	}
	h.watcher = &config.Watcher{ConfigPath: h.cfgPath, ProfilesPath: h.prof, Store: h.store, Logger: logger, OnResult: h.m.RecordConfigReload}
	h.svc = runner.New(runner.Options{Store: h.store, Client: cl, Metrics: h.m, Logger: logger, LoadtestAcknowledged: true})
	t.Cleanup(func() {
		if t.Failed() {
			logs := h.logs.String()
			if p := os.Getenv("BOTPLAY_TEST_LOGS"); p != "" {
				_ = os.WriteFile(p, []byte(logs), 0o600)
			}
			if len(logs) > 20000 {
				logs = logs[len(logs)-20000:]
			}
			t.Logf("bot-play logs (tail):\n%s", logs)
		}
	})
	return h
}

func (h *harness) start() {
	ctx, cancel := context.WithCancel(context.Background())
	h.cancel = cancel
	h.done = make(chan error, 1)
	go func() { h.done <- h.svc.Run(ctx) }()
	h.t.Cleanup(func() {
		cancel()
		select {
		case <-h.done:
		case <-time.After(30 * time.Second):
			h.t.Errorf("service did not stop")
		}
	})
}

// stop cancels the service and returns Run's error.
func (h *harness) stop(timeout time.Duration) error {
	h.cancel()
	select {
	case err := <-h.done:
		h.done <- err // keep for cleanup
		return err
	case <-time.After(timeout):
		h.t.Fatalf("service did not stop within %v", timeout)
		return nil
	}
}

func (h *harness) reload(mutate func(*config.Config)) error {
	cp := deepCopy(h.t, h.store.Config())
	mutate(cp)
	writeConfig(h.t, h.cfgPath, cp)
	return h.watcher.Reload("test")
}

func deepCopy(t *testing.T, c *config.Config) *config.Config {
	b, err := yaml.Marshal(c)
	if err != nil {
		t.Fatal(err)
	}
	out := config.Default()
	if err := yaml.Unmarshal(b, out); err != nil {
		t.Fatal(err)
	}
	return out
}

func waitFor(t *testing.T, timeout time.Duration, what string, cond func() bool) {
	t.Helper()
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		if cond() {
			return
		}
		time.Sleep(10 * time.Millisecond)
	}
	t.Fatalf("timed out after %v waiting for %s", timeout, what)
}

// metricValue sums a metric family's samples whose labels include all of want.
func (h *harness) metricValue(name string, want map[string]string) float64 {
	mfs, err := h.m.Registry.Gather()
	if err != nil {
		h.t.Fatal(err)
	}
	total := 0.0
	for _, mf := range mfs {
		if mf.GetName() != name {
			continue
		}
		for _, m := range mf.GetMetric() {
			if !labelsMatch(m, want) {
				continue
			}
			switch {
			case m.Counter != nil:
				total += m.Counter.GetValue()
			case m.Gauge != nil:
				total += m.Gauge.GetValue()
			case m.Histogram != nil:
				total += float64(m.Histogram.GetSampleCount())
			}
		}
	}
	return total
}

func labelsMatch(m *dto.Metric, want map[string]string) bool {
	for k, v := range want {
		found := false
		for _, lp := range m.GetLabel() {
			if lp.GetName() == k && lp.GetValue() == v {
				found = true
			}
		}
		if !found {
			return false
		}
	}
	return true
}

func roomFinished(f *fakebackend.Server, id string) func() bool {
	return func() bool {
		r, ok := f.Room(id)
		return ok && r.Finished
	}
}

func botUIDs(f *fakebackend.Server, roomID string) []string {
	r, _ := f.Room(roomID)
	var out []string
	for _, p := range r.Players {
		if p.Bot {
			out = append(out, p.UID)
		}
	}
	return out
}

func contains(xs []string, v string) bool {
	for _, x := range xs {
		if x == v {
			return true
		}
	}
	return false
}

func countMsgs(msgs []string, typ string) int {
	n := 0
	for _, m := range msgs {
		if strings.Contains(m, `"t":"`+typ+`"`) {
			n++
		}
	}
	return n
}

// nearHome puts every token of every seat close to home so games end fast.
func nearHome(seats int) [][]int {
	out := make([][]int, seats)
	for i := range out {
		out[i] = []int{50, 51, 52, 53}
	}
	return out
}
