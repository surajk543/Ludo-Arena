// Package config loads the ops bot's configuration from environment
// variables. Secrets (the Telegram bot token, the webhook bearer token, the
// backend operator key and Google credentials) come only from the
// environment or files referenced by it, and are never printed: String() and
// validation errors redact them.
package config

import (
	"errors"
	"fmt"
	"net/url"
	"strconv"
	"strings"
	"time"
)

// Format selects how a report is delivered.
type Format string

// Report and alert formats.
const (
	FormatPDF  Format = "pdf"
	FormatText Format = "text"
)

// Config is the complete ops bot configuration.
type Config struct {
	EnvName  string         // ENV_NAME, shown in every message header
	TZName   string         // TZ_NAME
	Location *time.Location // loaded from TZName
	HTTPAddr string         // HTTP_ADDR: /healthz, /metrics, /alertmanager
	LogLevel string         // LOG_LEVEL

	PromURL     string        // PROM_URL
	PromTimeout time.Duration // PROM_TIMEOUT
	BackendJob  string        // BACKEND_JOB
	BotPlayJob  string        // BOTPLAY_JOB
	NodeJob     string        // NODE_JOB

	TelegramToken    string        // TELEGRAM_BOT_TOKEN (secret)
	TelegramChatIDs  []string      // TELEGRAM_CHAT_IDS
	TelegramAPIURL   string        // TELEGRAM_API_URL
	TelegramCommands bool          // TELEGRAM_COMMANDS: answer /status, /digest, /live, /playtime, /metrics, /help
	TelegramMinGap   time.Duration // TELEGRAM_MIN_GAP between messages to one chat
	DryRun           bool          // TELEGRAM_DRY_RUN: log messages instead of sending
	DryRunDir        string        // DRY_RUN_DIR: where dry-run documents are written

	StatusInterval time.Duration // STATUS_INTERVAL (0 disables)
	StatusAlign    bool          // STATUS_ALIGN: run on multiples of the interval since local midnight
	StatusOnStart  bool          // STATUS_ON_START
	DailyReportAt  string        // DAILY_REPORT_AT "HH:MM" or "off"
	DailyHour      int
	DailyMinute    int
	DailyEnabled   bool
	TrendDays      int    // TREND_DAYS for the daily report charts
	ReportFormat   Format // REPORT_FORMAT pdf|text
	AlertFormat    Format // ALERT_FORMAT text|pdf

	AlertDedupeWindow  time.Duration // ALERT_DEDUPE_WINDOW
	WebhookBearerToken string        // WEBHOOK_BEARER_TOKEN (secret, optional)

	BackendAPIURL   string        // BACKEND_API_URL: backend REST base for the operator API (empty: per-user lists off)
	BackendAdminKey string        // BACKEND_ADMIN_KEY (secret): X-Admin-Key of /api/v1/admin/*
	CommandTimeout  time.Duration // COMMAND_REPORT_TIMEOUT: a command's report is cancelled after this
	CommandDedupe   time.Duration // COMMAND_DEDUPE_WINDOW: the same command from the same chat is dropped within this

	PlayBucket       string // PLAY_REPORTS_BUCKET (optional)
	PlayPackage      string // PLAY_PACKAGE_NAME
	GA4Property      string // GA4_PROPERTY_ID (optional)
	GCSAPIURL        string // GCS_API_URL (tests / emulators)
	GA4APIURL        string // GA4_API_URL (tests)
	GoogleCreds      string // GOOGLE_APPLICATION_CREDENTIALS (path; read by the Google client library)
	PlayEnabled      bool
	GA4Enabled       bool
	AlertChartWindow time.Duration // window of the charts in PDF alerts
}

// Defaults for every variable (documented in monitoring/README.md).
var Defaults = map[string]string{
	"ENV_NAME":               "development",
	"TZ_NAME":                "Asia/Kolkata",
	"HTTP_ADDR":              "127.0.0.1:9097",
	"LOG_LEVEL":              "info",
	"PROM_URL":               "http://127.0.0.1:9095",
	"PROM_TIMEOUT":           "20s",
	"BACKEND_JOB":            "backend",
	"BOTPLAY_JOB":            "bot-play",
	"NODE_JOB":               "node",
	"TELEGRAM_API_URL":       "https://api.telegram.org",
	"TELEGRAM_COMMANDS":      "true",
	"TELEGRAM_MIN_GAP":       "3s",
	"TELEGRAM_DRY_RUN":       "false",
	"STATUS_INTERVAL":        "1h",
	"STATUS_ALIGN":           "true",
	"STATUS_ON_START":        "false",
	"DAILY_REPORT_AT":        "09:00",
	"TREND_DAYS":             "30",
	"REPORT_FORMAT":          "pdf",
	"ALERT_FORMAT":           "text",
	"ALERT_DEDUPE_WINDOW":    "30m",
	"COMMAND_REPORT_TIMEOUT": "30s",
	"COMMAND_DEDUPE_WINDOW":  "30s",
	"PLAY_PACKAGE_NAME":      "com.sungamestudio.ludoarena",
}

