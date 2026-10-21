package health

import (
	"errors"
	"io"
	"log/slog"
	"net/http"
	"strings"
	"sync/atomic"
	"testing"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/collectors"
)

func TestEndpoints(t *testing.T) {
	reg := prometheus.NewRegistry()
	reg.MustRegister(collectors.NewGoCollector())
	var ready atomic.Bool
	srv, err := Listen("127.0.0.1:0", Handler(reg, func() error {
		if !ready.Load() {
			return errors.New("controller token not valid")
		}
		return nil
	}), slog.New(slog.NewTextHandler(io.Discard, nil)))
	if err != nil {
		t.Fatal(err)
	}
	go srv.Serve()
	defer srv.Shutdown(t.Context())
	get := func(path string) (int, string) {
		resp, err := http.Get("http://" + srv.Addr() + path)
		if err != nil {
			t.Fatal(err)
		}
		defer resp.Body.Close()
		b, _ := io.ReadAll(resp.Body)
		return resp.StatusCode, string(b)
	}
	if code, _ := get("/healthz"); code != 200 {
		t.Fatalf("healthz %d", code)
	}
	if code, body := get("/readyz"); code != 503 || !strings.Contains(body, "controller token") {
		t.Fatalf("readyz not ready: %d %s", code, body)
	}
	ready.Store(true)
	if code, _ := get("/readyz"); code != 200 {
		t.Fatalf("readyz %d", code)
	}
	if code, body := get("/metrics"); code != 200 || !strings.Contains(body, "go_goroutines") {
		t.Fatalf("metrics %d", code)
	}
}
