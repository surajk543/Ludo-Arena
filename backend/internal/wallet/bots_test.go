package wallet_test

import (
	"context"
	"errors"
	"os"
	"sync"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/prometheus/client_golang/prometheus"
	dto "github.com/prometheus/client_model/go"

	"ludoroyale/internal/metrics"
	"ludoroyale/internal/postgres"
	"ludoroyale/internal/wallet"
)

// rules are the owner's defaults: start 1 crore, below 1 lakh → 1 crore,
// above 10 crore → 1 crore before the next match.
var rules = wallet.DefaultBotRules()

func TestBotRulesBeforeMatch(t *testing.T) {
	cases := []struct {
		name          string
		coins, fee    int64
		want          int64
		reset, charge bool
		removed       int64
		minted        int64
	}{
		{"start balance pays as is", 10_000_000, 100_000, 10_000_000, false, false, 0, 0},
		{"just at the recharge threshold", 100_000, 100_000, 100_000, false, false, 0, 0},
		{"below 1 lakh is recharged to 1 crore", 99_999, 100_000, 10_000_000, false, true, 0, 9_900_001},
		{"broke bot", 0, 50_000, 10_000_000, false, true, 0, 10_000_000},
		{"exactly 10 crore is kept", 100_000_000, 100_000, 100_000_000, false, false, 0, 0},
		{"above 10 crore is reset to 1 crore", 100_000_001, 100_000, 10_000_000, true, false, 90_000_001, 0},
		{"far above", 750_000_000, 100_000, 10_000_000, true, false, 740_000_000, 0},
		{"above 1 lakh but short of the fee", 150_000, 400_000, 10_000_000, false, true, 0, 9_850_000},
		{"fee above the recharge target", 5_000_000, 30_000_000, 30_000_000, false, true, 0, 25_000_000},
		{"free round", 10_000_000, 0, 10_000_000, false, false, 0, 0},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got, a := rules.BeforeMatch(c.coins, c.fee)
			if got != c.want || a.Reset != c.reset || a.Recharged != c.charge || a.Removed != c.removed || a.Minted != c.minted {
				t.Fatalf("BeforeMatch(%d, %d) = %d %+v", c.coins, c.fee, got, a)
			}
			if got < c.fee {
				t.Fatalf("the bot cannot pay: %d < %d", got, c.fee)
			}
		})
	}
}

func TestBotRulesAfterSettlement(t *testing.T) {
	cases := []struct {
		coins, want int64
		recharged   bool
	}{
		{0, 10_000_000, true},
		{99_999, 10_000_000, true},
		{100_000, 100_000, false},
		{9_900_000, 9_900_000, false},
		// Above 10 crore stays until the bot's next match (BeforeMatch).
		{140_000_000, 140_000_000, false},
	}
	for _, c := range cases {
		got, a := rules.AfterSettlement(c.coins)
		if got != c.want || a.Recharged != c.recharged || (c.recharged && a.Minted != c.want-c.coins) {
			t.Errorf("AfterSettlement(%d) = %d %+v", c.coins, got, a)
		}
		// Settling again changes nothing (retries are safe).
		if again, a2 := rules.AfterSettlement(got); again != got || a2.Recharged {
			t.Errorf("AfterSettlement is not idempotent at %d", got)
		}
	}
}

func TestBotRulesValidate(t *testing.T) {
	if err := wallet.DefaultBotRules().Validate(); err != nil {
		t.Fatalf("defaults: %v", err)
	}
	if (wallet.BotRules{}).Validate() == nil {
		t.Fatal("zero rules accepted")
	}
	bad := wallet.DefaultBotRules()
	bad.RechargeTo = bad.ResetAbove + 1 // a recharge would trigger the reset
	if bad.Validate() == nil {
		t.Fatal("contradicting rules accepted")
	}
}

// ---- PostgreSQL ----

