package opsmetrics

import (
	"net/http/httptest"
	"strings"
	"testing"
)

func TestExposition(t *testing.T) {
	r := &Registry{}
	sent := r.Counter("opsbot_telegram_messages_total", "Telegram deliveries.", "kind", "result")
	dedup := r.Counter("opsbot_alerts_deduplicated_total", "Dropped duplicates.")
	last := r.Gauge("opsbot_last_success_timestamp_seconds", "Last success.", "kind")
	sent.Inc("status", "sent")
	sent.Inc("status", "sent")
	sent.Inc("alert", "failed")
	sent.Add(-5, "alert", "failed") // counters never decrease
	last.Set(1.7920000005e9, "status")
	last.Set(12, `we"ird`)

	rec := httptest.NewRecorder()
	r.ServeHTTP(rec, httptest.NewRequest("GET", "/metrics", nil))
	want := `# HELP opsbot_telegram_messages_total Telegram deliveries.
# TYPE opsbot_telegram_messages_total counter
opsbot_telegram_messages_total{kind="alert",result="failed"} 1
opsbot_telegram_messages_total{kind="status",result="sent"} 2
# HELP opsbot_alerts_deduplicated_total Dropped duplicates.
# TYPE opsbot_alerts_deduplicated_total counter
opsbot_alerts_deduplicated_total 0
# HELP opsbot_last_success_timestamp_seconds Last success.
# TYPE opsbot_last_success_timestamp_seconds gauge
opsbot_last_success_timestamp_seconds{kind="status"} 1.7920000005e+09
opsbot_last_success_timestamp_seconds{kind="we\"ird"} 12
`
	if got := rec.Body.String(); got != want {
		t.Errorf("exposition mismatch\n--- got ---\n%s\n--- want ---\n%s", got, want)
	}
	if !strings.HasPrefix(rec.Header().Get("Content-Type"), "text/plain; version=0.0.4") {
		t.Errorf("content type = %q", rec.Header().Get("Content-Type"))
	}
	if dedup.Value() != 0 || sent.Value("status", "sent") != 2 {
		t.Error("Value() mismatch")
	}
}

func TestWrongLabelCountPanics(t *testing.T) {
	defer func() {
		if recover() == nil {
			t.Error("expected a panic")
		}
	}()
	(&Registry{}).Counter("x_total", "x", "a").Inc()
}
