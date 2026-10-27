package config

import (
	"strings"
	"testing"
	"time"
)

const token = "123456789:AAH-fake-test-token-0123456789abcdef"

func env(kv map[string]string) func(string) string {
	return func(k string) string { return kv[k] }
}

func TestDefaults(t *testing.T) {
	c, err := Load(env(map[string]string{"TELEGRAM_BOT_TOKEN": token, "TELEGRAM_CHAT_IDS": "-1001234567890, 42"}))
	if err != nil {
		t.Fatal(err)
	}
	checks := []struct {
		name string
		got  any
		want any
	}{
		{"env", c.EnvName, "development"},
		{"tz", c.Location.String(), "Asia/Kolkata"},
		{"status interval", c.StatusInterval, time.Hour},
		{"align", c.StatusAlign, true},
		{"daily", [3]any{c.DailyEnabled, c.DailyHour, c.DailyMinute}, [3]any{true, 9, 0}},
		{"report format", c.ReportFormat, FormatPDF},
		{"alert format", c.AlertFormat, FormatText},
		{"chats", strings.Join(c.TelegramChatIDs, "|"), "-1001234567890|42"},
		{"prom", c.PromURL, "http://127.0.0.1:9095"},
		{"package", c.PlayPackage, "com.sungamestudio.ludoarena"},
		{"play", c.PlayEnabled, false},
		{"ga4", c.GA4Enabled, false},
		{"dedupe", c.AlertDedupeWindow, 30 * time.Minute},
		{"trend days", c.TrendDays, 30},
		{"commands", c.TelegramCommands, true},
		{"command timeout", c.CommandTimeout, 30 * time.Second},
		{"command dedupe", c.CommandDedupe, 30 * time.Second},
		{"backend api", c.BackendAPIURL, ""},
	}
	for _, ch := range checks {
		if ch.got != ch.want {
			t.Errorf("%s = %v, want %v", ch.name, ch.got, ch.want)
		}
	}
	if s := c.String(); strings.Contains(s, token) || strings.Contains(s, "AAH") || !strings.Contains(s, "token=set") {
		t.Errorf("String() must not reveal the token: %s", s)
	}
}

func TestOverridesAndDisabling(t *testing.T) {
	c, err := Load(env(map[string]string{
		"TELEGRAM_DRY_RUN": "true", "STATUS_INTERVAL": "0", "DAILY_REPORT_AT": "off", "REPORT_FORMAT": "TEXT",
		"ALERT_FORMAT": "pdf", "TZ_NAME": "UTC", "PLAY_REPORTS_BUCKET": "gs://pubsite_prod_rev_1", "GA4_PROPERTY_ID": "123",
		"PROM_URL": "http://prometheus:9090/", "ENV_NAME": "production",
	}))
	if err != nil {
		t.Fatal(err)
	}
	if c.StatusInterval != 0 || c.DailyEnabled || c.ReportFormat != FormatText || c.AlertFormat != FormatPDF ||
		!c.PlayEnabled || !c.GA4Enabled || c.PromURL != "http://prometheus:9090" || c.Location != time.UTC {
		t.Errorf("overrides not applied: %+v", c)
	}
}

