// Package app wires the ops bot together: scheduled status and daily
// reports, the Alertmanager webhook, Telegram commands, health and metrics.
package app

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"slices"
	"strconv"
	"sync"
	"time"

	"ludoarena/opsbot/internal/alertmanager"
	"ludoarena/opsbot/internal/config"
	"ludoarena/opsbot/internal/opsmetrics"
	"ludoarena/opsbot/internal/pdfreport"
	"ludoarena/opsbot/internal/report"
	"ludoarena/opsbot/internal/schedule"
	"ludoarena/opsbot/internal/telegram"
)

// Sender delivers messages and documents to one chat.
type Sender interface {
	SendMessage(ctx context.Context, chatID, html string) error
	SendDocument(ctx context.Context, chatID, filename string, data []byte, captionHTML string) error
}

// Updater long-polls Telegram for commands.
type Updater interface {
	GetUpdates(ctx context.Context, offset int64, timeout time.Duration) ([]telegram.Update, error)
}

// Metrics are the ops bot's own metrics.
type Metrics struct {
	Registry     *opsmetrics.Registry
	Sent         *opsmetrics.Vec // kind, result
	Alerts       *opsmetrics.Vec // status
	Deduplicated *opsmetrics.Vec
	QueryErrors  *opsmetrics.Vec
	LastSuccess  *opsmetrics.Vec // kind
	QueueFull    *opsmetrics.Vec
}

// NewMetrics registers the metrics.
func NewMetrics() *Metrics {
	r := &opsmetrics.Registry{}
	return &Metrics{
		Registry:     r,
		Sent:         r.Counter("opsbot_telegram_messages_total", "Telegram deliveries by kind (status, digest, alert, command) and result (sent, failed).", "kind", "result"),
		Alerts:       r.Counter("opsbot_alertmanager_alerts_total", "Alerts received from Alertmanager by status.", "status"),
		Deduplicated: r.Counter("opsbot_alerts_deduplicated_total", "Alert notifications dropped as duplicates."),
		QueryErrors:  r.Counter("opsbot_prometheus_query_errors_total", "Failed Prometheus API queries."),
		LastSuccess:  r.Gauge("opsbot_last_success_timestamp_seconds", "Unix time of the last successful delivery by kind.", "kind"),
		QueueFull:    r.Counter("opsbot_alert_queue_full_total", "Webhook calls rejected because the alert queue was full."),
	}
}

// App is the running ops bot.
type App struct {
	Cfg       *config.Config
	Sender    Sender
	Updates   Updater // nil disables commands
	Collector *report.Collector
	Metrics   *Metrics
	Log       *slog.Logger
	Clock     schedule.Clock
	Dedupe    *alertmanager.Deduper

	once   sync.Once
	alerts chan alertmanager.Payload
}

func (a *App) init() {
	a.once.Do(func() {
		a.alerts = make(chan alertmanager.Payload, 64)
		if a.Clock == nil {
			a.Clock = schedule.Real{}
		}
		if a.Dedupe == nil {
			a.Dedupe = &alertmanager.Deduper{Window: a.Cfg.AlertDedupeWindow, Now: a.Clock.Now}
		}
	})
}

func (a *App) meta() report.Meta { return report.Meta{Env: a.Cfg.EnvName, Loc: a.Cfg.Location} }

// deliver sends one item to every chat and records metrics.
func (a *App) deliver(ctx context.Context, kind string, chats []string, send func(chat string) error) error {
	var errs []error
	for _, chat := range chats {
		if err := send(chat); err != nil {
			a.Metrics.Sent.Inc(kind, "failed")
			a.Log.Error("telegram delivery failed", "kind", kind, "err", err)
			errs = append(errs, err)
			continue
		}
		a.Metrics.Sent.Inc(kind, "sent")
		a.Metrics.LastSuccess.Set(float64(a.Clock.Now().Unix()), kind)
	}
	return errors.Join(errs...)
}

