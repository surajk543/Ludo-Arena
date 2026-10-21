package config

import (
	"fmt"
	"net/url"
	"strings"
)

// LoadtestAckFlag is the CLI flag that must be passed to run load tests.
const LoadtestAckFlag = "--i-understand-this-is-a-load-test"

// Guard refusal reasons.
const (
	GuardEnvironment    = "environment"
	GuardDisabled       = "disabled"
	GuardNoAck          = "not_acknowledged"
	GuardForbiddenHost  = "forbidden_host"
	GuardHostNotAllowed = "host_not_allowed"
	GuardBadURL         = "bad_url"
	GuardBackendRefused = "backend_refused"
)

// GuardError explains why load-test mode refused to start.
type GuardError struct {
	Reason string
	Detail string
}

func (e *GuardError) Error() string {
	return "load test refused (" + e.Reason + "): " + e.Detail
}

// CheckLoadtestGuard enforces every local load-test safety rule. All must
// hold; the backend additionally refuses load-test sessions in production
// (that refusal is surfaced by the runner as GuardBackendRefused).
func CheckLoadtestGuard(c *Config, acknowledged bool) error {
	if c.App.Environment != EnvDevelopment && c.App.Environment != EnvPreprod {
		return &GuardError{GuardEnvironment, fmt.Sprintf("app.environment is %q; load tests run only in development or preprod", c.App.Environment)}
	}
	if !c.Loadtest.Enabled {
		return &GuardError{GuardDisabled, "loadtest.enabled is false"}
	}
	if !acknowledged {
		return &GuardError{GuardNoAck, "pass " + LoadtestAckFlag + " on the command line"}
	}
	for _, raw := range []string{c.Connection.BackendHTTPURL, c.Connection.BackendWSURL} {
		u, err := url.Parse(raw)
		if err != nil || u.Hostname() == "" {
			return &GuardError{GuardBadURL, fmt.Sprintf("cannot parse backend URL %q", raw)}
		}
		host := strings.ToLower(u.Hostname())
		for _, pat := range c.Loadtest.ForbiddenHosts {
			if HostMatches(pat, host) {
				return &GuardError{GuardForbiddenHost, fmt.Sprintf("backend host %q matches forbidden host %q", host, pat)}
			}
		}
		allowed := false
		for _, pat := range c.Loadtest.AllowedHosts {
			if HostMatches(pat, host) {
				allowed = true
				break
			}
		}
		if !allowed {
			return &GuardError{GuardHostNotAllowed, fmt.Sprintf("backend host %q is not in loadtest.allowed_hosts", host)}
		}
	}
	return nil
}

// HostMatches matches a hostname against an exact name or a "*.suffix"
// pattern (which matches any subdomain of suffix, not suffix itself).
// Matching is case-insensitive.
func HostMatches(pattern, host string) bool {
	pattern = strings.ToLower(strings.TrimSpace(pattern))
	host = strings.ToLower(strings.TrimSuffix(host, "."))
	if suffix, ok := strings.CutPrefix(pattern, "*."); ok {
		return strings.HasSuffix(host, "."+suffix)
	}
	return pattern == host
}
