package apppolicy

import (
	"context"
	"encoding/json"
	"io"
	"log/slog"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

var quiet = slog.New(slog.NewTextHandler(io.Discard, nil))

func basePolicy() map[string]any {
	plat := func(min string, minB int, latest string, latestB int, store string) map[string]any {
		return map[string]any{
			"minimumSupportedVersion": min, "minimumSupportedBuild": minB,
			"latestVersion": latest, "latestBuild": latestB, "storeUrl": store,
			"forceUpdateTitle": "Update required", "forceUpdateMessage": map[string]string{"en": "Please update.", "hi": "कृपया अपडेट करें।"},
			"optionalUpdateTitle": "New version", "optionalUpdateMessage": "Better dice.",
			"optionalUpdateReminderHours": 24, "securityCritical": false,
			"maintenance": map[string]any{"enabled": false, "message": ""},
		}
	}
	return map[string]any{
		"configVersion": 7,
		"environment":   "production",
		"maintenance":   map[string]any{"enabled": false, "message": map[string]string{"en": "Down for maintenance", "ar": "صيانة"}, "windows": []any{}},
		"platforms": map[string]any{
			"android": plat("1.2.0", 120, "1.4.0", 140, "https://play.google.com/store/apps/details?id=com.ludoarena.app"),
			"ios":     plat("1.1.0", 0, "1.1.0", 0, "https://apps.apple.com/app/id1"),
		},
	}
}

func writePolicy(t *testing.T, dir string, p map[string]any) string {
	t.Helper()
	raw, err := json.Marshal(p)
	if err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(dir, "policy.json")
	if err := os.WriteFile(path, raw, 0o600); err != nil {
		t.Fatal(err)
	}
	return path
}

func newStore(t *testing.T, p map[string]any) (*Store, string) {
	t.Helper()
	dir := t.TempDir()
	path := writePolicy(t, dir, p)
	s, err := NewStore(path, filepath.Join(dir, "MAINTENANCE"), "production", quiet)
	if err != nil {
		t.Fatalf("NewStore: %v", err)
	}
	return s, dir
}

func client(t *testing.T, platform, version string, build string) Client {
	t.Helper()
	c, err := ParseClient(platform, version, build)
	if err != nil {
		t.Fatalf("ParseClient(%s,%s,%s): %v", platform, version, build, err)
	}
	return c
}

func TestVersionCompareIsNumeric(t *testing.T) {
	cases := []struct {
		a, b string
		want int
	}{
		{"1.10.0", "1.9.0", 1},
		{"1.9.0", "1.10.0", -1},
		{"1.2", "1.2.0", 0},
		{"2", "1.99.99", 1},
		{"1.0.0.1", "1.0.0", 1},
		{"0.0.1", "0.0.1", 0},
	}
	for _, c := range cases {
		a, _ := ParseVersion(c.a)
		b, _ := ParseVersion(c.b)
		if got := a.Compare(b); got != c.want {
			t.Errorf("%s vs %s = %d, want %d", c.a, c.b, got, c.want)
		}
	}
}

func TestParseVersionRejectsInvalid(t *testing.T) {
	for _, s := range []string{"", "1..0", "1.0.0-beta", "1.0.0+5", "v1.0", "1.2.3.4.5", "-1.0", " ", "1.a", "1234567.0"} {
		if _, err := ParseVersion(s); err == nil {
			t.Errorf("ParseVersion(%q) accepted invalid input", s)
		}
	}
}

func TestParseClientValidation(t *testing.T) {
	bad := [][3]string{{"windows", "1.0.0", "1"}, {"android", "x", "1"}, {"ios", "1.0.0", "-3"}, {"", "1.0.0", "1"}, {"android", "1.0.0", "12345678901"}}
	for _, b := range bad {
		if _, err := ParseClient(b[0], b[1], b[2]); err == nil {
			t.Errorf("ParseClient(%v) accepted invalid metadata", b)
		}
	}
	c := client(t, "ANDROID", "1.2.0", "")
	if c.Platform != Android || c.Build != 0 {
		t.Fatalf("unexpected client %+v", c)
	}
}

func TestModes(t *testing.T) {
	s, _ := newStore(t, basePolicy())
	cases := []struct {
		name, platform, version, build string
		want                           Mode
	}{
		{"equal to minimum", "android", "1.2.0", "120", ModeOptionalUpdate},
		{"below minimum version", "android", "1.0.0", "200", ModeForceUpdate},
		{"same version older build", "android", "1.2.0", "119", ModeForceUpdate},
		{"newer available but supported", "android", "1.3.0", "130", ModeOptionalUpdate},
		{"latest", "android", "1.4.0", "140", ModeNormal},
		{"ahead of latest", "android", "1.10.0", "1", ModeNormal},
		{"ios different policy", "ios", "1.1.0", "1", ModeNormal},
		{"ios below its own minimum", "ios", "1.0.9", "999", ModeForceUpdate},
		{"android version that ios would accept", "android", "1.1.0", "999", ModeForceUpdate},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			d := s.Evaluate(client(t, c.platform, c.version, c.build), "en")
			if d.Mode != c.want {
				t.Fatalf("mode = %s, want %s", d.Mode, c.want)
			}
			if d.Blocks() != (c.want == ModeForceUpdate || c.want == ModeMaintenance) {
				t.Fatalf("Blocks() inconsistent for %s", d.Mode)
			}
		})
	}
}

