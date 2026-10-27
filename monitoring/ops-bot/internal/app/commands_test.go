package app

import (
	"bytes"
	"context"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"ludoarena/opsbot/internal/backendapi"
	"ludoarena/opsbot/internal/promapi"
	"ludoarena/opsbot/internal/promapi/promtest"
	"ludoarena/opsbot/internal/schedule"
	"ludoarena/opsbot/internal/telegram"
)

// waitFor waits until rec holds n deliveries (and a little longer, so extra
// deliveries are caught too).
func waitFor(t *testing.T, rec *recSender, n int) []sent {
	t.Helper()
	deadline := time.Now().Add(20 * time.Second)
	for len(rec.all()) < n && time.Now().Before(deadline) {
		time.Sleep(5 * time.Millisecond)
	}
	time.Sleep(50 * time.Millisecond)
	return rec.all()
}

type fakeBackend struct{}

func (fakeBackend) Online(_ context.Context, limit int) (backendapi.Online, error) {
	joined := time.Date(2026, 10, 2, 9, 0, 0, 0, time.UTC)
	return backendapi.Online{Total: 3, Counts: map[string]int{"ludo": 1, "snakes_ladders": 1, "lobby": 1},
		Users: []backendapi.OnlineUser{
			{UID: "u_AAAAAAAAAAAA", Name: "Asha", CreatedAt: &joined, Activity: "ludo", Game: "ludo", Mode: "public"},
			{UID: "u_BBBBBBBBBBBB", Name: "Bilal", Activity: "snakes_ladders", Game: "snakes_ladders", Mode: "practice"},
			{UID: "u_CCCCCCCCCCCC", Name: "Dewi", Activity: "lobby"},
		}}, nil
}

func (fakeBackend) Playtime(_ context.Context, hours, limit int) (backendapi.Playtime, error) {
	return backendapi.Playtime{Hours: hours, Games: []backendapi.GamePlaytime{
		{Game: "ludo", Seconds: 7200, Players: 2, Top: []backendapi.PlayerSeconds{{UID: "u_AAAAAAAAAAAA", Name: "Asha", Seconds: 5400}}},
		{Game: "snakes_ladders", Seconds: 600, Players: 1, Top: []backendapi.PlayerSeconds{{UID: "u_BBBBBBBBBBBB", Name: "Bilal", Seconds: 600}}},
	}}, nil
}

// actionSender records chat actions too (like the Telegram client).
type actionSender struct {
	recSender
	actions atomic.Int32
}

func (s *actionSender) SendChatAction(_ context.Context, chat, action string) error {
	if action == telegram.ActionUploadDocument {
		s.actions.Add(1)
	}
	return nil
}

func update(chat int64, text string, channel bool) telegram.Update {
	m := &telegram.Message{Chat: telegram.Chat{ID: chat}, Text: text}
	if channel {
		return telegram.Update{UpdateID: 1, ChannelPost: m}
	}
	return telegram.Update{UpdateID: 1, Message: m}
}

