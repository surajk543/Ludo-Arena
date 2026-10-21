package chatter

import (
	"math/rand/v2"
	"slices"
	"testing"
	"time"

	"ludoroyale/botplay/internal/config"
)

// fixedRand returns scripted Float64 values (cycled) and IntN from a seeded
// generator.
type fixedRand struct {
	f []float64
	i int
	r *rand.Rand
}

func (f *fixedRand) Float64() float64 {
	if len(f.f) == 0 {
		return f.r.Float64()
	}
	v := f.f[f.i%len(f.f)]
	f.i++
	return v
}

func (f *fixedRand) IntN(n int) int { return f.r.IntN(n) }

func seeded(fs ...float64) *fixedRand {
	return &fixedRand{f: fs, r: rand.New(rand.NewPCG(1, 2))}
}

func settings(p float64) Settings {
	s := FromConfig(config.Default().Bots.Chat, 1)
	for _, t := range Triggers {
		s.Probability[t] = p
	}
	return s
}

var t0 = time.Date(2026, 10, 21, 12, 0, 0, 0, time.UTC)

func TestDecideProbability(t *testing.T) {
	all := []string{"emote_wave", "emote_thumbs", "emote_laugh", "emote_wow", "emote_crown"}
	cases := []struct {
		name      string
		p, chatty float64
		roll      float64
		enabled   bool
		maxPer    int
		match     string
		want      bool
	}{
		{name: "p=0 never", p: 0, chatty: 1, roll: 0, enabled: true, maxPer: 3, match: "r/1", want: false},
		{name: "p=1 always", p: 1, chatty: 1, roll: 0.999999, enabled: true, maxPer: 3, match: "r/1", want: true},
		{name: "roll below p", p: 0.3, chatty: 1, roll: 0.29, enabled: true, maxPer: 3, match: "r/1", want: true},
		{name: "roll at p", p: 0.3, chatty: 1, roll: 0.3, enabled: true, maxPer: 3, match: "r/1", want: false},
		{name: "chattiness 0 silences", p: 1, chatty: 0, roll: 0, enabled: true, maxPer: 3, match: "r/1", want: false},
		{name: "chattiness scales up", p: 0.2, chatty: 2, roll: 0.39, enabled: true, maxPer: 3, match: "r/1", want: true},
		{name: "disabled", p: 1, chatty: 1, roll: 0, enabled: false, maxPer: 3, match: "r/1", want: false},
		{name: "cap 0", p: 1, chatty: 1, roll: 0, enabled: true, maxPer: 0, match: "r/1", want: false},
		{name: "no match", p: 1, chatty: 1, roll: 0, enabled: true, maxPer: 3, match: "", want: false},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			for _, trig := range Triggers {
				s := settings(c.p)
				s.Chattiness, s.Enabled, s.MaxPerMatch = c.chatty, c.enabled, c.maxPer
				var st State
				_, ok := Decide(s, &st, trig, c.match, all, t0, seeded(c.roll, 0.1))
				if ok != c.want {
					t.Fatalf("%s: got %v want %v", trig, ok, c.want)
				}
			}
		})
	}
}

func TestDecideCapsAndInterval(t *testing.T) {
	s := settings(1)
	s.MaxPerMatch, s.MinInterval = 2, 8*time.Second
	s.DelayMin, s.DelayMax = time.Second, time.Second
	var st State
	r := seeded(0)
	step := func(at time.Duration, match string) bool {
		_, ok := Decide(s, &st, Win, match, nil, t0.Add(at), r)
		return ok
	}
	steps := []struct {
		at    time.Duration
		match string
		want  bool
	}{
		{0, "a/1", true},                 // first message (sent at +1 s)
		{5 * time.Second, "a/1", false},  // only 4 s after the planned send
		{9 * time.Second, "a/1", true},   // 8 s after: second message
		{30 * time.Second, "a/1", false}, // per-match cap reached
		{60 * time.Second, "a/2", true},  // a new round resets the cap
	}
	for i, x := range steps {
		if got := step(x.at, x.match); got != x.want {
			t.Fatalf("step %d (%v %s): got %v want %v", i, x.at, x.match, got, x.want)
		}
	}
	if st.Sent("a/2") != 1 || st.Sent("a/1") != 0 {
		t.Fatalf("sent counters: %d %d", st.Sent("a/2"), st.Sent("a/1"))
	}
}

func TestDecideNeverBelowServerInterval(t *testing.T) {
	s := settings(1)
	s.MaxPerMatch, s.MinInterval = 10, 0 // misconfigured: the 3 s floor still holds
	s.DelayMin, s.DelayMax = 0, 0
	var st State
	r := seeded(0)
	if _, ok := Decide(s, &st, Win, "m", nil, t0, r); !ok {
		t.Fatal("first")
	}
	if _, ok := Decide(s, &st, Win, "m", nil, t0.Add(2900*time.Millisecond), r); ok {
		t.Fatal("second message within 3 s")
	}
	if _, ok := Decide(s, &st, Win, "m", nil, t0.Add(3*time.Second), r); !ok {
		t.Fatal("third after 3 s")
	}
}

