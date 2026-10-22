package rooms

import (
	"bytes"
	"compress/flate"
	"fmt"
	"math/rand/v2"
	"os"
	"sort"
	"strings"
	"testing"
	"time"

	"ludoarena/internal/game/ludo"
	snakes "ludoarena/internal/game/snakes_ladders"
	"ludoarena/internal/protocol"
)

// samplePayloads plays real games with the real engines and captures the
// exact protocol messages the server would send: deltas (dice, move, turn)
// and full snapshots, for 2- and 4-player rooms.
func samplePayloads(players int, game string, seed uint64) (deltas, snaps [][]byte) {
	rng := rand.New(rand.NewPCG(seed, seed))
	r := &Room{ID: "r_3kq81zxw5m2", Game: game, Variant: "classic", Mode: ModePublic, Capacity: players,
		Status: StatusPlaying, HostSeat: -1, EntryFee: 1000, Pot: int64(players) * 1000, Round: 1}
	names := []string{"Asha", "Rohan", "Siti", "Yusuf"}
	for i := 0; i < players; i++ {
		r.Players = append(r.Players, Player{UserID: fmt.Sprintf("00000000-0000-4000-8000-00000000000%d", i),
			UID: fmt.Sprintf("u_k3m9x2p7q%dzt", i), Name: names[i], Avatar: i * 3, Level: 4 + i, Title: "title_rookie",
			Cosmetics: map[string]string{"dice": "dice_classic", "token": "token_gem", "frame": "frame_bronze",
				"trail": "trail_none", "victory": "victory_confetti"}, Connected: true})
	}
	if game == GameLudo {
		r.Ludo, _ = ludo.New(players, ludo.Classic)
	} else {
		r.Snakes, _ = snakes.New(players)
	}
	m := &mutation{r: r, s: &Service{}}
	deadline := time.Now().UnixMilli()
	for steps := 0; steps < 400; steps++ {
		if r.Ludo != nil && r.Ludo.Phase == ludo.PhaseFinished || r.Snakes != nil && r.Snakes.Phase == snakes.PhaseFinished {
			break
		}
		seat, seq, _, _, _, _ := r.turnInfo()
		v := rng.IntN(6) + 1
		if r.Ludo != nil {
			res, err := r.Ludo.Roll(seat, v)
			if err != nil {
				break
			}
			deltas = append(deltas, protocol.Encode(protocol.TDiceResult, "", diceResultP{RoomID: r.ID, V: r.V + 1,
				H: r.Ludo.Hash(), Seat: seat, Value: v, TurnSeq: res.TurnSeq, Phase: string(res.Phase),
				Deadline: deadline, Legal: res.Legal, SixStreak: res.SixStreak}))
			if len(res.Legal) > 0 {
				mv, _ := r.Ludo.Move(seat, res.Legal[rng.IntN(len(res.Legal))])
				deltas = append(deltas, protocol.Encode(protocol.TMoveApplied, "", moveAppliedP{RoomID: r.ID, V: r.V + 2,
					H: r.Ludo.HashAt(seq, seat), Seat: seat, Token: mv.Token, From: mv.From, To: mv.To, Captures: []tokenRef{}}))
			}
		} else {
			res, err := r.Snakes.Roll(seat, v)
			if err != nil {
				break
			}
			deltas = append(deltas, protocol.Encode(protocol.TDiceResult, "", diceResultP{RoomID: r.ID, V: r.V + 1,
				H: r.Snakes.Hash(), Seat: seat, Value: v, TurnSeq: seq, Phase: PhaseAwaitingRoll, Deadline: deadline, Legal: []int{}}))
			deltas = append(deltas, protocol.Encode(protocol.TMoveApplied, "", moveAppliedP{RoomID: r.ID, V: r.V + 2,
				H: r.Snakes.Hash(), Seat: seat, From: res.From, To: res.To, Captures: []tokenRef{}}))
		}
		r.V += 3
		s2, seq2, ph, _, _, six := r.turnInfo()
		deltas = append(deltas, protocol.Encode(protocol.TTurnChanged, "", turnChangedP{RoomID: r.ID, V: r.V,
			H: r.hash(), Seat: s2, TurnSeq: seq2, Phase: ph, Deadline: deadline, SixStreak: six}))
		if steps%10 == 0 {
			snaps = append(snaps, protocol.Encode(protocol.TGameState, "", map[string]any{"room": r.View()}))
		}
	}
	_ = m
	return deltas, snaps
}