// SendStatus collects and sends the status report to chats.
func (a *App) SendStatus(ctx context.Context, kind string, chats []string) error {
	a.init()
	pdf := a.Cfg.ReportFormat == config.FormatPDF
	st := a.Collector.Status(ctx, pdf)
	m := a.meta()
	if !pdf {
		text := report.StatusText(st, m)
		return a.deliver(ctx, kind, chats, func(chat string) error { return a.Sender.SendMessage(ctx, chat, text) })
	}
	doc, err := pdfreport.StatusPDF(st, m, pdfreport.Options{})
	if err != nil {
		a.Log.Error("status pdf failed; sending text", "err", err)
		text := report.StatusText(st, m)
		return a.deliver(ctx, kind, chats, func(chat string) error { return a.Sender.SendMessage(ctx, chat, text) })
	}
	name := pdfreport.StatusFileName(st.At, m.Loc)
	caption := report.StatusCaption(st, m)
	return a.deliver(ctx, kind, chats, func(chat string) error { return a.Sender.SendDocument(ctx, chat, name, doc, caption) })
}

// SendDigest collects and sends the daily report for the local day containing day.
func (a *App) SendDigest(ctx context.Context, kind string, day time.Time, chats []string) error {
	a.init()
	pdf := a.Cfg.ReportFormat == config.FormatPDF
	dg := a.Collector.Digest(ctx, day, pdf)
	m := a.meta()
	if !pdf {
		text := report.DigestText(dg, m)
		return a.deliver(ctx, kind, chats, func(chat string) error { return a.Sender.SendMessage(ctx, chat, text) })
	}
	doc, err := pdfreport.DigestPDF(dg, m, a.Clock.Now(), pdfreport.Options{})
	if err != nil {
		a.Log.Error("digest pdf failed; sending text", "err", err)
		text := report.DigestText(dg, m)
		return a.deliver(ctx, kind, chats, func(chat string) error { return a.Sender.SendMessage(ctx, chat, text) })
	}
	name := pdfreport.DigestFileName(dg.Day)
	caption := report.DigestCaption(dg, m)
	return a.deliver(ctx, kind, chats, func(chat string) error { return a.Sender.SendDocument(ctx, chat, name, doc, caption) })
}

// Enqueue queues an Alertmanager notification (false when the queue is full).
func (a *App) Enqueue(p alertmanager.Payload) bool {
	a.init()
	select {
	case a.alerts <- p:
		return true
	default:
		a.Metrics.QueueFull.Inc()
		return false
	}
}

// DeliverAlerts enriches and sends one notification (after de-duplication).
func (a *App) DeliverAlerts(ctx context.Context, p alertmanager.Payload) error {
	a.init()
	alerts := a.Dedupe.Filter(p.Alerts)
	if dropped := len(p.Alerts) - len(alerts); dropped > 0 {
		a.Metrics.Deduplicated.Add(float64(dropped))
	}
	if len(alerts) == 0 {
		return nil
	}
	m := a.meta()
	snap := a.Collector.Snapshot(ctx)
	now := a.Clock.Now()
	if a.Cfg.AlertFormat == config.FormatPDF {
		ch, _ := a.Collector.AlertCharts(ctx, a.Cfg.AlertChartWindow)
		doc, err := pdfreport.AlertPDF(alerts, snap, ch, m, now, pdfreport.Options{})
		if err == nil {
			name := pdfreport.AlertFileName(alerts, now, m.Loc)
			caption := report.AlertCaption(alerts, m, now)
			return a.deliver(ctx, "alert", a.Cfg.TelegramChatIDs, func(chat string) error {
				return a.Sender.SendDocument(ctx, chat, name, doc, caption)
			})
		}
		a.Log.Error("alert pdf failed; sending text", "err", err)
	}
	text := report.AlertText(alerts, snap, m, now)
	return a.deliver(ctx, "alert", a.Cfg.TelegramChatIDs, func(chat string) error { return a.Sender.SendMessage(ctx, chat, text) })
}