func TestDecideMessageChoice(t *testing.T) {
	cases := []struct {
		name     string
		trig     Trigger
		allowed  []string
		share    float64
		wantKind string // "" = no message
	}{
		{"emote share 1 uses an allowed emote", Win, []string{"emote_wave"}, 1, KindEmote},
		{"emote share 0 uses quick chat", Win, []string{"emote_wave"}, 0, KindQuick},
		{"no allowed emote falls back to quick chat", Win, nil, 1, KindQuick},
		{"unrelated emotes fall back to quick chat", Captured, []string{"emote_crown"}, 1, KindQuick},
		{"six without emotes says nothing", Six, nil, 1, ""},
		{"six with an emote", Six, []string{"emote_thumbs"}, 0, KindEmote},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			for i := 0; i < 50; i++ {
				s := settings(1)
				s.EmoteShare = c.share
				var st State
				m, ok := Decide(s, &st, c.trig, "m", c.allowed, t0, &fixedRand{r: rand.New(rand.NewPCG(uint64(i), 9))})
				if c.wantKind == "" {
					if ok {
						t.Fatalf("unexpected message %+v", m)
					}
					return
				}
				if !ok || m.Kind != c.wantKind {
					t.Fatalf("got %+v ok=%v, want kind %s", m, ok, c.wantKind)
				}
				if m.Kind == KindEmote && !slices.Contains(c.allowed, m.ID) {
					t.Fatalf("emote %s not in the allowed list %v", m.ID, c.allowed)
				}
				if m.Kind == KindQuick && (!slices.Contains(QuickChatIDs, m.ID) || slices.Contains(neverSay, m.ID)) {
					t.Fatalf("quick chat %s not allowed", m.ID)
				}
			}
		})
	}
}

// Bots never offer a rematch they will not vote for, whatever the trigger.
func TestNeverRematchOrAgain(t *testing.T) {
	r := rand.New(rand.NewPCG(3, 4))
	for i := 0; i < 2000; i++ {
		s := settings(1)
		s.EmoteShare = 0
		var st State
		trig := Triggers[r.IntN(len(Triggers))]
		m, ok := Decide(s, &st, trig, "m", nil, t0, &fixedRand{r: r})
		if ok && (m.ID == "rematch" || m.ID == "again") {
			t.Fatalf("%s: %s", trig, m.ID)
		}
	}
	for _, trig := range Triggers {
		for _, q := range Phrases(trig) {
			if !slices.Contains(QuickChatIDs, q) {
				t.Fatalf("%s: %q is not a server quick-chat id", trig, q)
			}
		}
	}
}

func TestDecideDelayRange(t *testing.T) {
	s := settings(1)
	s.DelayMin, s.DelayMax = 600*time.Millisecond, 2500*time.Millisecond
	r := rand.New(rand.NewPCG(5, 6))
	for i := 0; i < 500; i++ {
		var st State
		m, ok := Decide(s, &st, Loss, "m", nil, t0, &fixedRand{r: r})
		if !ok {
			t.Fatal("no message")
		}
		if m.Delay < s.DelayMin || m.Delay > s.DelayMax {
			t.Fatalf("delay %v outside [%v, %v]", m.Delay, s.DelayMin, s.DelayMax)
		}
	}
}

// With the default probabilities a bot chats rarely: across many simulated
// matches the average stays well under the cap.
func TestDefaultsAreSparing(t *testing.T) {
	s := FromConfig(config.Default().Bots.Chat, 1)
	r := rand.New(rand.NewPCG(7, 8))
	const matches = 2000
	total := 0
	for i := 0; i < matches; i++ {
		var st State
		now := t0
		match := "m"
		// A typical Ludo game for one bot: ~8 sixes, a few captures each way.
		events := []Trigger{GameStart}
		for j := 0; j < 8; j++ {
			events = append(events, Six)
		}
		for j := 0; j < 2; j++ {
			events = append(events, Capture, Captured, OtherCapture)
		}
		events = append(events, Loss)
		for _, e := range events {
			now = now.Add(20 * time.Second)
			if _, ok := Decide(s, &st, e, match, []string{"emote_wave", "emote_thumbs"}, now, &fixedRand{r: r}); ok {
				total++
			}
		}
		if st.Sent(match) > s.MaxPerMatch {
			t.Fatalf("cap exceeded: %d", st.Sent(match))
		}
	}
	if avg := float64(total) / matches; avg > 1.5 || avg < 0.3 {
		t.Fatalf("average %.2f messages per match", avg)
	}
}