func TestInvalid(t *testing.T) {
	tests := []struct {
		name string
		env  map[string]string
		want string
	}{
		{"missing token", map[string]string{"TELEGRAM_CHAT_IDS": "1"}, "TELEGRAM_BOT_TOKEN is required"},
		{"missing chats", map[string]string{"TELEGRAM_BOT_TOKEN": token}, "TELEGRAM_CHAT_IDS is required"},
		{"malformed token", map[string]string{"TELEGRAM_BOT_TOKEN": "not-a-token-secretvalue", "TELEGRAM_CHAT_IDS": "1"}, "does not look like a bot token"},
		{"bad chat id", map[string]string{"TELEGRAM_DRY_RUN": "1", "TELEGRAM_CHAT_IDS": "abc"}, "neither a numeric chat id"},
		{"bad interval", map[string]string{"TELEGRAM_DRY_RUN": "1", "STATUS_INTERVAL": "5s"}, "STATUS_INTERVAL: must be at least 1m0s"},
		{"bad daily", map[string]string{"TELEGRAM_DRY_RUN": "1", "DAILY_REPORT_AT": "9am"}, "DAILY_REPORT_AT"},
		{"bad tz", map[string]string{"TELEGRAM_DRY_RUN": "1", "TZ_NAME": "Mars/Base"}, "unknown time zone"},
		{"bad format", map[string]string{"TELEGRAM_DRY_RUN": "1", "REPORT_FORMAT": "docx"}, "REPORT_FORMAT"},
		{"bad prom url", map[string]string{"TELEGRAM_DRY_RUN": "1", "PROM_URL": "prometheus:9090"}, "PROM_URL"},
		{"bad trend days", map[string]string{"TELEGRAM_DRY_RUN": "1", "TREND_DAYS": "365"}, "TREND_DAYS"},
		{"backend without key", map[string]string{"TELEGRAM_DRY_RUN": "1", "BACKEND_API_URL": "http://127.0.0.1:8080"}, "BACKEND_ADMIN_KEY is required"},
		{"bad backend url", map[string]string{"TELEGRAM_DRY_RUN": "1", "BACKEND_API_URL": "127.0.0.1:8080", "BACKEND_ADMIN_KEY": "secretvalue"}, "BACKEND_API_URL"},
		{"bad command timeout", map[string]string{"TELEGRAM_DRY_RUN": "1", "COMMAND_REPORT_TIMEOUT": "1s"}, "COMMAND_REPORT_TIMEOUT: must be at least 5s"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			_, err := Load(env(tt.env))
			if err == nil || !strings.Contains(err.Error(), tt.want) {
				t.Fatalf("err = %v, want %q", err, tt.want)
			}
			if strings.Contains(err.Error(), "secretvalue") {
				t.Errorf("error leaks the token: %v", err)
			}
		})
	}
}

func TestBackendAPI(t *testing.T) {
	c, err := Load(env(map[string]string{"TELEGRAM_DRY_RUN": "true", "BACKEND_API_URL": "http://127.0.0.1:8080/",
		"BACKEND_ADMIN_KEY": "op-key-secretvalue", "COMMAND_REPORT_TIMEOUT": "45s", "COMMAND_DEDUPE_WINDOW": "0"}))
	if err != nil {
		t.Fatal(err)
	}
	if c.BackendAPIURL != "http://127.0.0.1:8080" || c.BackendAdminKey != "op-key-secretvalue" || c.CommandTimeout != 45*time.Second || c.CommandDedupe != 0 {
		t.Errorf("backend settings = %q %s %s", c.BackendAPIURL, c.CommandTimeout, c.CommandDedupe)
	}
	if s := c.String(); strings.Contains(s, "secretvalue") || !strings.Contains(s, "admin_key=set") || !strings.Contains(s, "backend_api=http://127.0.0.1:8080") {
		t.Errorf("String() = %s", s)
	}
}

func TestParseClock(t *testing.T) {
	tests := []struct {
		in     string
		h, m   int
		wantOK bool
	}{
		{"09:00", 9, 0, true}, {"9:05", 9, 5, true}, {"23:59", 23, 59, true}, {"00:00", 0, 0, true},
		{"24:00", 0, 0, false}, {"09:60", 0, 0, false}, {"0900", 0, 0, false}, {"9:5", 0, 0, false}, {"", 0, 0, false},
	}
	for _, tt := range tests {
		h, m, ok := ParseClock(tt.in)
		if ok != tt.wantOK || (ok && (h != tt.h || m != tt.m)) {
			t.Errorf("ParseClock(%q) = %d,%d,%v", tt.in, h, m, ok)
		}
	}
}
