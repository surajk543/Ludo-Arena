// Package httpapi serves the REST API (/api/v1). Routes declare their
// requirements (authentication, app version gate, rate limits) once, and the
// router applies them consistently.
package httpapi

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net"
	"net/http"
	"runtime/debug"
	"strconv"
	"strings"
	"time"

	"ludoroyale/internal/apppolicy"
	"ludoroyale/internal/auth"
	"ludoroyale/internal/metrics"
	"ludoroyale/internal/ratelimit"
)

// APIError is a structured error response.
type APIError struct {
	Status  int
	Code    string
	Message string
	Details any
	Retry   time.Duration
}

func (e *APIError) Error() string { return e.Code + ": " + e.Message }

// Errf builds an APIError.
func Errf(status int, code, msg string) *APIError {
	return &APIError{Status: status, Code: code, Message: msg}
}

// Common errors.
var (
	ErrBadRequest   = Errf(http.StatusBadRequest, "bad_request", "The request is malformed.")
	ErrUnauthorized = Errf(http.StatusUnauthorized, "unauthorized", "Authentication required.")
	ErrForbidden    = Errf(http.StatusForbidden, "forbidden", "Not allowed.")
	ErrNotFound     = Errf(http.StatusNotFound, "not_found", "Not found.")
	ErrInternal     = Errf(http.StatusInternalServerError, "internal", "Something went wrong. Please try again.")
)

// Auth requirement for a route.
type Auth int

// Auth modes.
const (
	AuthNone Auth = iota
	AuthHuman
	AuthBotController
)

// Route options.
type Route struct {
	Auth Auth
	// Gate applies the app version/maintenance policy (requires X-App-* headers).
	Gate bool
	// IPRule / UserRule rate-limit the route per client IP / per account.
	IPRule   *ratelimit.Rule
	UserRule *ratelimit.Rule
	// MaxBody limits the request body (default 16 KiB).
	MaxBody int64
}

// HandlerFunc handles a request and may return an error to be rendered.
type HandlerFunc func(w http.ResponseWriter, r *http.Request) error

type ctxKey int

const (
	keyPrincipal ctxKey = iota
	keyClient
	keyIP
)

// PrincipalFrom returns the authenticated caller.
func PrincipalFrom(ctx context.Context) (auth.Principal, bool) {
	p, ok := ctx.Value(keyPrincipal).(auth.Principal)
	return p, ok
}

// ClientFrom returns the parsed app client metadata (gated routes).
func ClientFrom(ctx context.Context) (apppolicy.Client, bool) {
	c, ok := ctx.Value(keyClient).(apppolicy.Client)
	return c, ok
}

// Router wraps http.ServeMux with the route requirements.
type Router struct {
	mux      *http.ServeMux
	log      *slog.Logger
	auth     *auth.Service
	policy   *apppolicy.Store
	limiter  *ratelimit.Limiter
	proxyHop int
}

// NewRouter returns a Router.
func NewRouter(log *slog.Logger, a *auth.Service, p *apppolicy.Store, l *ratelimit.Limiter, proxyHops int) *Router {
	return &Router{mux: http.NewServeMux(), log: log, auth: a, policy: p, limiter: l, proxyHop: proxyHops}
}

// Mux exposes the underlying mux for non-JSON handlers (WebSocket, metrics).
func (rt *Router) Mux() *http.ServeMux { return rt.mux }

// Handle registers pattern (e.g. "POST /api/v1/auth/guest").
func (rt *Router) Handle(pattern string, opts Route, h HandlerFunc) {
	route := pattern
	if i := strings.IndexByte(pattern, ' '); i > 0 {
		route = pattern[i+1:]
	}
	rt.mux.HandleFunc(pattern, func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		sw := &statusWriter{ResponseWriter: w, status: 200}
		defer func() {
			if rec := recover(); rec != nil {
				rt.log.Error("panic", "route", route, "panic", rec, "stack", string(debug.Stack()))
				rt.writeError(sw, r, ErrInternal)
			}
			metrics.HTTPRequests.WithLabelValues(route, strconv.Itoa(sw.status/100)+"xx").Inc()
			metrics.HTTPSeconds.WithLabelValues(route).Observe(time.Since(start).Seconds())
		}()
		maxBody := opts.MaxBody
		if maxBody == 0 {
			maxBody = 16 << 10
		}
		r.Body = http.MaxBytesReader(sw, r.Body, maxBody)
		ip := ClientIP(r, rt.proxyHop)
		ctx := context.WithValue(r.Context(), keyIP, ip)

		if opts.IPRule != nil {
			if ok, retry := rt.limiter.Allow(ctx, *opts.IPRule, ip); !ok {
				rt.writeError(sw, r, rateLimited(retry))
				return
			}
		}
		if opts.Gate {
			c, err := apppolicy.ParseClient(r.Header.Get("X-App-Platform"), r.Header.Get("X-App-Version"), r.Header.Get("X-App-Build"))
			if err != nil {
				rt.writeError(sw, r, Errf(http.StatusBadRequest, "client_version_required",
					"X-App-Platform, X-App-Version and X-App-Build are required."))
				return
			}
			if apiErr := PolicyError(rt.policy.Evaluate(c, Locale(r)), "rest"); apiErr != nil {
				rt.writeError(sw, r, apiErr)
				return
			}
			ctx = context.WithValue(ctx, keyClient, c)
		}
		if opts.Auth != AuthNone {
			p, err := rt.authenticate(ctx, r)
			if err != nil {
				rt.writeError(sw, r, ErrUnauthorized)
				return
			}
			switch {
			case opts.Auth == AuthHuman && p.Kind != auth.KindAccess:
				rt.writeError(sw, r, ErrForbidden)
				return
			case opts.Auth == AuthBotController && p.Kind != auth.KindBotController:
				rt.writeError(sw, r, ErrForbidden)
				return
			}
			ctx = context.WithValue(ctx, keyPrincipal, p)
			if opts.UserRule != nil {
				if ok, retry := rt.limiter.Allow(ctx, *opts.UserRule, p.UserID.String()); !ok {
					rt.writeError(sw, r, rateLimited(retry))
					return
				}
			}
		}
		if err := h(sw, r.WithContext(ctx)); err != nil {
			rt.writeError(sw, r, err)
		}
	})
}

