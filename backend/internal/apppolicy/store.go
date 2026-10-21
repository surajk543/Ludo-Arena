package apppolicy

import (
	"bufio"
	"context"
	"errors"
	"log/slog"
	"os"
	"os/signal"
	"strings"
	"sync"
	"sync/atomic"
	"syscall"
	"time"
)

// ErrClientVersion is returned when the client's platform/version/build
// metadata is missing or malformed.
var ErrClientVersion = errors.New("client version metadata missing or invalid")

// Store holds the active policy and reloads it.
type Store struct {
	path     string
	flagPath string
	env      string
	log      *slog.Logger
	now      func() time.Time

	cur atomic.Pointer[state]

	mu          sync.Mutex // serializes reloads
	fileModTime time.Time
	flagModTime time.Time
	flagPresent bool
}

type state struct {
	policy      *compiled
	flagActive  bool
	flagMessage string
}

// NewStore loads the policy file once; it fails if the file is invalid.
func NewStore(path, flagPath, env string, log *slog.Logger) (*Store, error) {
	s := &Store{path: path, flagPath: flagPath, env: env, log: log, now: time.Now}
	if err := s.Reload(); err != nil {
		return nil, err
	}
	return s, nil
}

// SetClock overrides the clock (tests).
func (s *Store) SetClock(now func() time.Time) { s.now = now }

// Reload re-reads the policy file and the maintenance flag file. On a policy
// validation error the previous policy stays active and the error is returned.
func (s *Store) Reload() error {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.reloadLocked(true)
}

func (s *Store) reloadLocked(force bool) error {
	prev := s.cur.Load()
	next := &state{}
	if prev != nil {
		*next = *prev
	}

	var policyErr error
	if info, err := os.Stat(s.path); err != nil {
		policyErr = err
	} else if force || !info.ModTime().Equal(s.fileModTime) {
		raw, err := os.ReadFile(s.path)
		if err == nil {
			var c *compiled
			if c, err = Parse(raw, s.env); err == nil {
				next.policy = c
				s.fileModTime = info.ModTime()
				if prev == nil || prev.policy == nil || prev.policy.sha256 != c.sha256 {
					s.log.Info("app policy loaded", "configVersion", c.file.ConfigVersion,
						"environment", c.file.Environment, "entryFees", c.entryFees, "welcome", c.welcome,
						"sha256", c.sha256)
				}
			}
		}
		if err != nil {
			policyErr = err
			s.fileModTime = info.ModTime() // don't re-log the same bad file every poll
			s.log.Error("app policy rejected; keeping previous policy", "error", err.Error())
		}
	}

	if s.flagPath != "" {
		info, err := os.Stat(s.flagPath)
		switch {
		case err == nil:
			if force || !s.flagPresent || !info.ModTime().Equal(s.flagModTime) {
				next.flagActive = true
				next.flagMessage = readFlagMessage(s.flagPath)
				s.flagModTime = info.ModTime()
				if !s.flagPresent {
					s.log.Warn("maintenance flag file present: maintenance enabled")
				}
			}
			s.flagPresent = true
		case errors.Is(err, os.ErrNotExist):
			if s.flagPresent {
				s.log.Warn("maintenance flag file removed: flag maintenance disabled")
			}
			next.flagActive, next.flagMessage, s.flagPresent = false, "", false
		}
	}

	if next.policy == nil {
		if policyErr == nil {
			policyErr = errors.New("no policy loaded")
		}
		return policyErr
	}
	s.cur.Store(next)
	return policyErr
}

func readFlagMessage(path string) string {
	f, err := os.Open(path)
	if err != nil {
		return ""
	}
	defer f.Close()
	sc := bufio.NewScanner(f)
	if sc.Scan() {
		msg := strings.TrimSpace(sc.Text())
		if r := []rune(msg); len(r) > 500 {
			msg = string(r[:500])
		}
		return msg
	}
	return ""
}

// Run polls for changes every interval and reloads on SIGHUP until ctx ends.
func (s *Store) Run(ctx context.Context, interval time.Duration) {
	hup := make(chan os.Signal, 1)
	signal.Notify(hup, syscall.SIGHUP)
	defer signal.Stop(hup)
	t := time.NewTicker(interval)
	defer t.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-hup:
			s.log.Info("SIGHUP: reloading app policy")
			_ = s.Reload()
		case <-t.C:
			s.mu.Lock()
			_ = s.reloadLocked(false)
			s.mu.Unlock()
		}
	}
}

