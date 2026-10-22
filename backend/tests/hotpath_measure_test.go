package tests

import (
	"context"
	"fmt"
	"os"
	"sort"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"ludoarena/internal/postgres"
	"ludoarena/internal/rooms"
)

// openPG opens the app's pool; with a tracer it mirrors postgres.Open's
// settings and traces every query (used to count queries per request).
func openPG(ctx context.Context, url string, tracer pgx.QueryTracer) (*pgxpool.Pool, error) {
	if tracer == nil {
		return postgres.Open(ctx, url, 10)
	}
	cfg, err := pgxpool.ParseConfig(url)
	if err != nil {
		return nil, err
	}
	cfg.MaxConns = int32(envInt("MEASURE_PG_CONNS", 10))
	cfg.ConnConfig.RuntimeParams["statement_timeout"] = "5000"
	cfg.ConnConfig.Tracer = tracer
	return pgxpool.NewWithConfig(ctx, cfg)
}

// queryCounter counts PostgreSQL statements (BEGIN/COMMIT included: each is a
// round trip holding a pool connection), and separately those that touch the
// progression schema.
type queryCounter struct{ n, prog atomic.Int64 }

func (q *queryCounter) TraceQueryStart(ctx context.Context, _ *pgx.Conn, d pgx.TraceQueryStartData) context.Context {
	q.n.Add(1)
	if strings.Contains(d.SQL, "progression.") {
		q.prog.Add(1)
	}
	return ctx
}

func (q *queryCounter) TraceQueryEnd(context.Context, *pgx.Conn, pgx.TraceQueryEndData) {}

// sample is one timed call: latency, PostgreSQL statements it issued (q) and
// how many of them touched the progression schema (p).
type sample struct {
	d    time.Duration
	q, p int64
}

type samples []sample

func (s samples) pct(p float64) time.Duration {
	if len(s) == 0 {
		return 0
	}
	ds := make([]time.Duration, len(s))
	for i, x := range s {
		ds[i] = x.d
	}
	sort.Slice(ds, func(a, b int) bool { return ds[a] < ds[b] })
	return ds[int(float64(len(ds)-1)*p)]
}

func median(xs []int64) int64 {
	if len(xs) == 0 {
		return 0
	}
	sort.Slice(xs, func(a, b int) bool { return xs[a] < xs[b] })
	return xs[len(xs)/2]
}

func (s samples) String() string {
	qs, ps := make([]int64, len(s)), make([]int64, len(s))
	for i, x := range s {
		qs[i], ps[i] = x.q, x.p
	}
	return fmt.Sprintf("n=%-4d p50=%-9s p95=%-9s p99=%-9s pg/call=%d (progression %d)",
		len(s), s.pct(.5).Round(time.Microsecond), s.pct(.95).Round(time.Microsecond),
		s.pct(.99).Round(time.Microsecond), median(qs), median(ps))
}

func envInt(key string, def int) int {
	if v, err := strconv.Atoi(os.Getenv(key)); err == nil && v > 0 {
		return v
	}
	return def
}

// timed runs fn and records its latency and PostgreSQL statement counts
// (exact only when nothing else queries PostgreSQL concurrently).
func timed(qc *queryCounter, fn func() error) (sample, error) {
	q0, p0, t0 := qc.n.Load(), qc.prog.Load(), time.Now()
	err := fn()
	return sample{d: time.Since(t0), q: qc.n.Load() - q0, p: qc.prog.Load() - p0}, err
}