func testStore(t *testing.T) (*wallet.Store, *pgxpool.Pool) {
	t.Helper()
	url := os.Getenv("TEST_DATABASE_URL")
	if url == "" {
		t.Skip("TEST_DATABASE_URL not set")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	pool, err := postgres.Open(ctx, url, 16)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(pool.Close)
	if err := postgres.Migrate(ctx, pool); err != nil {
		t.Fatal(err)
	}
	return wallet.NewStore(pool), pool
}

// person creates a person's wallet (an account row, is_bot = FALSE).
func person(t *testing.T, pool *pgxpool.Pool, coins int64) uuid.UUID {
	t.Helper()
	id := uuid.New()
	if _, err := pool.Exec(context.Background(), `INSERT INTO wallet.wallets (user_id, coins, diamonds) VALUES ($1, $2, 5)`,
		id, coins); err != nil {
		t.Fatal(err)
	}
	return id
}

type row struct {
	coins, diamonds int64
	bot             bool
}

func walletRow(t *testing.T, pool *pgxpool.Pool, id uuid.UUID) row {
	t.Helper()
	var r row
	if err := pool.QueryRow(context.Background(), `SELECT coins, diamonds, is_bot FROM wallet.wallets WHERE user_id = $1`, id).
		Scan(&r.coins, &r.diamonds, &r.bot); err != nil {
		t.Fatalf("wallet %s: %v", id, err)
	}
	return r
}

func setCoins(t *testing.T, pool *pgxpool.Pool, id uuid.UUID, coins int64) {
	t.Helper()
	if _, err := pool.Exec(context.Background(), `UPDATE wallet.wallets SET coins = $2 WHERE user_id = $1`, id, coins); err != nil {
		t.Fatal(err)
	}
}

func value(c prometheus.Counter) float64 {
	var m dto.Metric
	_ = c.Write(&m)
	return m.GetCounter().GetValue()
}

// counters snapshots the bot coin metrics.
type counters struct{ recharges, resets, mintedStart, mintedRecharge, removed float64 }

func snapshot() counters {
	return counters{value(metrics.BotWalletRecharges), value(metrics.BotWalletResets),
		value(metrics.BotCoinsMinted.WithLabelValues("start")), value(metrics.BotCoinsMinted.WithLabelValues("recharge")),
		value(metrics.BotCoinsRemoved.WithLabelValues("reset"))}
}

func (c counters) minus(o counters) counters {
	return counters{c.recharges - o.recharges, c.resets - o.resets, c.mintedStart - o.mintedStart,
		c.mintedRecharge - o.mintedRecharge, c.removed - o.removed}
}

// A bot wallet starts with 1 crore and no diamonds the first time, once.
func TestEnsureBotsCreatesOnce(t *testing.T) {
	s, pool := testStore(t)
	ctx := context.Background()
	bot := uuid.New()
	before := snapshot()
	for i, want := range []int{1, 0} {
		n, err := s.EnsureBots(ctx, []uuid.UUID{bot, bot}, rules.Start)
		if err != nil || n != want {
			t.Fatalf("ensure #%d: created %d err %v, want %d", i, n, err, want)
		}
	}
	if r := walletRow(t, pool, bot); r != (row{10_000_000, 0, true}) {
		t.Fatalf("new bot wallet %+v", r)
	}
	if d := snapshot().minus(before); d.mintedStart != 10_000_000 {
		t.Fatalf("minted at start %v", d.mintedStart)
	}
	// A person's existing row is never turned into a bot wallet.
	p := person(t, pool, 1_000)
	if n, err := s.EnsureBots(ctx, []uuid.UUID{p}, rules.Start); err != nil || n != 0 {
		t.Fatalf("ensure over a person: %d %v", n, err)
	}
	if r := walletRow(t, pool, p); r != (row{1_000, 5, false}) {
		t.Fatalf("person changed: %+v", r)
	}
}

// One transaction charges people and bots; the before-match rules run first.
func TestChargeEntryPeopleAndBots(t *testing.T) {
	s, pool := testStore(t)
	ctx := context.Background()
	const fee = 100_000
	a := person(t, pool, 1_000_000)
	fresh, poor, rich := uuid.New(), uuid.New(), uuid.New()
	if _, err := s.EnsureBots(ctx, []uuid.UUID{poor, rich}, rules.Start); err != nil {
		t.Fatal(err)
	}
	setCoins(t, pool, poor, 99_999)
	setCoins(t, pool, rich, 150_000_000)
	before := snapshot()
	got, err := s.ChargeEntry(ctx, []uuid.UUID{a}, []uuid.UUID{fresh, poor, rich}, fee, rules)
	if err != nil {
		t.Fatal(err)
	}
	want := map[uuid.UUID]int64{
		a:     900_000,
		fresh: 10_000_000 - fee, // created with 1 crore, then charged
		poor:  10_000_000 - fee, // below 1 lakh: recharged to 1 crore, then charged
		rich:  10_000_000 - fee, // above 10 crore: reset to 1 crore, then charged
	}
	for id, coins := range want {
		if got[id].Coins != coins || walletRow(t, pool, id).coins != coins {
			t.Fatalf("%s: returned %d stored %d, want %d", id, got[id].Coins, walletRow(t, pool, id).coins, coins)
		}
	}
	d := snapshot().minus(before)
	if d.recharges != 1 || d.mintedRecharge != 10_000_000-99_999 || d.resets != 1 || d.removed != 140_000_000 ||
		d.mintedStart != 10_000_000 {
		t.Fatalf("metrics %+v", d)
	}
}

// A person who cannot pay fails the whole charge: no bot is charged,
// recharged or reset either.
func TestChargeEntryShortPersonChargesNobody(t *testing.T) {
	s, pool := testStore(t)
	ctx := context.Background()
	rich, broke := person(t, pool, 1_000_000), person(t, pool, 10)
	bot := uuid.New()
	if _, err := s.EnsureBots(ctx, []uuid.UUID{bot}, rules.Start); err != nil {
		t.Fatal(err)
	}
	setCoins(t, pool, bot, 200_000_000)
	before := snapshot()
	_, err := s.ChargeEntry(ctx, []uuid.UUID{rich, broke}, []uuid.UUID{bot}, 100_000, rules)
	var short *wallet.ShortError
	if !errors.As(err, &short) || len(short.Users) != 1 || short.Users[0] != broke {
		t.Fatalf("err = %v", err)
	}
	if walletRow(t, pool, rich).coins != 1_000_000 || walletRow(t, pool, bot).coins != 200_000_000 {
		t.Fatal("a failed charge changed a wallet")
	}
	if d := snapshot().minus(before); d != (counters{}) {
		t.Fatalf("a failed charge counted rules: %+v", d)
	}
}

// After a settlement a bot below 1 lakh is recharged; settling again (a
// retry) changes nothing, and a person's wallet is never touched.
func TestSettleBots(t *testing.T) {
	s, pool := testStore(t)
	ctx := context.Background()
	low, ok, rich := uuid.New(), uuid.New(), uuid.New()
	if _, err := s.EnsureBots(ctx, []uuid.UUID{low, ok, rich}, rules.Start); err != nil {
		t.Fatal(err)
	}
	setCoins(t, pool, low, 40_000)
	setCoins(t, pool, ok, 100_000)
	setCoins(t, pool, rich, 300_000_000)
	p := person(t, pool, 5)
	before := snapshot()
	for i := 0; i < 2; i++ {
		if err := s.SettleBots(ctx, []uuid.UUID{low, ok, rich, p, uuid.New()}, rules); err != nil {
			t.Fatal(err)
		}
	}
	for id, want := range map[uuid.UUID]int64{low: 10_000_000, ok: 100_000, rich: 300_000_000, p: 5} {
		if got := walletRow(t, pool, id).coins; got != want {
			t.Fatalf("%s: %d, want %d", id, got, want)
		}
	}
	if d := snapshot().minus(before); d.recharges != 1 || d.mintedRecharge != 10_000_000-40_000 || d.resets != 0 {
		t.Fatalf("metrics %+v", d)
	}
}

// Concurrent matches of one persona serialize on its wallet row: every fee
// is charged exactly once and no update is lost (no double spend).
func TestConcurrentChargesOfOneBot(t *testing.T) {
	s, pool := testStore(t)
	ctx := context.Background()
	bot := uuid.New()
	if _, err := s.EnsureBots(ctx, []uuid.UUID{bot}, rules.Start); err != nil {
		t.Fatal(err)
	}
	setCoins(t, pool, bot, 200_000)
	const n, fee = 8, 100_000
	before := snapshot()
	var wg sync.WaitGroup
	errs := make(chan error, n)
	for i := 0; i < n; i++ {
		p := person(t, pool, 1_000_000)
		wg.Add(1)
		go func() {
			defer wg.Done()
			_, err := s.ChargeEntry(ctx, []uuid.UUID{p}, []uuid.UUID{bot}, fee, rules)
			errs <- err
		}()
	}
	wg.Wait()
	close(errs)
	for err := range errs {
		if err != nil {
			t.Fatal(err)
		}
	}
	// 200k → 100k → 0; then 0 < 1 lakh: recharged to 1 crore and charged
	// six more times.
	if got := walletRow(t, pool, bot).coins; got != 10_000_000-6*fee {
		t.Fatalf("bot balance %d, want %d", got, 10_000_000-6*fee)
	}
	if d := snapshot().minus(before); d.recharges != 1 || d.mintedRecharge != 10_000_000 {
		t.Fatalf("metrics %+v", d)
	}
}
