package progression

import (
	"context"
	"net/http"
	"strconv"

	"ludoarena/internal/httpapi"
)

// GET /api/v1/store/emotes?filter=all|owned&excludeOwned=&limit=&cursor=
func (s *Service) handleStoreEmotes(w http.ResponseWriter, r *http.Request) error {
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
	page, err := s.StoreEmotes(r.Context(), uid, q.Get("filter"), excludeOwned, limit, q.Get("cursor"))
	if err != nil {
		return mapErr(err)
	}
	httpapi.WriteJSON(w, http.StatusOK, page)
	return nil
}

// POST /api/v1/store/emotes/{emoteId}/purchase (Idempotency-Key).
func (s *Service) handlePurchaseEmote(w http.ResponseWriter, r *http.Request) error {
	uid, err := caller(r)
	if err != nil {
		return err
	}
	id := r.PathValue("emoteId")
	return s.idempotent(w, r, uid, func(ctx context.Context) (int, any, error) {
		res, err := s.PurchaseEmote(ctx, uid, id)
		if err != nil {
			return 0, nil, mapErr(err)
		}
		return http.StatusOK, res, nil
	})
}
