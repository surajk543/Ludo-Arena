package apppolicy

import (
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
			"android": plat("1.2.0", 120, "1.4.0", 140, "https://play.google.com/store/apps/details?id=com.ludoroyale.app"),
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
		if _, err := Parse(raw, env); err != nil {
			t.Errorf("%s policy invalid: %v", env, err)
		}
	}
}
