package chatter

import (
	"bufio"
	"math/rand/v2"
	"os"
	"slices"
	"strings"
	"testing"
)

// Every Store emote a trigger may use exists in the backend catalogue
// (backend/config/emotes.tsv), so a persona that owns it can send it.
func TestStoreEmotesExistInTheCatalogue(t *testing.T) {
	f, err := os.Open("../../../backend/config/emotes.tsv")
	if err != nil {
		t.Skipf("backend catalogue not available: %v", err)
	}
	defer f.Close()
	ids := map[string]bool{}
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		id, _, _ := strings.Cut(sc.Text(), "\t")
		ids[id] = true
	}
	n := 0
	for trig, list := range emotes {
		for _, id := range list {
			if strings.HasPrefix(id, "em_") {
				n++
				if !ids[id] {
					t.Errorf("%s: %s is not a Store emote", trig, id)
				}
			}
		}
	}
	if n == 0 {
		t.Fatal("no Store emotes mapped")
	}
}

// A persona that owns Store emotes uses those that fit the moment, never
// others.
func TestDecideUsesOwnedStoreEmotes(t *testing.T) {
	owned := []string{"em_party", "em_angry", "em_bunny"} // em_bunny fits no trigger
	for i := 0; i < 100; i++ {
		s := settings(1)
		s.EmoteShare = 1
		for trig, want := range map[Trigger]string{Win: "em_party", Captured: "em_angry"} {
			var st State
			m, ok := Decide(s, &st, trig, "m", owned, t0, &fixedRand{r: rand.New(rand.NewPCG(uint64(i), 3))})
			if !ok || m.Kind != KindEmote || m.ID != want {
				t.Fatalf("%s: %+v ok=%v, want %s", trig, m, ok, want)
			}
		}
		var st State
		if m, ok := Decide(s, &st, GameStart, "m", owned, t0, &fixedRand{r: rand.New(rand.NewPCG(uint64(i), 4))}); !ok ||
			m.Kind != KindQuick || slices.Contains(owned, m.ID) {
			t.Fatalf("game start without a fitting emote: %+v ok=%v", m, ok)
		}
	}
}
