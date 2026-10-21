package progression

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"strconv"

	"ludoroyale/internal/httpapi"
	"ludoroyale/internal/metrics"
)

// GET /api/v1/store/profile-pictures?filter=&excludeOwned=&limit=&cursor=
func (s *Service) handleStorePictures(w http.ResponseWriter, r *http.Request) error {
	uid, err := caller(r)
	if err != nil {
		return err
	}
	q := r.URL.Query()
	excludeOwned := false
	switch q.Get("excludeOwned") {
	case "", "false":
	case "true":
		excludeOwned = true
	default:
		return mapErr(ErrBadStoreQuery)
	}
	limit := 0
	if raw := q.Get("limit"); raw != "" {
		n, err := strconv.Atoi(raw)
		if err != nil || n < 1 {
			return mapErr(ErrBadStoreQuery)
		}
		limit = n
	}
	page, err := s.StorePictures(r.Context(), uid, q.Get("filter"), excludeOwned, limit, q.Get("cursor"))
	if err != nil {
		return mapErr(err)
	}
	httpapi.WriteJSON(w, http.StatusOK, page)
	return nil
}

// POST /api/v1/store/profile-pictures/{pictureId}/purchase (Idempotency-Key).
func (s *Service) handlePurchasePicture(w http.ResponseWriter, r *http.Request) error {
	uid, err := caller(r)
	if err != nil {
		return err
	}
	id := r.PathValue("pictureId")
	return s.idempotent(w, r, uid, func(ctx context.Context) (int, any, error) {
		res, err := s.PurchasePicture(ctx, uid, id)
		if err != nil {
			return 0, nil, mapErr(err)
		}
		return http.StatusOK, res, nil
	})
}

// PUT /api/v1/me/profile-picture {"id": "pp_x" | null}
func (s *Service) handleApplyPicture(w http.ResponseWriter, r *http.Request) error {
	uid, err := caller(r)
	if err != nil {
		return err
	}
	var body struct {
		ID json.RawMessage `json:"id"`
	}
	if err := httpapi.DecodeJSON(r, &body); err != nil {
		return err
	}
	// "id" is required: a picture id, or null for the built-in avatar.
	var id *string
	if len(body.ID) == 0 || json.Unmarshal(body.ID, &id) != nil || (id != nil && *id == "") {
		return httpapi.Errf(http.StatusBadRequest, "bad_request", `"id" must be a profile picture id or null.`)
	}
	pic := ""
	if id != nil {
		pic = *id
	}
	eq, err := s.ApplyPicture(r.Context(), uid, pic)
	if errors.Is(err, ErrItemLocked) {
		return httpapi.Errf(http.StatusUnprocessableEntity, "item_locked", "Buy this profile picture before applying it.")
	}
	if err != nil {
		return mapErr(err)
	}
	httpapi.WriteJSON(w, http.StatusOK, EquippedPicture{Equipped: eq})
	return nil
}

// POST /api/v1/assets/sign {"paths": [...]} → {"urls": {path: url}, "expiresAt": ms}.
// Only catalogue paths are signed; others are left out. Signed URLs are
// never logged.
func (s *Service) handleSignAssets(w http.ResponseWriter, r *http.Request) error {
	if _, err := caller(r); err != nil {
		return err
	}
	if s.signer == nil {
		metrics.AssetSignRequests.WithLabelValues("unavailable").Inc()
		return httpapi.Errf(http.StatusServiceUnavailable, "assets_unavailable", "Pictures cannot be downloaded right now.")
	}
	var body struct {
		Paths []string `json:"paths"`
	}
	if err := httpapi.DecodeJSON(r, &body); err != nil {
		return err
	}
	if len(body.Paths) < 1 || len(body.Paths) > MaxSignPaths {
		return httpapi.Errf(http.StatusBadRequest, "bad_request", "paths must hold 1 to 50 asset paths.")
	}
	for _, p := range body.Paths {
		if p == "" || len(p) > 255 {
			return httpapi.Errf(http.StatusBadRequest, "bad_request", "Each path must be 1 to 255 characters.")
		}
	}
	urls, exp, _ := s.SignAssetPaths(body.Paths)
	metrics.AssetSignRequests.WithLabelValues("ok").Inc()
	metrics.AssetURLsSigned.Add(float64(len(urls)))
	httpapi.WriteJSON(w, http.StatusOK, map[string]any{"urls": urls, "expiresAt": exp.UnixMilli()})
	return nil
}
