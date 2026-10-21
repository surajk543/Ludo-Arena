package schedule

import (
	"context"
	"sync/atomic"
	"testing"
	"time"
)

func loc(t *testing.T, name string) *time.Location {
	t.Helper()
	l, err := time.LoadLocation(name)
	if err != nil {
		t.Fatal(err)
	}
	return l
}

func TestNextInterval(t *testing.T) {
	ist := loc(t, "Asia/Kolkata")
	at := func(h, m int) time.Time { return time.Date(2026, 10, 21, h, m, 0, 0, ist) }
	tests := []struct {
		name     string
		now      time.Time
		interval time.Duration
		align    bool
		want     time.Time
	}{
		{"zero disables", at(10, 7), 0, true, time.Time{}},
		{"hourly aligned to local hours", at(10, 7), time.Hour, true, at(11, 0)},
		{"exactly on the hour moves on", at(11, 0), time.Hour, true, at(12, 0)},
		{"half-hourly", at(10, 7), 30 * time.Minute, true, at(10, 30)},
		{"7h slots restart at midnight", at(22, 0), 7 * time.Hour, true, time.Date(2026, 10, 22, 0, 0, 0, 0, ist)},
		{"not aligned", at(10, 7), time.Hour, false, at(11, 7)},
		{"longer than a day", at(10, 7), 48 * time.Hour, true, at(10, 7).Add(48 * time.Hour)},
	}
	for _, tt := range tests {
		if got := NextInterval(tt.now, tt.interval, ist, tt.align); !got.Equal(tt.want) {
			t.Errorf("%s: got %v, want %v", tt.name, got, tt.want)
		}
	}
}

func TestNextDaily(t *testing.T) {
	ist := loc(t, "Asia/Kolkata")
	ny := loc(t, "America/New_York")
	tests := []struct {
		name string
		now  time.Time
		h, m int
		l    *time.Location
		want time.Time
	}{
		{"later today", time.Date(2026, 10, 21, 8, 0, 0, 0, ist), 9, 0, ist, time.Date(2026, 10, 21, 9, 0, 0, 0, ist)},
		{"already passed", time.Date(2026, 10, 21, 9, 0, 0, 0, ist), 9, 0, ist, time.Date(2026, 10, 22, 9, 0, 0, 0, ist)},
		{"now given in UTC", time.Date(2026, 10, 21, 3, 0, 0, 0, time.UTC), 9, 0, ist, time.Date(2026, 10, 21, 9, 0, 0, 0, ist)},
		{"across DST change", time.Date(2026, 11, 1, 1, 0, 0, 0, ny), 9, 0, ny, time.Date(2026, 11, 1, 9, 0, 0, 0, ny)},
	}
	for _, tt := range tests {
		if got := NextDaily(tt.now, tt.h, tt.m, tt.l); !got.Equal(tt.want) {
			t.Errorf("%s: got %v, want %v", tt.name, got, tt.want)
		}
	}
}

func TestRunWithFakeClock(t *testing.T) {
	ist := loc(t, "Asia/Kolkata")
	clock := NewFake(time.Date(2026, 10, 21, 10, 59, 0, 0, ist))
	var runs atomic.Int32
	ran := make(chan time.Time, 10)
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan struct{})
	go func() {
		Run(ctx, clock, Job{
			Name: "status",
			Next: func(now time.Time) time.Time { return NextInterval(now, time.Hour, ist, true) },
			Run:  func(context.Context) { runs.Add(1); ran <- clock.Now() },
		})
		close(done)
	}()
	for i, want := range []time.Time{
		time.Date(2026, 10, 21, 11, 0, 0, 0, ist),
		time.Date(2026, 10, 21, 12, 0, 0, 0, ist),
	} {
		clock.BlockUntilWaiters(1)
		if next := clock.NextWaiter(); !next.Equal(want) {
			t.Fatalf("run %d scheduled for %v, want %v", i, next, want)
		}
		clock.Advance(want.Sub(clock.Now()))
		if got := <-ran; !got.Equal(want) {
			t.Fatalf("run %d at %v, want %v", i, got, want)
		}
	}
	clock.BlockUntilWaiters(1)
	cancel()
	<-done
	if runs.Load() != 2 {
		t.Errorf("runs = %d, want 2", runs.Load())
	}
}

func TestRunDisabledJobReturns(t *testing.T) {
	clock := NewFake(time.Now())
	done := make(chan struct{})
	go func() {
		Run(context.Background(), clock, Job{Next: func(time.Time) time.Time { return time.Time{} }, Run: func(context.Context) { t.Error("disabled job ran") }})
		close(done)
	}()
	select {
	case <-done:
	case <-time.After(2 * time.Second):
		t.Fatal("a disabled job must return immediately")
	}
}
