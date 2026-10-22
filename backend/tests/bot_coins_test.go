package tests

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"

	"ludoarena/internal/rooms"
)

// Bots play for coins like people (backend/docs/game-rules.md "Coins with
// bots"): every seat of a public or private match pays the entry fee (a bot
// from its wallet.wallets row flagged is_bot), the winner takes the pot,
// practice stays free, and the bot rules recharge (below 1 lakh → 1 crore)
// and reset (above 10 crore → 1 crore before the next match).

const (
	ludoFee   = 100_000    // default Ludo entry fee
	botStart  = 10_000_000 // BOT_COINS_START default (1 crore)
	welcomeCo = 1_000_000  // test accounts' welcome grant
)

// uniqueName is a bot display name of this test run: a persona's id (and so
// its wallet row) is derived from its name, and the test database outlives
// runs, so every run meets fresh personas.
func uniqueName(base string) string {
	return base + runID[len(runID)-6:]
}

// botUserID is the user id of a bot session (its token's subject): the
// persona id, which is also the bot wallet's user_id.
func botUserID(t *testing.T, a account) uuid.UUID {
	t.Helper()
	parts := strings.Split(a.Token, ".")
	if len(parts) != 3 {
		t.Fatalf("bot token is not a JWT")
	}
	raw, err := base64.RawURLEncoding.DecodeString(parts[1])
	if err != nil {
		t.Fatal(err)
	}
	var c struct {
		Sub string `json:"sub"`
	}
	if err := json.Unmarshal(raw, &c); err != nil {
		t.Fatal(err)
	}
	id, err := uuid.Parse(c.Sub)
	if err != nil {
		t.Fatalf("bot subject %q: %v", c.Sub, err)
	}
	return id
}

// botIDOf returns the user id of the spawned bot with public id uid.
func (e *env) botIDOf(t *testing.T, uid string) uuid.UUID {
	t.Helper()
	for _, c := range e.botClients {
		if c.acct.UID == uid {
			return botUserID(t, c.acct)
		}
	}
	t.Fatalf("no bot client with uid %s", uid)
	return uuid.Nil
}

// botWallet reads a wallet row: coins, diamonds and the is_bot flag.
func (e *env) botWallet(t *testing.T, id uuid.UUID) (coins, diamonds int64, isBot bool) {
	t.Helper()
	if err := e.app.PG.QueryRow(context.Background(),
		`SELECT coins, diamonds, is_bot FROM wallet.wallets WHERE user_id = $1`, id).Scan(&coins, &diamonds, &isBot); err != nil {
		t.Fatalf("wallet of %s: %v", id, err)
	}
	return coins, diamonds, isBot
}

func (e *env) botCoins(t *testing.T, id uuid.UUID) int64 {
	t.Helper()
	c, _, _ := e.botWallet(t, id)
	return c
}

func (e *env) setBotCoins(t *testing.T, id uuid.UUID, coins int64) {
	t.Helper()
	if _, err := e.app.PG.Exec(context.Background(), `UPDATE wallet.wallets SET coins = $2 WHERE user_id = $1 AND is_bot`,
		id, coins); err != nil {
		t.Fatal(err)
	}
}

// countRows counts rows of query with one id argument.
func (e *env) countRows(t *testing.T, query string, id uuid.UUID) int {
	t.Helper()
	var n int
	if err := e.app.PG.QueryRow(context.Background(), query, id).Scan(&n); err != nil {
		t.Fatal(err)
	}
	return n
}

// assertBotNotAccount checks that a bot wallet never becomes an account:
// no identity, progression, inventory or friendship rows.
func (e *env) assertBotNotAccount(t *testing.T, id uuid.UUID) {
	t.Helper()
	for _, q := range []string{
		`SELECT count(*) FROM identity.auth_identities WHERE user_id = $1`,
		`SELECT count(*) FROM progression.player_progress WHERE user_id = $1`,
		`SELECT count(*) FROM progression.inventory WHERE user_id = $1`,
		`SELECT count(*) FROM progression.loadout WHERE user_id = $1`,
		`SELECT count(*) FROM progression.match_receipts WHERE user_id = $1`,
		`SELECT count(*) FROM progression.friendships WHERE user_lo = $1 OR user_hi = $1`,
	} {
		if n := e.countRows(t, q, id); n != 0 {
			t.Fatalf("bot %s has account rows: %s → %d", id, q, n)
		}
	}
	if ok, err := e.app.IDs.Exists(context.Background(), id); err != nil || ok {
		t.Fatalf("a bot wallet counts as an account: %v %v", ok, err)
	}
}

