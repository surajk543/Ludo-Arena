package client

import (
	"context"
	"math/rand/v2"
	"time"
)

// Backoff is bounded exponential backoff with full jitter:
// delay(attempt) = random(0, min(Max, Base * 2^attempt)).
type Backoff struct {
	Base time.Duration
	Max  time.Duration
}

// Delay returns the jittered delay for a zero-based attempt number.
func (b Backoff) Delay(attempt int) time.Duration {
	return FullJitter(b.Ceiling(attempt))
}

// Ceiling returns the un-jittered upper bound for an attempt.
func (b Backoff) Ceiling(attempt int) time.Duration {
	if b.Base <= 0 {
		return 0
	}
	ceil := b.Max
	if attempt < 30 {
		if d := b.Base << uint(attempt); d > 0 && d < ceil {
			ceil = d
		}
	}
	return ceil
}

// FullJitter returns a uniformly random duration in [0, d].
func FullJitter(d time.Duration) time.Duration {
	if d <= 0 {
		return 0
	}
	return time.Duration(rand.Int64N(int64(d) + 1))
}

// Jitter returns d scaled by a random factor in [1-frac, 1+frac].
func Jitter(d time.Duration, frac float64) time.Duration {
	if d <= 0 || frac <= 0 {
		return d
	}
	f := 1 - frac + rand.Float64()*2*frac
	return time.Duration(float64(d) * f)
}

// Sleep waits for d or until ctx is done (returning ctx.Err()).
func Sleep(ctx context.Context, d time.Duration) error {
	if d <= 0 {
		return ctx.Err()
	}
	t := time.NewTimer(d)
	defer t.Stop()
	select {
	case <-ctx.Done():
		return ctx.Err()
	case <-t.C:
		return nil
	}
}