// Load reads the configuration through getenv (os.Getenv in production).
func Load(getenv func(string) string) (*Config, error) {
	get := func(k string) string {
		if v := strings.TrimSpace(getenv(k)); v != "" {
			return v
		}
		return Defaults[k]
	}
	var errs []error
	fail := func(format string, a ...any) { errs = append(errs, fmt.Errorf(format, a...)) }
	dur := func(k string, min time.Duration, allowZero bool) time.Duration {
		d, err := time.ParseDuration(get(k))
		if err != nil {
			fail("%s: invalid duration %q", k, get(k))
			return 0
		}
		if d == 0 && allowZero {
			return 0
		}
		if d < min {
			fail("%s: must be at least %s (or 0 to disable)", k, min)
		}
		return d
	}
	boolean := func(k string) bool {
		b, err := strconv.ParseBool(get(k))
		if err != nil {
			fail("%s: invalid boolean %q", k, get(k))
		}
		return b
	}

	c := &Config{
		EnvName:            get("ENV_NAME"),
		TZName:             get("TZ_NAME"),
		HTTPAddr:           get("HTTP_ADDR"),
		LogLevel:           strings.ToLower(get("LOG_LEVEL")),
		PromURL:            strings.TrimRight(get("PROM_URL"), "/"),
		BackendJob:         get("BACKEND_JOB"),
		BotPlayJob:         get("BOTPLAY_JOB"),
		NodeJob:            get("NODE_JOB"),
		TelegramToken:      strings.TrimSpace(getenv("TELEGRAM_BOT_TOKEN")),
		TelegramAPIURL:     strings.TrimRight(get("TELEGRAM_API_URL"), "/"),
		DryRunDir:          get("DRY_RUN_DIR"),
		DailyReportAt:      get("DAILY_REPORT_AT"),
		WebhookBearerToken: strings.TrimSpace(getenv("WEBHOOK_BEARER_TOKEN")),
		BackendAPIURL:      strings.TrimRight(get("BACKEND_API_URL"), "/"),
		BackendAdminKey:    strings.TrimSpace(getenv("BACKEND_ADMIN_KEY")),
		PlayBucket:         get("PLAY_REPORTS_BUCKET"),
		PlayPackage:        get("PLAY_PACKAGE_NAME"),
		GA4Property:        get("GA4_PROPERTY_ID"),
		GCSAPIURL:          get("GCS_API_URL"),
		GA4APIURL:          get("GA4_API_URL"),
		GoogleCreds:        get("GOOGLE_APPLICATION_CREDENTIALS"),
		AlertChartWindow:   time.Hour,
	}
	c.PromTimeout = dur("PROM_TIMEOUT", time.Second, false)
	c.TelegramMinGap = dur("TELEGRAM_MIN_GAP", 0, true)
	c.StatusInterval = dur("STATUS_INTERVAL", time.Minute, true)
	c.AlertDedupeWindow = dur("ALERT_DEDUPE_WINDOW", 0, true)
	c.CommandTimeout = dur("COMMAND_REPORT_TIMEOUT", 5*time.Second, false)
	c.CommandDedupe = dur("COMMAND_DEDUPE_WINDOW", 0, true)
	c.TelegramCommands = boolean("TELEGRAM_COMMANDS")
	c.DryRun = boolean("TELEGRAM_DRY_RUN")
	c.StatusAlign = boolean("STATUS_ALIGN")
	c.StatusOnStart = boolean("STATUS_ON_START")

	loc, err := time.LoadLocation(c.TZName)
	if err != nil {
		fail("TZ_NAME: unknown time zone %q", c.TZName)
		loc = time.UTC
	}
	c.Location = loc

	switch strings.ToLower(c.DailyReportAt) {
	case "off", "false", "0", "disabled":
		c.DailyEnabled = false
	default:
		h, m, ok := ParseClock(c.DailyReportAt)
		if !ok {
			fail("DAILY_REPORT_AT: want HH:MM (24 h) or off, got %q", c.DailyReportAt)
		}
		c.DailyHour, c.DailyMinute, c.DailyEnabled = h, m, ok
	}

	if n, err := strconv.Atoi(get("TREND_DAYS")); err != nil || n < 2 || n > 90 {
		fail("TREND_DAYS: want an integer between 2 and 90")
	} else {
		c.TrendDays = n
	}
	c.ReportFormat = Format(strings.ToLower(get("REPORT_FORMAT")))
	if c.ReportFormat != FormatPDF && c.ReportFormat != FormatText {
		fail("REPORT_FORMAT: want pdf or text")
	}
	c.AlertFormat = Format(strings.ToLower(get("ALERT_FORMAT")))
	if c.AlertFormat != FormatPDF && c.AlertFormat != FormatText {
		fail("ALERT_FORMAT: want text or pdf")
	}

	if u, err := url.Parse(c.PromURL); err != nil || u.Scheme == "" || u.Host == "" {
		fail("PROM_URL: want an absolute http(s) URL")
	}
	if u, err := url.Parse(c.TelegramAPIURL); err != nil || u.Scheme == "" || u.Host == "" {
		fail("TELEGRAM_API_URL: want an absolute http(s) URL")
	}
	if c.BackendAPIURL != "" {
		if u, err := url.Parse(c.BackendAPIURL); err != nil || (u.Scheme != "http" && u.Scheme != "https") || u.Host == "" {
			fail("BACKEND_API_URL: want an absolute http(s) URL")
		}
		if c.BackendAdminKey == "" {
			fail("BACKEND_ADMIN_KEY is required when BACKEND_API_URL is set")
		}
	}
	for _, id := range strings.Split(getenv("TELEGRAM_CHAT_IDS"), ",") {
		id = strings.TrimSpace(id)
		if id == "" {
			continue
		}
		if _, err := strconv.ParseInt(id, 10, 64); err != nil && !strings.HasPrefix(id, "@") {
			fail("TELEGRAM_CHAT_IDS: %q is neither a numeric chat id nor an @channel", id)
			continue
		}
		c.TelegramChatIDs = append(c.TelegramChatIDs, id)
	}
	if !c.DryRun {
		if c.TelegramToken == "" {
			fail("TELEGRAM_BOT_TOKEN is required (or set TELEGRAM_DRY_RUN=true)")
		} else if !validToken(c.TelegramToken) {
			fail("TELEGRAM_BOT_TOKEN does not look like a bot token (<digits>:<secret>); value not shown")
		}
		if len(c.TelegramChatIDs) == 0 {
			fail("TELEGRAM_CHAT_IDS is required (comma-separated chat ids)")
		}
	}
	c.PlayEnabled = c.PlayBucket != ""
	c.GA4Enabled = c.GA4Property != ""
	if len(errs) > 0 {
		return nil, errors.Join(errs...)
	}
	return c, nil
}

