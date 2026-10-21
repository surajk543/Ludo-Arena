// Package apppolicy implements backend-controlled force update, optional
// update and maintenance mode (docs/app-version-policy.md).
//
// The policy is a validated JSON file per environment, reloaded atomically on
// SIGHUP or when its modification time changes. An invalid file is rejected as
// a whole and the previous policy stays active. A flag file provides an
// emergency maintenance switch that needs no JSON editing.
package apppolicy

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"net/url"
	"strings"
	"time"
)

// Platform is a client platform.
type Platform string

// Supported platforms.
const (
	Android Platform = "android"
	IOS     Platform = "ios"
)

// ParsePlatform validates a platform name.
func ParsePlatform(s string) (Platform, bool) {
	switch Platform(strings.ToLower(strings.TrimSpace(s))) {
	case Android:
		return Android, true
	case IOS:
		return IOS, true
	}
	return "", false
}

// Mode is the evaluated policy outcome.
type Mode string

// Policy modes, in precedence order.
const (
	ModeMaintenance    Mode = "maintenance"
	ModeForceUpdate    Mode = "force_update"
	ModeOptionalUpdate Mode = "optional_update"
	ModeNormal         Mode = "normal"
)

// Text is a message that is either a plain string or a map of locale → text.
type Text map[string]string

// UnmarshalJSON accepts "text" or {"en":"...","hi":"..."}.
func (t *Text) UnmarshalJSON(b []byte) error {
	b = bytes.TrimSpace(b)
	if len(b) > 0 && b[0] == '"' {
		var s string
		if err := json.Unmarshal(b, &s); err != nil {
			return err
		}
		*t = Text{"en": s}
		return nil
	}
	var m map[string]string
	if err := json.Unmarshal(b, &m); err != nil {
		return err
	}
	*t = Text(m)
	return nil
}

// Resolve picks the best translation for locale: exact tag, then language,
// then English, then empty (the client then shows its own translated text).
func (t Text) Resolve(locale string) string {
	if len(t) == 0 {
		return ""
	}
	locale = strings.ToLower(strings.ReplaceAll(strings.TrimSpace(locale), "_", "-"))
	if v := t[locale]; v != "" {
		return v
	}
	if lang, _, ok := strings.Cut(locale, "-"); ok {
		if v := t[lang]; v != "" {
			return v
		}
	}
	return t["en"]
}

func (t Text) validate(field string) error {
	for k, v := range t {
		if len(k) < 2 || len(k) > 10 {
			return fmt.Errorf("%s: invalid locale key %q", field, k)
		}
		if len([]rune(v)) > 500 {
			return fmt.Errorf("%s[%s]: message longer than 500 characters", field, k)
		}
	}
	return nil
}

// File is the on-disk policy document.
type File struct {
	ConfigVersion int                       `json:"configVersion"`
	Environment   string                    `json:"environment"`
	Maintenance   GlobalMaintenance         `json:"maintenance"`
	Platforms     map[string]PlatformPolicy `json:"platforms"`
}

// GlobalMaintenance applies to every platform.
type GlobalMaintenance struct {
	Enabled bool     `json:"enabled"`
	Message Text     `json:"message"`
	Windows []Window `json:"windows"`
}

// Window is a scheduled maintenance period.
type Window struct {
	StartsAtUTC time.Time `json:"startsAtUtc"`
	EndsAtUTC   time.Time `json:"endsAtUtc"`
	Message     Text      `json:"message"`
}

// PlatformPolicy is the per-platform policy.
type PlatformPolicy struct {
	MinimumSupportedVersion     string `json:"minimumSupportedVersion"`
	MinimumSupportedBuild       int    `json:"minimumSupportedBuild"`
	LatestVersion               string `json:"latestVersion"`
	LatestBuild                 int    `json:"latestBuild"`
	StoreURL                    string `json:"storeUrl"`
	ForceUpdateTitle            Text   `json:"forceUpdateTitle"`
	ForceUpdateMessage          Text   `json:"forceUpdateMessage"`
	OptionalUpdateTitle         Text   `json:"optionalUpdateTitle"`
	OptionalUpdateMessage       Text   `json:"optionalUpdateMessage"`
	OptionalUpdateReminderHours int    `json:"optionalUpdateReminderHours"`
	SecurityCritical            bool   `json:"securityCritical"`
	Maintenance                 struct {
		Enabled bool `json:"enabled"`
		Message Text `json:"message"`
	} `json:"maintenance"`
}

// compiled is a validated, parsed policy.
type compiled struct {
	file      File
	sha256    string
	platforms map[Platform]compiledPlatform
}

type compiledPlatform struct {
	PlatformPolicy
	min    Release
	latest Release
}

