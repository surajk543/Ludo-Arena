package client

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"sync/atomic"
	"testing"
	"time"

	"ludoarena/botplay/internal/config"
)

func TestBackoffBounds(t *testing.T) {
	b := Backoff{Base: 100 * time.Millisecond, Max: time.Second}
	for attempt := 0; attempt < 40; attempt++ {
		ceil := b.Ceiling(attempt)
		if ceil > time.Second || ceil <= 0 {
			t.Fatalf("ceiling %v at %d", ceil, attempt)
		}
		for i := 0; i < 20; i++ {
			if d := b.Delay(attempt); d < 0 || d > ceil {
				t.Fatalf("delay %v > ceiling %v", d, ceil)
			}
		}
	}
	if b.Ceiling(0) != 100*time.Millisecond || b.Ceiling(3) != 800*time.Millisecond {
		t.Fatal("exponential growth")
	}
}

func TestControllerTokenCachingRefreshAndAuth(t *testing.T) {
	var issued, lobbies atomic.Int32
	ttl := 2 * time.Second
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/api/v1/bot/controller/token":
			if r.Header.Get("Authorization") != "Bot-Service k3y" {
				w.WriteHeader(401)
				_, _ = w.Write([]byte(`{"error":{"code":"unauthorized","message":"bad key"}}`))
				return
			}
			n := issued.Add(1)
			_ = json.NewEncoder(w).Encode(map[string]any{"token": "ct" + string(rune('0'+n)), "expiresAt": time.Now().Add(ttl).UnixMilli()})
		case "/api/v1/bot/lobbies":
			lobbies.Add(1)
			if r.Header.Get("Authorization") == "Bearer ct1" && lobbies.Load() == 2 {
				w.WriteHeader(401) // token revoked server-side -> client refreshes once
				return
			}
			_ = json.NewEncoder(w).Encode(map[string]any{"lobbies": []any{}})
		case "/api/v1/bot/sessions":
			w.WriteHeader(503)
			w.Header().Set("Retry-After", "3")
			_, _ = w.Write([]byte(`{"error":{"code":"maintenance","message":"m"}}`))
		}
	}))
	defer srv.Close()
	c, err := New(Options{BaseURL: srv.URL + "/api/v1", ServiceKey: config.NewSecret("k3y"), RequestTimeout: time.Second})
	if err != nil {
		t.Fatal(err)
	}
	ctx := context.Background()
	if c.TokenValid() {
		t.Fatal("no token yet")
	}
	if _, err := c.Lobbies(ctx); err != nil {
		t.Fatal(err)
	}
	if _, err := c.Lobbies(ctx); err != nil { // 401 -> refresh -> retry
		t.Fatal(err)
	}
	if issued.Load() != 2 || !c.TokenValid() {
		t.Fatalf("issued %d", issued.Load())
	}
	// Refresh at 80% of lifetime / 30 s before expiry: with a 2 s TTL every
	// call after expiry-30s refreshes.
	if _, err := c.ControllerToken(ctx); err != nil {
		t.Fatal(err)
	}
	if issued.Load() < 3 {
		t.Fatalf("expected proactive refresh, issued %d", issued.Load())
	}
	_, err = c.CreateSession(ctx, SessionRequest{Name: "Bot A", AssignmentID: "as1"})
	if !IsMaintenance(err) {
		t.Fatalf("want maintenance, got %v", err)
	}
	bad, _ := New(Options{BaseURL: srv.URL + "/api/v1", ServiceKey: config.NewSecret("wrong")})
	if _, err := bad.ControllerToken(ctx); !IsStatus(err, 401) {
		t.Fatalf("bad key: %v", err)
	}
	if c.LastSuccess().IsZero() {
		t.Fatal("last success not tracked")
	}
}

// POST /bot/sessions: "emotes" lists what the bot may send; an older backend
// without the field gives an empty list (no emotes).
func TestCreateSessionEmotes(t *testing.T) {
	cases := []struct {
		name string
		body string
		want []string
	}{
		{"with emotes", `{"accessToken":"bt","expiresAt":1,"uid":"u_abcdefghijkm","roomId":"r_1","emotes":["emote_wave","emote_thumbs"]}`, []string{"emote_wave", "emote_thumbs"}},
		{"older backend", `{"accessToken":"bt","expiresAt":1,"uid":"u_abcdefghijkm","roomId":"r_1"}`, nil},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				switch r.URL.Path {
				case "/api/v1/bot/controller/token":
					_ = json.NewEncoder(w).Encode(map[string]any{"token": "ct", "expiresAt": time.Now().Add(time.Hour).UnixMilli()})
				case "/api/v1/bot/sessions":
					_, _ = w.Write([]byte(tc.body))
				}
			}))
			defer srv.Close()
			c, err := New(Options{BaseURL: srv.URL + "/api/v1", ServiceKey: config.NewSecret("k3y"), RequestTimeout: time.Second})
			if err != nil {
				t.Fatal(err)
			}
			s, err := c.CreateSession(context.Background(), SessionRequest{Name: "Asha", AssignmentID: "as1"})
			if err != nil {
				t.Fatal(err)
			}
			if s.UID != "u_abcdefghijkm" || len(s.Emotes) != len(tc.want) {
				t.Fatalf("session %+v", s)
			}
			for i := range tc.want {
				if s.Emotes[i] != tc.want[i] {
					t.Fatalf("emotes %v", s.Emotes)
				}
			}
		})
	}
}
