package config

import (
	"errors"
	"fmt"
	"log/slog"
	"os"
	"strings"
	"unicode"
)

// ServiceKeyEnv is the only supported source of the bot service key. The key
// is never read from configuration files and is never logged.
const ServiceKeyEnv = "BOT_SERVICE_KEY"

// Secret holds a credential. Every formatting path (fmt, slog, JSON) prints
// "[REDACTED]"; use Reveal only where the raw value must go on the wire.
type Secret struct{ v string }

// NewSecret wraps a raw secret.
func NewSecret(v string) Secret { return Secret{v: v} }

// Reveal returns the raw value. Only HTTP header construction may call it.
func (s Secret) Reveal() string { return s.v }

// Empty reports whether the secret is unset.
func (s Secret) Empty() bool { return s.v == "" }

func (s Secret) String() string   { return "[REDACTED]" }
func (s Secret) GoString() string { return "[REDACTED]" }

// Format makes %v, %+v, %#v, %s and %q all redact.
func (s Secret) Format(f fmt.State, _ rune) { _, _ = f.Write([]byte("[REDACTED]")) }

// LogValue redacts in slog.
func (s Secret) LogValue() slog.Value { return slog.StringValue("[REDACTED]") }

// MarshalJSON redacts in JSON.
func (s Secret) MarshalJSON() ([]byte, error) { return []byte(`"[REDACTED]"`), nil }

// MarshalText redacts in text encoders.
func (s Secret) MarshalText() ([]byte, error) { return []byte("[REDACTED]"), nil }

// ServiceKeyFromEnv reads BOT_SERVICE_KEY. The returned warning (if any) is
// safe to log; it never contains the key.
func ServiceKeyFromEnv() (key Secret, warning string, err error) {
	return ServiceKeyFrom(os.Getenv(ServiceKeyEnv))
}

// ServiceKeyFrom validates a raw service key.
func ServiceKeyFrom(raw string) (key Secret, warning string, err error) {
	if raw == "" {
		return Secret{}, "", fmt.Errorf("%s is not set (the bot service key is only read from the environment)", ServiceKeyEnv)
	}
	if strings.IndexFunc(raw, func(r rune) bool { return unicode.IsSpace(r) || unicode.IsControl(r) }) >= 0 {
		return Secret{}, "", errors.New(ServiceKeyEnv + " contains whitespace or control characters")
	}
	// The backend only accepts keys of 32..256 characters (its SHA-256 is
	// configured as BOT_SERVICE_KEY_SHA256); fail fast instead of retrying 401s.
	if len(raw) < 32 || len(raw) > 256 {
		return Secret{}, "", fmt.Errorf("%s must be 32..256 characters", ServiceKeyEnv)
	}
	if len(raw) < 48 {
		warning = ServiceKeyEnv + " is shorter than 48 characters; prefer a long random key (e.g. openssl rand -hex 32)"
	}
	return NewSecret(raw), warning, nil
}

// sensitiveSuffixes: attributes whose (lower-cased) key equals or ends with
// one of these are redacted by RedactAttr regardless of value type.
var sensitiveSuffixes = []string{"token", "authorization", "key", "secret", "password", "jwt", "bearer", "cookie"}

// RedactAttr is a slog ReplaceAttr hook that blanks attributes whose key
// looks sensitive. It is defence in depth on top of the Secret type: no code
// in bot-play logs tokens, and this guarantees accidental additions are
// redacted too. (Ludo token indices are logged as "piece" for this reason.)
func RedactAttr(_ []string, a slog.Attr) slog.Attr {
	k := strings.ToLower(a.Key)
	for _, s := range sensitiveSuffixes {
		if strings.HasSuffix(k, s) {
			return slog.String(a.Key, "[REDACTED]")
		}
	}
	return a
}