// TestMeasureHotPathLatency times the room-engine paths that touch
// PostgreSQL: matchmaking joins (seat summary + wallet pre-check), owned
// emotes, the wallet pre-check alone and the entry-fee debit, sequentially and
// with MEASURE_PARALLEL concurrent players (private rooms, so they never
// fill each other's lobbies). It drives the service in-process (no WebSocket
// overhead) against the test PostgreSQL and Redis and prints p50/p95/p99 and
// PostgreSQL statements per call.
//
//	MEASURE_HOT_PATH=1 MEASURE_ACCOUNTS=100 MEASURE_JOINS=20 MEASURE_PARALLEL=32 \
//	  go test -run TestMeasureHotPathLatency -v ./tests/
func TestMeasureHotPathLatency(t *testing.T) {
	if os.Getenv("MEASURE_HOT_PATH") == "" {
		t.Skip("set MEASURE_HOT_PATH=1 to measure")
	}
	t.Setenv("RATE_LIMIT_DISABLED", "true") // many sign-ups and joins from one IP
	qc := &queryCounter{}
	e := newEnv(t, envOpts{pgTracer: qc})
	ctx := context.Background()
	nAccounts, nJoins := envInt("MEASURE_ACCOUNTS", 50), envInt("MEASURE_JOINS", 10)

	accts := make([]account, nAccounts)
	var signup samples
	for i := range accts {
		s, _ := timed(qc, func() error { accts[i] = e.guest(); return nil })
		signup = append(signup, s)
	}
	time.Sleep(300 * time.Millisecond) // let new-account work settle
	for i := range accts {
		// A purchased (non-starter) emote, so the ownership check needs data.
		if _, err := e.app.PG.Exec(ctx, `INSERT INTO progression.inventory (user_id, item_id) VALUES ($1, 'emote_crown')
			ON CONFLICT DO NOTHING`, accts[i].UserID); err != nil {
			t.Fatal(err)
		}
	}

	var joinCold, joinWarm, emoteCold, emoteWarm, cancel samples
	for round := 0; round < nJoins; round++ {
		for _, a := range accts {
			c := rooms.Caller{UserID: a.UserID}
			var room *rooms.Room
			s, err := timed(qc, func() (err error) {
				room, err = e.app.Rooms.MatchmakingJoin(ctx, c, "ludo", "classic", 4)
				return err
			})
			if err != nil {
				t.Fatalf("join: %v", err)
			}
			if round == 0 {
				joinCold = append(joinCold, s)
			} else {
				joinWarm = append(joinWarm, s)
			}
			s, err = timed(qc, func() error { return e.app.Rooms.QuickChat(ctx, c, room.ID, "", "emote_crown") })
			if err != nil {
				t.Fatalf("emote: %v", err)
			}
			if round == 0 {
				emoteCold = append(emoteCold, s)
			} else {
				emoteWarm = append(emoteWarm, s)
			}
			s, err = timed(qc, func() error { return e.app.Rooms.MatchmakingCancel(ctx, c) })
			if err != nil {
				t.Fatalf("cancel: %v", err)
			}
			cancel = append(cancel, s)
		}
	}

	// Concurrent players: each creates a private room, sends an emote, leaves.
	par := envInt("MEASURE_PARALLEL", 32)
	if par > nAccounts {
		par = nAccounts
	}
	var mu sync.Mutex
	var pCreate, pEmote samples
	var wg sync.WaitGroup
	q0, start := qc.n.Load(), time.Now()
	for w := 0; w < par; w++ {
		wg.Add(1)
		go func(a account) {
			defer wg.Done()
			c := rooms.Caller{UserID: a.UserID}
			for k := 0; k < nJoins; k++ {
				t0 := time.Now()
				room, err := e.app.Rooms.CreatePrivate(ctx, c, "ludo", "classic", 4)
				d1 := time.Since(t0)
				if err != nil {
					t.Errorf("create: %v", err)
					return
				}
				t0 = time.Now()
				err = e.app.Rooms.QuickChat(ctx, c, room.ID, "", "emote_crown")
				d2 := time.Since(t0)
				if err != nil {
					t.Errorf("emote: %v", err)
					return
				}
				if err := e.app.Rooms.Leave(ctx, c, room.ID); err != nil {
					t.Errorf("leave: %v", err)
					return
				}
				mu.Lock()
				pCreate, pEmote = append(pCreate, sample{d: d1}), append(pEmote, sample{d: d2})
				mu.Unlock()
			}
		}(accts[w])
	}
	wg.Wait()
	elapsed, pq := time.Since(start), qc.n.Load()-q0

	// The two wallet reads/writes that stay synchronous.
	var walletGet, debitAll samples
	for i := 0; i < nAccounts*nJoins; i++ {
		id := uuid.MustParse(accts[i%nAccounts].UserID)
		s, err := timed(qc, func() error { _, err := e.app.Wallets.Get(ctx, id); return err })
		if err != nil {
			t.Fatal(err)
		}
		walletGet = append(walletGet, s)
	}
	for i := 0; i < nAccounts; i++ {
		ids := []uuid.UUID{uuid.MustParse(accts[i].UserID), uuid.MustParse(accts[(i+1)%nAccounts].UserID)}
		s, err := timed(qc, func() error { _, err := e.app.Wallets.DebitAll(ctx, ids, 1); return err })
		if err != nil {
			t.Fatal(err)
		}
		debitAll = append(debitAll, s)
		for _, id := range ids {
			if _, err := e.app.Wallets.Credit(ctx, id, 1, 0); err != nil {
				t.Fatal(err)
			}
		}
	}

	t.Logf("POST /auth/guest (new account)      : %s", signup)
	t.Logf("matchmaking.join first per account  : %s", joinCold)
	t.Logf("matchmaking.join repeat             : %s", joinWarm)
	t.Logf("chat emote (owned) first            : %s", emoteCold)
	t.Logf("chat emote (owned) repeat           : %s", emoteWarm)
	t.Logf("matchmaking.cancel                  : %s", cancel)
	t.Logf("wallet pre-check alone (Wallets.Get): %s", walletGet)
	t.Logf("entry-fee DebitAll (2 players)      : %s", debitAll)
	t.Logf("parallel x%d room.create            : %s", par, pCreate)
	t.Logf("parallel x%d chat emote             : %s", par, pEmote)
	t.Logf("parallel x%d totals                 : %d rounds in %s (%.0f rounds/s), %.2f pg statements/round",
		par, len(pCreate), elapsed.Round(time.Millisecond), float64(len(pCreate))/elapsed.Seconds(),
		float64(pq)/float64(max(1, len(pCreate))))
}
