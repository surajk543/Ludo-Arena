package app

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"log/slog"
	"mime"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"

	"ludoarena/opsbot/internal/alertmanager"
	"ludoarena/opsbot/internal/config"
	"ludoarena/opsbot/internal/promapi"
	"ludoarena/opsbot/internal/promapi/promtest"
	"ludoarena/opsbot/internal/report"
	"ludoarena/opsbot/internal/schedule"
	"ludoarena/opsbot/internal/telegram"
)

type sent struct {
	chat, text, file, caption string
	data                      []byte
}

type recSender struct {
	mu  sync.Mutex
	out []sent
}

func (r *recSender) SendMessage(_ context.Context, chat, html string) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.out = append(r.out, sent{chat: chat, text: html})
	return nil
}

func (r *recSender) SendDocument(_ context.Context, chat, file string, data []byte, caption string) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.out = append(r.out, sent{chat: chat, file: file, data: data, caption: caption})
	return nil
}

func (r *recSender) all() []sent {
	r.mu.Lock()
	defer r.mu.Unlock()
	return append([]sent(nil), r.out...)
}

var S = promtest.S

func fakeProm() *promtest.Server {
	return promtest.New(
		promtest.Rule{Match: `up{job="backend"}`, Vector: []promapi.Sample{S(1, "instance", "b1:9090")}},
		promtest.Rule{Match: "players_in_game", Vector: []promapi.Sample{S(1234, "actor", "human"), S(456, "actor", "bot")}},
		promtest.Rule{Match: "node_cpu_seconds_total", Vector: []promapi.Sample{S(41, "instance", "h1:9100")}},
		promtest.Rule{Match: "node_memory", Vector: []promapi.Sample{S(63, "instance", "h1:9100")}},
	)
}

func newApp(t *testing.T, env map[string]string, prom *promtest.Server, sender Sender) *App {
	t.Helper()
	base := map[string]string{"TELEGRAM_DRY_RUN": "true", "TELEGRAM_CHAT_IDS": "111,222", "ENV_NAME": "staging"}
	for k, v := range env {
		base[k] = v
	}
	cfg, err := config.Load(func(k string) string { return base[k] })
	if err != nil {
		t.Fatal(err)
	}
	now := time.Date(2026, 10, 21, 17, 0, 0, 0, cfg.Location)
	clock := schedule.NewFake(now)
	return &App{
		Cfg:    cfg,
		Sender: sender,
		Collector: &report.Collector{Prom: promapi.New(prom.URL, 5*time.Second), Q: report.Queries{Backend: "backend", BotPlay: "bot-play", Node: "node"},
			Loc: cfg.Location, Now: clock.Now, TrendDays: cfg.TrendDays},
		Metrics: NewMetrics(),
		Log:     slog.New(slog.NewTextHandler(io.Discard, nil)),
		Clock:   clock,
	}
}

func TestReportFormatSwitch(t *testing.T) {
	prom := fakeProm()
	defer prom.Close()
	for _, format := range []string{"pdf", "text"} {
		t.Run(format, func(t *testing.T) {
			rec := &recSender{}
			a := newApp(t, map[string]string{"REPORT_FORMAT": format}, prom, rec)
			if err := a.SendStatus(context.Background(), "status", a.Cfg.TelegramChatIDs); err != nil {
				t.Fatal(err)
			}
			if err := a.SendDigest(context.Background(), "digest", report.Yesterday(a.Clock.Now(), a.Cfg.Location), a.Cfg.TelegramChatIDs); err != nil {
				t.Fatal(err)
			}
			out := rec.all()
			if len(out) != 4 || out[0].chat != "111" || out[1].chat != "222" {
				t.Fatalf("deliveries = %+v", out)
			}
			status, digest := out[0], out[2]
			if format == "pdf" {
				if status.file != "ludo-arena-status-2026-10-21-1700-IST.pdf" || !bytes.HasPrefix(status.data, []byte("%PDF-")) {
					t.Errorf("status document = %q (%d bytes)", status.file, len(status.data))
				}
				if status.caption != "staging · Playing: 1,234 players · 456 bots · CPU 41% · RAM 63%" {
					t.Errorf("status caption = %q", status.caption)
				}
				if digest.file != "ludo-arena-daily-2026-10-20.pdf" || !bytes.HasPrefix(digest.data, []byte("%PDF-")) || !strings.HasPrefix(digest.caption, "staging · 20 Oct:") {
					t.Errorf("digest document = %q caption %q", digest.file, digest.caption)
				}
			} else {
				if status.file != "" || !strings.Contains(status.text, "hourly status") || !strings.Contains(status.text, "Real players 1,234 · Bots 456") {
					t.Errorf("status text = %q", status.text)
				}
				if !strings.Contains(digest.text, "daily KPIs") || !strings.Contains(digest.text, "not configured (set PLAY_REPORTS_BUCKET)") {
					t.Errorf("digest text = %q", digest.text)
				}
			}
			if got := a.Metrics.Sent.Value("status", "sent"); got != 2 {
				t.Errorf("sent metric = %v", got)
			}
		})
	}
}

