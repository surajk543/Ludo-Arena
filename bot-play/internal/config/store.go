package config

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"log/slog"
	"os"
	"sync"
	"sync/atomic"
	"time"

	"ludoroyale/botplay/internal/profiles"
)

// Snapshot is one immutable, validated configuration generation. Readers
// must never mutate it.
type Snapshot struct {
	Config     *Config
	Profiles   *profiles.Set
	Generation int64
	LoadedAt   time.Time
	Digest     string // sha256 of config+profiles bytes (for logs)
}

// LoadFiles parses and cross-validates the config and profiles files.
func LoadFiles(configPath, profilesPath string) (*Snapshot, error) {
	cb, err := os.ReadFile(configPath)
	if err != nil {
		return nil, fmt.Errorf("config: read %s: %w", configPath, err)
	}
	pb, err := os.ReadFile(profilesPath)
	if err != nil {
		return nil, fmt.Errorf("profiles: read %s: %w", profilesPath, err)
	}
	return LoadBytes(cb, pb)
}

// LoadBytes is LoadFiles for in-memory content.
func LoadBytes(configYAML, profilesYAML []byte) (*Snapshot, error) {
	c, err := Parse(configYAML)
	if err != nil {
		return nil, err
	}
	ps, err := profiles.Parse(profilesYAML)
	if err != nil {
		return nil, err
	}
	if err := c.ValidateProfiles(ps); err != nil {
		return nil, err
	}
	h := sha256.New()
	h.Write(configYAML)
	h.Write([]byte{0})
	h.Write(profilesYAML)
	return &Snapshot{Config: c, Profiles: ps, LoadedAt: time.Now(), Digest: hex.EncodeToString(h.Sum(nil))[:16]}, nil
}

// Store holds the active snapshot and swaps it atomically.
type Store struct {
	cur  atomic.Pointer[Snapshot]
	mu   sync.Mutex
	subs []chan *Snapshot
}

// NewStore creates a store with an initial snapshot.
func NewStore(initial *Snapshot) *Store {
	s := &Store{}
	initial.Generation = 1
	s.cur.Store(initial)
	return s
}

// Load returns the active snapshot (never nil).
func (s *Store) Load() *Snapshot { return s.cur.Load() }

// Config is shorthand for Load().Config.
func (s *Store) Config() *Config { return s.cur.Load().Config }

// Apply validates compatibility and swaps in next. On error the previous
// snapshot stays active.
func (s *Store) Apply(next *Snapshot) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	old := s.cur.Load()
	if err := CheckReloadCompatible(old.Config, next.Config); err != nil {
		return err
	}
	next.Generation = old.Generation + 1
	s.cur.Store(next)
	for _, ch := range s.subs {
		select { // coalesce: subscribers only need the latest snapshot
		case ch <- next:
		default:
			select {
			case <-ch:
			default:
			}
			select {
			case ch <- next:
			default:
			}
		}
	}
	return nil
}

// Subscribe returns a channel that receives each newly applied snapshot
// (coalesced: a slow subscriber sees the latest).
func (s *Store) Subscribe() <-chan *Snapshot {
	s.mu.Lock()
	defer s.mu.Unlock()
	ch := make(chan *Snapshot, 1)
	s.subs = append(s.subs, ch)
	return ch
}

// ReloadResult is reported to observers (metrics).
type ReloadResult func(ok bool)

// Watcher reloads the config and profiles files when they change (mtime/size
// poll every app.reload_poll_seconds) or on demand (SIGHUP).
type Watcher struct {
	ConfigPath   string
	ProfilesPath string
	Store        *Store
	Logger       *slog.Logger
	OnResult     ReloadResult

	lastCfg, lastProf fileStamp
}

type fileStamp struct {
	mod  time.Time
	size int64
}

func stamp(path string) fileStamp {
	fi, err := os.Stat(path)
	if err != nil {
		return fileStamp{}
	}
	return fileStamp{mod: fi.ModTime(), size: fi.Size()}
}

// Reload re-reads both files. Invalid content is rejected as a whole and the
// last valid snapshot stays active.
func (w *Watcher) Reload(reason string) error {
	w.lastCfg, w.lastProf = stamp(w.ConfigPath), stamp(w.ProfilesPath)
	next, err := LoadFiles(w.ConfigPath, w.ProfilesPath)
	if err == nil {
		err = w.Store.Apply(next)
	}
	if err != nil {
		w.Logger.Error("config reload rejected; keeping last valid configuration",
			"reason", reason, "error", err.Error(), "active_generation", w.Store.Load().Generation)
		if w.OnResult != nil {
			w.OnResult(false)
		}
		return err
	}
	w.Logger.Info("config reloaded", "reason", reason, "generation", next.Generation, "digest", next.Digest)
	if w.OnResult != nil {
		w.OnResult(true)
	}
	return nil
}

// Run polls for changes and handles reload requests until ctx is done.
func (w *Watcher) Run(ctx context.Context, hup <-chan os.Signal) {
	if w.lastCfg == (fileStamp{}) {
		w.lastCfg, w.lastProf = stamp(w.ConfigPath), stamp(w.ProfilesPath)
	}
	for {
		poll := time.Duration(w.Store.Config().App.ReloadPollSeconds) * time.Second
		var tick <-chan time.Time
		var t *time.Timer
		if poll > 0 {
			t = time.NewTimer(poll)
			tick = t.C
		}
		select {
		case <-ctx.Done():
			if t != nil {
				t.Stop()
			}
			return
		case <-hup:
			_ = w.Reload("sighup")
		case <-tick:
			if c, p := stamp(w.ConfigPath), stamp(w.ProfilesPath); c != w.lastCfg || p != w.lastProf {
				_ = w.Reload("file_changed")
			}
		}
		if t != nil {
			t.Stop()
		}
	}
}
