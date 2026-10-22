package async

import (
	"context"
	"errors"
	"io"
	"log/slog"
	"sync/atomic"
	"testing"
	"time"

	dto "github.com/prometheus/client_model/go"

	"ludoarena/internal/metrics"
)

func quiet() *slog.Logger { return slog.New(slog.NewTextHandler(io.Discard, nil)) }

func count(job, result string) float64 {
	var m dto.Metric
	if err := metrics.AsyncJobs.WithLabelValues(job, result).Write(&m); err != nil {
		panic(err)
	}
	return m.GetCounter().GetValue()
}

func waitUntil(t *testing.T, what string, cond func() bool) {
	t.Helper()
	deadline := time.Now().Add(5 * time.Second)
	for !cond() {
		if time.Now().After(deadline) {
			t.Fatalf("timed out waiting for %s", what)
		}
		time.Sleep(time.Millisecond)
	}
}

func start(t *testing.T, o Options) (*Runner, context.CancelFunc) {
	t.Helper()
	o.Log = quiet()
	r := New(o)
	ctx, cancel := context.WithCancel(context.Background())
	go r.Run(ctx)
	t.Cleanup(func() {
		cancel()
		_ = r.Wait(context.Background())
	})
	return r, cancel
}

func TestRunsJobsAndCountsOutcomes(t *testing.T) {
	r, _ := start(t, Options{Workers: 2})
	ok0, err0, panic0 := count("t_ok", "ok"), count("t_err", "error"), count("t_panic", "panic")
	var ran atomic.Int32
	for i := 0; i < 10; i++ {
		r.Go("t_ok", func(ctx context.Context) error {
			if _, has := ctx.Deadline(); !has {
				t.Error("job context has no timeout")
			}
			ran.Add(1)
			return nil
		})
	}
	r.Go("t_err", func(context.Context) error { return errors.New("boom") })
	r.Go("t_panic", func(context.Context) error { panic("kaboom") })
	waitUntil(t, "jobs", func() bool {
		return count("t_ok", "ok")-ok0 == 10 && count("t_err", "error")-err0 == 1 && count("t_panic", "panic")-panic0 == 1
	})
	if ran.Load() != 10 {
		t.Fatalf("ran %d jobs", ran.Load())
	}
	// The runner survives a panicking job.
	done := make(chan struct{})
	r.Go("t_ok", func(context.Context) error { close(done); return nil })
	<-done
}

func TestFullQueueDropsWithoutBlocking(t *testing.T) {
	r, _ := start(t, Options{Workers: 1, Queue: 1})
	release, busy := make(chan struct{}), make(chan struct{})
	defer close(release)
	r.Go("t_block", func(context.Context) error { close(busy); <-release; return nil })
	<-busy
	if !r.Go("t_full", func(context.Context) error { return nil }) {
		t.Fatal("first queued job should fit")
	}
	d0 := count("t_full", "dropped")
	t0 := time.Now()
	if r.Go("t_full", func(context.Context) error { return nil }) {
		t.Fatal("job accepted by a full queue")
	}
	if time.Since(t0) > 50*time.Millisecond {
		t.Fatal("Go blocked on a full queue")
	}
	if count("t_full", "dropped")-d0 != 1 {
		t.Fatal("dropped job not counted")
	}
}

func TestShutdownDrainsQueuedJobs(t *testing.T) {
	r, cancel := start(t, Options{Workers: 1, DrainTimeout: 5 * time.Second})
	release, busy := make(chan struct{}), make(chan struct{})
	r.Go("t_block", func(context.Context) error { close(busy); <-release; return nil })
	<-busy
	var ran atomic.Int32
	for i := 0; i < 5; i++ {
		r.Go("t_drain", func(context.Context) error { ran.Add(1); return nil })
	}
	cancel() // shutdown begins while 5 jobs are queued behind a busy worker
	close(release)
	ctx, stop := context.WithTimeout(context.Background(), 3*time.Second)
	defer stop()
	if err := r.Wait(ctx); err != nil {
		t.Fatal(err)
	}
	if ran.Load() != 5 {
		t.Fatalf("drained %d of 5 queued jobs", ran.Load())
	}
	d0 := count("t_late", "dropped")
	if r.Go("t_late", func(context.Context) error { return nil }) || count("t_late", "dropped")-d0 != 1 {
		t.Fatal("a job enqueued after shutdown must be dropped and counted")
	}
}

func TestShutdownAbandonsAfterDrainDeadline(t *testing.T) {
	r, cancel := start(t, Options{Workers: 1, DrainTimeout: 100 * time.Millisecond, JobTimeout: time.Minute})
	busy := make(chan struct{})
	cancelled := make(chan struct{})
	r.Go("t_stuck", func(ctx context.Context) error {
		close(busy)
		<-ctx.Done() // a stuck PostgreSQL call honouring its context
		close(cancelled)
		return ctx.Err()
	})
	<-busy
	a0 := count("t_pending", "abandoned")
	for i := 0; i < 3; i++ {
		r.Go("t_pending", func(context.Context) error { t.Error("abandoned job ran"); return nil })
	}
	t0 := time.Now()
	cancel()
	ctx, stop := context.WithTimeout(context.Background(), 3*time.Second)
	defer stop()
	if err := r.Wait(ctx); err != nil {
		t.Fatal(err)
	}
	if el := time.Since(t0); el > 2*time.Second {
		t.Fatalf("shutdown took %s with a 100ms drain deadline", el)
	}
	<-cancelled
	if got := count("t_pending", "abandoned") - a0; got != 3 {
		t.Fatalf("abandoned = %v, want 3", got)
	}
}

func TestWaitWithoutRun(t *testing.T) {
	if err := New(Options{Log: quiet()}).Wait(context.Background()); err != nil {
		t.Fatal(err)
	}
}
