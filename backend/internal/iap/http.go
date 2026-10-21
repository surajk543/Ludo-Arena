package iap

import (
	"context"
	"errors"
	"net/http"
	"time"

	"ludoroyale/internal/httpapi"
	"ludoroyale/internal/metrics"
	"ludoroyale/internal/ratelimit"
)

// Rate limits.
var (
	// ReadPerUser bounds GET /store/coin-packs.
	ReadPerUser = ratelimit.Rule{Name: "iap_read_user", Limit: 120, Window: time.Minute}
	// PurchasePerUser bounds POST /store/purchases (the app retries a few
	// times per purchase).
	PurchasePerUser = ratelimit.Rule{Name: "iap_purchase_user", Limit: 30, Window: time.Minute}
	// AppleNotifyPerIP bounds the App Store Server Notifications endpoint.
	AppleNotifyPerIP = ratelimit.Rule{Name: "iap_apple_notify_ip", Limit: 600, Window: time.Minute}
)

// API errors.
var (
	errUnavailable = httpapi.Errf(http.StatusServiceUnavailable, "iap_unavailable",
		"Purchases are not available right now.")
	errInvalid = httpapi.Errf(http.StatusUnprocessableEntity, "purchase_invalid",
		"This purchase could not be verified.")
	errPending = httpapi.Errf(http.StatusConflict, "purchase_pending",
		"The payment is still pending. Your coins arrive once it completes.")
	errUnreachable = httpapi.Errf(http.StatusBadGateway, "store_unreachable",
		"The store could not be reached. Your purchase is safe; try again shortly.")
)

// Register adds the coin pack routes:
//
//	GET  /api/v1/store/coin-packs           humans, version gated
//	POST /api/v1/store/purchases            humans, version gated
//	POST /api/v1/iap/apple/notifications    App Store Server Notifications V2
func (s *Service) Register(rt *httpapi.Router) {
	read, buy, notify := ReadPerUser, PurchasePerUser, AppleNotifyPerIP
	rt.Handle("GET /api/v1/store/coin-packs", httpapi.Route{Auth: httpapi.AuthHuman, Gate: true, UserRule: &read},
		s.handlePacks)
	rt.Handle("POST /api/v1/store/purchases", httpapi.Route{Auth: httpapi.AuthHuman, Gate: true, UserRule: &buy,
		MaxBody: 48 << 10}, s.handlePurchase)
	// Called by Apple (no app headers, no account): the signed payload is
	// the authentication.
	rt.Handle("POST /api/v1/iap/apple/notifications", httpapi.Route{IPRule: &notify, MaxBody: 128 << 10},
		s.handleAppleNotification)
}

// CoinPacks is the GET /store/coin-packs answer.
type CoinPacks struct {
	Packs []PackView `json:"packs"`
	// PurchasesAvailable: the server can verify this platform's purchases.
	PurchasesAvailable bool `json:"purchasesAvailable"`
	// AccountToken is passed to the store with every purchase.
	AccountToken string `json:"accountToken"`
}

func (s *Service) handlePacks(w http.ResponseWriter, r *http.Request) error {
	p, ok := httpapi.PrincipalFrom(r.Context())
	if !ok {
		return httpapi.ErrUnauthorized
	}
	platform := PlatformAndroid
	if c, ok := httpapi.ClientFrom(r.Context()); ok {
		platform = string(c.Platform)
	}
	list := s.packs.Packs().List()
	out := CoinPacks{Packs: make([]PackView, 0, len(list)), PurchasesAvailable: s.Available(platform),
		AccountToken: s.AccountToken(p.UserID)}
	for _, pk := range list {
		out.Packs = append(out.Packs, pk.View(platform))
	}
	httpapi.WriteJSON(w, http.StatusOK, out)
	return nil
}

func (s *Service) handlePurchase(w http.ResponseWriter, r *http.Request) error {
	p, ok := httpapi.PrincipalFrom(r.Context())
	if !ok {
		return httpapi.ErrUnauthorized
	}
	var req PurchaseRequest
	if err := httpapi.DecodeJSON(r, &req); err != nil {
		metrics.IAPPurchases.WithLabelValues("unknown", "bad_request").Inc()
		return err
	}
	// Not cancelled by a client that hangs up: a verified purchase is
	// granted (the app's retry then gets the replay).
	res, err := s.Purchase(context.WithoutCancel(r.Context()), p.UserID, req)
	if err != nil {
		return s.httpErr(err)
	}
	httpapi.WriteJSON(w, http.StatusOK, res)
	return nil
}

// httpErr maps service errors; details are logged, never sent (no token or
// id echoes).
func (s *Service) httpErr(err error) error {
	switch {
	case errors.Is(err, ErrBadRequest):
		return httpapi.Errf(http.StatusBadRequest, "bad_request", "The purchase request is invalid.")
	case errors.Is(err, ErrUnavailable):
		return errUnavailable
	case errors.Is(err, ErrInvalid):
		s.log.Info("purchase refused", "reason", err.Error())
		return errInvalid
	case errors.Is(err, ErrPending):
		return errPending
	case errors.Is(err, ErrStoreUnreachable):
		s.log.Warn("store unreachable during a purchase", "error", err.Error())
		return errUnreachable
	case errors.Is(err, ErrUnknownAccount):
		return httpapi.ErrUnauthorized
	}
	return err
}

func (s *Service) handleAppleNotification(w http.ResponseWriter, r *http.Request) error {
	var body struct {
		SignedPayload string `json:"signedPayload"`
	}
	if err := httpapi.DecodeJSON(r, &body); err != nil || body.SignedPayload == "" {
		metrics.IAPAppleNotifications.WithLabelValues("invalid").Inc()
		return httpapi.ErrBadRequest
	}
	res, err := s.HandleAppleNotification(context.WithoutCancel(r.Context()), body.SignedPayload)
	switch {
	case errors.Is(err, ErrUnavailable):
		return errUnavailable
	case errors.Is(err, ErrBadRequest):
		metrics.IAPAppleNotifications.WithLabelValues("invalid").Inc()
		s.log.Warn("app store notification rejected", "reason", err.Error())
		return httpapi.ErrBadRequest
	case err != nil:
		// 5xx: Apple retries the notification later.
		metrics.IAPAppleNotifications.WithLabelValues("error").Inc()
		return err
	}
	metrics.IAPAppleNotifications.WithLabelValues(res).Inc()
	httpapi.WriteJSON(w, http.StatusOK, map[string]string{"result": res})
	return nil
}