// publicBotMatch matchmakes a fresh person into a 2-seat public Ludo lobby,
// fills the other seat with a bot named name and waits for the game.
func (e *env) publicBotMatch(t *testing.T, ctl, name string) (account, *client, *client) {
	t.Helper()
	human := e.guest()
	hc := e.mustDial("human-"+name, human)
	if m := hc.call("matchmaking.join", map[string]any{"game": "ludo", "variant": "quick", "capacity": 2}); m.T != "matchmaking.status" {
		t.Fatalf("matchmaking.join: %s %s", m.T, m.P)
	}
	waitFor(t, 3*time.Second, "lobby", func() bool { return hc.snapshot() != nil })
	if r := e.do("POST", "/api/v1/bot/lobbies/"+hc.snapshot().ID+"/fill", ctl, map[string]any{"count": 1}); r.Status != 200 {
		t.Fatalf("fill: %d %s", r.Status, r.Raw)
	}
	bot := e.spawnNamedBots(t, ctl, []string{name})[0]
	waitFor(t, 10*time.Second, "public game", func() bool { return hc.snapshot().Status == "playing" })
	return human, hc, bot
}

// A public match with a bot is played for coins exactly like one between
// people: both seats pay, the pot is the sum, the winner takes it.
func TestBotsPlayPublicMatchesForCoins(t *testing.T) {
	e := newEnv(t, envOpts{dice: rooms.NewSeededDice(41)})
	ctl := e.botController(t)

	// 1. The person wins (the bot leaves): the pot goes to the person.
	human, hc, bot := e.publicBotMatch(t, ctl, uniqueName("Kabir"))
	s := hc.snapshot()
	if s.EntryFee != ludoFee || s.Pot != 2*ludoFee || len(s.ComputerSeats) != 0 || s.PendingBots != 0 {
		t.Fatalf("public bot room: entryFee %d pot %d computerSeats %v pendingBots %d", s.EntryFee, s.Pot, s.ComputerSeats, s.PendingBots)
	}
	if got := e.coins(human.Token); got != welcomeCo-ludoFee {
		t.Fatalf("person after the fee: %d", got)
	}
	botID := botUserID(t, bot.acct)
	if coins, diamonds, isBot := e.botWallet(t, botID); coins != botStart-ludoFee || diamonds != 0 || !isBot {
		t.Fatalf("bot wallet after the fee: %d coins %d diamonds bot=%v", coins, diamonds, isBot)
	}
	waitFor(t, 3*time.Second, "entry fee wallet.updated", func() bool { return hc.count("wallet.updated") == 1 })
	if n := bot.count("wallet.updated"); n != 0 {
		t.Fatalf("the bot received %d wallet messages", n)
	}
	if r := e.do("DELETE", "/api/v1/bot/sessions/"+bot.acct.UID, ctl, nil); r.Status != 204 {
		t.Fatalf("end bot session: %d %s", r.Status, r.Raw)
	}
	waitFor(t, 5*time.Second, "person wins", func() bool { return hc.snapshot().Status == "finished" })
	if res := hc.snapshot().Result; res == nil || res.WinnerSeat != hc.seat() || res.Payout != 2*ludoFee {
		t.Fatalf("result %+v", res)
	}
	waitFor(t, 5*time.Second, "payout to the person", func() bool { return e.coins(human.Token) == welcomeCo+ludoFee })
	if got := e.botCoins(t, botID); got != botStart-ludoFee {
		t.Fatalf("bot wallet after losing: %d", got)
	}

	// 2. The bot wins (the person leaves): the pot goes to the bot's wallet
	// and the person keeps only what they had after the fee.
	human2, h2, bot2 := e.publicBotMatch(t, ctl, uniqueName("Meera"))
	bot2ID := botUserID(t, bot2.acct)
	if s := h2.snapshot(); s.Pot != 2*ludoFee {
		t.Fatalf("pot %d", s.Pot)
	}
	if m := h2.call("room.leave", map[string]any{"roomId": h2.snapshot().ID}); m.T != "ack" {
		t.Fatalf("leave: %s %s", m.T, m.P)
	}
	waitFor(t, 5*time.Second, "bot wins", func() bool { s := bot2.snapshot(); return s != nil && s.Status == "finished" })
	if res := bot2.snapshot().Result; res == nil || res.WinnerSeat != bot2.seat() || res.Payout != 2*ludoFee {
		t.Fatalf("result %+v", res)
	}
	waitFor(t, 5*time.Second, "payout to the bot", func() bool { return e.botCoins(t, bot2ID) == botStart+ludoFee })
	if got := e.coins(human2.Token); got != welcomeCo-ludoFee {
		t.Fatalf("person who lost: %d", got)
	}
	e.assertBotNotAccount(t, botID)
	e.assertBotNotAccount(t, bot2ID)
}

