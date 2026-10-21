// Command ops-bot sends Ludo Royale operations reports and alerts to
// Telegram: an hourly status (PDF or text), a daily KPI report, and
// Alertmanager notifications enriched with CPU, RAM and player counts.
//
// Configuration comes from environment variables (see
// monitoring/.env.example and monitoring/README.md). One-shot modes:
//
//	ops-bot --validate                  check the configuration and exit
//	ops-bot --run-status-now            send one status report and exit
//	ops-bot --run-digest-now            send yesterday's daily report and exit
//	ops-bot --run-digest-now --digest-date 2026-10-20
package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"log/slog"
	"os"
	"os/signal"
	"syscall"
	"time"
	_ "time/tzdata" // TZ_NAME works in minimal container images

	"ludoroyale/opsbot/internal/app"
	"ludoroyale/opsbot/internal/config"
	"ludoroyale/opsbot/internal/google"
	"ludoroyale/opsbot/internal/promapi"
	"ludoroyale/opsbot/internal/report"
	"ludoroyale/opsbot/internal/schedule"
	"ludoroyale/opsbot/internal/telegram"
)

func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, "ops-bot:", err)
		os.Exit(1)
	}
}

func run() error {
	validate := flag.Bool("validate", false, "validate the configuration and exit")
	statusNow := flag.Bool("run-status-now", false, "send one status report to every chat and exit")
	digestNow := flag.Bool("run-digest-now", false, "send the daily report for yesterday (or --digest-date) and exit")
	digestDate := flag.String("digest-date", "", "local date YYYY-MM-DD for --run-digest-now (default: yesterday)")
	flag.Parse()

	cfg, err := config.Load(os.Getenv)
	if err != nil {
		return fmt.Errorf("configuration:\n%w", err)
	}
	log := newLogger(cfg.LogLevel)
	if *validate {
		fmt.Println("configuration ok:", cfg)
		return nil
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	metrics := app.NewMetrics()
	prom := promapi.New(cfg.PromURL, cfg.PromTimeout)
	prom.OnError = func(err error) {
		metrics.QueryErrors.Inc()
		log.Warn("prometheus query failed", "err", err)
	}
	collector := &report.Collector{
		Prom:      prom,
		Q:         report.Queries{Backend: cfg.BackendJob, BotPlay: cfg.BotPlayJob, Node: cfg.NodeJob},
		Loc:       cfg.Location,
		TrendDays: cfg.TrendDays,
	}
	setupGoogle(ctx, cfg, collector, log)

	var sender app.Sender
	var updater app.Updater
	if cfg.DryRun {
		sender = &app.DryRunSender{Dir: cfg.DryRunDir, Log: log}
	} else {
		minGap := cfg.TelegramMinGap
		if minGap == 0 {
			minGap = -1 // 0 means "no gap" in our configuration
		}
		tg := telegram.New(telegram.Config{BaseURL: cfg.TelegramAPIURL, Token: cfg.TelegramToken, MinGap: minGap, Logger: log})
		sender = tg
		if cfg.TelegramCommands {
			updater = tg
		}
	}
	a := &app.App{Cfg: cfg, Sender: sender, Updates: updater, Collector: collector, Metrics: metrics, Log: log, Clock: schedule.Real{}}
	log.Info("starting", "config", cfg.String())

	switch {
	case *statusNow:
		return a.SendStatus(ctx, "status", cfg.TelegramChatIDs)
	case *digestNow:
		day := report.Yesterday(time.Now(), cfg.Location)
		if *digestDate != "" {
			d, err := time.ParseInLocation("2006-01-02", *digestDate, cfg.Location)
			if err != nil {
				return errors.New("--digest-date: want YYYY-MM-DD")
			}
			day = d
		}
		return a.SendDigest(ctx, "digest", day, cfg.TelegramChatIDs)
	}
	return a.Run(ctx)
}

// setupGoogle attaches the optional Play and GA4 sources. Missing
// credentials do not stop the bot: the daily report shows the error.
func setupGoogle(ctx context.Context, cfg *config.Config, c *report.Collector, log *slog.Logger) {
	if !cfg.PlayEnabled && !cfg.GA4Enabled {
		return
	}
	var scopes []string
	if cfg.PlayEnabled {
		scopes = append(scopes, google.ScopeStorageRead)
	}
	if cfg.GA4Enabled {
		scopes = append(scopes, google.ScopeAnalyticsRead)
	}
	hc, err := google.NewHTTPClient(ctx, scopes...)
	if err != nil {
		log.Warn("google credentials unavailable; Play/GA4 sections will show the error", "err", err)
	}
	if cfg.PlayEnabled {
		if err != nil {
			c.Play = failingPlay{err}
		} else {
			c.Play = &google.PlayClient{Bucket: google.NormalizeBucket(cfg.PlayBucket), Package: cfg.PlayPackage, BaseURL: cfg.GCSAPIURL, HTTP: hc}
		}
	}
	if cfg.GA4Enabled {
		if err != nil {
			c.GA4 = failingGA4{err}
		} else {
			c.GA4 = &google.GA4Client{PropertyID: cfg.GA4Property, BaseURL: cfg.GA4APIURL, HTTP: hc}
		}
	}
}

type failingPlay struct{ err error }

func (f failingPlay) Installs(context.Context, time.Time, int) (google.PlayReport, error) {
	return google.PlayReport{}, f.err
}

type failingGA4 struct{ err error }

func (f failingGA4) Summary(context.Context, time.Time, int) (google.GA4Summary, error) {
	return google.GA4Summary{}, f.err
}

func newLogger(level string) *slog.Logger {
	var l slog.Level
	switch level {
	case "debug":
		l = slog.LevelDebug
	case "warn":
		l = slog.LevelWarn
	case "error":
		l = slog.LevelError
	default:
		l = slog.LevelInfo
	}
	log := slog.New(slog.NewTextHandler(os.Stderr, &slog.HandlerOptions{Level: l}))
	slog.SetDefault(log)
	return log
}
