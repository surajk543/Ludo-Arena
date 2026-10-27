package httpapi

import (
	"crypto/sha256"
	"crypto/subtle"
	"net/http"
	"time"

	"ludoarena/internal/ratelimit"
)

// Operator API (/api/v1/admin/*; docs/rest-api.md → Operator API): not for
// the app, no user token, not version gated. Every operator route shares
// one guard and one per-IP budget, and answers 404 while
// ADMIN_API_KEY_SHA256 is unset. The routes must only be reachable on the
// private network (the public proxy blocks /api/v1/admin/).

// AdminKeyHeader carries the operator key.
const AdminKeyHeader = "X-Admin-Key"

// AdminPerIP limits the operator API per client IP (checked before the key;
// one budget for every operator route).
var AdminPerIP = ratelimit.Rule{Name: "admin_ip", Limit: 60, Window: time.Minute}

// AdminEnabled reports whether keySHA256 (sha256 of the operator key)
// configures the operator API.
func AdminEnabled(keySHA256 []byte) bool { return len(keySHA256) == sha256.Size }

// AdminAuthorized compares sha256(key) with want in constant time. Nothing is
// authorized while want is not a sha256 (the operator API is disabled).
func AdminAuthorized(want []byte, key string) bool {
	if !AdminEnabled(want) || key == "" {
		return false
	}
	sum := sha256.Sum256([]byte(key))
	return subtle.ConstantTimeCompare(sum[:], want) == 1
}

// Admin guards an operator handler: 404 not_found when the operator API is
// not configured, 401 unauthorized for a missing or wrong X-Admin-Key.
func Admin(keySHA256 []byte, h HandlerFunc) HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) error {
		if !AdminEnabled(keySHA256) {
			return ErrNotFound
		}
		if !AdminAuthorized(keySHA256, r.Header.Get(AdminKeyHeader)) {
			return Errf(http.StatusUnauthorized, "unauthorized", "A valid X-Admin-Key is required.")
		}
		return h(w, r)
	}
}

// HandleAdmin registers an operator route: rate limited per client IP
// (AdminPerIP, before the key is checked) and guarded by Admin.
func (rt *Router) HandleAdmin(pattern string, keySHA256 []byte, h HandlerFunc) {
	rule := AdminPerIP
	rt.Handle(pattern, Route{IPRule: &rule}, Admin(keySHA256, h))
}
