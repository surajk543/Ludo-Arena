package rooms

import (
	"context"
	"errors"
	"strconv"
	"strings"
	"time"

	"github.com/redis/go-redis/v9"

	"ludoroyale/internal/gameevents"
	"ludoroyale/internal/metrics"
	"ludoroyale/internal/protocol"
	"ludoroyale/internal/wallet"
)

// RunScheduler processes due timers (turn deadlines, fill deadlines, lobby
// kicks, rematch windows, bot expiry, payouts, match recording). Entries live
// in the Redis ZSET "sched"; whichever instance ZREMs an entry first owns it,
// so timers survive restarts and run exactly once across instances. Every
// handler re-validates against current room state, so stale entries are
// harmless.
func (s *Service) RunScheduler(ctx context.Context, workers int) {
	jobs := make(chan string, 1024)
	for i := 0; i < workers; i++ {
		go func() {
			for member := range jobs {
				s.runJob(ctx, member)
			}
		}()
	}
	t := time.NewTicker(100 * time.Millisecond)
	defer t.Stop()
	defer close(jobs)
	for {
		select {
		case <-ctx.Done():
			return
		case <-t.C:
		}
		due, err := s.RDB.ZRangeByScore(ctx, schedKey, &redis.ZRangeBy{
			Min: "-inf", Max: strconv.FormatInt(s.nowMs(), 10), Count: 256}).Result()
		if err != nil {
			continue
		}
		for _, member := range due {
			n, err := s.RDB.ZRem(ctx, schedKey, member).Result()
			if err != nil || n == 0 {
				continue // another instance took it
			}
			select {
			case jobs <- member:
			case <-ctx.Done():
				return
			}
		}
	}
}

func (s *Service) runJob(ctx context.Context, member string) {
	parts := strings.SplitN(member, "|", 3)
	if len(parts) != 3 {
		return
	}
	kind, roomID, arg := parts[0], parts[1], parts[2]
	jctx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()
	var err error
	switch kind {
	case "turn":
		seq, _ := strconv.Atoi(arg)
		err = s.handleTurnTimeout(jctx, roomID, seq)
	case "fill":
		err = s.handleFill(jctx, roomID)
	case "lobbykick":
		err = s.handleLobbyKick(jctx, roomID, arg)
	case "rematch":
		round, _ := strconv.Atoi(arg)
		err = s.resolveRematch(jctx, roomID, round)
	case "practice":
		round, _ := strconv.Atoi(arg)
		err = s.handlePracticeDeadline(jctx, roomID, round)
	case "botexp":
		err = s.handleBotExpiry(jctx, roomID, arg)
	case "payout":
		round, _ := strconv.Atoi(arg)
		err = s.handlePayout(jctx, roomID, round)
	case "record":
		round, _ := strconv.Atoi(arg)
		err = s.handleRecord(jctx, roomID, round)
	}
	if err != nil && err != protocol.ErrRoomNotFound {
		s.Log.Warn("scheduled job failed", "kind", kind, "error", err.Error())
	}
}

