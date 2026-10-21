package alertmanager

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

// payload is a real Alertmanager v4 webhook body (one firing, one resolved).
const payload = `{
  "version": "4",
  "groupKey": "{}:{alertname=\"HostCPUHigh\"}",
  "truncatedAlerts": 0,
  "status": "firing",
  "receiver": "ops-bot",
  "groupLabels": {"alertname": "HostCPUHigh"},
  "commonLabels": {"alertname": "HostCPUHigh", "severity": "warning"},
  "commonAnnotations": {},
  "externalURL": "http://alertmanager:9093",
  "alerts": [
    {"status": "firing", "labels": {"alertname": "HostCPUHigh", "severity": "warning", "instance": "app-1:9100", "job": "node"},
     "annotations": {"summary": "CPU usage on app-1:9100 is 92%", "description": "Above 85% for 5 minutes."},
     "startsAt": "2026-10-21T11:18:00Z", "endsAt": "0001-01-01T00:00:00Z",
     "generatorURL": "http://prometheus:9090/graph", "fingerprint": "a1b2c3"},
    {"status": "resolved", "labels": {"alertname": "HostCPUHigh", "instance": "app-2:9100", "job": "node"},
     "annotations": {}, "startsAt": "2026-10-21T10:00:00Z", "endsAt": "2026-10-21T10:25:00Z", "fingerprint": "d4e5f6"}
  ]
}`

func TestDecode(t *testing.T) {
	p, err := Decode(strings.NewReader(payload))
	if err != nil {
		t.Fatal(err)
	}
	if p.Version != "4" || len(p.Alerts) != 2 {
		t.Fatalf("payload = %+v", p)
	}
	a, r := p.Alerts[0], p.Alerts[1]
	checks := []struct{ got, want string }{
		{a.Name(), "HostCPUHigh"}, {a.Severity(), "warning"}, {a.Instance(), "app-1:9100"},
		{a.Summary(), "CPU usage on app-1:9100 is 92%"}, {a.Description(), "Above 85% for 5 minutes."},
		{r.Severity(), "warning"}, {r.Summary(), "HostCPUHigh"}, {r.Key(), "d4e5f6"},
	}
	for _, c := range checks {
		if c.got != c.want {
			t.Errorf("got %q, want %q", c.got, c.want)
		}
	}
	if !a.Firing() || r.Firing() || r.EndsAt.Sub(r.StartsAt) != 25*time.Minute {
		t.Errorf("status/times wrong: %+v %+v", a, r)
	}
	for _, bad := range []string{`{`, `{"alerts":[]}`, `[]`} {
		if _, err := Decode(strings.NewReader(bad)); err == nil {
			t.Errorf("Decode(%q) succeeded", bad)
		}
	}
}

func TestDeduper(t *testing.T) {
	now := time.Date(2026, 10, 21, 12, 0, 0, 0, time.UTC)
	d := &Deduper{Window: 30 * time.Minute, Now: func() time.Time { return now }}
	firing := Alert{Status: "firing", Fingerprint: "x"}
	resolved := Alert{Status: "resolved", Fingerprint: "x"}
	other := Alert{Status: "firing", Labels: map[string]string{"alertname": "B"}}
	steps := []struct {
		advance time.Duration
		in      []Alert
		want    int
	}{
		{0, []Alert{firing, other}, 2},        // first delivery
		{5 * time.Minute, []Alert{firing}, 0}, // group update inside the window
		{0, []Alert{resolved}, 1},             // status change always passes
		{time.Minute, []Alert{firing}, 1},     // flapping back to firing passes
		{29 * time.Minute, []Alert{firing}, 0},
		{2 * time.Minute, []Alert{firing, other}, 2}, // repeat after the window (other keyed by labels)
	}
	for i, s := range steps {
		now = now.Add(s.advance)
		if got := len(d.Filter(s.in)); got != s.want {
			t.Errorf("step %d: delivered %d, want %d", i, got, s.want)
		}
	}
	zero := &Deduper{}
	if len(zero.Filter([]Alert{firing})) != 1 || len(zero.Filter([]Alert{firing})) != 1 {
		t.Error("a zero window must not drop anything")
	}
}

func TestHandler(t *testing.T) {
	var got []Payload
	full := false
	h := &Handler{BearerToken: "s3cret", Enqueue: func(p Payload) bool {
		if full {
			return false
		}
		got = append(got, p)
		return true
	}}
	tests := []struct {
		name, method, auth, body string
		full                     bool
		want                     int
	}{
		{"ok", http.MethodPost, "Bearer s3cret", payload, false, http.StatusOK},
		{"wrong token", http.MethodPost, "Bearer nope", payload, false, http.StatusUnauthorized},
		{"no token", http.MethodPost, "", payload, false, http.StatusUnauthorized},
		{"bad json", http.MethodPost, "Bearer s3cret", "{", false, http.StatusBadRequest},
		{"queue full", http.MethodPost, "Bearer s3cret", payload, true, http.StatusServiceUnavailable},
		{"get", http.MethodGet, "Bearer s3cret", "", false, http.StatusMethodNotAllowed},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			full = tt.full
			req := httptest.NewRequest(tt.method, "/alertmanager", strings.NewReader(tt.body))
			if tt.auth != "" {
				req.Header.Set("Authorization", tt.auth)
			}
			rec := httptest.NewRecorder()
			h.ServeHTTP(rec, req)
			if rec.Code != tt.want {
				t.Errorf("status = %d, want %d", rec.Code, tt.want)
			}
		})
	}
	if len(got) != 1 || len(got[0].Alerts) != 2 {
		t.Errorf("enqueued = %+v", got)
	}
}