func (rt *Router) authenticate(ctx context.Context, r *http.Request) (auth.Principal, error) {
	h := r.Header.Get("Authorization")
	tok, ok := strings.CutPrefix(h, "Bearer ")
	if !ok || tok == "" {
		return auth.Principal{}, auth.ErrInvalidToken
	}
	return rt.auth.Authenticate(ctx, strings.TrimSpace(tok))
}

func rateLimited(retry time.Duration) *APIError {
	e := Errf(http.StatusTooManyRequests, "rate_limited", "Too many requests. Please slow down.")
	e.Retry = retry
	return e
}

// PolicyError converts a blocking policy decision into an API error.
func PolicyError(d apppolicy.Decision, surface string) *APIError {
	switch d.Mode {
	case apppolicy.ModeMaintenance:
		metrics.PolicyBlocks.WithLabelValues("maintenance", surface).Inc()
		e := Errf(http.StatusServiceUnavailable, "maintenance", "The game is temporarily unavailable for maintenance.")
		e.Details = d
		return e
	case apppolicy.ModeForceUpdate:
		metrics.PolicyBlocks.WithLabelValues("force_update", surface).Inc()
		e := Errf(http.StatusUpgradeRequired, "update_required", "Please update the app to continue.")
		e.Details = d
		return e
	}
	return nil
}

func (rt *Router) writeError(w http.ResponseWriter, r *http.Request, err error) {
	var apiErr *APIError
	if !errors.As(err, &apiErr) {
		var mbe *http.MaxBytesError
		if errors.As(err, &mbe) {
			apiErr = Errf(http.StatusRequestEntityTooLarge, "bad_request", "Request body too large.")
		} else {
			rt.log.Error("request failed", "method", r.Method, "path", r.URL.Path, "error", err.Error())
			apiErr = ErrInternal
		}
	}
	if apiErr.Retry > 0 {
		w.Header().Set("Retry-After", strconv.Itoa(int(apiErr.Retry.Seconds())+1))
	}
	body := map[string]any{"code": apiErr.Code, "message": apiErr.Message}
	if apiErr.Details != nil {
		body["details"] = apiErr.Details
	}
	WriteJSON(w, apiErr.Status, map[string]any{"error": body})
}

// WriteJSON writes v as JSON with the given status.
func WriteJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

// DecodeJSON strictly decodes a JSON body (unknown fields rejected).
func DecodeJSON(r *http.Request, v any) error {
	dec := json.NewDecoder(r.Body)
	dec.DisallowUnknownFields()
	if err := dec.Decode(v); err != nil {
		var mbe *http.MaxBytesError
		if errors.As(err, &mbe) {
			return err
		}
		if errors.Is(err, io.EOF) {
			return ErrBadRequest
		}
		return Errf(http.StatusBadRequest, "bad_request", "The request body is invalid.")
	}
	if dec.More() {
		return ErrBadRequest
	}
	return nil
}

// Locale returns the request locale from ?locale= or Accept-Language.
func Locale(r *http.Request) string {
	if l := r.URL.Query().Get("locale"); l != "" && len(l) <= 10 {
		return l
	}
	al := r.Header.Get("Accept-Language")
	if i := strings.IndexAny(al, ",;"); i >= 0 {
		al = al[:i]
	}
	if len(al) > 10 {
		return "en"
	}
	return strings.TrimSpace(al)
}

// ClientIP returns the caller IP, honoring TRUSTED_PROXY_HOPS.
func ClientIP(r *http.Request, hops int) string {
	if hops > 0 {
		parts := strings.Split(r.Header.Get("X-Forwarded-For"), ",")
		if idx := len(parts) - hops; idx >= 0 && idx < len(parts) {
			if ip := strings.TrimSpace(parts[idx]); net.ParseIP(ip) != nil {
				return ip
			}
		}
	}
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return r.RemoteAddr
	}
	return host
}

// IPFrom returns the client IP stored by the router.
func IPFrom(ctx context.Context) string { s, _ := ctx.Value(keyIP).(string); return s }

type statusWriter struct {
	http.ResponseWriter
	status int
}

func (w *statusWriter) WriteHeader(code int) {
	w.status = code
	w.ResponseWriter.WriteHeader(code)
}

func (w *statusWriter) Unwrap() http.ResponseWriter { return w.ResponseWriter }