// EntryFee returns the live entry fee for game: the active policy file's value
// when it sets one, otherwise fallback (the ENTRY_FEE_* environment value or
// the built-in default). It reflects every accepted reload immediately.
func (s *Store) EntryFee(game string, fallback int64) int64 {
	if st := s.cur.Load(); st != nil && st.policy != nil {
		if fee, ok := st.policy.entryFees[game]; ok {
			return fee
		}
	}
	return fallback
}

// EntryFees resolves EntryFee for every game in fallback and returns a new
// map (game id → coins).
func (s *Store) EntryFees(fallback map[string]int64) map[string]int64 {
	out := make(map[string]int64, len(fallback))
	for game, fee := range fallback {
		out[game] = s.EntryFee(game, fee)
	}
	return out
}

// Welcome returns the live one-time grant for a new account: each of coins and
// diamonds comes from the active policy file when it sets it, otherwise from
// the fallback (WELCOME_COINS / WELCOME_DIAMONDS or the built-in default).
func (s *Store) Welcome(fallbackCoins, fallbackDiamonds int64) (coins, diamonds int64) {
	coins, diamonds = fallbackCoins, fallbackDiamonds
	if st := s.cur.Load(); st != nil && st.policy != nil {
		if v, ok := st.policy.welcome[WelcomeCoins]; ok {
			coins = v
		}
		if v, ok := st.policy.welcome[WelcomeDiamonds]; ok {
			diamonds = v
		}
	}
	return coins, diamonds
}

// Client identifies the calling app build.
type Client struct {
	Platform Platform
	Version  Version
	Build    int
}

// ParseClient validates raw header/query values.
func ParseClient(platform, version, build string) (Client, error) {
	p, ok := ParsePlatform(platform)
	if !ok {
		return Client{}, ErrClientVersion
	}
	v, err := ParseVersion(version)
	if err != nil {
		return Client{}, ErrClientVersion
	}
	b := 0
	if strings.TrimSpace(build) != "" {
		for _, r := range strings.TrimSpace(build) {
			if r < '0' || r > '9' {
				return Client{}, ErrClientVersion
			}
		}
		if len(build) > 9 {
			return Client{}, ErrClientVersion
		}
		for _, r := range strings.TrimSpace(build) {
			b = b*10 + int(r-'0')
		}
	}
	return Client{Platform: p, Version: v, Build: b}, nil
}

// MaintenanceInfo describes maintenance status in a Decision.
type MaintenanceInfo struct {
	Enabled         bool       `json:"enabled"`
	Message         string     `json:"message"`
	StartsAtUTC     *time.Time `json:"startsAtUtc"`
	ScheduledEndUTC *time.Time `json:"scheduledEndUtc"`
}

// Decision is the evaluated policy for one client (the /app/config body).
type Decision struct {
	ConfigVersion               int             `json:"configVersion"`
	Environment                 string          `json:"environment"`
	Platform                    Platform        `json:"platform"`
	Mode                        Mode            `json:"mode"`
	InstalledVersion            string          `json:"installedVersion"`
	InstalledBuild              int             `json:"installedBuild"`
	MinimumSupportedVersion     string          `json:"minimumSupportedVersion"`
	MinimumSupportedBuild       int             `json:"minimumSupportedBuild"`
	LatestVersion               string          `json:"latestVersion"`
	LatestBuild                 int             `json:"latestBuild"`
	StoreURL                    string          `json:"storeUrl"`
	StoreAvailable              bool            `json:"storeAvailable"`
	Title                       string          `json:"title"`
	Message                     string          `json:"message"`
	OptionalUpdateReminderHours int             `json:"optionalUpdateReminderHours"`
	Maintenance                 MaintenanceInfo `json:"maintenance"`
}

// Blocks reports whether the decision forbids online services.
func (d Decision) Blocks() bool { return d.Mode == ModeMaintenance || d.Mode == ModeForceUpdate }

