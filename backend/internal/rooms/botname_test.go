package rooms

import (
	"slices"
	"strings"
	"testing"
)

func TestBotNameCarriesNoLabel(t *testing.T) {
	cases := []struct{ in, want string }{
		{"Asha", "Asha"},
		{"  Rizky   Putra ", "Rizky Putra"},
		{"Bot Asha", "Asha"},
		{"bot asha", "asha"},
		{"BOT-Omar", "Omar"},
		{"Bot_Layla", "Layla"},
		{"Bot: Noor", "Noor"},
		{"Bot Bot Kavya", "Kavya"},
		{"Bot 0042", "0042"},
		{"Botan", "Botan"}, // a name that merely starts with "bot"
		{"Abbot", "Abbot"}, // "bot" elsewhere is kept
		{"Robot Rae", "Robot Rae"},
		{"Bot Abcdefghijklmnopqrstuvwxyz", "Abcdefghijklmnop"}, // sanitized to 20 runes first
	}
	for _, c := range cases {
		if got := botName(c.in, "seed"); got != c.want {
			t.Errorf("botName(%q) = %q, want %q", c.in, got, c.want)
		}
	}
	// Empty, whitespace-only and label-only names fall back to a neutral
	// first name (deterministic per seed), never "Bot".
	for _, in := range []string{"", "   ", "Bot", "bot", "Bot ", "Bot - ", "\u0000"} {
		got := botName(in, "assignment-1")
		if !slices.Contains(neutralBotNames, got) || got != botName(in, "assignment-1") {
			t.Errorf("botName(%q) = %q, want a stable neutral name", in, got)
		}
	}
	seen := map[string]bool{}
	for i := 0; i < 200; i++ {
		seen[botName("", strings.Repeat("x", i))] = true
	}
	if len(seen) < 5 {
		t.Fatalf("fallback names are not varied: %v", seen)
	}
	for _, n := range neutralBotNames {
		if strings.HasPrefix(strings.ToLower(n), "bot") || len([]rune(n)) > 20 {
			t.Fatalf("bad fallback name %q", n)
		}
	}
}
