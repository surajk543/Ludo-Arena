package progression

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"time"

	"github.com/google/uuid"
	"github.com/redis/go-redis/v9"

	"ludoarena/internal/httpapi"
	"ludoarena/internal/ratelimit"
	"ludoarena/internal/wallet"
)

// Per-account rate limits (in addition to the router's global protections).
var (
	ReadPerUser    = ratelimit.Rule{Name: "progression_read_user", Limit: 120, Window: time.Minute}
	LoadoutPerUser = ratelimit.Rule{Name: "loadout_user", Limit: 60, Window: time.Minute}
	// AssetSignPerUser bounds POST /assets/sign (a phone signs at most 50
	// paths per request and caches every file forever).
	AssetSignPerUser = ratelimit.Rule{Name: "asset_sign_user", Limit: 120, Window: time.Minute}
)

// MaxSignPaths is the most paths one POST /assets/sign may name.
const MaxSignPaths = 50

// Register adds the progression, missions and Collection Room routes. All
// require a human access token and pass the app version gate.
func (s *Service) Register(rt *httpapi.Router) {
	route := func(rule ratelimit.Rule) httpapi.Route {
		return httpapi.Route{Auth: httpapi.AuthHuman, Gate: true, UserRule: &rule}
	}
	read, write, equip := ReadPerUser, ratelimit.WalletOpPerUser, LoadoutPerUser
	rt.Handle("GET /api/v1/progression", route(read), s.handleProgression)
	rt.Handle("GET /api/v1/missions", route(read), s.handleMissions)
	rt.Handle("GET /api/v1/playtime", route(read), s.handlePlaytime)
	rt.Handle("POST /api/v1/missions/{periodKey}/{missionId}/claim", route(write), s.handleClaim)
	rt.Handle("GET /api/v1/collection", route(read), s.handleCollection)
	rt.Handle("PUT /api/v1/collection/loadout", route(equip), s.handleLoadout)
	rt.Handle("POST /api/v1/collection/items/{itemId}/purchase", route(write), s.handlePurchase)
	// Profile-picture Store (pictures_http.go).
	sign := AssetSignPerUser
	rt.Handle("GET /api/v1/store/profile-pictures", route(read), s.handleStorePictures)
	rt.Handle("POST /api/v1/store/profile-pictures/{pictureId}/purchase", route(write), s.handlePurchasePicture)
	rt.Handle("PUT /api/v1/me/profile-picture", route(equip), s.handleApplyPicture)
	rt.Handle("POST /api/v1/assets/sign", route(sign), s.handleSignAssets)
	// Store emotes (emotes_http.go).
	rt.Handle("GET /api/v1/store/emotes", route(read), s.handleStoreEmotes)
	rt.Handle("POST /api/v1/store/emotes/{emoteId}/purchase", route(write), s.handlePurchaseEmote)
}

func caller(r *http.Request) (uuid.UUID, error) {
	p, ok := httpapi.PrincipalFrom(r.Context())
	if !ok {
		return uuid.Nil, httpapi.ErrUnauthorized
	}
	return p.UserID, nil
}

func (s *Service) handleProgression(w http.ResponseWriter, r *http.Request) error {
	uid, err := caller(r)
	if err != nil {
		return err
	}
	v, err := s.Progression(r.Context(), uid)
	if err != nil {
		return err
	}
	httpapi.WriteJSON(w, http.StatusOK, v)
	return nil
}

func (s *Service) handleMissions(w http.ResponseWriter, r *http.Request) error {
	uid, err := caller(r)
	if err != nil {
		return err
	}
	v, err := s.Missions(r.Context(), uid)
	if err != nil {
		return err
	}
	httpapi.WriteJSON(w, http.StatusOK, v)
	return nil
}

func (s *Service) handlePlaytime(w http.ResponseWriter, r *http.Request) error {
	uid, err := caller(r)
	if err != nil {
		return err
	}
	v, err := s.Playtime(r.Context(), uid)
	if err != nil {
		return mapErr(err)
	}
	if v == nil {
		return httpapi.Errf(http.StatusNotFound, "not_found", "Daily playtime is not available.")
	}
	httpapi.WriteJSON(w, http.StatusOK, v)
	return nil
}