func TestOnDemandReports(t *testing.T) {
	prom := promtest.New(
		promtest.Rule{Match: `up{job="backend"}`, Vector: []promapi.Sample{S(1, "instance", "b1:9090")}},
		promtest.Rule{Match: "node_cpu_seconds_total", Vector: []promapi.Sample{S(41, "instance", "h1:9100")}},
		promtest.Rule{Match: "node_memory", Vector: []promapi.Sample{S(63, "instance", "h1:9100")}},
	)
	defer prom.Close()
	rec := &actionSender{}
	a := newApp(t, nil, prom, rec)
	a.Collector.Backend = fakeBackend{}
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	go a.RunReports(ctx)

	a.HandleUpdate(ctx, update(111, "/live", true)) // a channel post
	a.HandleUpdate(ctx, update(111, "/playtime", false))
	a.HandleUpdate(ctx, update(222, "/metrics@LudoOpsBot", false))
	out := waitFor(t, &rec.recSender, 3)
	if len(out) != 3 {
		t.Fatalf("deliveries = %+v", out)
	}
	want := []struct{ chat, file, caption string }{
		{"111", "ludo-arena-live-2026-10-21-1700-IST.pdf", "staging · 3 online · Ludo 1 · S&amp;L 1 · lobby 1 · peak n/a"},
		{"111", "ludo-arena-playtime-2026-10-21-1700-IST.pdf", "staging · last 24 h · Ludo 120 min (2 players) · S&amp;L 10 min (1 player)"},
		{"222", "ludo-arena-metrics-2026-10-21-1700-IST.pdf", "staging · PostgreSQL n/a"},
	}
	for i, w := range want {
		got := out[i]
		if got.chat != w.chat || got.file != w.file || !bytes.HasPrefix(got.data, []byte("%PDF-")) {
			t.Errorf("delivery %d = %s %s (%d bytes)", i, got.chat, got.file, len(got.data))
		}
		if !strings.HasPrefix(got.caption, w.caption) {
			t.Errorf("caption %d = %q, want prefix %q", i, got.caption, w.caption)
		}
	}
	if rec.actions.Load() < 3 {
		t.Errorf("chat actions = %d, want one per report at least", rec.actions.Load())
	}
	for _, cmd := range []string{"live", "playtime", "metrics"} {
		if a.Metrics.Commands.Value(cmd, "sent") != 1 {
			t.Errorf("%s sent metric = %v", cmd, a.Metrics.Commands.Value(cmd, "sent"))
		}
	}
}

func TestChannelConfiguredByUsername(t *testing.T) {
	prom := fakeProm()
	defer prom.Close()
	rec := &recSender{}
	a := newApp(t, map[string]string{"TELEGRAM_CHAT_IDS": "111,@LudoOps"}, prom, rec)
	post := func(id int64, user string) telegram.Update {
		return telegram.Update{UpdateID: 1, ChannelPost: &telegram.Message{Chat: telegram.Chat{ID: id, Type: "channel", Username: user}, Text: "/help"}}
	}
	a.HandleUpdate(context.Background(), post(-1001, "ludoops")) // usernames are case-insensitive
	a.HandleUpdate(context.Background(), post(-1002, "someoneelse"))
	a.HandleUpdate(context.Background(), post(-1003, ""))
	if out := rec.all(); len(out) != 1 || out[0].chat != "-1001" || out[0].text != HelpText {
		t.Fatalf("replies = %+v", out)
	}
}

func TestRepeatedCommandsAreDropped(t *testing.T) {
	prom := fakeProm()
	defer prom.Close()
	rec := &recSender{}
	a := newApp(t, map[string]string{"REPORT_FORMAT": "text"}, prom, rec)
	clock := a.Clock.(*schedule.Fake)
	ctx := context.Background()
	a.HandleUpdate(ctx, update(111, "/status", false))
	a.HandleUpdate(ctx, update(111, "/status", false))           // same chat, same command: dropped
	a.HandleUpdate(ctx, update(111, "/status@LudoOpsBot", true)) // still the same request
	a.HandleUpdate(ctx, update(222, "/status", false))           // another chat
	a.HandleUpdate(ctx, update(111, "/daily", false))            // another command
	clock.Advance(29 * time.Second)
	a.HandleUpdate(ctx, update(111, "/digest", false)) // alias of /daily within 30 s: dropped
	clock.Advance(time.Second)
	a.HandleUpdate(ctx, update(111, "/status", false)) // 30 s later: accepted again
	if got := len(a.jobs); got != 4 {
		t.Fatalf("queued = %d, want 4", got)
	}
	if d := a.Metrics.Commands.Value("status", "duplicate") + a.Metrics.Commands.Value("digest", "duplicate"); d != 3 {
		t.Errorf("duplicates = %v, want 3", d)
	}

	// A fifth distinct command does not fit in the queue.
	a.HandleUpdate(ctx, update(222, "/live", false))
	out := rec.all()
	if len(out) != 1 || out[0].chat != "222" || !strings.Contains(out[0].text, "/live not started") {
		t.Fatalf("busy reply = %+v", out)
	}
	if a.Metrics.Commands.Value("live", "busy") != 1 {
		t.Errorf("busy metric = %v", a.Metrics.Commands.Value("live", "busy"))
	}
}