func TestStoreLinkSelectionAndLocalization(t *testing.T) {
	s, _ := newStore(t, basePolicy())
	a := s.Evaluate(client(t, "android", "1.0.0", "1"), "hi-IN")
	if !strings.HasPrefix(a.StoreURL, "https://play.google.com/") || !a.StoreAvailable {
		t.Fatalf("android store url = %q", a.StoreURL)
	}
	if a.Message != "कृपया अपडेट करें।" {
		t.Fatalf("hi message not resolved by language fallback: %q", a.Message)
	}
	i := s.Evaluate(client(t, "ios", "1.0.0", "1"), "ur")
	if !strings.HasPrefix(i.StoreURL, "https://apps.apple.com/") {
		t.Fatalf("ios store url = %q", i.StoreURL)
	}
	if i.Message != "Please update." {
		t.Fatalf("missing ur translation should fall back to English, got %q", i.Message)
	}
}

func TestEmptyStoreURLMeansUnavailable(t *testing.T) {
	p := basePolicy()
	p["platforms"].(map[string]any)["android"].(map[string]any)["storeUrl"] = ""
	s, _ := newStore(t, p)
	d := s.Evaluate(client(t, "android", "1.0.0", "1"), "en")
	if d.Mode != ModeForceUpdate || d.StoreAvailable || d.StoreURL != "" {
		t.Fatalf("got %+v", d)
	}
}

func TestValidationRejectsBadPolicies(t *testing.T) {
	mut := []struct {
		name string
		fn   func(p map[string]any)
	}{
		{"android url on ios", func(p map[string]any) {
			p["platforms"].(map[string]any)["ios"].(map[string]any)["storeUrl"] = "https://play.google.com/store/apps/details?id=x"
		}},
		{"ios url on android", func(p map[string]any) {
			p["platforms"].(map[string]any)["android"].(map[string]any)["storeUrl"] = "https://apps.apple.com/app/id1"
		}},
		{"http url", func(p map[string]any) {
			p["platforms"].(map[string]any)["android"].(map[string]any)["storeUrl"] = "http://play.google.com/x"
		}},
		{"latest below minimum", func(p map[string]any) {
			p["platforms"].(map[string]any)["android"].(map[string]any)["latestVersion"] = "1.1.0"
		}},
		{"missing ios", func(p map[string]any) { delete(p["platforms"].(map[string]any), "ios") }},
		{"unknown platform", func(p map[string]any) { p["platforms"].(map[string]any)["web"] = map[string]any{} }},
		{"wrong environment", func(p map[string]any) { p["environment"] = "preproduction" }},
		{"bad version", func(p map[string]any) {
			p["platforms"].(map[string]any)["android"].(map[string]any)["minimumSupportedVersion"] = "1.x"
		}},
		{"window end before start", func(p map[string]any) {
			p["maintenance"].(map[string]any)["windows"] = []any{map[string]any{"startsAtUtc": "2026-11-02T02:00:00Z", "endsAtUtc": "2026-11-02T01:00:00Z"}}
		}},
		{"unknown field", func(p map[string]any) { p["maintenanceMode"] = true }},
		{"config version zero", func(p map[string]any) { p["configVersion"] = 0 }},
	}
	for _, m := range mut {
		t.Run(m.name, func(t *testing.T) {
			p := basePolicy()
			m.fn(p)
			raw, _ := json.Marshal(p)
			if _, err := Parse(raw, "production"); err == nil {
				t.Fatal("invalid policy accepted")
			}
		})
	}
}

