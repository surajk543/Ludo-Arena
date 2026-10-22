package iap

// Refunds: Google Play voided purchases (polled) and App Store Server
// Notifications V2 (REFUND / REVOKE) take back what a purchase granted.

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"

	"ludoarena/internal/metrics"
	"ludoarena/internal/wallet"
)

// ------------------------------------------------------------------ refunds

// RefundResult is the outcome of Refund.
type RefundResult string

// Refund outcomes.
const (
	RefundApplied RefundResult = "refunded"
	RefundAlready RefundResult = "already_refunded"
	RefundUnknown RefundResult = "unknown" // not ours, or the account was deleted
)

// Refund marks a granted purchase refunded and takes back the coins and
// diamonds it granted, each clamped at the current balance (never below
// zero). Idempotent: a second call changes nothing. Locks the wallet before
// the purchase row, like account deletion.
func (s *Service) Refund(ctx context.Context, store, txID string) (RefundResult, error) {
	res, err := s.refund(ctx, store, txID)
	if err != nil {
		metrics.IAPRefunds.WithLabelValues(store, "error").Inc()
		return res, err
	}
	metrics.IAPRefunds.WithLabelValues(store, string(res)).Inc()
	return res, nil
}

func (s *Service) refund(ctx context.Context, store, txID string) (RefundResult, error) {
	var owner uuid.UUID
	err := s.pool.QueryRow(ctx, `SELECT user_id FROM progression.purchases WHERE store = $1 AND transaction_id = $2`,
		store, txID).Scan(&owner)
	if errors.Is(err, pgx.ErrNoRows) {
		return RefundUnknown, nil
	}
	if err != nil {
		return "", err
	}
	tx, err := s.pool.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		return "", err
	}
	defer tx.Rollback(ctx) //nolint:errcheck
	var bal wallet.Wallet
	err = tx.QueryRow(ctx, `SELECT coins, diamonds FROM wallet.wallets WHERE user_id = $1 AND NOT is_bot FOR UPDATE`, owner).
		Scan(&bal.Coins, &bal.Diamonds)
	if errors.Is(err, pgx.ErrNoRows) {
		return RefundUnknown, nil
	}
	if err != nil {
		return "", err
	}
	var coins, diamonds int64
	var status string
	err = tx.QueryRow(ctx, `SELECT coins, diamonds, status FROM progression.purchases
		WHERE store = $1 AND transaction_id = $2 AND user_id = $3 FOR UPDATE`, store, txID, owner).
		Scan(&coins, &diamonds, &status)
	if errors.Is(err, pgx.ErrNoRows) {
		return RefundUnknown, nil
	}
	if err != nil {
		return "", err
	}
	if status == "refunded" {
		return RefundAlready, nil
	}
	takeC, takeD := min(coins, bal.Coins), min(diamonds, bal.Diamonds)
	wal, err := wallet.AdjustTx(ctx, tx, owner, -takeC, -takeD)
	if err != nil {
		return "", err
	}
	if _, err := tx.Exec(ctx, `UPDATE progression.purchases
		SET status = 'refunded', refunded_at = now(), updated_at = now()
		WHERE store = $1 AND transaction_id = $2`, store, txID); err != nil {
		return "", err
	}
	if err := tx.Commit(ctx); err != nil {
		return "", err
	}
	if takeC < coins || takeD < diamonds {
		metrics.IAPRefundShortfalls.WithLabelValues(store).Inc()
	}
	s.push(ctx, owner, wal, -takeC, -takeD, ReasonRefund)
	return RefundApplied, nil
}

// ---------------------------------------------------- Google voided purchases

// VoidedLockKey makes one instance poll per interval.
const VoidedLockKey = "iap:google:voided:lock"

// RunVoided polls Google's voided purchases every VoidedInterval (and once at
// start) until ctx ends. A no-op without Google or with interval 0.
func (s *Service) RunVoided(ctx context.Context) {
	if s.opts.Google == nil || s.opts.VoidedInterval <= 0 {
		return
	}
	t := time.NewTicker(s.opts.VoidedInterval)
	defer t.Stop()
	for {
		if s.lockVoided(ctx) {
			if n, err := s.PollVoided(ctx); err != nil {
				s.log.Warn("google play voided purchases poll failed", "error", err.Error())
				metrics.IAPVoidedPolls.WithLabelValues("error").Inc()
			} else {
				metrics.IAPVoidedPolls.WithLabelValues("ok").Inc()
				if n > 0 {
					s.log.Info("google play refunds applied", "purchases", n)
				}
			}
		}
		select {
		case <-ctx.Done():
			return
		case <-t.C:
		}
	}
}

func (s *Service) lockVoided(ctx context.Context) bool {
	if s.rdb == nil {
		return true
	}
	ttl := s.opts.VoidedInterval / 2
	if ttl < time.Second {
		ttl = time.Second
	}
	ok, err := s.rdb.SetNX(ctx, VoidedLockKey, "1", ttl).Result()
	return err == nil && ok
}

// PollVoided reads every in-app purchase Google voided within VoidedLookback
// and refunds the ones granted here (idempotent). It returns how many were
// newly refunded.
func (s *Service) PollVoided(ctx context.Context) (int, error) {
	g := s.opts.Google
	if g == nil {
		return 0, ErrUnavailable
	}
	// Google accepts a startTime at most 30 days back.
	since := s.opts.Now().Add(-min(s.opts.VoidedLookback, 30*24*time.Hour-time.Hour))
	applied, page := 0, ""
	for pages := 0; pages < 100; pages++ {
		list, next, err := g.Voided(ctx, since, page)
		if err != nil {
			return applied, err
		}
		for _, v := range list {
			if v.PurchaseToken == "" {
				continue
			}
			res, err := s.Refund(ctx, StoreGooglePlay, TokenHash(v.PurchaseToken))
			if err != nil {
				return applied, err
			}
			if res == RefundApplied {
				applied++
			}
		}
		if next == "" {
			return applied, nil
		}
		page = next
	}
	return applied, nil
}

// ------------------------------------------------- Apple server notifications

// HandleAppleNotification verifies an App Store Server Notification V2 and
// applies REFUND / REVOKE (other types are acknowledged and ignored). The
// result is a RefundResult or "ignored".
func (s *Service) HandleAppleNotification(ctx context.Context, signedPayload string) (string, error) {
	a := s.opts.Apple
	if a == nil {
		return "", ErrUnavailable
	}
	n, err := a.VerifyNotification(signedPayload)
	if err != nil {
		return "", fmt.Errorf("%w: %s", ErrBadRequest, err.Error())
	}
	if n.Data.BundleID != "" && n.Data.BundleID != a.BundleID() {
		return "", fmt.Errorf("%w: bundle id", ErrBadRequest)
	}
	switch n.NotificationType {
	case "REFUND", "REVOKE":
	default:
		return "ignored", nil // TEST, CONSUMPTION_REQUEST, REFUND_DECLINED, REFUND_REVERSED, …
	}
	if !a.EnvironmentAllowed(n.Data.Environment) {
		return "ignored", nil
	}
	tx, err := a.VerifyTransaction(n.Data.SignedTransactionInfo)
	if err != nil {
		return "", fmt.Errorf("%w: %s", ErrBadRequest, err.Error())
	}
	if tx.BundleID != a.BundleID() {
		return "", fmt.Errorf("%w: bundle id", ErrBadRequest)
	}
	res, err := s.Refund(ctx, StoreAppStore, tx.TransactionID)
	return string(res), err
}
