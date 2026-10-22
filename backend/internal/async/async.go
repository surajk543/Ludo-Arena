// Package async runs best-effort work off the request path: a bounded queue
// drained by a fixed pool of workers.
//
// A job gets its own context with a timeout, so finishing (or cancelling) the
// request that enqueued it never cancels it. Panics are recovered and every
// outcome is counted in async_jobs_total{job,result}. Go never blocks: when
// the queue is full, or after shutdown, the job is dropped and counted.
//
// On shutdown (the Run context is cancelled) workers keep draining the queue
// for at most DrainTimeout; then in-flight jobs are cancelled and jobs still
// queued are abandoned (counted). Only enqueue work that is safe to lose:
// idempotent and recreated lazily elsewhere (e.g. progression.Bootstrap).
package async

import (
	"context"
	"fmt"
	"log/slog"
	"sync"
	"time"

	"ludoarena/internal/metrics"
)

// Options configure a Runner. Zero values take the defaults.
type Options struct {
	Workers      int           // default 4
	Queue        int           // default 1024
	JobTimeout   time.Duration // default 10 s
	DrainTimeout time.Duration // default 5 s
	Log          *slog.Logger
}

type job struct {
	name string
	fn   func(ctx context.Context) error
}

// Runner is a bounded background job queue.
type Runner struct {
	opts  Options
	queue chan job

	mu     sync.Mutex
	closed bool // no more jobs are accepted

	started chan struct{} // closed when Run starts
	done    chan struct{} // closed when Run has returned
	once    sync.Once
}

// New returns a Runner; call Run to start its workers.
func New(o Options) *Runner {
	if o.Workers <= 0 {
		o.Workers = 4
	}
	if o.Queue <= 0 {
		o.Queue = 1024
	}
	if o.JobTimeout <= 0 {
		o.JobTimeout = 10 * time.Second
	}
	if o.DrainTimeout <= 0 {
		o.DrainTimeout = 5 * time.Second
	}
	if o.Log == nil {
		o.Log = slog.Default()
	}
	return &Runner{opts: o, queue: make(chan job, o.Queue), started: make(chan struct{}), done: make(chan struct{})}
}

// Workers returns the number of workers.
func (r *Runner) Workers() int { return r.opts.Workers }

// Go enqueues fn under name without blocking. It reports false when the job
// was dropped (queue full or runner stopped).
func (r *Runner) Go(name string, fn func(ctx context.Context) error) bool {
	r.mu.Lock()
	defer r.mu.Unlock()
	if r.closed {
		metrics.AsyncJobs.WithLabelValues(name, "dropped").Inc()
		return false
	}
	select {
	case r.queue <- job{name: name, fn: fn}:
		return true
	default:
		metrics.AsyncJobs.WithLabelValues(name, "dropped").Inc()
		r.opts.Log.Warn("background queue full; job dropped", "job", name)
		return false
	}
}

// Run starts the workers and blocks until ctx is cancelled and the queue has
// been drained (or DrainTimeout passed). Call it once.
func (r *Runner) Run(ctx context.Context) {
	ran := false
	r.once.Do(func() { ran = true })
	if !ran {
		return
	}
	close(r.started)
	defer close(r.done)
	// hard is cancelled at the drain deadline: in-flight jobs stop and
	// workers stop taking queued jobs.
	hard, cancelHard := context.WithCancel(context.Background())
	defer cancelHard()
	var wg sync.WaitGroup
	for i := 0; i < r.opts.Workers; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			r.work(ctx, hard)
		}()
	}
	<-ctx.Done()
	timer := time.AfterFunc(r.opts.DrainTimeout, cancelHard)
	wg.Wait()
	timer.Stop()

	r.mu.Lock()
	r.closed = true
	r.mu.Unlock()
	abandoned := 0
	for {
		select {
		case j := <-r.queue:
			metrics.AsyncJobs.WithLabelValues(j.name, "abandoned").Inc()
			abandoned++
		default:
			if abandoned > 0 {
				r.opts.Log.Warn("background jobs abandoned at shutdown", "count", abandoned)
			}
			return
		}
	}
}

// Wait blocks until Run has returned (shutdown drained) or ctx is done. It
// returns immediately when Run was never started.
func (r *Runner) Wait(ctx context.Context) error {
	select {
	case <-r.started:
	default:
		return nil
	}
	select {
	case <-r.done:
		return nil
	case <-ctx.Done():
		return ctx.Err()
	}
}

func (r *Runner) work(ctx, hard context.Context) {
	for hard.Err() == nil {
		if ctx.Err() != nil {
			// Shutting down: drain what is queued until empty or the deadline.
			select {
			case j := <-r.queue:
				r.exec(hard, j)
				continue
			default:
				return
			}
		}
		select {
		case j := <-r.queue:
			r.exec(hard, j)
		case <-ctx.Done():
		}
	}
}

func (r *Runner) exec(parent context.Context, j job) {
	if parent.Err() != nil { // the drain deadline passed while it was queued
		metrics.AsyncJobs.WithLabelValues(j.name, "abandoned").Inc()
		return
	}
	ctx, cancel := context.WithTimeout(parent, r.opts.JobTimeout)
	defer cancel()
	result := "ok"
	defer func() {
		if p := recover(); p != nil {
			result = "panic"
			r.opts.Log.Error("background job panicked", "job", j.name, "panic", fmt.Sprint(p))
		}
		metrics.AsyncJobs.WithLabelValues(j.name, result).Inc()
	}()
	if err := j.fn(ctx); err != nil {
		result = "error"
		r.opts.Log.Warn("background job failed", "job", j.name, "error", err.Error())
	}
}