func TestMaintenanceSwitchesAndPrecedence(t *testing.T) {
	p := basePolicy()
	p["maintenance"].(map[string]any)["enabled"] = true
	s, dir := newStore(t, p)
	d := s.Evaluate(client(t, "android", "1.0.0", "1"), "ar")
	if d.Mode != ModeMaintenance || d.Maintenance.Message != "صيانة" {
		t.Fatalf("maintenance should win over force update: %+v", d)
	}

	// Security-critical update overrides maintenance for clients below minimum.
	p["platforms"].(map[string]any)["android"].(map[string]any)["securityCritical"] = true
	writePolicy(t, dir, p)
	if err := s.Reload(); err != nil {
		t.Fatal(err)
	}
	if d := s.Evaluate(client(t, "android", "1.0.0", "1"), "en"); d.Mode != ModeForceUpdate {
		t.Fatalf("security-critical: mode=%s", d.Mode)
	}
	if d := s.Evaluate(client(t, "android", "1.4.0", "140"), "en"); d.Mode != ModeMaintenance {
		t.Fatalf("supported client during maintenance: mode=%s", d.Mode)
	}
}

func TestMaintenanceWindowSchedule(t *testing.T) {
	p := basePolicy()
	p["maintenance"].(map[string]any)["windows"] = []any{map[string]any{
		"startsAtUtc": "2026-11-02T01:00:00Z", "endsAtUtc": "2026-11-02T02:00:00Z",
		"message": "Scheduled maintenance",
	}}
	s, _ := newStore(t, p)
	at := func(ts string) Decision {
		tm, _ := time.Parse(time.RFC3339, ts)
		s.SetClock(func() time.Time { return tm })
		return s.Evaluate(client(t, "ios", "1.1.0", "1"), "en")
	}
	if d := at("2026-11-01T20:00:00Z"); d.Mode != ModeNormal || d.Maintenance.Enabled || d.Maintenance.StartsAtUTC == nil {
		t.Fatalf("upcoming window should be announced but not block: %+v", d)
	}
	if d := at("2026-11-02T01:30:00Z"); d.Mode != ModeMaintenance || d.Maintenance.ScheduledEndUTC == nil || d.Maintenance.Message != "Scheduled maintenance" {
		t.Fatalf("inside window: %+v", d)
	}
	if d := at("2026-11-02T02:00:00Z"); d.Mode != ModeNormal {
		t.Fatalf("window end must restore service automatically: %+v", d.Mode)
	}
	if s.GlobalMaintenanceActive() {
		t.Fatal("global maintenance should be inactive after the window")
	}
}

