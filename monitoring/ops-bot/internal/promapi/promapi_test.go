package promapi_test

import (
	"context"
	"errors"
	"math"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"ludoroyale/opsbot/internal/promapi"
	"ludoroyale/opsbot/internal/promapi/promtest"
)

func TestQueryAgainstFakeAPI(t *testing.T) {
	ts := time.Unix(1_792_000_000, 0)
	srv := promtest.New(
		promtest.Rule{Match: "players_in_game", Vector: []promapi.Sample{promtest.S(12, "actor", "human"), promtest.S(3, "actor", "bot")}},
		promtest.Rule{Match: "broken(", Err: "parse error"},
		promtest.Rule{Match: "nan_metric", Vector: []promapi.Sample{promtest.S(math.NaN())}},
		promtest.Rule{Match: "cpu", Matrix: []promapi.Series{{Labels: map[string]string{"instance": "a"},
			Points: []promapi.Point{{T: ts, V: 10}, {T: ts.Add(time.Minute), V: 20.5}}}}},
	)
	defer srv.Close()
	c := promapi.New(srv.URL, 5*time.Second)
	var errCount int
	c.OnError = func(error) { errCount++ }
	ctx := context.Background()

	tests := []struct {
		name    string
		expr    string
		wantN   int
		wantSum float64
		wantOK  bool
		wantErr string
	}{
		{"labelled vector", `max by (actor) (players_in_game{job="backend"})`, 2, 15, true, ""},
		{"no data", `rooms_in_game`, 0, 0, false, ""},
		{"api error", `broken(`, 0, 0, false, "parse error"},
		{"NaN is not a value", `nan_metric`, 1, 0, false, ""},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := c.Query(ctx, tt.expr, ts)
			if tt.wantErr != "" {
				var apiErr *promapi.Error
				if !errors.As(err, &apiErr) || !strings.Contains(err.Error(), tt.wantErr) || apiErr.ErrorType != "bad_data" {
					t.Fatalf("err = %v, want bad_data %q", err, tt.wantErr)
				}
				return
			}
			if err != nil {
				t.Fatal(err)
			}
			if len(got) != tt.wantN {
				t.Fatalf("samples = %d, want %d", len(got), tt.wantN)
			}
			sum, ok := promapi.Sum(got)
			if ok != tt.wantOK || sum != tt.wantSum {
				t.Errorf("Sum = %v,%v want %v,%v", sum, ok, tt.wantSum, tt.wantOK)
			}
		})
	}
	if errCount != 1 {
		t.Errorf("OnError calls = %d, want 1", errCount)
	}

	series, err := c.QueryRange(ctx, "cpu", ts, ts.Add(time.Minute), 30*time.Second)
	if err != nil {
		t.Fatal(err)
	}
	if len(series) != 1 || len(series[0].Points) != 2 || series[0].Points[1].V != 20.5 || !series[0].Points[1].T.Equal(ts.Add(time.Minute)) {
		t.Fatalf("matrix = %+v", series)
	}
	if by := promapi.ByLabel([]promapi.Sample{promtest.S(1, "actor", "human"), promtest.S(2, "actor", "human")}, "actor"); by["human"] != 3 {
		t.Errorf("ByLabel = %v", by)
	}
}

func TestRequestParameters(t *testing.T) {
	var form map[string]string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_ = r.ParseForm()
		form = map[string]string{"path": r.URL.Path, "query": r.Form.Get("query"), "time": r.Form.Get("time"),
			"start": r.Form.Get("start"), "end": r.Form.Get("end"), "step": r.Form.Get("step")}
		_, _ = w.Write([]byte(`{"status":"success","data":{"resultType":"scalar","result":[1792000000,"42"]}}`))
	}))
	defer srv.Close()
	c := promapi.New(srv.URL+"/", time.Second)
	got, err := c.Query(context.Background(), "vector(42)", time.UnixMilli(1_792_000_000_500))
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 1 || got[0].Value != 42 {
		t.Fatalf("scalar = %+v", got)
	}
	if form["path"] != "/api/v1/query" || form["query"] != "vector(42)" || form["time"] != "1792000000.5" {
		t.Errorf("form = %v", form)
	}
	_, _ = c.QueryRange(context.Background(), "up", time.Unix(100, 0), time.Unix(200, 0), 90*time.Second)
	if form["path"] != "/api/v1/query_range" || form["start"] != "100" || form["end"] != "200" || form["step"] != "90" {
		t.Errorf("range form = %v", form)
	}
}

func TestTransportAndDecodeErrors(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusServiceUnavailable)
		_, _ = w.Write([]byte("<html>maintenance</html>"))
	}))
	c := promapi.New(srv.URL, time.Second)
	_, err := c.Query(context.Background(), "up", time.Time{})
	var apiErr *promapi.Error
	if !errors.As(err, &apiErr) || apiErr.Status != 503 || apiErr.ErrorType != "invalid_response" {
		t.Fatalf("err = %v", err)
	}
	srv.Close()
	if _, err := c.Query(context.Background(), "up", time.Time{}); err == nil {
		t.Fatal("expected a transport error from a closed server")
	}
}