// Practice stays free for the person and the bots; the bot's wallet exists
// from its first seating.
func TestPracticeStaysFreeWithBotWallets(t *testing.T) {
	e := newEnv(t, envOpts{dice: rooms.NewSeededDice(42)})
	human := e.guest()
	hc, _, bots := e.practiceWithBots(t, human, []string{uniqueName("Isha")})
	botID := e.botIDOf(t, bots[0].UID)
	if s := hc.snapshot(); s.EntryFee != 0 || s.Pot != 0 {
		t.Fatalf("practice: entryFee %d pot %d", s.EntryFee, s.Pot)
	}
	all := []*client{hc}
	for _, c := range e.botClients {
		all = append(all, c)
	}
	playAll(t, all)
	if res := hc.snapshot().Result; res == nil || res.Payout != 0 {
		t.Fatalf("practice result %+v", res)
	}
	time.Sleep(300 * time.Millisecond) // nothing is scheduled to settle
	if got := e.coins(human.Token); got != welcomeCo {
		t.Fatalf("practice changed the person's coins: %d", got)
	}
	if coins, _, isBot := e.botWallet(t, botID); coins != botStart || !isBot {
		t.Fatalf("practice changed the bot's coins: %d bot=%v", coins, isBot)
	}
	e.assertBotNotAccount(t, botID)
}

// privateBotRoom creates a private Ludo room whose host adds n bots, and
// waits until everyone is seated and connected.
func (e *env) privateBotRoom(t *testing.T, ctl string, names []string) (account, *client, []uuid.UUID) {
	t.Helper()
	host := e.guest()
	hc := e.mustDial("host-"+names[0], host)
	if m := hc.call("room.create", map[string]any{"game": "ludo", "variant": "quick", "capacity": len(names) + 1}); m.T != "room.updated" {
		t.Fatalf("room.create: %s %s", m.T, m.P)
	}
	waitFor(t, 3*time.Second, "private lobby", func() bool { return hc.snapshot() != nil && hc.snapshot().Code != "" })
	roomID := hc.snapshot().ID
	if m := hc.call("room.allow_bots", map[string]any{"roomId": roomID, "allow": true}); m.T != "ack" {
		t.Fatalf("allow_bots: %s %s", m.T, m.P)
	}
	for range names {
		if m := hc.call("room.add_bot", map[string]any{"roomId": roomID}); m.T != "ack" {
			t.Fatalf("add_bot: %s %s", m.T, m.P)
		}
	}
	bots := e.spawnNamedBots(t, ctl, names)
	waitFor(t, 10*time.Second, "bots seated and connected", func() bool {
		s := hc.snapshot()
		if s == nil || len(s.Players) != len(names)+1 || s.PendingBots != 0 {
			return false
		}
		for _, p := range s.Players {
			if !p.Connected {
				return false
			}
		}
		return true
	})
	var ids []uuid.UUID
	for _, b := range bots {
		ids = append(ids, botUserID(t, b.acct))
	}
	return host, hc, ids
}