func TestFlagFileEmergencyMaintenance(t *testing.T) {
	s, dir := newStore(t, basePolicy())
	flag := filepath.Join(dir, "MAINTENANCE")
	if err := os.WriteFile(flag, []byte("Emergency fix in progress\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	_ = s.Reload()
	d := s.Evaluate(client(t, "android", "1.4.0", "140"), "en")
	if d.Mode != ModeMaintenance || d.Maintenance.Message != "Emergency fix in progress" || !s.GlobalMaintenanceActive() {
		t.Fatalf("flag maintenance: %+v", d)
	}
	if err := os.Remove(flag); err != nil {
		t.Fatal(err)
	}
	_ = s.Reload()
	if d := s.Evaluate(client(t, "android", "1.4.0", "140"), "en"); d.Mode != ModeNormal {
		t.Fatalf("flag removal should end maintenance: %s", d.Mode)
	}
}

func TestPlatformOnlyMaintenance(t *testing.T) {
	p := basePolicy()
	p["platforms"].(map[string]any)["ios"].(map[string]any)["maintenance"] = map[string]any{"enabled": true, "message": "iOS maintenance"}
	s, _ := newStore(t, p)
	if d := s.Evaluate(client(t, "ios", "1.1.0", "1"), "en"); d.Mode != ModeMaintenance || d.Maintenance.Message != "iOS maintenance" {
		t.Fatalf("ios: %+v", d)
	}
	if d := s.Evaluate(client(t, "android", "1.4.0", "140"), "en"); d.Mode != ModeNormal {
		t.Fatalf("android must be unaffected: %s", d.Mode)
	}
	if s.GlobalMaintenanceActive() {
		t.Fatal("platform maintenance is not global")
	}
}

func TestInvalidReloadKeepsPreviousPolicy(t *testing.T) {
	s, dir := newStore(t, basePolicy())
	if err := os.WriteFile(filepath.Join(dir, "policy.json"), []byte(`{"configVersion": 8, "environment": "production"`), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := s.Reload(); err == nil {
		t.Fatal("expected reload error for truncated JSON")
	}
	d := s.Evaluate(client(t, "android", "1.0.0", "1"), "en")
	if d.ConfigVersion != 7 || d.Mode != ModeForceUpdate {
		t.Fatalf("previous policy must stay active: %+v", d)
	}

	// A valid change is applied without restarting (no new app build needed).
	p := basePolicy()
	p["configVersion"] = 9
	p["platforms"].(map[string]any)["android"].(map[string]any)["minimumSupportedVersion"] = "0.9.0"
	p["platforms"].(map[string]any)["android"].(map[string]any)["minimumSupportedBuild"] = 0
	writePolicy(t, dir, p)
	if err := s.Reload(); err != nil {
		t.Fatal(err)
	}
	if d := s.Evaluate(client(t, "android", "1.0.0", "1"), "en"); d.ConfigVersion != 9 || d.Mode != ModeOptionalUpdate {
		t.Fatalf("policy change not applied: %+v", d)
	}
}

func TestShippedPolicyFilesAreValid(t *testing.T) {
	for _, env := range []string{"development", "preproduction", "production"} {
		raw, err := os.ReadFile(filepath.Join("..", "..", "config", "app-policy."+env+".json"))
		if err != nil {
			t.Fatal(err)
		}
		c, err := Parse(raw, env)
		if err != nil {
			t.Errorf("%s policy invalid: %v", env, err)
			continue
		}
		// The shipped entry fees: Ludo 100,000 and Snakes & Ladders 50,000 coins.
		if c.entryFees[GameLudo] != 100_000 || c.entryFees[GameSnakesLadders] != 50_000 || len(c.entryFees) != 2 {
			t.Errorf("%s entry fees = %v, want ludo 100000, snakes_ladders 50000", env, c.entryFees)
		}
		// The shipped welcome grant: 10 lakh (1,000,000) coins and 50 diamonds.
		if c.welcome[WelcomeCoins] != 1_000_000 || c.welcome[WelcomeDiamonds] != 50 || len(c.welcome) != 2 {
			t.Errorf("%s welcome = %v, want coins 1000000, diamonds 50", env, c.welcome)
		}
	}
}

// fallbackFees stands in for ENTRY_FEE_* / the built-in defaults.
var fallbackFees = map[string]int64{GameLudo: 1_111, GameSnakesLadders: 2_222}

func TestEntryFeesFromPolicyFile(t *testing.T) {
	p := basePolicy()
	p["entryFees"] = map[string]any{"ludo": 100_000, "snakes_ladders": 50_000}
	s, _ := newStore(t, p)
	if got := s.EntryFee(GameLudo, 1); got != 100_000 {
		t.Fatalf("ludo fee = %d", got)
	}
	if got := s.EntryFee(GameSnakesLadders, 1); got != 50_000 {
		t.Fatalf("snakes fee = %d", got)
	}
	got := s.EntryFees(fallbackFees)
	if len(got) != 2 || got[GameLudo] != 100_000 || got[GameSnakesLadders] != 50_000 {
		t.Fatalf("EntryFees = %v", got)
	}
	// The result is a copy: callers cannot mutate the live policy.
	got[GameLudo] = 1
	if s.EntryFee(GameLudo, 0) != 100_000 {
		t.Fatal("EntryFees result aliases the policy")
	}
}

func TestEntryFeesPrecedence(t *testing.T) {
	cases := []struct {
		name       string
		fees       any // nil: no entryFees object
		ludo, snkl int64
	}{
		{"absent: fallback for both", nil, 1_111, 2_222},
		{"empty object: fallback for both", map[string]any{}, 1_111, 2_222},
		{"only ludo set", map[string]any{"ludo": 70_000}, 70_000, 2_222},
		{"only snakes set", map[string]any{"snakes_ladders": 30_000}, 1_111, 30_000},
		{"zero is a real fee (free), not unset", map[string]any{"ludo": 0, "snakes_ladders": 0}, 0, 0},
		{"maximum accepted", map[string]any{"ludo": MaxEntryFee}, MaxEntryFee, 2_222},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			p := basePolicy()
			if c.fees != nil {
				p["entryFees"] = c.fees
			}
			s, _ := newStore(t, p)
			got := s.EntryFees(fallbackFees)
			if got[GameLudo] != c.ludo || got[GameSnakesLadders] != c.snkl {
				t.Fatalf("fees = %v, want ludo %d snakes %d", got, c.ludo, c.snkl)
			}
		})
	}
}

func TestEntryFeesValidation(t *testing.T) {
	bad := map[string]string{
		"unknown game":     `{"ludo": 50000, "chess": 10}`,
		"game id casing":   `{"Ludo": 50000}`,
		"negative":         `{"ludo": -1}`,
		"above maximum":    `{"snakes_ladders": 100000001}`,
		"fraction":         `{"ludo": 50000.5}`,
		"exponent":         `{"ludo": 5e4}`,
		"string":           `{"ludo": "50000"}`,
		"null":             `{"ludo": null}`,
		"int64 overflow":   `{"ludo": 99999999999999999999}`,
		"not an object":    `[100000, 50000]`,
		"number as object": `50000`,
	}
	withFees := func(t *testing.T, fees string) []byte {
		t.Helper()
		raw, _ := json.Marshal(basePolicy())
		out := strings.Replace(string(raw), `"configVersion":7`, `"configVersion":7,"entryFees":`+fees, 1)
		if out == string(raw) {
			t.Fatal("test setup: entryFees not injected")
		}
		return []byte(out)
	}
	// Control: the same injection with valid fees parses.
	if _, err := Parse(withFees(t, `{"ludo": 50000, "snakes_ladders": 0}`), "production"); err != nil {
		t.Fatalf("valid entryFees rejected: %v", err)
	}
	for name, fees := range bad {
		t.Run(name, func(t *testing.T) {
			if _, err := Parse(withFees(t, fees), "production"); err == nil {
				t.Fatalf("invalid entryFees %s accepted", fees)
			}
		})
	}
}

func TestEntryFeesInvalidReloadKeepsPreviousFees(t *testing.T) {
	p := basePolicy()
	p["entryFees"] = map[string]any{"ludo": 100_000, "snakes_ladders": 50_000}
	s, dir := newStore(t, p)

	// A bad fee rejects the whole file: the previous fees (and the rest of the
	// policy) stay active.
	p["configVersion"] = 8
	p["entryFees"] = map[string]any{"ludo": -5, "snakes_ladders": 30_000}
	writePolicy(t, dir, p)
	if err := s.Reload(); err == nil || !strings.Contains(err.Error(), "entryFees.ludo") {
		t.Fatalf("expected an entryFees.ludo error, got %v", err)
	}
	if s.EntryFee(GameLudo, 1) != 100_000 || s.EntryFee(GameSnakesLadders, 1) != 50_000 {
		t.Fatalf("previous fees not kept: %v", s.EntryFees(fallbackFees))
	}
	if d := s.Evaluate(client(t, "android", "1.4.0", "140"), "en"); d.ConfigVersion != 7 {
		t.Fatalf("previous policy not kept: configVersion %d", d.ConfigVersion)
	}

	// A valid change applies on the next reload, without a restart.
	p["configVersion"] = 9
	p["entryFees"] = map[string]any{"ludo": 75_000, "snakes_ladders": 30_000}
	writePolicy(t, dir, p)
	if err := s.Reload(); err != nil {
		t.Fatal(err)
	}
	if s.EntryFee(GameLudo, 1) != 75_000 || s.EntryFee(GameSnakesLadders, 1) != 30_000 {
		t.Fatalf("new fees not applied: %v", s.EntryFees(fallbackFees))
	}

	// Removing the object falls back to ENTRY_FEE_* / the built-in defaults.
	delete(p, "entryFees")
	writePolicy(t, dir, p)
	if err := s.Reload(); err != nil {
		t.Fatal(err)
	}
	if got := s.EntryFees(fallbackFees); got[GameLudo] != 1_111 || got[GameSnakesLadders] != 2_222 {
		t.Fatalf("fallback not used after removal: %v", got)
	}
}

func TestEntryFeesHotReloadByPolling(t *testing.T) {
	p := basePolicy()
	p["entryFees"] = map[string]any{"ludo": 100_000, "snakes_ladders": 50_000}
	s, dir := newStore(t, p)
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	go s.Run(ctx, 10*time.Millisecond)

	p["configVersion"] = 8
	p["entryFees"] = map[string]any{"ludo": 60_000, "snakes_ladders": 35_000}
	path := writePolicy(t, dir, p)
	// Make the modification time differ even on coarse-grained filesystems.
	future := time.Now().Add(2 * time.Second)
	if err := os.Chtimes(path, future, future); err != nil {
		t.Fatal(err)
	}
	deadline := time.Now().Add(5 * time.Second)
	for s.EntryFee(GameLudo, 0) != 60_000 || s.EntryFee(GameSnakesLadders, 0) != 35_000 {
		if time.Now().After(deadline) {
			t.Fatalf("fees not hot-reloaded: %v", s.EntryFees(fallbackFees))
		}
		time.Sleep(5 * time.Millisecond)
	}
}

func TestWelcomePrecedence(t *testing.T) {
	const fbCoins, fbDiamonds = 7_777, 7 // stand-ins for WELCOME_* / defaults
	cases := []struct {
		name            string
		welcome         any // nil: no welcome object
		coins, diamonds int64
	}{
		{"absent: fallback for both", nil, fbCoins, fbDiamonds},
		{"empty object: fallback for both", map[string]any{}, fbCoins, fbDiamonds},
		{"both set", map[string]any{"coins": 1_000_000, "diamonds": 50}, 1_000_000, 50},
		{"only coins set", map[string]any{"coins": 2_000_000}, 2_000_000, fbDiamonds},
		{"only diamonds set", map[string]any{"diamonds": 75}, fbCoins, 75},
		{"zero is a real grant, not unset", map[string]any{"coins": 0, "diamonds": 0}, 0, 0},
		{"maximums accepted", map[string]any{"coins": MaxWelcomeCoins, "diamonds": MaxWelcomeDiamonds}, MaxWelcomeCoins, MaxWelcomeDiamonds},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			p := basePolicy()
			if c.welcome != nil {
				p["welcome"] = c.welcome
			}
			s, _ := newStore(t, p)
			if coins, diamonds := s.Welcome(fbCoins, fbDiamonds); coins != c.coins || diamonds != c.diamonds {
				t.Fatalf("welcome = %d coins / %d diamonds, want %d / %d", coins, diamonds, c.coins, c.diamonds)
			}
		})
	}
}

