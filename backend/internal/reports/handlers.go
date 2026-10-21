package reports

import (
	"crypto/sha256"
	"crypto/subtle"
	"errors"
	"net/http"
	"strconv"
	"time"
	"unicode/utf8"

	"github.com/google/uuid"

	"ludoroyale/internal/httpapi"
	"ludoroyale/internal/ratelimit"
)

// Rate limits.
var (
	// WritePerUser limits POST /reports attempts (the daily report limit is
	// separate and enforced in PostgreSQL).
	WritePerUser = ratelimit.Rule{Name: "report_user", Limit: 20, Window: time.Minute}
	// ReadPerUser limits GET /reports.
	ReadPerUser = ratelimit.Rule{Name: "report_read_user", Limit: 120, Window: time.Minute}
	// AdminPerIP limits the operator API per client IP (checked before the key).
	AdminPerIP = ratelimit.Rule{Name: "admin_ip", Limit: 60, Window: time.Minute}
)

// AdminKeyHeader carries the operator key.
const AdminKeyHeader = "X-Admin-Key"

// Register adds the player routes (human token, version gated) and the
// operator routes (X-Admin-Key, not version gated, rate limited per IP; they
// answer 404 when ADMIN_API_KEY_SHA256 is unset and must only be reachable on
// the private network).
func (s *Service) Register(rt *httpapi.Router) {
	write, read, admin := WritePerUser, ReadPerUser, AdminPerIP
	rt.Handle("POST /api/v1/reports", httpapi.Route{Auth: httpapi.AuthHuman, Gate: true, UserRule: &write}, s.handleCreate)
	rt.Handle("GET /api/v1/reports", httpapi.Route{Auth: httpapi.AuthHuman, Gate: true, UserRule: &read}, s.handleMine)
	adminRoute := httpapi.Route{IPRule: &admin}
	rt.Handle("GET /api/v1/admin/reports", adminRoute, s.admin(s.handleAdminList))
	rt.Handle("PATCH /api/v1/admin/reports/{id}", adminRoute, s.admin(s.handleAdminUpdate))
}

func caller(r *http.Request) (uuid.UUID, error) {
	p, ok := httpapi.PrincipalFrom(r.Context())
	if !ok {
		return uuid.Nil, httpapi.ErrUnauthorized
	}
	return p.UserID, nil
}

func mapErr(err error) error {
	var le *LimitError
	switch {
	case errors.As(err, &le):
		e := httpapi.Errf(http.StatusTooManyRequests, "report_limit", "You have reached the daily report limit. Please try again later.")
		e.Retry = le.Retry
		e.Details = le.Limit
		return e
	case errors.Is(err, ErrInvalid):
		return httpapi.Errf(http.StatusBadRequest, "bad_request", "The report is invalid.")
	case errors.Is(err, ErrUnknownPlayer):
		return httpapi.Errf(http.StatusNotFound, "not_found", "No player has this id.")
	case errors.Is(err, ErrRoomGone):
		return httpapi.Errf(http.StatusNotFound, "room_not_found", "This game is no longer available to report from.")
	case errors.Is(err, ErrSelf):
		return httpapi.Errf(http.StatusUnprocessableEntity, "cannot_report_self", "You cannot report yourself.")
	case errors.Is(err, ErrNotInRoom):
		return httpapi.Errf(http.StatusUnprocessableEntity, "not_in_room", "You can only report players from a game you played together.")
	case errors.Is(err, ErrAlreadyReported):
		return httpapi.Errf(http.StatusConflict, "already_reported", "You already reported this player in the last 24 hours.")
	case errors.Is(err, ErrNotFound):
		return httpapi.Errf(http.StatusNotFound, "not_found", "Report not found.")
	}
	return err
}

func (s *Service) handleCreate(w http.ResponseWriter, r *http.Request) error {
	me, err := caller(r)
	if err != nil {
		return err
	}
	var in CreateInput
	if err := httpapi.DecodeJSON(r, &in); err != nil {
		return err
	}
	rep, lim, err := s.Create(r.Context(), me, in)
	if err != nil {
		return mapErr(err)
	}
	httpapi.WriteJSON(w, http.StatusCreated, map[string]any{"report": rep, "limit": lim})
	return nil
}

