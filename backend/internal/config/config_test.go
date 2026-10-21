package config

import (
	"strings"
	"testing"
	"time"
)

// minimalEnv sets the variables Load requires; ENTRY_FEE_* start unset (an
// empty value counts as unset).
func minimalEnv(t *testing.T) {
	t.Helper()
	for k, v := range map[string]string{
		"APP_ENV": EnvDevelopment, "DATABASE_URL": "postgres://unused",
		"JWT_SIGNING_KEY": strings.Repeat("k", 40), "PUBLIC_ID_KEY": strings.Repeat("p", 40),
		"ENTRY_FEE_LUDO": "", "ENTRY_FEE_SNAKES": "", "WELCOME_COINS": "", "WELCOME_DIAMONDS": "",
		"GAME_STATS_INTERVAL": "",
	} {
		t.Setenv(k, v)
	}
}

func TestEntryFeeFallbacks(t *testing.T) {
	cases := []struct {
		name         string
		ludo, snakes string
		wantL, wantS int64
		wantErr      string
	}{
		{"built-in defaults", "", "", 100_000, 50_000, ""},
		{"env overrides defaults", "70000", "30000", 70_000, 30_000, ""},
		{"zero means free", "0", "0", 0, 0, ""},
		{"maximum", "100000000", "", 100_000_000, 50_000, ""},
		{"negative", "-1", "", 0, 0, "ENTRY_FEE_LUDO must be between 0 and 100000000"},
		{"above maximum", "", "100000001", 0, 0, "ENTRY_FEE_SNAKES must be between 0 and 100000000"},
		{"not an integer", "50k", "", 0, 0, "ENTRY_FEE_LUDO: not an integer"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			minimalEnv(t)
			t.Setenv("ENTRY_FEE_LUDO", c.ludo)
			t.Setenv("ENTRY_FEE_SNAKES", c.snakes)
			cfg, err := Load()
			if c.wantErr != "" {
				if err == nil || !strings.Contains(err.Error(), c.wantErr) {
					t.Fatalf("err = %v, want %q", err, c.wantErr)
				}
				return
			}
			if err != nil {
				t.Fatal(err)
			}
			if cfg.Game.EntryFeeLudo != c.wantL || cfg.Game.EntryFeeSnakes != c.wantS {
				t.Fatalf("fees = %d / %d, want %d / %d", cfg.Game.EntryFeeLudo, cfg.Game.EntryFeeSnakes, c.wantL, c.wantS)
			}
		})
	}
	if DefaultEntryFeeLudo != 100_000 || DefaultEntryFeeSnakes != 50_000 {
		t.Fatalf("built-in defaults changed: %d / %d", DefaultEntryFeeLudo, DefaultEntryFeeSnakes)
	}
}

func TestWelcomeFallbacks(t *testing.T) {
	cases := []struct {
		name            string
		coins, diamonds string
		wantC, wantD    int64
		wantErr         string
	}{
		{"built-in defaults", "", "", 1_000_000, 50, ""},
		{"env overrides defaults", "2000000", "75", 2_000_000, 75, ""},
		{"zero grant", "0", "0", 0, 0, ""},
		{"maximums", "1000000000", "1000000", 1_000_000_000, 1_000_000, ""},
		{"negative coins", "-1", "", 0, 0, "WELCOME_COINS must be between 0 and 1000000000"},
		{"coins above maximum", "1000000001", "", 0, 0, "WELCOME_COINS must be between 0 and 1000000000"},
		{"diamonds above maximum", "", "1000001", 0, 0, "WELCOME_DIAMONDS must be between 0 and 1000000"},
		{"not an integer", "", "lots", 0, 0, "WELCOME_DIAMONDS: not an integer"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			minimalEnv(t)
			t.Setenv("WELCOME_COINS", c.coins)
			t.Setenv("WELCOME_DIAMONDS", c.diamonds)
			cfg, err := Load()
			if c.wantErr != "" {
				if err == nil || !strings.Contains(err.Error(), c.wantErr) {
					t.Fatalf("err = %v, want %q", err, c.wantErr)
				}
				return
			}
			if err != nil {
				t.Fatal(err)
			}
			if cfg.Wallet.WelcomeCoins != c.wantC || cfg.Wallet.WelcomeDiamonds != c.wantD {
				t.Fatalf("welcome = %d / %d, want %d / %d", cfg.Wallet.WelcomeCoins, cfg.Wallet.WelcomeDiamonds, c.wantC, c.wantD)
			}
		})
	}
	if DefaultWelcomeCoins != 1_000_000 || DefaultWelcomeDiamonds != 50 {
		t.Fatalf("built-in welcome defaults changed: %d / %d", DefaultWelcomeCoins, DefaultWelcomeDiamonds)
	}
}

func TestGameStatsInterval(t *testing.T) {
	cases := []struct {
		raw     string
		want    time.Duration
		wantErr string
	}{
		{"", 15 * time.Second, ""},
		{"30s", 30 * time.Second, ""},
		{"5", 5 * time.Second, ""}, // plain integers are seconds
		{"1s", time.Second, ""},
		{"500ms", 0, "GAME_STATS_INTERVAL must be at least 1s"},
		{"soon", 0, "GAME_STATS_INTERVAL: not a duration"},
	}
	for _, c := range cases {
		t.Run(c.raw, func(t *testing.T) {
			minimalEnv(t)
			t.Setenv("GAME_STATS_INTERVAL", c.raw)
			cfg, err := Load()
			if c.wantErr != "" {
				if err == nil || !strings.Contains(err.Error(), c.wantErr) {
					t.Fatalf("err = %v, want %q", err, c.wantErr)
				}
				return
			}
			if err != nil {
				t.Fatal(err)
			}
			if cfg.GameStatsInterval != c.want {
				t.Fatalf("interval = %v, want %v", cfg.GameStatsInterval, c.want)
			}
		})
	}
}