// ParseClock parses "HH:MM" (24-hour clock).
func ParseClock(s string) (hour, minute int, ok bool) {
	h, m, found := strings.Cut(strings.TrimSpace(s), ":")
	if !found {
		return 0, 0, false
	}
	hh, err1 := strconv.Atoi(h)
	mm, err2 := strconv.Atoi(m)
	if err1 != nil || err2 != nil || hh < 0 || hh > 23 || mm < 0 || mm > 59 || len(m) != 2 {
		return 0, 0, false
	}
	return hh, mm, true
}

func validToken(t string) bool {
	id, secret, ok := strings.Cut(t, ":")
	if !ok || id == "" || len(secret) < 20 {
		return false
	}
	_, err := strconv.ParseInt(id, 10, 64)
	return err == nil
}

func orUnset(s string) string {
	if s == "" {
		return "unset"
	}
	return s
}

// String describes the configuration without secrets (for the startup log).
func (c *Config) String() string {
	set := func(s string) string {
		if s == "" {
			return "unset"
		}
		return "set"
	}
	daily := "off"
	if c.DailyEnabled {
		daily = fmt.Sprintf("%02d:%02d", c.DailyHour, c.DailyMinute)
	}
	return fmt.Sprintf("env=%s tz=%s http=%s prom=%s status_interval=%s daily=%s report=%s alert=%s "+
		"chats=%d token=%s dry_run=%t commands=%t play=%t ga4=%t webhook_auth=%s backend_api=%s admin_key=%s "+
		"command_timeout=%s command_dedupe=%s",
		c.EnvName, c.TZName, c.HTTPAddr, c.PromURL, c.StatusInterval, daily, c.ReportFormat, c.AlertFormat,
		len(c.TelegramChatIDs), set(c.TelegramToken), c.DryRun, c.TelegramCommands, c.PlayEnabled, c.GA4Enabled,
		set(c.WebhookBearerToken), orUnset(c.BackendAPIURL), set(c.BackendAdminKey), c.CommandTimeout, c.CommandDedupe)
}