func (s *Service) handleMine(w http.ResponseWriter, r *http.Request) error {
	me, err := caller(r)
	if err != nil {
		return err
	}
	list, lim, err := s.Mine(r.Context(), me)
	if err != nil {
		return err
	}
	httpapi.WriteJSON(w, http.StatusOK, map[string]any{"reports": list, "limit": lim})
	return nil
}

// adminAuthorized compares sha256(key) with the configured hash in constant
// time.
func adminAuthorized(want []byte, key string) bool {
	if len(want) != sha256.Size || key == "" {
		return false
	}
	sum := sha256.Sum256([]byte(key))
	return subtle.ConstantTimeCompare(sum[:], want) == 1
}

// admin guards an operator handler: 404 when the admin API is not configured,
// 401 unauthorized for a missing or wrong X-Admin-Key.
func (s *Service) admin(h httpapi.HandlerFunc) httpapi.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) error {
		if !s.AdminEnabled() {
			return httpapi.ErrNotFound
		}
		if !adminAuthorized(s.opts.AdminKeySHA256, r.Header.Get(AdminKeyHeader)) {
			return httpapi.Errf(http.StatusUnauthorized, "unauthorized", "A valid X-Admin-Key is required.")
		}
		return h(w, r)
	}
}

// parseAdminQuery validates ?status= and ?limit=.
func parseAdminQuery(status, limit string) (string, int, error) {
	if status != "" && !ValidStatus(status) {
		return "", 0, httpapi.Errf(http.StatusBadRequest, "bad_request", "Unknown status.")
	}
	n := AdminDefaultLimit
	if limit != "" {
		v, err := strconv.Atoi(limit)
		if err != nil || v < 1 || v > AdminMaxLimit {
			return "", 0, httpapi.Errf(http.StatusBadRequest, "bad_request", "limit must be between 1 and 200.")
		}
		n = v
	}
	return status, n, nil
}

func (s *Service) handleAdminList(w http.ResponseWriter, r *http.Request) error {
	q := r.URL.Query()
	status, limit, err := parseAdminQuery(q.Get("status"), q.Get("limit"))
	if err != nil {
		return err
	}
	list, err := s.AdminList(r.Context(), status, limit)
	if err != nil {
		return err
	}
	httpapi.WriteJSON(w, http.StatusOK, map[string]any{"reports": list})
	return nil
}

// AdminPatch is the PATCH /admin/reports/{id} body; at least one field.
type AdminPatch struct {
	Status *string `json:"status"`
	Note   *string `json:"note"`
}

func (p AdminPatch) validate() error {
	if p.Status == nil && p.Note == nil {
		return httpapi.Errf(http.StatusBadRequest, "bad_request", "Send status and/or note.")
	}
	if p.Status != nil && !ValidStatus(*p.Status) {
		return httpapi.Errf(http.StatusBadRequest, "bad_request", "Unknown status.")
	}
	if p.Note != nil && (!utf8.ValidString(*p.Note) || utf8.RuneCountInString(*p.Note) > MaxNoteLength) {
		return httpapi.Errf(http.StatusBadRequest, "bad_request", "note must be at most 1000 characters.")
	}
	return nil
}

func (s *Service) handleAdminUpdate(w http.ResponseWriter, r *http.Request) error {
	id, err := uuid.Parse(r.PathValue("id"))
	if err != nil {
		return mapErr(ErrNotFound)
	}
	var body AdminPatch
	if err := httpapi.DecodeJSON(r, &body); err != nil {
		return err
	}
	if err := body.validate(); err != nil {
		return err
	}
	rep, err := s.AdminUpdate(r.Context(), id, body.Status, body.Note)
	if err != nil {
		return mapErr(err)
	}
	httpapi.WriteJSON(w, http.StatusOK, map[string]any{"report": rep})
	return nil
}