func TestDedupeDisabled(t *testing.T) {
	prom := fakeProm()
	defer prom.Close()
	a := newApp(t, map[string]string{"COMMAND_DEDUPE_WINDOW": "0"}, prom, &recSender{})
	a.HandleUpdate(context.Background(), update(111, "/status", false))
	a.HandleUpdate(context.Background(), update(111, "/status", false))
	if len(a.jobs) != 2 {
		t.Errorf("queued = %d, want 2 with COMMAND_DEDUPE_WINDOW=0", len(a.jobs))
	}
}

// TestReportTimeout: a generation that overruns is cancelled and its late
// result discarded; the next report waits until it has really returned, so
// two generations never overlap, scheduled reports included.
func TestReportTimeout(t *testing.T) {
	prom := fakeProm()
	defer prom.Close()
	rec := &recSender{}
	a := newApp(t, map[string]string{"REPORT_FORMAT": "text"}, prom, rec)
	a.Cfg.CommandTimeout = 150 * time.Millisecond
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	go a.RunReports(ctx)

	var running, maxRunning atomic.Int32
	track := func() func() {
		n := running.Add(1)
		for {
			m := maxRunning.Load()
			if n <= m || maxRunning.CompareAndSwap(m, n) {
				break
			}
		}
		return func() { running.Add(-1) }
	}
	var stubbornDone atomic.Bool
	// Ignores cancellation and finishes 300 ms after its deadline.
	stubborn := func(ctx context.Context) (rendered, error) {
		defer track()()
		<-ctx.Done()
		time.Sleep(300 * time.Millisecond)
		stubbornDone.Store(true)
		return rendered{name: "late.pdf", doc: []byte("%PDF-late")}, nil
	}
	quick := func(ctx context.Context) (rendered, error) {
		defer track()()
		if !stubbornDone.Load() {
			t.Error("the next report started before the cancelled one returned")
		}
		return rendered{text: "quick report"}, nil
	}
	a.submit(ctx, "live", "111", stubborn)
	a.submit(ctx, "metrics", "111", quick)
	var wg sync.WaitGroup
	wg.Go(func() { // a scheduled report competes for the same lock
		time.Sleep(20 * time.Millisecond)
		if err := a.SendStatus(ctx, "status", []string{"222"}); err != nil {
			t.Error(err)
		}
	})
	out := waitFor(t, rec, 3)
	wg.Wait()
	var timeoutMsg, quickMsg, status int
	for _, o := range out {
		switch {
		case o.file == "late.pdf":
			t.Error("the late report was sent")
		case strings.Contains(o.text, "/live was cancelled") && strings.Contains(o.text, "150ms"):
			timeoutMsg++
		case o.text == "quick report":
			quickMsg++
		case o.chat == "222" && strings.Contains(o.text, "hourly status"):
			status++
		}
	}
	if timeoutMsg != 1 || quickMsg != 1 || status != 1 {
		t.Fatalf("deliveries = %+v", out)
	}
	if maxRunning.Load() != 1 {
		t.Errorf("concurrent generations = %d, want 1", maxRunning.Load())
	}
	if a.Metrics.Commands.Value("live", "timeout") != 1 || a.Metrics.Commands.Value("metrics", "sent") != 1 {
		t.Errorf("metrics: timeout %v, sent %v", a.Metrics.Commands.Value("live", "timeout"), a.Metrics.Commands.Value("metrics", "sent"))
	}
}

// TestCommandLoopDoesNotWait: polling continues while a report is generated.
func TestCommandLoopDoesNotWait(t *testing.T) {
	prom := fakeProm()
	defer prom.Close()
	rec := &recSender{}
	a := newApp(t, nil, prom, rec)
	release := make(chan struct{})
	a.submit(context.Background(), "live", "111", func(ctx context.Context) (rendered, error) {
		<-release
		return rendered{text: "x"}, nil
	})
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	go a.RunReports(ctx)
	start := time.Now()
	a.HandleUpdate(ctx, update(111, "/status", false)) // queued behind the blocked report
	a.HandleUpdate(ctx, update(111, "/help", false))
	if d := time.Since(start); d > time.Second {
		t.Errorf("HandleUpdate blocked for %v", d)
	}
	if out := rec.all(); len(out) != 1 || out[0].text != HelpText {
		t.Errorf("help reply = %+v", out)
	}
	close(release)
}
