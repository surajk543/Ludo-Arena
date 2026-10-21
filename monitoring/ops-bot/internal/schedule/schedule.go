// Package schedule runs the periodic jobs (hourly status, daily digest) on
// an injectable clock so the timing logic is testable without waiting.
package schedule

import (
	"context"
	"sync"
	"time"
)

// Clock abstracts time for the scheduler.
type Clock interface {
	Now() time.Time
	After(d time.Duration) <-chan time.Time
}

// Real is the wall clock.
type Real struct{}

// Now returns time.Now().
func (Real) Now() time.Time { return time.Now() }

// After returns time.After(d).
func (Real) After(d time.Duration) <-chan time.Time { return time.After(d) }

// NextInterval returns the next run after now for a repeating interval.
// With align, runs fall on multiples of the interval counted from local
// midnight (1h → every full hour, 30m → :00 and :30), and a day never has a
// partial last slot: the next day restarts at midnight. A zero interval
// disables the job (zero time).
func NextInterval(now time.Time, interval time.Duration, loc *time.Location, align bool) time.Time {
	if interval <= 0 {
		return time.Time{}
	}
	if !align || interval > 24*time.Hour {
		return now.Add(interval)
	}
	l := now.In(loc)
	midnight := time.Date(l.Year(), l.Month(), l.Day(), 0, 0, 0, 0, loc)
	nextMidnight := midnight.AddDate(0, 0, 1)
	k := now.Sub(midnight)/interval + 1
	next := midnight.Add(k * interval)
	if next.After(nextMidnight) {
		next = nextMidnight
	}
	return next
}

// NextDaily returns the next occurrence of hour:minute in loc strictly after now.
func NextDaily(now time.Time, hour, minute int, loc *time.Location) time.Time {
	l := now.In(loc)
	next := time.Date(l.Year(), l.Month(), l.Day(), hour, minute, 0, 0, loc)
	if !next.After(now) {
		next = time.Date(l.Year(), l.Month(), l.Day()+1, hour, minute, 0, 0, loc)
	}
	return next
}

// Job is a periodic task. Next returns the zero time to disable the job.
type Job struct {
	Name string
	Next func(now time.Time) time.Time
	Run  func(ctx context.Context)
}

// Run executes job at each Next time until ctx ends. Runs never overlap; a
// run that overlaps the next slot simply moves on to the following one.
func Run(ctx context.Context, clock Clock, job Job) {
	for {
		now := clock.Now()
		next := job.Next(now)
		if next.IsZero() {
			return
		}
		select {
		case <-ctx.Done():
			return
		case <-clock.After(next.Sub(now)):
		}
		if ctx.Err() != nil {
			return
		}
		job.Run(ctx)
	}
}

// Fake is a manually advanced clock for tests.
type Fake struct {
	mu      sync.Mutex
	cond    *sync.Cond
	now     time.Time
	waiters []fakeWaiter
}

type fakeWaiter struct {
	at time.Time
	ch chan time.Time
}

// NewFake returns a fake clock set to now.
func NewFake(now time.Time) *Fake {
	f := &Fake{now: now}
	f.cond = sync.NewCond(&f.mu)
	return f
}

// Now returns the fake time.
func (f *Fake) Now() time.Time {
	f.mu.Lock()
	defer f.mu.Unlock()
	return f.now
}

// After returns a channel that fires once the fake time reaches now+d.
func (f *Fake) After(d time.Duration) <-chan time.Time {
	f.mu.Lock()
	defer f.mu.Unlock()
	ch := make(chan time.Time, 1)
	if d <= 0 {
		ch <- f.now
		return ch
	}
	f.waiters = append(f.waiters, fakeWaiter{at: f.now.Add(d), ch: ch})
	f.cond.Broadcast()
	return ch
}

// Advance moves the clock forward and fires due timers.
func (f *Fake) Advance(d time.Duration) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.now = f.now.Add(d)
	kept := f.waiters[:0]
	for _, w := range f.waiters {
		if !w.at.After(f.now) {
			w.ch <- f.now
		} else {
			kept = append(kept, w)
		}
	}
	f.waiters = kept
}

// BlockUntilWaiters waits until n timers are pending.
func (f *Fake) BlockUntilWaiters(n int) {
	f.mu.Lock()
	defer f.mu.Unlock()
	for len(f.waiters) < n {
		f.cond.Wait()
	}
}

// NextWaiter returns the earliest pending deadline (zero if none).
func (f *Fake) NextWaiter() time.Time {
	f.mu.Lock()
	defer f.mu.Unlock()
	var t time.Time
	for _, w := range f.waiters {
		if t.IsZero() || w.at.Before(t) {
			t = w.at
		}
	}
	return t
}
