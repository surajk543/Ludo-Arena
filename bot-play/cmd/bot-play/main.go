// Command bot-play runs automated Ludo Arena players. Bots are pure
// protocol clients of the authoritative Go backend: they never generate
// dice, decide legality, touch wallets or claim outcomes.
package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"io"
	"log/slog"
	"os"
	"os/signal"
	"syscall"
	"time"

	"ludoarena/botplay/internal/client"
	"ludoarena/botplay/internal/config"
	"ludoarena/botplay/internal/health"
	"ludoarena/botplay/internal/metrics"
	"ludoarena/botplay/internal/runner"
)

// Exit codes.
const (
	exitOK       = 0
	exitRuntime  = 1
	exitConfig   = 2
	exitRefused  = 3
	exitInternal = 4
)

func main() { os.Exit(run(os.Args[1:], os.Stderr)) }

func run(args []string, stderr io.Writer) int {
	fs := flag.NewFlagSet("bot-play", flag.ContinueOnError)
	fs.SetOutput(stderr)
	configPath := fs.String("config", "configs/environments/development.yaml", "path to the YAML configuration file")
	profilesPath := fs.String("profiles", "configs/profiles.yaml", "path to the YAML profiles file")
	ack := fs.Bool("i-understand-this-is-a-load-test", false, "required to run loadtest mode (development/preprod only)")
	validateOnly := fs.Bool("validate", false, "validate the configuration and profiles, then exit")
	showVersion := fs.Bool("version", false, "print the version and exit")
	if err := fs.Parse(args); err != nil {
		return exitConfig
	}
	if *showVersion {
		v, b := config.ClientVersion()
		fmt.Fprintf(stderr, "bot-play %s (build %s)\n", v, b)
		return exitOK
	}

	snap, err := config.LoadFiles(*configPath, *profilesPath)
	if err != nil {
		fmt.Fprintf(stderr, "invalid configuration:\n%v\n", err)
		return exitConfig
	}
	cfg := snap.Config
	if cfg.IsLoadtest() {
		if err := config.CheckLoadtestGuard(cfg, *ack); err != nil {
			fmt.Fprintln(stderr, err)
			return exitRefused
		}
	}
	if *validateOnly {
		fmt.Fprintf(stderr, "configuration OK (environment=%s modes=%v profiles=%v)\n", cfg.App.Environment, cfg.Bots.Modes, snap.Profiles.Names())
		return exitOK
	}

	key, warning, err := config.ServiceKeyFromEnv()
	if err != nil {
		fmt.Fprintln(stderr, err)
		return exitConfig
	}

	level := new(slog.LevelVar)
	level.Set(parseLevel(cfg.App.LogLevel))
	logger := newLogger(os.Stdout, cfg.App.LogFormat, level).With("service", cfg.App.Name, "environment", cfg.App.Environment)
	slog.SetDefault(logger)
	if warning != "" {
		logger.Warn(warning)
	}

	store := config.NewStore(snap)
	m := metrics.New()
	v, _ := config.ClientVersion()
	cl, err := client.New(client.Options{
		BaseURL:        cfg.Connection.BackendHTTPURL,
		ServiceKey:     key,
		RequestTimeout: cfg.Connection.RequestTimeout(),
		UserAgent:      "bot-play/" + v,
		OnToken: func(ok bool) {
			if ok {
				m.ControllerTokens.WithLabelValues("success").Inc()
			} else {
				m.ControllerTokens.WithLabelValues("failure").Inc()
			}
		},
	})
	if err != nil {
		logger.Error("client setup failed", "error", err.Error())
		return exitInternal
	}
	svc := runner.New(runner.Options{Store: store, Client: cl, Metrics: m, Logger: logger, LoadtestAcknowledged: *ack})

	var hs *health.Server
	if cfg.Metrics.Enabled {
		hs, err = health.Listen(cfg.Metrics.ListenAddr, health.Handler(m.Registry, svc.Ready), logger)
		if err != nil {
			logger.Error("cannot listen for health/metrics", "addr", cfg.Metrics.ListenAddr, "error", err.Error())
			return exitConfig
		}
		go hs.Serve()
		logger.Info("health and metrics listening", "addr", hs.Addr())
	}

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()
	hup := make(chan os.Signal, 1)
	signal.Notify(hup, syscall.SIGHUP)
	defer signal.Stop(hup)

	watchCtx, cancelWatch := context.WithCancel(context.Background())
	defer cancelWatch()
	w := &config.Watcher{ConfigPath: *configPath, ProfilesPath: *profilesPath, Store: store, Logger: logger, OnResult: m.RecordConfigReload}
	go w.Run(watchCtx, hup)
	go func(sub <-chan *config.Snapshot) {
		for {
			select {
			case <-watchCtx.Done():
				return
			case s := <-sub:
				level.Set(parseLevel(s.Config.App.LogLevel))
			}
		}
	}(store.Subscribe())

	runErr := svc.Run(ctx)
	cancelWatch()
	if hs != nil {
		sctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		_ = hs.Shutdown(sctx)
		cancel()
	}
	if runErr != nil {
		var ge *config.GuardError
		if errors.As(runErr, &ge) {
			logger.Error("load test refused", "reason", ge.Reason, "detail", ge.Detail)
			return exitRefused
		}
		logger.Error("bot-play stopped with error", "error", runErr.Error())
		return exitRuntime
	}
	logger.Info("bot-play stopped")
	return exitOK
}

func parseLevel(s string) slog.Level {
	switch s {
	case "debug":
		return slog.LevelDebug
	case "warn":
		return slog.LevelWarn
	case "error":
		return slog.LevelError
	default:
		return slog.LevelInfo
	}
}

func newLogger(w io.Writer, format string, level slog.Leveler) *slog.Logger {
	opts := &slog.HandlerOptions{Level: level, ReplaceAttr: config.RedactAttr}
	if format == "text" {
		return slog.New(slog.NewTextHandler(w, opts))
	}
	return slog.New(slog.NewJSONHandler(w, opts))
}
