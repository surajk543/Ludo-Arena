package backendapi

import (
	"context"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

const key = "op-key-for-tests-only-7d2f"

func TestOnlineAndPlaytime(t *testing.T) {
	var paths []string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		paths = append(paths, r.URL.RequestURI())
		if r.Header.Get("X-Admin-Key") != key {
			w.WriteHeader(http.StatusUnauthorized)
			_, _ = io.WriteString(w, `{"error":{"code":"unauthorized","message":"A valid X-Admin-Key is required."}}`)
			return
		}
		switch r.URL.Path {
		case "/api/v1/admin/ops/online":
			_, _ = io.WriteString(w, `{"at":"2026-10-27T15:04:05Z","total":3,"counts":{"ludo":1,"snakes_ladders":0,"waiting":1,"lobby":1},
			  "users":[{"uid":"u_AAAAAAAAAAAA","userId":"6f1c0000-0000-4000-8000-000000000001","name":"Asha","createdAt":"2026-10-01T10:00:00Z",
			            "onlineSince":"2026-10-27T14:00:00Z","activity":"ludo","game":"ludo","mode":"public"},
			           {"uid":"u_BBBBBBBBBBBB","userId":"6f1c0000-0000-4000-8000-000000000002","name":"Bilal","createdAt":null,
			            "onlineSince":"2026-10-27T15:00:00Z","activity":"lobby","game":null,"mode":null}]}`)
		case "/api/v1/admin/ops/playtime":
			_, _ = io.WriteString(w, `{"from":"2026-10-26T15:04:05Z","to":"2026-10-27T15:04:05Z","hours":24,
			  "games":[{"game":"ludo","seconds":5400,"players":2,"hourly":[{"hour":"2026-10-27T14:00:00Z","seconds":5400}],
			            "top":[{"uid":"u_AAAAAAAAAAAA","userId":"x","name":"Asha","createdAt":null,"seconds":3600}]},
			           {"game":"snakes_ladders","seconds":0,"players":0,"hourly":[],"top":[]}]}`)
		default:
			http.NotFound(w, r)
		}
	}))
	defer srv.Close()
	c := New(srv.URL+"/", key)
	ctx := context.Background()

	on, err := c.Online(ctx, 100)
	if err != nil {
		t.Fatal(err)
	}
	if on.Total != 3 || on.Counts[ActivityWaiting] != 1 || len(on.Users) != 2 {
		t.Fatalf("online = %+v", on)
	}
	u0, u1 := on.Users[0], on.Users[1]
	if u0.UID != "u_AAAAAAAAAAAA" || u0.CreatedAt == nil || !u0.CreatedAt.Equal(time.Date(2026, 10, 1, 10, 0, 0, 0, time.UTC)) ||
		u0.Activity != ActivityLudo || u0.Mode != "public" {
		t.Errorf("user 0 = %+v", u0)
	}
	if u1.CreatedAt != nil || u1.Game != "" || u1.Activity != ActivityLobby {
		t.Errorf("user 1 = %+v", u1)
	}

	pt, err := c.Playtime(ctx, 24, 100)
	if err != nil {
		t.Fatal(err)
	}
	if l := pt.Game("ludo"); l.Seconds != 5400 || l.Players != 2 || len(l.Top) != 1 || l.Top[0].Seconds != 3600 {
		t.Errorf("ludo = %+v", l)
	}
	if s := pt.Game("snakes_ladders"); s.Seconds != 0 || s.Top == nil {
		t.Errorf("snakes = %+v", s)
	}
	if m := pt.Game("chess"); m.Game != "chess" || m.Seconds != 0 {
		t.Errorf("missing game = %+v", m)
	}
	if strings.Join(paths, " ") != "/api/v1/admin/ops/online?limit=100 /api/v1/admin/ops/playtime?hours=24&limit=100" {
		t.Errorf("paths = %v", paths)
	}

	_, err = New(srv.URL, "wrong-key").Online(ctx, 100)
	var ae *Error
	if !errors.As(err, &ae) || ae.StatusCode != http.StatusUnauthorized || !strings.Contains(err.Error(), "BACKEND_ADMIN_KEY") {
		t.Errorf("wrong key err = %v", err)
	}
	if strings.Contains(err.Error(), "wrong-key") {
		t.Errorf("error leaks the key: %v", err)
	}
}

func TestErrors(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Query().Get("limit") {
		case "1":
			http.NotFound(w, r)
		case "2":
			w.WriteHeader(http.StatusBadRequest)
			_, _ = io.WriteString(w, `{"error":{"code":"bad_request"}}`)
		default:
			_, _ = io.WriteString(w, `not json`)
		}
	}))
	defer srv.Close()
	c := New(srv.URL, key)
	ctx := context.Background()
	for limit, want := range map[int]string{1: "operator API disabled", 2: "400 bad_request", 3: "decode"} {
		if _, err := c.Online(ctx, limit); err == nil || !strings.Contains(err.Error(), want) {
			t.Errorf("limit %d: err = %v, want %q", limit, err, want)
		}
	}
	cctx, cancel := context.WithCancel(ctx)
	cancel()
	if _, err := c.Online(cctx, 5); !errors.Is(err, context.Canceled) {
		t.Errorf("cancelled err = %v", err)
	}
}