func TestWelcomeValidation(t *testing.T) {
	bad := map[string]string{
		"unknown key":        `{"coins": 1000000, "gems": 5}`,
		"key casing":         `{"Coins": 1000000}`,
		"negative coins":     `{"coins": -1}`,
		"negative diamonds":  `{"diamonds": -1}`,
		"coins above max":    `{"coins": 1000000001}`,
		"diamonds above max": `{"diamonds": 1000001}`,
		"fraction":           `{"coins": 1000000.5}`,
		"exponent":           `{"coins": 1e6}`,
		"string":             `{"diamonds": "50"}`,
		"null":               `{"coins": null}`,
		"not an object":      `[1000000, 50]`,
	}
	withWelcome := func(t *testing.T, w string) []byte {
		t.Helper()
		raw, _ := json.Marshal(basePolicy())
		out := strings.Replace(string(raw), `"configVersion":7`, `"configVersion":7,"welcome":`+w, 1)
		if out == string(raw) {
			t.Fatal("test setup: welcome not injected")
		}
		return []byte(out)
	}
	if _, err := Parse(withWelcome(t, `{"coins": 1000000, "diamonds": 50}`), "production"); err != nil {
		t.Fatalf("valid welcome rejected: %v", err)
	}
	for name, w := range bad {
		t.Run(name, func(t *testing.T) {
			if _, err := Parse(withWelcome(t, w), "production"); err == nil {
				t.Fatalf("invalid welcome %s accepted", w)
			}
		})
	}
}