func (s *Service) handleClaim(w http.ResponseWriter, r *http.Request) error {
	uid, err := caller(r)
	if err != nil {
		return err
	}
	period, mission := r.PathValue("periodKey"), r.PathValue("missionId")
	return s.idempotent(w, r, uid, func(ctx context.Context) (int, any, error) {
		res, err := s.Claim(ctx, uid, period, mission)
		if err != nil {
			return 0, nil, mapErr(err)
		}
		return http.StatusOK, res, nil
	})
}

func (s *Service) handleCollection(w http.ResponseWriter, r *http.Request) error {
	uid, err := caller(r)
	if err != nil {
		return err
	}
	v, err := s.Collection(r.Context(), uid)
	if err != nil {
		return err
	}
	httpapi.WriteJSON(w, http.StatusOK, v)
	return nil
}

func (s *Service) handleLoadout(w http.ResponseWriter, r *http.Request) error {
	uid, err := caller(r)
	if err != nil {
		return err
	}
	var body struct {
		Slot   string  `json:"slot"`
		ItemID *string `json:"itemId"`
	}
	if err := httpapi.DecodeJSON(r, &body); err != nil {
		return err
	}
	item := ""
	if body.ItemID != nil {
		item = *body.ItemID
	}
	lo, err := s.Equip(r.Context(), uid, body.Slot, item)
	if err != nil {
		return mapErr(err)
	}
	httpapi.WriteJSON(w, http.StatusOK, map[string]any{"loadout": lo})
	return nil
}

func (s *Service) handlePurchase(w http.ResponseWriter, r *http.Request) error {
	uid, err := caller(r)
	if err != nil {
		return err
	}
	item := r.PathValue("itemId")
	return s.idempotent(w, r, uid, func(ctx context.Context) (int, any, error) {
		res, err := s.Purchase(ctx, uid, item)
		if err != nil {
			return 0, nil, mapErr(err)
		}
		return http.StatusOK, res, nil
	})
}

// mapErr converts service errors to API errors.
func mapErr(err error) error {
	switch {
	case errors.Is(err, ErrMissionNotFound):
		return httpapi.Errf(http.StatusNotFound, "not_found", "This mission is not available in the current period.")
	case errors.Is(err, ErrNotCompleted):
		return httpapi.Errf(http.StatusUnprocessableEntity, "not_completed", "Complete the mission before claiming its reward.")
	case errors.Is(err, ErrAlreadyClaimed):
		return httpapi.Errf(http.StatusConflict, "already_claimed", "This reward was already claimed.")
	case errors.Is(err, ErrItemNotFound):
		return httpapi.Errf(http.StatusNotFound, "not_found", "Item not found.")
	case errors.Is(err, ErrPictureNotFound):
		return httpapi.Errf(http.StatusNotFound, "not_found", "This profile picture is not available.")
	case errors.Is(err, ErrEmoteNotFound):
		return httpapi.Errf(http.StatusNotFound, "not_found", "This emote is not available.")
	case errors.Is(err, ErrBadStoreQuery):
		return httpapi.Errf(http.StatusBadRequest, "bad_request", "Invalid filter, limit or cursor.")
	case errors.Is(err, ErrItemLocked):
		return httpapi.Errf(http.StatusUnprocessableEntity, "item_locked", "This item is locked.")
	case errors.Is(err, ErrAlreadyOwned):
		return httpapi.Errf(http.StatusConflict, "already_owned", "You already own this item.")
	case errors.Is(err, ErrWrongSlot):
		return httpapi.Errf(http.StatusBadRequest, "bad_request", "This item does not fit that slot.")
	case errors.Is(err, ErrUnknownSlot):
		return httpapi.Errf(http.StatusBadRequest, "bad_request", "Unknown loadout slot.")
	case isInsufficient(err):
		return httpapi.Errf(http.StatusUnprocessableEntity, "insufficient_funds", "You do not have enough coins or diamonds.")
	case errors.Is(err, ErrUnknownUser), errors.Is(err, wallet.ErrNotFound):
		return httpapi.ErrNotFound
	}
	return err
}

// ------------------------------------------------------------- idempotency

