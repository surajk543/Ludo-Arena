package opsstats

import (
	"net/http"
	"strconv"

	"ludoarena/internal/httpapi"
)

// Query limits of the operator routes.
const (
	DefaultLimit = 100
	MaxLimit     = 500
	DefaultHours = 24
	MaxHours     = 24
)

// Register adds the operator routes (httpapi.HandleAdmin: X-Admin-Key, not
// version gated, rate limited per IP, 404 while ADMIN_API_KEY_SHA256 is
// unset; private network only).
func (s *Service) Register(rt *httpapi.Router) {
	rt.HandleAdmin("GET /api/v1/admin/ops/online", s.opts.AdminKeySHA256, s.handleOnline)
	rt.HandleAdmin("GET /api/v1/admin/ops/playtime", s.opts.AdminKeySHA256, s.handlePlaytime)
}

// intParam parses an optional integer query parameter in [lo, hi]
// (def when absent); anything else is 400 bad_request.
func intParam(raw, name string, def, lo, hi int) (int, error) {
	if raw == "" {
		return def, nil
	}
	v, err := strconv.Atoi(raw)
	if err != nil || v < lo || v > hi {
		return 0, httpapi.Errf(http.StatusBadRequest, "bad_request",
			name+" must be between "+strconv.Itoa(lo)+" and "+strconv.Itoa(hi)+".")
	}
	return v, nil
}

func (s *Service) handleOnline(w http.ResponseWriter, r *http.Request) error {
	limit, err := intParam(r.URL.Query().Get("limit"), "limit", DefaultLimit, 1, MaxLimit)
	if err != nil {
		return err
	}
	rep, err := s.Online(r.Context(), limit)
	if err != nil {
		return err
	}
	httpapi.WriteJSON(w, http.StatusOK, rep)
	return nil
}

func (s *Service) handlePlaytime(w http.ResponseWriter, r *http.Request) error {
	q := r.URL.Query()
	hours, err := intParam(q.Get("hours"), "hours", DefaultHours, 1, MaxHours)
	if err != nil {
		return err
	}
	limit, err := intParam(q.Get("limit"), "limit", DefaultLimit, 1, MaxLimit)
	if err != nil {
		return err
	}
	rep, err := s.Playtime(r.Context(), hours, limit)
	if err != nil {
		return err
	}
	httpapi.WriteJSON(w, http.StatusOK, rep)
	return nil
}