func (a *App) alertWorker(ctx context.Context) {
	for {
		select {
		case <-ctx.Done():
			return
		case p := <-a.alerts:
			rctx, cancel := context.WithTimeout(ctx, 3*time.Minute)
			_ = a.DeliverAlerts(rctx, p)
			cancel()
		}
	}
}

// Handler serves /healthz, /metrics and /alertmanager.
func (a *App) Handler() http.Handler {
	a.init()
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = fmt.Fprintf(w, `{"status":"ok","env":%q}`+"\n", a.Cfg.EnvName)
	})
	mux.Handle("GET /metrics", a.Metrics.Registry)
	mux.Handle("/alertmanager", &alertmanager.Handler{
		BearerToken: a.Cfg.WebhookBearerToken,
		Enqueue:     a.Enqueue,
		OnReceive: func(p alertmanager.Payload) {
			for _, al := range p.Alerts {
				a.Metrics.Alerts.Inc(al.Status)
			}
		},
	})
	return mux
}

// Jobs returns the scheduled jobs (disabled ones are omitted).
func (a *App) Jobs() []schedule.Job {
	a.init()
	cfg := a.Cfg
	var jobs []schedule.Job
	if cfg.StatusInterval > 0 {
		jobs = append(jobs, schedule.Job{
			Name: "status",
			Next: func(now time.Time) time.Time {
				return schedule.NextInterval(now, cfg.StatusInterval, cfg.Location, cfg.StatusAlign)
			},
			Run: func(ctx context.Context) {
				rctx, cancel := context.WithTimeout(ctx, 5*time.Minute)
				defer cancel()
				if err := a.SendStatus(rctx, "status", cfg.TelegramChatIDs); err != nil {
					a.Log.Error("hourly status failed", "err", err)
				}
			},
		})
	}
	if cfg.DailyEnabled {
		jobs = append(jobs, schedule.Job{
			Name: "daily",
			Next: func(now time.Time) time.Time {
				return schedule.NextDaily(now, cfg.DailyHour, cfg.DailyMinute, cfg.Location)
			},
			Run: func(ctx context.Context) {
				rctx, cancel := context.WithTimeout(ctx, 10*time.Minute)
				defer cancel()
				day := report.Yesterday(a.Clock.Now(), cfg.Location)
				if err := a.SendDigest(rctx, "digest", day, cfg.TelegramChatIDs); err != nil {
					a.Log.Error("daily report failed", "err", err)
				}
			},
		})
	}
	return jobs
}

// HelpText is the reply to /help.
const HelpText = "<b>Ludo Arena ops bot</b>\n/status — current status report\n/digest — yesterday's KPI report\n/help — this message"

// HandleUpdate answers one Telegram update from an allowed chat.
func (a *App) HandleUpdate(ctx context.Context, u telegram.Update) {
	if u.Message == nil {
		return
	}
	chat := strconv.FormatInt(u.Message.Chat.ID, 10)
	if !slices.Contains(a.Cfg.TelegramChatIDs, chat) {
		a.Log.Debug("ignoring message from a chat that is not configured")
		return
	}
	cmd, _ := telegram.ParseCommand(u.Message.Text)
	var err error
	switch cmd {
	case "":
		return
	case "status":
		err = a.SendStatus(ctx, "command", []string{chat})
	case "digest", "daily":
		err = a.SendDigest(ctx, "command", report.Yesterday(a.Clock.Now(), a.Cfg.Location), []string{chat})
	default:
		err = a.deliver(ctx, "command", []string{chat}, func(c string) error { return a.Sender.SendMessage(ctx, c, HelpText) })
	}
	if err != nil {
		a.Log.Error("command failed", "command", cmd, "err", err)
	}
}

