// Package logging configures structured JSON logging.
package logging

import (
	"log/slog"
	"os"
	"strings"
)

// New returns a JSON slog logger at the given level (debug|info|warn|error).
func New(level string) *slog.Logger {
	var lvl slog.Level
	switch strings.ToLower(level) {
	case "debug":
		lvl = slog.LevelDebug
	case "warn":
		lvl = slog.LevelWarn
	case "error":
		lvl = slog.LevelError
	default:
		lvl = slog.LevelInfo
	}
	return slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{
		Level: lvl,
		ReplaceAttr: func(_ []string, a slog.Attr) slog.Attr {
			// Defense in depth: never emit credential-like attributes even if a
			// caller passes them by mistake.
			switch strings.ToLower(a.Key) {
			case "token", "access_token", "refresh_token", "id_token", "authorization",
				"password", "secret", "guest_secret", "api_key", "key":
				return slog.String(a.Key, "[REDACTED]")
			}
			return a
		},
	}))
}