var writers = map[int]*flate.Writer{}

// deflate compresses one message the way permessage-deflate without context
// takeover does: a reset (pooled) writer, sync flush, 4-byte tail removed.
func deflate(level int, msg []byte) int {
	var buf bytes.Buffer
	w := writers[level]
	if w == nil {
		w, _ = flate.NewWriter(&buf, level)
		writers[level] = w
	} else {
		w.Reset(&buf)
	}
	_, _ = w.Write(msg)
	_ = w.Flush()
	return buf.Len() - 4
}

// deflateStream simulates context takeover: one writer for a whole sequence.
func deflateStream(level int, msgs [][]byte) int {
	var buf bytes.Buffer
	w, _ := flate.NewWriter(&buf, level)
	total := 0
	for _, m := range msgs {
		before := buf.Len()
		_, _ = w.Write(m)
		_ = w.Flush()
		total += buf.Len() - before - 4
	}
	return total
}

func stats(sizes []int) (avg float64, p50 int) {
	s := append([]int(nil), sizes...)
	sort.Ints(s)
	sum := 0
	for _, v := range s {
		sum += v
	}
	return float64(sum) / float64(len(s)), s[len(s)/2]
}

// TestCompressionReport prints measured payload sizes, compressed sizes and
// compression CPU cost per message for the real protocol messages. Run with
// COMPRESSION_REPORT=1 go test -run TestCompressionReport -v ./internal/rooms/
func TestCompressionReport(t *testing.T) {
	if os.Getenv("COMPRESSION_REPORT") == "" {
		t.Skip("set COMPRESSION_REPORT=1 to print the report")
	}
	var b strings.Builder
	fmt.Fprintf(&b, "| sample | messages | avg bytes | p50 | L1 (BestSpeed) avg | L1 µs/msg | L6 avg | L6 µs/msg | L9 avg | context-takeover L1 avg |\n|---|---|---|---|---|---|---|---|---|---|\n")
	for _, tc := range []struct {
		name    string
		game    string
		players int
	}{{"ludo 2p", GameLudo, 2}, {"ludo 4p", GameLudo, 4}, {"snakes 4p", GameSnakes, 4}} {
		deltas, snaps := samplePayloads(tc.players, tc.game, 7)
		for _, kind := range []struct {
			label string
			msgs  [][]byte
		}{{"deltas", deltas}, {"snapshots", snaps}} {
			var raw, l1, l6, l9 []int
			for _, m := range kind.msgs {
				raw = append(raw, len(m))
				l1 = append(l1, deflate(flate.BestSpeed, m))
				l6 = append(l6, deflate(flate.DefaultCompression, m))
				l9 = append(l9, deflate(flate.BestCompression, m))
			}
			timePer := func(level int) float64 {
				start := time.Now()
				for i := 0; i < 20; i++ {
					for _, m := range kind.msgs {
						deflate(level, m)
					}
				}
				return float64(time.Since(start).Microseconds()) / float64(20*len(kind.msgs))
			}
			avg, p50 := stats(raw)
			a1, _ := stats(l1)
			a6, _ := stats(l6)
			a9, _ := stats(l9)
			ct := float64(deflateStream(flate.BestSpeed, kind.msgs)) / float64(len(kind.msgs))
			fmt.Fprintf(&b, "| %s %s | %d | %.0f | %d | %.0f (%.0f%%) | %.1f | %.0f | %.1f | %.0f | %.0f (%.0f%%) |\n",
				tc.name, kind.label, len(kind.msgs), avg, p50, a1, 100*a1/avg, timePer(flate.BestSpeed),
				a6, timePer(flate.DefaultCompression), a9, ct, 100*ct/avg)
		}
	}
	t.Log("\n" + b.String())
}

func BenchmarkDeflateSnapshot(b *testing.B) {
	_, snaps := samplePayloads(4, GameLudo, 3)
	for _, level := range []int{flate.BestSpeed, flate.DefaultCompression} {
		b.Run(fmt.Sprintf("level%d", level), func(b *testing.B) {
			for i := 0; i < b.N; i++ {
				deflate(level, snaps[i%len(snaps)])
			}
		})
	}
}
