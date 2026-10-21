package apppolicy

import (
	"errors"
	"strconv"
	"strings"
)

// ErrInvalidVersion is returned for malformed version strings.
var ErrInvalidVersion = errors.New("invalid version")

// Version is a numeric dotted version with 1–4 components ("1", "1.2",
// "1.10.0", "2.0.0.1"). Missing components compare as zero, so 1.2 == 1.2.0.
// Pre-release or build suffixes are rejected.
type Version struct {
	parts [4]int
	raw   string
}

// ParseVersion parses s strictly.
func ParseVersion(s string) (Version, error) {
	s = strings.TrimSpace(s)
	if s == "" || len(s) > 32 {
		return Version{}, ErrInvalidVersion
	}
	fields := strings.Split(s, ".")
	if len(fields) > 4 {
		return Version{}, ErrInvalidVersion
	}
	var v Version
	for i, f := range fields {
		if f == "" || len(f) > 6 {
			return Version{}, ErrInvalidVersion
		}
		for _, r := range f {
			if r < '0' || r > '9' {
				return Version{}, ErrInvalidVersion
			}
		}
		n, err := strconv.Atoi(f)
		if err != nil {
			return Version{}, ErrInvalidVersion
		}
		v.parts[i] = n
	}
	v.raw = s
	return v, nil
}

// String returns the version as it was written.
func (v Version) String() string { return v.raw }

// Compare returns -1, 0 or 1 comparing numeric components (never lexically).
func (v Version) Compare(o Version) int {
	for i := range v.parts {
		switch {
		case v.parts[i] < o.parts[i]:
			return -1
		case v.parts[i] > o.parts[i]:
			return 1
		}
	}
	return 0
}

// Release is a (version, build) pair. Builds only matter when versions are
// equal; a build of 0 in a requirement means "any build".
type Release struct {
	Version Version
	Build   int
}

// Less reports whether r is older than the requirement req.
func (r Release) Less(req Release) bool {
	switch r.Version.Compare(req.Version) {
	case -1:
		return true
	case 1:
		return false
	}
	return req.Build > 0 && r.Build < req.Build
}
