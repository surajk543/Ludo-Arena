// Package profiles defines bot behaviour profiles (think time + Ludo move
// scoring weights) loaded from profiles.yaml.
//
// A profile never changes what is legal: the backend decides legality and
// dice. A profile only changes how long a bot "thinks" and how it ranks the
// legal Ludo moves the server already listed. Snakes & Ladders has no choices,
// so profiles only affect its think time.
package profiles

import (
	"bytes"
	"errors"
	"fmt"
	"os"
	"regexp"
	"sort"

	"go.yaml.in/yaml/v3"
)

// Limits used by validation.
const (
	MaxWeight      = 1000.0
	MaxThinkTimeMS = 15000
)

var nameRE = regexp.MustCompile(`^[a-z][a-z0-9_-]{0,31}$`)

// ThinkTime is a think-time range in milliseconds.
type ThinkTime struct {
	MinMS int `yaml:"min" json:"min"`
	MaxMS int `yaml:"max" json:"max"`
}

// Weights are the Ludo move-scoring weights. All weights are magnitudes
// (>= 0); AvoidDanger is applied as a penalty.
type Weights struct {
	// Bonus for bringing a token out of base onto its start square.
	EnterFromBase float64 `yaml:"enter_from_base" json:"enter_from_base"`
	// Bonus per opponent token sent back to base.
	CaptureOpponent float64 `yaml:"capture_opponent" json:"capture_opponent"`
	// Bonus for ending on a safe square (start/star squares, home column)
	// when the token is not already safe.
	ReachSafeSquare float64 `yaml:"reach_safe_square" json:"reach_safe_square"`
	// Bonus scaled by how far along the token is after the move (0..1).
	ProgressTowardHome float64 `yaml:"progress_toward_home" json:"progress_toward_home"`
	// Bonus for a move that reaches home (progress 56).
	CompleteHome float64 `yaml:"complete_home" json:"complete_home"`
	// Bonus for leaving a square an opponent could reach with a roll of 1-6.
	EscapeDanger float64 `yaml:"escape_danger" json:"escape_danger"`
	// Penalty for landing on a non-safe square 1-6 squares ahead of an
	// opponent token.
	AvoidDanger float64 `yaml:"avoid_danger" json:"avoid_danger"`
	// Amplitude of the seeded random jitter added to every candidate score.
	RandomJitter float64 `yaml:"random_jitter" json:"random_jitter"`
}

// Profile is one named behaviour profile.
type Profile struct {
	Name        string    `yaml:"-" json:"name"`
	Description string    `yaml:"description" json:"description"`
	ThinkTime   ThinkTime `yaml:"think_time_ms" json:"think_time_ms"`
	Weights     Weights   `yaml:"weights" json:"weights"`
}

// Set is the parsed profiles file.
type Set struct {
	Profiles map[string]*Profile `yaml:"profiles"`
}

// Get returns the profile with the given name.
func (s *Set) Get(name string) (*Profile, bool) {
	if s == nil {
		return nil, false
	}
	p, ok := s.Profiles[name]
	return p, ok
}

// Names returns the sorted profile names.
func (s *Set) Names() []string {
	if s == nil {
		return nil
	}
	out := make([]string, 0, len(s.Profiles))
	for n := range s.Profiles {
		out = append(out, n)
	}
	sort.Strings(out)
	return out
}

// LoadFile reads and validates a profiles file.
func LoadFile(path string) (*Set, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("profiles: read %s: %w", path, err)
	}
	return Parse(b)
}

// Parse decodes (strictly: unknown keys are errors) and validates profiles.
func Parse(b []byte) (*Set, error) {
	var s Set
	dec := yaml.NewDecoder(bytes.NewReader(b))
	dec.KnownFields(true)
	if err := dec.Decode(&s); err != nil {
		return nil, fmt.Errorf("profiles: parse: %w", err)
	}
	for name, p := range s.Profiles {
		if p == nil {
			return nil, fmt.Errorf("profiles: %q is empty", name)
		}
		p.Name = name
	}
	if err := s.Validate(); err != nil {
		return nil, err
	}
	return &s, nil
}

// Validate checks names, ranges and think times.
func (s *Set) Validate() error {
	if s == nil || len(s.Profiles) == 0 {
		return errors.New("profiles: at least one profile is required")
	}
	var errs []error
	for _, name := range s.Names() {
		p := s.Profiles[name]
		if !nameRE.MatchString(name) {
			errs = append(errs, fmt.Errorf("profiles: invalid name %q (want %s)", name, nameRE))
		}
		tt := p.ThinkTime
		if tt.MinMS < 0 || tt.MaxMS < 0 || tt.MaxMS > MaxThinkTimeMS {
			errs = append(errs, fmt.Errorf("profiles.%s.think_time_ms: values must be in 0..%d", name, MaxThinkTimeMS))
		}
		if tt.MinMS > tt.MaxMS {
			errs = append(errs, fmt.Errorf("profiles.%s.think_time_ms: min (%d) > max (%d)", name, tt.MinMS, tt.MaxMS))
		}
		w := p.Weights
		for _, f := range []struct {
			field string
			v     float64
		}{
			{"enter_from_base", w.EnterFromBase}, {"capture_opponent", w.CaptureOpponent},
			{"reach_safe_square", w.ReachSafeSquare}, {"progress_toward_home", w.ProgressTowardHome},
			{"complete_home", w.CompleteHome}, {"escape_danger", w.EscapeDanger},
			{"avoid_danger", w.AvoidDanger}, {"random_jitter", w.RandomJitter},
		} {
			if f.v < 0 || f.v > MaxWeight || f.v != f.v {
				errs = append(errs, fmt.Errorf("profiles.%s.weights.%s: must be in 0..%g", name, f.field, MaxWeight))
			}
		}
	}
	return errors.Join(errs...)
}