func (a *App) commandLoop(ctx context.Context) {
	if a.Updates == nil {
		return
	}
	// Skip commands sent while the bot was down.
	var offset int64
	if ups, err := a.Updates.GetUpdates(ctx, 0, 0); err == nil {
		for _, u := range ups {
			offset = max(offset, u.UpdateID+1)
		}
	}
	backoff := 5 * time.Second
	for ctx.Err() == nil {
		ups, err := a.Updates.GetUpdates(ctx, offset, 50*time.Second)
		if err != nil {
			if ctx.Err() != nil {
				return
			}
			wait := backoff
			var apiErr *telegram.APIError
			if errors.As(err, &apiErr) && apiErr.StatusCode == http.StatusConflict {
				wait = time.Minute // another poller uses this bot token
			}
			a.Log.Warn("telegram getUpdates failed", "err", err, "retry_in", wait)
			select {
			case <-ctx.Done():
				return
			case <-a.Clock.After(wait):
			}
			backoff = min(backoff*2, time.Minute)
			continue
		}
		backoff = 5 * time.Second
		for _, u := range ups {
			offset = max(offset, u.UpdateID+1)
			rctx, cancel := context.WithTimeout(ctx, 5*time.Minute)
			a.HandleUpdate(rctx, u)
			cancel()
		}
	}
}

// Run serves HTTP and runs the jobs, worker and command loop until ctx ends.
func (a *App) Run(ctx context.Context) error {
	a.init()
	ln, err := net.Listen("tcp", a.Cfg.HTTPAddr)
	if err != nil {
		return fmt.Errorf("listen %s: %w", a.Cfg.HTTPAddr, err)
	}
	srv := &http.Server{Handler: a.Handler(), ReadHeaderTimeout: 10 * time.Second, ReadTimeout: 30 * time.Second, WriteTimeout: 30 * time.Second}
	var wg sync.WaitGroup
	wg.Go(func() {
		if err := srv.Serve(ln); err != nil && !errors.Is(err, http.ErrServerClosed) {
			a.Log.Error("http server stopped", "err", err)
		}
	})
	wg.Go(func() { a.alertWorker(ctx) })
	wg.Go(func() { a.commandLoop(ctx) })
	for _, j := range a.Jobs() {
		wg.Go(func() { schedule.Run(ctx, a.Clock, j) })
		a.Log.Info("scheduled", "job", j.Name, "next", j.Next(a.Clock.Now()).In(a.Cfg.Location).Format(time.RFC3339))
	}
	if a.Cfg.StatusOnStart {
		wg.Go(func() {
			if err := a.SendStatus(ctx, "status", a.Cfg.TelegramChatIDs); err != nil {
				a.Log.Error("startup status failed", "err", err)
			}
		})
	}
	a.Log.Info("ops bot running", "http", ln.Addr().String())
	<-ctx.Done()
	shutdown, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	_ = srv.Shutdown(shutdown)
	wg.Wait()
	return nil
}

// DryRunSender logs messages and writes documents to a directory instead
// of calling Telegram (TELEGRAM_DRY_RUN=true).
type DryRunSender struct {
	Dir string
	Log *slog.Logger
	mu  sync.Mutex
	n   int
}

// SendMessage logs the message.
func (s *DryRunSender) SendMessage(_ context.Context, chatID, html string) error {
	s.Log.Info("dry run: message", "chat", chatID, "text", html)
	return nil
}

// SendDocument writes the document to Dir (when set) and logs it.
func (s *DryRunSender) SendDocument(_ context.Context, chatID, filename string, data []byte, caption string) error {
	path := ""
	if s.Dir != "" {
		s.mu.Lock()
		s.n++
		n := s.n
		s.mu.Unlock()
		if err := os.MkdirAll(s.Dir, 0o755); err != nil {
			return err
		}
		path = filepath.Join(s.Dir, fmt.Sprintf("%03d-%s", n, filepath.Base(filename)))
		if err := os.WriteFile(path, data, 0o644); err != nil {
			return err
		}
	}
	s.Log.Info("dry run: document", "chat", chatID, "file", filename, "bytes", len(data), "caption", caption, "saved", path)
	return nil
}
