// Package health serves /healthz, /readyz and /metrics on
// metrics.listen_addr (default 127.0.0.1:9091; keep it internal).
package health

import (
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"net"
	"net/http"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

// ReadinessFunc returns nil when the service is ready.
type ReadinessFunc func() error

// Handler builds the HTTP handler.
func Handler(reg *prometheus.Registry, ready ReadinessFunc) http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, _ *http.Request) {
		writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
	})
	mux.HandleFunc("GET /readyz", func(w http.ResponseWriter, _ *http.Request) {
		if err := ready(); err != nil {
			writeJSON(w, http.StatusServiceUnavailable, map[string]string{"status": "not_ready", "reason": err.Error()})
			return
		}
		writeJSON(w, http.StatusOK, map[string]string{"status": "ready"})
	})
	mux.Handle("GET /metrics", promhttp.HandlerFor(reg, promhttp.HandlerOpts{Registry: reg}))
	return mux
}

func writeJSON(w http.ResponseWriter, code int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Cache-Control", "no-store")
	w.WriteHeader(code)
	_ = json.NewEncoder(w).Encode(v)
}

// Server is the health/metrics HTTP server.
type Server struct {
	srv *http.Server
	ln  net.Listener
	log *slog.Logger
}

// Listen binds addr (so startup fails fast on a bad/used address).
func Listen(addr string, h http.Handler, log *slog.Logger) (*Server, error) {
	ln, err := net.Listen("tcp", addr)
	if err != nil {
		return nil, err
	}
	return &Server{
		srv: &http.Server{Handler: h, ReadHeaderTimeout: 5 * time.Second, ReadTimeout: 10 * time.Second, WriteTimeout: 30 * time.Second},
		ln:  ln, log: log,
	}, nil
}

// Addr returns the bound address.
func (s *Server) Addr() string { return s.ln.Addr().String() }

// Serve runs until Shutdown.
func (s *Server) Serve() {
	if err := s.srv.Serve(s.ln); err != nil && !errors.Is(err, http.ErrServerClosed) {
		s.log.Error("health server stopped", "error", err.Error())
	}
}

// Shutdown stops the server.
func (s *Server) Shutdown(ctx context.Context) error { return s.srv.Shutdown(ctx) }