func alertPayload(status string) alertmanager.Payload {
	return alertmanager.Payload{Status: status, Alerts: []alertmanager.Alert{{
		Status:      status,
		Labels:      map[string]string{"alertname": "HostCPUHigh", "severity": "critical", "instance": "h1:9100"},
		Annotations: map[string]string{"summary": "CPU usage on h1:9100 is 92%"},
		StartsAt:    time.Date(2026, 10, 21, 11, 18, 0, 0, time.UTC),
		Fingerprint: "fp1",
	}}}
}

func TestAlertFormatSwitchAndDedupe(t *testing.T) {
	prom := fakeProm()
	defer prom.Close()
	t.Run("text", func(t *testing.T) {
		rec := &recSender{}
		a := newApp(t, nil, prom, rec)
		ctx := context.Background()
		if err := a.DeliverAlerts(ctx, alertPayload("firing")); err != nil {
			t.Fatal(err)
		}
		_ = a.DeliverAlerts(ctx, alertPayload("firing")) // duplicate inside the window
		_ = a.DeliverAlerts(ctx, alertPayload("resolved"))
		out := rec.all()
		if len(out) != 4 {
			t.Fatalf("deliveries = %d, want 4 (2 chats × firing + resolved)", len(out))
		}
		if !strings.Contains(out[0].text, "🔴 <b>FIRING</b> · critical · HostCPUHigh") ||
			!strings.Contains(out[0].text, "<b>Now</b> CPU 41% · RAM 63%") ||
			!strings.Contains(out[0].text, "Playing: real 1,234 · bots 456") {
			t.Errorf("alert text = %q", out[0].text)
		}
		if !strings.Contains(out[2].text, "RESOLVED") {
			t.Errorf("resolved text = %q", out[2].text)
		}
		if a.Metrics.Deduplicated.Value() != 1 {
			t.Errorf("deduplicated = %v", a.Metrics.Deduplicated.Value())
		}
	})
	t.Run("pdf", func(t *testing.T) {
		rec := &recSender{}
		a := newApp(t, map[string]string{"ALERT_FORMAT": "pdf"}, prom, rec)
		if err := a.DeliverAlerts(context.Background(), alertPayload("firing")); err != nil {
			t.Fatal(err)
		}
		out := rec.all()
		if len(out) != 2 || out[0].file != "ludo-arena-alert-HostCPUHigh-2026-10-21-1700-IST.pdf" ||
			!bytes.HasPrefix(out[0].data, []byte("%PDF-")) || out[0].caption != "staging · FIRING: HostCPUHigh · 17:00 IST" {
			t.Errorf("pdf alert = %+v", out)
		}
	})
}

func TestWebhookToWorker(t *testing.T) {
	prom := fakeProm()
	defer prom.Close()
	rec := &recSender{}
	a := newApp(t, map[string]string{"WEBHOOK_BEARER_TOKEN": "hook-secret"}, prom, rec)
	srv := httptest.NewServer(a.Handler())
	defer srv.Close()
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	go a.alertWorker(ctx)

	body, _ := json.Marshal(alertPayload("firing"))
	req, _ := http.NewRequest(http.MethodPost, srv.URL+"/alertmanager", bytes.NewReader(body))
	req.Header.Set("Authorization", "Bearer hook-secret")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("webhook status = %d", resp.StatusCode)
	}
	deadline := time.Now().Add(5 * time.Second)
	for len(rec.all()) < 2 && time.Now().Before(deadline) {
		time.Sleep(10 * time.Millisecond)
	}
	if len(rec.all()) != 2 {
		t.Fatalf("worker delivered %d messages", len(rec.all()))
	}
	for path, want := range map[string]string{"/healthz": `"status":"ok"`, "/metrics": `opsbot_alertmanager_alerts_total{status="firing"} 1`} {
		resp, err := http.Get(srv.URL + path)
		if err != nil {
			t.Fatal(err)
		}
		b, _ := io.ReadAll(resp.Body)
		resp.Body.Close()
		if !strings.Contains(string(b), want) {
			t.Errorf("%s = %q, want %q", path, b, want)
		}
	}
}