// handlePayout credits the pot to the winner (a person's wallet or a bot's)
// at most once: a Redis settlement key is claimed before the PostgreSQL
// credit. If the process dies between the claim and the credit, the payout is
// NOT retried (it may be lost); it is never paid twice. See
// docs/architecture.md. Once paid, the bots of the round get the
// after-settlement rule (recharge below BOT_COINS_RECHARGE_BELOW).
func (s *Service) handlePayout(ctx context.Context, roomID string, round int) error {
	r, _, err := s.st.load(ctx, roomID)
	if err != nil {
		return err
	}
	if r.Round != round || r.Result == nil || r.Paid || r.Result.Payout <= 0 {
		return nil
	}
	winner := r.Players[r.Result.WinnerSeat]
	key := "settle:pay:" + roomID + ":" + strconv.Itoa(round)
	ok, err := s.RDB.SetNX(ctx, key, "claimed", 7*24*time.Hour).Result()
	if err != nil {
		return err
	}
	if !ok {
		return nil
	}
	w, err := s.Wallets.Credit(ctx, userUUID(winner.UserID), r.Result.Payout, 0)
	if errors.Is(err, wallet.ErrNotFound) {
		// The winner deleted their account before the payout: there is
		// nobody to pay, and retrying cannot help.
		s.RDB.Set(ctx, key, "account_gone", 7*24*time.Hour)
		s.Log.Warn("payout skipped: winner account no longer exists", "room", roomID)
		s.settleBots(ctx, r)
		return nil
	}
	if err != nil {
		// The credit did not happen: release the claim and retry later.
		s.RDB.Del(ctx, key)
		metrics.SettlementFailures.WithLabelValues("payout").Inc()
		attempt, _ := s.RDB.Incr(ctx, "settle:retry:"+roomID+":"+strconv.Itoa(round)).Result()
		s.RDB.Expire(ctx, "settle:retry:"+roomID+":"+strconv.Itoa(round), time.Hour)
		if attempt <= 10 {
			s.RDB.ZAdd(ctx, schedKey, redis.Z{Score: float64(s.nowMs() + attempt*5000),
				Member: "payout|" + roomID + "|" + strconv.Itoa(round)})
		}
		return err
	}
	s.RDB.Set(ctx, key, "paid", 7*24*time.Hour)
	_, _ = s.mutate(ctx, roomID, func(m *mutation) error {
		if m.r.Round != round {
			return errNoop
		}
		m.r.Paid = true
		m.write = true
		return nil
	})
	if !winner.Bot {
		s.notifyUser(ctx, winner.UserID, protocol.TWalletUpdated, map[string]any{
			"coins": w.Coins, "diamonds": w.Diamonds,
			"delta": map[string]int64{"coins": r.Result.Payout, "diamonds": 0}, "reason": "payout"})
	}
	s.settleBots(ctx, r)
	return nil
}

// settleBots applies the after-settlement rule to the wallets of the round's
// bots. A failure is only logged: the same rule runs again before the bot's
// next entry fee.
func (s *Service) settleBots(ctx context.Context, r *Room) {
	_, bots := seatIDs(r)
	if len(bots) == 0 || s.Wallets == nil {
		return
	}
	if err := s.Wallets.SettleBots(ctx, bots, s.Bots.Coins); err != nil {
		metrics.SettlementFailures.WithLabelValues("bot_recharge").Inc()
		s.Log.Warn("bot wallet settlement failed", "room", r.ID, "error", err.Error())
	}
}

// handleRecord emits the finished-match record to progression/missions. The
// recorder is idempotent per (MatchID, user), so retries are safe.
func (s *Service) handleRecord(ctx context.Context, roomID string, round int) error {
	if s.Recorder == nil {
		return nil
	}
	r, _, err := s.st.load(ctx, roomID)
	if err != nil {
		return err
	}
	if r.Round != round || r.Result == nil || r.LoadTest {
		return nil
	}
	rec := gameevents.MatchRecord{
		MatchID: r.ID + ":" + strconv.Itoa(r.Round), Game: r.Game, Variant: r.Variant, Mode: r.Mode,
		Reason: r.Result.Reason, HasBots: r.Bots() > 0,
		StartedAt: time.UnixMilli(r.StartedAt), FinishedAt: time.UnixMilli(s.nowMs()),
	}
	placement := map[int]int{}
	for i, seat := range r.Result.Placements {
		placement[seat] = i + 1
	}
	for i, p := range r.Players {
		rec.Players = append(rec.Players, gameevents.Participant{
			UserID: userUUID(p.UserID), UID: p.UID, Seat: i, Bot: p.Bot, Won: i == r.Result.WinnerSeat,
			Placement: placement[i], Forfeited: p.Forfeited, Actions: p.Actions,
		})
	}
	if err := s.Recorder.RecordMatch(ctx, rec); err != nil {
		attempt, _ := s.RDB.Incr(ctx, "record:retry:"+rec.MatchID).Result()
		s.RDB.Expire(ctx, "record:retry:"+rec.MatchID, time.Hour)
		if attempt <= 10 {
			s.RDB.ZAdd(ctx, schedKey, redis.Z{Score: float64(s.nowMs() + attempt*3000),
				Member: "record|" + roomID + "|" + strconv.Itoa(round)})
		}
		return err
	}
	return nil
}