// Private rooms charge the bots the host added like any seat. A bot under
// 1 lakh after a settlement is recharged to 1 crore; before its next match a
// bot above 10 crore is reset to 1 crore and one under 1 lakh recharged.
func TestBotWalletRechargeAndReset(t *testing.T) {
	e := newEnv(t, envOpts{dice: rooms.NewSeededDice(43)})
	ctl := e.botController(t)
	metric := func(series string) float64 { return e.metricValue(series) }

	// 1. After settlement: the bot pays from 1.5 lakh down to 50,000, loses,
	// and is recharged to 1 crore once the payout is made.
	host, hc, ids := e.privateBotRoom(t, ctl, []string{uniqueName("Ravi")})
	bot := ids[0]
	if c := e.botCoins(t, bot); c != botStart {
		t.Fatalf("new bot wallet: %d", c)
	}
	e.setBotCoins(t, bot, 150_000)
	recharges, minted := metric("bot_wallet_recharges_total"), metric(`bot_coins_minted_total{reason="recharge"}`)
	if m := hc.call("game.start", map[string]any{"roomId": hc.snapshot().ID}); m.T != "ack" {
		t.Fatalf("start: %s %s", m.T, m.P)
	}
	waitFor(t, 5*time.Second, "private game", func() bool { return hc.snapshot().Status == "playing" })
	if s := hc.snapshot(); s.Pot != 2*ludoFee || s.EntryFee != ludoFee {
		t.Fatalf("private room with a bot: entryFee %d pot %d", s.EntryFee, s.Pot)
	}
	if got := e.coins(host.Token); got != welcomeCo-ludoFee {
		t.Fatalf("host after the fee: %d", got)
	}
	if got := e.botCoins(t, bot); got != 50_000 {
		t.Fatalf("bot after the fee: %d (no recharge expected at 1.5 lakh)", got)
	}
	var botUID string
	for _, c := range e.botClients {
		if botUserID(t, c.acct) == bot {
			botUID = c.acct.UID
		}
	}
	if r := e.do("DELETE", "/api/v1/bot/sessions/"+botUID, ctl, nil); r.Status != 204 {
		t.Fatalf("end bot session: %d %s", r.Status, r.Raw)
	}
	waitFor(t, 5*time.Second, "host paid", func() bool { return e.coins(host.Token) == welcomeCo+ludoFee })
	waitFor(t, 5*time.Second, "bot recharged after settlement", func() bool { return e.botCoins(t, bot) == botStart })
	if d := metric("bot_wallet_recharges_total") - recharges; d != 1 {
		t.Fatalf("recharges counted: %v", d)
	}
	if d := metric(`bot_coins_minted_total{reason="recharge"}`) - minted; d != botStart-50_000 {
		t.Fatalf("minted by the recharge: %v", d)
	}

	// 2. Before the next match: a rich bot is reset, a poor one recharged,
	// then both pay the fee.
	host2, h2, ids2 := e.privateBotRoom(t, ctl, []string{uniqueName("Noor"), uniqueName("Omar")})
	rich, poor := ids2[0], ids2[1]
	e.setBotCoins(t, rich, 150_000_000)
	e.setBotCoins(t, poor, 40_000)
	resets, removed := metric("bot_wallet_resets_total"), metric(`bot_coins_removed_total{reason="reset"}`)
	recharges = metric("bot_wallet_recharges_total")
	if m := h2.call("game.start", map[string]any{"roomId": h2.snapshot().ID}); m.T != "ack" {
		t.Fatalf("start 2: %s %s", m.T, m.P)
	}
	waitFor(t, 5*time.Second, "second private game", func() bool { return h2.snapshot().Status == "playing" })
	if s := h2.snapshot(); s.Pot != 3*ludoFee {
		t.Fatalf("pot %d, want %d", s.Pot, 3*ludoFee)
	}
	if got := e.coins(host2.Token); got != welcomeCo-ludoFee {
		t.Fatalf("host 2 after the fee: %d", got)
	}
	for _, id := range []uuid.UUID{rich, poor} {
		if got := e.botCoins(t, id); got != botStart-ludoFee {
			t.Fatalf("bot %s before its match: %d, want %d", id, got, botStart-ludoFee)
		}
	}
	if d := metric("bot_wallet_resets_total") - resets; d != 1 {
		t.Fatalf("resets counted: %v", d)
	}
	if d := metric(`bot_coins_removed_total{reason="reset"}`) - removed; d != 150_000_000-botStart {
		t.Fatalf("removed by the reset: %v", d)
	}
	if d := metric("bot_wallet_recharges_total") - recharges; d != 1 {
		t.Fatalf("recharges counted before the match: %v", d)
	}
	for _, id := range append(ids, ids2...) {
		e.assertBotNotAccount(t, id)
	}
}
