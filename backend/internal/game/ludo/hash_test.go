package ludo

import (
	"encoding/json"
	"hash/fnv"
	"reflect"
	"testing"

	"ludoroyale/internal/game"
)

func TestHashVectors(t *testing.T) {
	vectors := []struct {
		s string
		h uint32
	}{
		{"L|7|1|-1,-1,5,56;0,-1,-1,-1", 2902942580},
		{"S|12|0|34,0,99", 1234224186},
		{"L|0|0|-1,-1,-1,-1;-1,-1,-1,-1", 638091788},
		{"L|3|1|-1,12;56,-1", 224748060}, // Quick Ludo vector (game-rules.md)
	}
	for _, v := range vectors {
		if got := game.FNV1a32(v.s); got != v.h {
			t.Errorf("FNV1a32(%q) = %d, want %d", v.s, got, v.h)
		}
	}
	for _, s := range []string{"", "a", "L|", "hello world", "\xff\x00\x80"} {
		h := fnv.New32a()
		h.Write([]byte(s))
		if got := game.FNV1a32(s); got != h.Sum32() {
			t.Errorf("FNV1a32(%q) = %d, stdlib %d", s, got, h.Sum32())
		}
	}
}

func TestCanonicalString(t *testing.T) {
	t.Run("documented example", func(t *testing.T) {
		s := &State{
			Variant: Classic,
			Players: []Player{
				{Color: Red, Tokens: []int{-1, -1, 5, 56}},
				{Color: Yellow, Tokens: []int{0, -1, -1, -1}},
			},
			Turn:    1,
			Phase:   PhaseAwaitingRoll,
			Winner:  -1,
			TurnSeq: 7,
		}
		const want = "L|7|1|-1,-1,5,56;0,-1,-1,-1"
		if got := s.CanonicalString(); got != want {
			t.Fatalf("CanonicalString = %q, want %q", got, want)
		}
		if s.Hash() != 2902942580 {
			t.Fatalf("Hash = %d, want 2902942580", s.Hash())
		}
	})
	t.Run("new two-player classic game", func(t *testing.T) {
		s := mustNew(t, 2, Classic)
		if got := s.CanonicalString(); got != "L|0|0|-1,-1,-1,-1;-1,-1,-1,-1" {
			t.Fatalf("CanonicalString = %q", got)
		}
		if s.Hash() != 638091788 {
			t.Fatalf("Hash = %d, want 638091788", s.Hash())
		}
	})
	t.Run("quick lists two tokens per seat", func(t *testing.T) {
		s := setup(t, Quick, []int{-1, 12}, []int{56, -1})
		s.Turn, s.TurnSeq = 1, 3
		if got := s.CanonicalString(); got != "L|3|1|-1,12;56,-1" {
			t.Fatalf("CanonicalString = %q", got)
		}
		if s.Hash() != 224748060 {
			t.Fatalf("Hash = %d", s.Hash())
		}
	})
	t.Run("HashAt overrides turnSeq and seat only", func(t *testing.T) {
		s := setup(t, Classic, []int{-1, -1, 5, 56}, []int{0, -1, -1, -1})
		if got := s.CanonicalStringAt(7, 1); got != "L|7|1|-1,-1,5,56;0,-1,-1,-1" {
			t.Fatalf("CanonicalStringAt = %q", got)
		}
		if s.HashAt(7, 1) != 2902942580 || s.HashAt(s.TurnSeq, s.Turn) != s.Hash() {
			t.Fatal("HashAt mismatch")
		}
	})
	t.Run("finished state uses the winner's seat", func(t *testing.T) {
		s := setup(t, Quick, []int{56, 55}, []int{3, -1})
		mustRoll(t, s, 0, 1)
		mustMove(t, s, 0, 1)
		if got := s.CanonicalString(); got != "L|2|0|56,56;3,-1" {
			t.Fatalf("CanonicalString = %q", got)
		}
	})
}

func TestJSONRoundTrip(t *testing.T) {
	states := map[string]*State{}

	mid := setup(t, Classic, []int{-1, -1, 10, 20}, []int{5, -1, -1, -1}, []int{30, 56, -1, -1})
	mid.Forfeit(1)
	mustRoll(t, mid, 0, 6)
	states["mid-game classic"] = mid

	fin := setup(t, Quick, []int{56, 55}, []int{3, -1})
	mustRoll(t, fin, 0, 1)
	mustMove(t, fin, 0, 1)
	states["finished quick"] = fin

	states["new"] = mustNew(t, 4, Classic)

	for name, s := range states {
		t.Run(name, func(t *testing.T) {
			data, err := json.Marshal(s)
			if err != nil {
				t.Fatal(err)
			}
			var back State
			if err := json.Unmarshal(data, &back); err != nil {
				t.Fatal(err)
			}
			if !reflect.DeepEqual(s, &back) {
				t.Fatalf("round trip mismatch:\n%+v\n%+v", s, &back)
			}
			if back.Hash() != s.Hash() {
				t.Fatal("hash changed across round trip")
			}
			var keys map[string]json.RawMessage
			if err := json.Unmarshal(data, &keys); err != nil {
				t.Fatal(err)
			}
			for _, k := range []string{"variant", "players", "turn", "phase", "dice", "sixStreak", "legal", "winner", "turnSeq", "placements", "forfeitOrder"} {
				if _, ok := keys[k]; !ok {
					t.Errorf("missing JSON key %q in %s", k, data)
				}
			}
			var players []map[string]json.RawMessage
			if err := json.Unmarshal(keys["players"], &players); err != nil {
				t.Fatal(err)
			}
			for _, k := range []string{"color", "tokens", "forfeited"} {
				if _, ok := players[0][k]; !ok {
					t.Errorf("missing player JSON key %q", k)
				}
			}
			if string(keys["legal"]) == "null" || string(keys["placements"]) == "null" {
				t.Errorf("slices must encode as [] not null: %s", data)
			}
		})
	}
}