// Evaluate computes the decision for c at the current time.
func (s *Store) Evaluate(c Client, locale string) Decision {
	st := s.cur.Load()
	now := s.now().UTC()
	p := st.policy.platforms[c.Platform]
	installed := Release{Version: c.Version, Build: c.Build}

	d := Decision{
		ConfigVersion:               st.policy.file.ConfigVersion,
		Environment:                 st.policy.file.Environment,
		Platform:                    c.Platform,
		InstalledVersion:            c.Version.String(),
		InstalledBuild:              c.Build,
		MinimumSupportedVersion:     p.MinimumSupportedVersion,
		MinimumSupportedBuild:       p.MinimumSupportedBuild,
		LatestVersion:               p.LatestVersion,
		LatestBuild:                 p.LatestBuild,
		StoreURL:                    p.StoreURL,
		StoreAvailable:              p.StoreURL != "",
		OptionalUpdateReminderHours: p.OptionalUpdateReminderHours,
	}

	maint := s.maintenance(st, p, now, locale)
	d.Maintenance = maint
	belowMin := installed.Less(p.min)

	switch {
	case maint.Enabled && !(belowMin && p.SecurityCritical):
		d.Mode = ModeMaintenance
		d.Message = maint.Message
	case belowMin:
		d.Mode = ModeForceUpdate
		d.Title = p.ForceUpdateTitle.Resolve(locale)
		d.Message = p.ForceUpdateMessage.Resolve(locale)
	case installed.Less(p.latest):
		d.Mode = ModeOptionalUpdate
		d.Title = p.OptionalUpdateTitle.Resolve(locale)
		d.Message = p.OptionalUpdateMessage.Resolve(locale)
	default:
		d.Mode = ModeNormal
	}
	return d
}

// MaintenanceActive reports whether maintenance applies to platform right now
// (used for bots and server-side timers, which have no app version).
func (s *Store) MaintenanceActive(platform Platform) bool {
	st := s.cur.Load()
	p, ok := st.policy.platforms[platform]
	if !ok {
		p = compiledPlatform{}
	}
	return s.maintenance(st, p, s.now().UTC(), "en").Enabled
}

// GlobalMaintenanceActive reports maintenance that applies to every platform
// (flag file, global switch or an active window). Platform-only maintenance
// does not pause games, because players on the other platform may continue.
func (s *Store) GlobalMaintenanceActive() bool {
	return s.maintenance(s.cur.Load(), compiledPlatform{}, s.now().UTC(), "en").Enabled
}

func (s *Store) maintenance(st *state, p compiledPlatform, now time.Time, locale string) MaintenanceInfo {
	f := st.policy.file
	var info MaintenanceInfo
	var windowMsg Text
	var upcoming *Window
	for i := range f.Maintenance.Windows {
		w := f.Maintenance.Windows[i]
		if !now.Before(w.StartsAtUTC) && now.Before(w.EndsAtUTC) {
			info.Enabled = true
			start, end := w.StartsAtUTC, w.EndsAtUTC
			info.StartsAtUTC, info.ScheduledEndUTC = &start, &end
			windowMsg = w.Message
			break
		}
		if now.Before(w.StartsAtUTC) && w.StartsAtUTC.Sub(now) <= 24*time.Hour &&
			(upcoming == nil || w.StartsAtUTC.Before(upcoming.StartsAtUTC)) {
			upcoming = &w
		}
	}
	if st.flagActive || f.Maintenance.Enabled || p.Maintenance.Enabled {
		info.Enabled = true
	}
	if !info.Enabled && upcoming != nil {
		// Announce the next window without blocking anything yet.
		start, end := upcoming.StartsAtUTC, upcoming.EndsAtUTC
		info.StartsAtUTC, info.ScheduledEndUTC = &start, &end
		info.Message = upcoming.Message.Resolve(locale)
		return info
	}
	if !info.Enabled {
		return info
	}
	switch {
	case st.flagActive && st.flagMessage != "":
		info.Message = st.flagMessage
	case len(windowMsg) > 0:
		info.Message = windowMsg.Resolve(locale)
	case p.Maintenance.Enabled && !f.Maintenance.Enabled && len(p.Maintenance.Message) > 0:
		info.Message = p.Maintenance.Message.Resolve(locale)
	default:
		info.Message = f.Maintenance.Message.Resolve(locale)
	}
	return info
}