// idemRecord is a cached successful response.
type idemRecord struct {
	Route  string          `json:"route"`
	Status int             `json:"status"`
	Body   json.RawMessage `json:"body"`
}

func validIdemKey(k string) bool {
	if len(k) < 8 || len(k) > 64 {
		return false
	}
	for i := 0; i < len(k); i++ {
		c := k[i]
		if !(c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z' || c >= '0' && c <= '9' || c == '-' || c == '_' || c == '.' || c == ':') {
			return false
		}
	}
	return true
}

// IdempotencyKey is the Redis key of a cached response.
func IdempotencyKey(userID uuid.UUID, key string) string {
	return "idem:" + userID.String() + ":" + key
}

// idempotent runs fn at most once per (account, Idempotency-Key): the
// successful response is cached in Redis for 24 h and replayed verbatim (with
// `Idempotent-Replayed: true`). A concurrent request with the same key waits
// for the first to finish. Errors are not cached (a retry re-executes; the
// database constraints still make the operation exactly-once).
func (s *Service) idempotent(w http.ResponseWriter, r *http.Request, userID uuid.UUID,
	fn func(ctx context.Context) (int, any, error)) error {
	ctx := r.Context()
	key := r.Header.Get("Idempotency-Key")
	if key == "" || s.rdb == nil {
		status, body, err := fn(ctx)
		if err != nil {
			return err
		}
		httpapi.WriteJSON(w, status, body)
		return nil
	}
	if !validIdemKey(key) {
		return httpapi.Errf(http.StatusBadRequest, "bad_request", "Idempotency-Key must be 8-64 characters [A-Za-z0-9-_.:].")
	}
	route := r.Method + " " + r.URL.Path
	rkey := IdempotencyKey(userID, key)
	lockKey := rkey + ":lock"

	deadline := time.Now().Add(5 * time.Second)
	rechecked := false
	for {
		raw, err := s.rdb.Get(ctx, rkey).Bytes()
		if err == nil {
			var rec idemRecord
			if json.Unmarshal(raw, &rec) == nil {
				if rec.Route != route {
					return httpapi.Errf(http.StatusUnprocessableEntity, "idempotency_key_reused",
						"This Idempotency-Key was already used for a different request.")
				}
				w.Header().Set("Content-Type", "application/json; charset=utf-8")
				w.Header().Set("Cache-Control", "no-store")
				w.Header().Set("Idempotent-Replayed", "true")
				w.WriteHeader(rec.Status)
				_, _ = w.Write(append(rec.Body, '\n'))
				return nil
			}
		} else if !errors.Is(err, redis.Nil) {
			s.log.Warn("idempotency cache unavailable", "error", err.Error())
			break // fail open: the database still guarantees exactly-once
		}
		ok, err := s.rdb.SetNX(ctx, lockKey, "1", 30*time.Second).Result()
		if err != nil {
			s.log.Warn("idempotency lock unavailable", "error", err.Error())
			break
		}
		if ok {
			// Re-check under the lock: a request with the same key may have
			// stored its response and released the lock between the GET
			// above and this SETNX; replay it instead of running again.
			if n, err := s.rdb.Exists(ctx, rkey).Result(); err == nil && n == 1 && !rechecked {
				rechecked = true
				s.rdb.Del(context.WithoutCancel(ctx), lockKey)
				continue
			}
			defer s.rdb.Del(context.WithoutCancel(ctx), lockKey)
			break
		}
		if time.Now().After(deadline) {
			return httpapi.Errf(http.StatusConflict, "request_in_progress", "The same request is still being processed.")
		}
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-time.After(50 * time.Millisecond):
		}
	}

	status, body, err := fn(ctx)
	if err != nil {
		return err
	}
	raw, err := json.Marshal(body)
	if err != nil {
		return err
	}
	if rec, err := json.Marshal(idemRecord{Route: route, Status: status, Body: raw}); err == nil {
		if err := s.rdb.Set(context.WithoutCancel(ctx), rkey, rec, idempotencyTTL).Err(); err != nil {
			s.log.Warn("idempotency cache write failed", "error", err.Error())
		}
	}
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	w.WriteHeader(status)
	_, _ = w.Write(append(raw, '\n'))
	return nil
}
