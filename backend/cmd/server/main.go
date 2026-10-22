// Command server runs the Ludo Arena backend: REST API, WebSocket gateway,
// room engine and schedulers.
package main

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"ludoarena/internal/buildinfo"
	"ludoarena/internal/config"
	"ludoarena/internal/logging"
	"ludoarena/internal/postgres"
	"ludoarena/internal/redisstore"
	"ludoarena/internal/server"
)

func main() {
	if err := run(); err != nil {
		slog.Error("server stopped", "error", err.Error())
		os.Exit(1)
	}
}

func run() error {
	cfg, err := config.Load()
	if err != nil {
		return err
	}
	log := logging.New(cfg.LogLevel)
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	pg, err := postgres.Open(ctx, cfg.DatabaseURL, cfg.DBMaxConns)
	if err != nil {
		return err
	}
	defer pg.Close()
	if err := postgres.Migrate(ctx, pg); err != nil {
		return err
	}
	rdb, err := redisstore.Open(ctx, cfg.RedisAddr, cfg.RedisPassword, cfg.RedisDB, cfg.RedisTLS)
	if err != nil {
		return err
	}
	defer rdb.Close()

	core := server.NewCore(cfg, log, pg, rdb)
	ext, err := extensions(ctx, core)
	if err != nil {
		return err
	}
	app, err := server.New(ctx, core, ext, nil)
	if err != nil {
		return err
	}
	runCtx, cancelRun := context.WithCancel(context.Background())
	app.Start(runCtx)

	srv := &http.Server{
		Addr:              cfg.HTTPAddr,
		Handler:           app.Handler(),
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       15 * time.Second,
		WriteTimeout:      30 * time.Second, // hijacked WebSocket conns manage their own deadlines
		IdleTimeout:       90 * time.Second,
		MaxHeaderBytes:    16 << 10,
	}
	metricsSrv := &http.Server{Addr: cfg.MetricsAddr, Handler: app.MetricsHandler(), ReadHeaderTimeout: 5 * time.Second}
	errCh := make(chan error, 2)
	go func() { errCh <- srv.ListenAndServe() }()
	go func() { errCh <- metricsSrv.ListenAndServe() }()
	log.Info("backend started", "version", buildinfo.Version, "commit", buildinfo.Commit, "addr", cfg.HTTPAddr, "metrics", cfg.MetricsAddr, "env", cfg.Env,
		"ws_compression", cfg.WS.CompressionMode, "ws_threshold", cfg.WS.CompressionThreshold)

	select {
	case <-ctx.Done():
	case err := <-errCh:
		if !errors.Is(err, http.ErrServerClosed) {
			cancelRun()
			return err
		}
	}
	log.Info("shutting down")
	shutdownCtx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	cancelRun() // closes WebSockets with 1001 so clients reconnect elsewhere
	_ = srv.Shutdown(shutdownCtx)
	_ = metricsSrv.Shutdown(shutdownCtx)
	// Drain background work (bounded) before the pools close.
	if err := app.Wait(shutdownCtx); err != nil {
		log.Warn("background work not drained", "error", err.Error())
	}
	return nil
}