// Parse validates raw policy JSON for the given environment.
func Parse(raw []byte, env string) (*compiled, error) {
	dec := json.NewDecoder(bytes.NewReader(raw))
	dec.DisallowUnknownFields()
	var f File
	if err := dec.Decode(&f); err != nil {
		return nil, fmt.Errorf("decode policy: %w", err)
	}
	var errs []error
	if f.ConfigVersion < 1 {
		errs = append(errs, errors.New("configVersion must be >= 1"))
	}
	switch f.Environment {
	case "development", "preproduction", "production":
	default:
		errs = append(errs, errors.New("environment must be development, preproduction or production"))
	}
	if f.Environment != env {
		errs = append(errs, fmt.Errorf("environment %q does not match APP_ENV %q", f.Environment, env))
	}
	if err := f.Maintenance.Message.validate("maintenance.message"); err != nil {
		errs = append(errs, err)
	}
	for i, w := range f.Maintenance.Windows {
		if w.StartsAtUTC.IsZero() || w.EndsAtUTC.IsZero() || !w.EndsAtUTC.After(w.StartsAtUTC) {
			errs = append(errs, fmt.Errorf("maintenance.windows[%d]: endsAtUtc must be after startsAtUtc", i))
		}
		if err := w.Message.validate(fmt.Sprintf("maintenance.windows[%d].message", i)); err != nil {
			errs = append(errs, err)
		}
	}
	c := &compiled{file: f, platforms: map[Platform]compiledPlatform{}}
	for name := range f.Platforms {
		if _, ok := ParsePlatform(name); !ok || name != strings.ToLower(name) {
			errs = append(errs, fmt.Errorf("platforms: unknown platform %q", name))
		}
	}
	for _, p := range []Platform{Android, IOS} {
		pp, ok := f.Platforms[string(p)]
		if !ok {
			errs = append(errs, fmt.Errorf("platforms.%s is required", p))
			continue
		}
		cp := compiledPlatform{PlatformPolicy: pp}
		var err error
		if cp.min.Version, err = ParseVersion(pp.MinimumSupportedVersion); err != nil {
			errs = append(errs, fmt.Errorf("platforms.%s.minimumSupportedVersion: %w", p, err))
		}
		if cp.latest.Version, err = ParseVersion(pp.LatestVersion); err != nil {
			errs = append(errs, fmt.Errorf("platforms.%s.latestVersion: %w", p, err))
		}
		if pp.MinimumSupportedBuild < 0 || pp.LatestBuild < 0 {
			errs = append(errs, fmt.Errorf("platforms.%s: builds must be >= 0", p))
		}
		cp.min.Build, cp.latest.Build = pp.MinimumSupportedBuild, pp.LatestBuild
		if cp.latest.Less(cp.min) {
			errs = append(errs, fmt.Errorf("platforms.%s: latest version/build must be >= minimum", p))
		}
		if pp.OptionalUpdateReminderHours < 0 || pp.OptionalUpdateReminderHours > 24*30 {
			errs = append(errs, fmt.Errorf("platforms.%s.optionalUpdateReminderHours must be 0..720", p))
		}
		if err := validateStoreURL(p, pp.StoreURL); err != nil {
			errs = append(errs, fmt.Errorf("platforms.%s.storeUrl: %w", p, err))
		}
		for field, t := range map[string]Text{
			"forceUpdateTitle": pp.ForceUpdateTitle, "forceUpdateMessage": pp.ForceUpdateMessage,
			"optionalUpdateTitle": pp.OptionalUpdateTitle, "optionalUpdateMessage": pp.OptionalUpdateMessage,
			"maintenance.message": pp.Maintenance.Message,
		} {
			if err := t.validate(fmt.Sprintf("platforms.%s.%s", p, field)); err != nil {
				errs = append(errs, err)
			}
		}
		c.platforms[p] = cp
	}
	if len(errs) > 0 {
		return nil, errors.Join(errs...)
	}
	sum := sha256.Sum256(raw)
	c.sha256 = hex.EncodeToString(sum[:])
	return c, nil
}

// validateStoreURL requires an official store host for the platform, or empty
// (meaning the update is not yet available in the store).
func validateStoreURL(p Platform, raw string) error {
	if raw == "" {
		return nil
	}
	u, err := url.Parse(raw)
	if err != nil || u.Scheme != "https" || u.Host == "" {
		return errors.New("must be an https URL or empty")
	}
	switch p {
	case Android:
		if u.Host != "play.google.com" {
			return errors.New("android store URL must be on play.google.com")
		}
	case IOS:
		if u.Host != "apps.apple.com" && u.Host != "itunes.apple.com" {
			return errors.New("ios store URL must be on apps.apple.com")
		}
	}
	return nil
}