func TestWelcomeReloadKeepsLastGoodAndHotReloads(t *testing.T) {
	p := basePolicy()
	p["welcome"] = map[string]any{"coins": 1_000_000, "diamonds": 50}
	s, dir := newStore(t, p)
	want := func(coins, diamonds int64) {
		t.Helper()
		if c, d := s.Welcome(1, 1); c != coins || d != diamonds {
			t.Fatalf("welcome = %d / %d, want %d / %d", c, d, coins, diamonds)
		}
	}
	want(1_000_000, 50)

	// An invalid grant rejects the whole file; the last good one stays.
	p["configVersion"] = 8
	p["welcome"] = map[string]any{"coins": 2_000_000_000, "diamonds": 60}
	writePolicy(t, dir, p)
	if err := s.Reload(); err == nil || !strings.Contains(err.Error(), "welcome.coins") {
		t.Fatalf("expected a welcome.coins error, got %v", err)
	}
	want(1_000_000, 50)

	// A valid change is picked up by the poller without a restart.
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	go s.Run(ctx, 10*time.Millisecond)
	p["configVersion"] = 9
	p["welcome"] = map[string]any{"coins": 1_500_000, "diamonds": 75}
	path := writePolicy(t, dir, p)
	future := time.Now().Add(3 * time.Second)
	if err := os.Chtimes(path, future, future); err != nil {
		t.Fatal(err)
	}
	deadline := time.Now().Add(5 * time.Second)
	for {
		if c, d := s.Welcome(1, 1); c == 1_500_000 && d == 75 {
			break
		}
		if time.Now().After(deadline) {
			c, d := s.Welcome(1, 1)
			t.Fatalf("welcome not hot-reloaded: %d / %d", c, d)
		}
		time.Sleep(5 * time.Millisecond)
	}
}
