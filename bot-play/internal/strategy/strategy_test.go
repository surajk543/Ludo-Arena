package strategy

import (
	"testing"
	"time"

	"ludoarena/botplay/internal/config"
	"ludoarena/botplay/internal/connection"
	"ludoarena/botplay/internal/profiles"
)

func TestThinkDelayClampAndDeadlineCap(t *testing.T) {
	p := &profiles.Profile{ThinkTime: profiles.ThinkTime{MinMS: 100, MaxMS: 9000}}
	g := config.ThinkTimeConfig{MinMS: 300, MaxMS: 2000, Randomize: true}
	lo, hi := ThinkRange(p, g, nil)
	if lo != 300*time.Millisecond || hi != 2*time.Second {
		t.Fatalf("clamp: %v %v", lo, hi)
	}
	s := New(1)
	for i := 0; i < 200; i++ {
		d := s.ThinkDelay(p, g, nil, time.Hour, true)
		if d < lo || d > hi {
			t.Fatalf("delay %v outside [%v,%v]", d, lo, hi)
		}
		// Never more than 40% of the remaining time.
		if d := s.ThinkDelay(p, g, nil, time.Second, true); d > 400*time.Millisecond {
			t.Fatalf("delay %v exceeds 40%% of 1s", d)
		}
	}
	if d := s.ThinkDelay(p, g, nil, -time.Second, true); d != 0 {
		t.Fatalf("past deadline must act immediately, got %v", d)
	}
	g.Randomize = false
	if d := s.ThinkDelay(p, g, nil, time.Hour, true); d != 1150*time.Millisecond {
		t.Fatalf("midpoint: %v", d)
	}
	ov := &config.RangeMS{Min: 5, Max: 5}
	if d := s.ThinkDelay(p, g, ov, time.Hour, true); d != 5*time.Millisecond {
		t.Fatalf("override: %v", d)
	}
}

func TestChooseUsesServerLegalOnly(t *testing.T) {
	room := &connection.Room{Game: "ludo",
		Players: []connection.Player{{Seat: 0, Color: "red"}, {Seat: 1, Color: "yellow"}},
		Turn:    connection.Turn{Seat: 0, Dice: 4, Legal: []int{0, 1}},
		Board:   connection.Board{Tokens: [][]int{{10, 30, -1, -1}, {40, -1, -1, -1}}}}
	p := &profiles.Profile{Weights: profiles.Weights{CaptureOpponent: 50, ProgressTowardHome: 1}}
	tok, cands, ok := New(3).ChooseLudoMove(room, 0, p)
	if !ok || tok != 0 || len(cands) != 2 {
		t.Fatalf("expected capture with token 0, got %d %+v", tok, cands)
	}
	room.Turn.Legal = []int{1}
	if tok, _, _ := New(3).ChooseLudoMove(room, 0, p); tok != 1 {
		t.Fatal("single legal token must be used as-is")
	}
	room.Turn.Legal = nil
	if _, _, ok := New(3).ChooseLudoMove(room, 0, p); ok {
		t.Fatal("no legal tokens")
	}
}