func TestCommands(t *testing.T) {
	prom := fakeProm()
	defer prom.Close()
	rec := &recSender{}
	a := newApp(t, map[string]string{"REPORT_FORMAT": "text"}, prom, rec)
	msg := func(chat int64, text string) telegram.Update {
		return telegram.Update{UpdateID: 1, Message: &telegram.Message{Chat: telegram.Chat{ID: chat}, Text: text}}
	}
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	go a.RunReports(ctx)
	a.HandleUpdate(ctx, msg(999, "/status"))            // not a configured chat
	a.HandleUpdate(ctx, msg(222, "hello"))              // not a command
	a.HandleUpdate(ctx, msg(111, "/help"))              // answered at once
	a.HandleUpdate(ctx, msg(222, "/status@LudoOpsBot")) // reply only to the asking chat, asynchronously
	out := waitFor(t, rec, 2)
	if len(out) != 2 || out[0].chat != "111" || out[0].text != HelpText || out[1].chat != "222" || !strings.Contains(out[1].text, "hourly status") {
		t.Fatalf("command replies = %+v", out)
	}
}

func TestJobsHonourConfig(t *testing.T) {
	prom := fakeProm()
	defer prom.Close()
	names := func(js []schedule.Job) (out []string) {
		for _, j := range js {
			out = append(out, j.Name)
		}
		return out
	}
	if got := names(newApp(t, nil, prom, &recSender{}).Jobs()); strings.Join(got, ",") != "status,daily" {
		t.Errorf("default jobs = %v", got)
	}
	if got := names(newApp(t, map[string]string{"STATUS_INTERVAL": "0", "DAILY_REPORT_AT": "off"}, prom, &recSender{}).Jobs()); len(got) != 0 {
		t.Errorf("disabled jobs = %v", got)
	}
	a := newApp(t, map[string]string{"STATUS_INTERVAL": "2h", "DAILY_REPORT_AT": "08:30"}, prom, &recSender{})
	js := a.Jobs()
	now := a.Clock.Now() // 17:00 IST
	if got := js[0].Next(now); got.Hour() != 18 || got.Minute() != 0 {
		t.Errorf("2h status next = %v", got)
	}
	if got := js[1].Next(now).In(a.Cfg.Location); got.Day() != 22 || got.Hour() != 8 || got.Minute() != 30 {
		t.Errorf("daily next = %v", got)
	}
}

// TestSendDocumentThroughFakeTelegram drives the real Telegram client
// against a fake Bot API: multipart upload, caption, every chat, and a 429.
func TestSendDocumentThroughFakeTelegram(t *testing.T) {
	prom := fakeProm()
	defer prom.Close()
	type upload struct {
		chat, file, caption, parseMode string
		size                           int
	}
	var mu sync.Mutex
	var uploads []upload
	calls := 0
	tg := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		mu.Lock()
		defer mu.Unlock()
		calls++
		if !strings.HasSuffix(r.URL.Path, "/sendDocument") {
			http.NotFound(w, r)
			return
		}
		if calls == 1 {
			w.WriteHeader(http.StatusTooManyRequests)
			_, _ = io.WriteString(w, `{"ok":false,"error_code":429,"description":"Too Many Requests: retry after 1","parameters":{"retry_after":1}}`)
			return
		}
		_, params, _ := mime.ParseMediaType(r.Header.Get("Content-Type"))
		mr := multipart.NewReader(r.Body, params["boundary"])
		u := upload{}
		for {
			p, err := mr.NextPart()
			if err != nil {
				break
			}
			b, _ := io.ReadAll(p)
			switch p.FormName() {
			case "chat_id":
				u.chat = string(b)
			case "caption":
				u.caption = string(b)
			case "parse_mode":
				u.parseMode = string(b)
			case "document":
				u.file, u.size = p.FileName(), len(b)
				if !bytes.HasPrefix(b, []byte("%PDF-")) {
					t.Errorf("uploaded document is not a PDF")
				}
			}
		}
		uploads = append(uploads, u)
		_, _ = io.WriteString(w, `{"ok":true,"result":{"message_id":1}}`)
	}))
	defer tg.Close()
	var slept []time.Duration
	client := telegram.New(telegram.Config{BaseURL: tg.URL, Token: "123:fake-token-for-tests-only-0000", MinGap: -1,
		Sleep: func(_ context.Context, d time.Duration) error { slept = append(slept, d); return nil }})
	a := newApp(t, nil, prom, client)
	if err := a.SendStatus(context.Background(), "status", a.Cfg.TelegramChatIDs); err != nil {
		t.Fatal(err)
	}
	mu.Lock()
	defer mu.Unlock()
	if len(uploads) != 2 || uploads[0].chat != "111" || uploads[1].chat != "222" {
		t.Fatalf("uploads = %+v", uploads)
	}
	for _, u := range uploads {
		if u.file != "ludo-arena-status-2026-10-21-1700-IST.pdf" || u.parseMode != "HTML" || u.size < 1000 ||
			u.caption != "staging · Playing: 1,234 players · 456 bots · CPU 41% · RAM 63%" {
			t.Errorf("upload = %+v", u)
		}
	}
	if len(slept) != 1 || slept[0] != time.Second {
		t.Errorf("retry sleeps = %v, want [1s]", slept)
	}
}
