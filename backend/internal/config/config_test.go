package config

import (
	"strings"
	"testing"
	"time"

	"ludoroyale/internal/wallet"
)

// minimalEnv sets the variables Load requires; ENTRY_FEE_* start unset (an
// empty value counts as unset).
func minimalEnv(t *testing.T) {
	t.Helper()
	for k, v := range map[string]string{
		"APP_ENV": EnvDevelopment, "DATABASE_URL": "postgres://unused",
		"JWT_SIGNING_KEY": strings.Repeat("k", 40), "PUBLIC_ID_KEY": strings.Repeat("p", 40),
		"ENTRY_FEE_LUDO": "", "ENTRY_FEE_SNAKES": "", "WELCOME_COINS": "", "WELCOME_DIAMONDS": "",
		"GAME_STATS_INTERVAL": "", "R2_ACCOUNT_ID": "", "R2_BUCKET": "", "R2_ACCESS_KEY_ID": "",
		"R2_SECRET_ACCESS_KEY": "", "R2_ENDPOINT": "", "ASSET_URL_TTL": "", "BOT_PICTURE_SHARE": "",
		"BOT_COINS_START": "", "BOT_COINS_RECHARGE_BELOW": "", "BOT_COINS_RECHARGE_TO": "",
		"BOT_COINS_RESET_ABOVE": "", "BOT_COINS_RESET_TO": "",
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

func TestSocialAndAdminSettings(t *testing.T) {
	hash := strings.Repeat("ab", 32)
	cases := []struct {
		name                     string
		friends, reports, admin  string
		wantFriends, wantReports int
		wantAdmin                bool
		wantErr                  string
	}{
		{"defaults", "", "", "", 20, 2, false, ""},
		{"overrides", "35", "5", hash, 35, 5, true, ""},
		{"minimums", "1", "1", "", 1, 1, false, ""},
		{"zero friends", "0", "", "", 0, 0, false, "FRIENDS_MAX must be >= 1"},
		{"negative reports", "", "-2", "", 0, 0, false, "REPORTS_PER_DAY must be >= 1"},
		{"friends not an integer", "twenty", "", "", 0, 0, false, "FRIENDS_MAX: not an integer"},
		{"admin hash not hex", "", "", strings.Repeat("zz", 32), 0, 0, false, "ADMIN_API_KEY_SHA256 must be 64 hex characters"},
		{"admin hash too short", "", "", "abcd", 0, 0, false, "ADMIN_API_KEY_SHA256 must be 64 hex characters"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			minimalEnv(t)
			t.Setenv("FRIENDS_MAX", c.friends)
			t.Setenv("REPORTS_PER_DAY", c.reports)
			t.Setenv("ADMIN_API_KEY_SHA256", c.admin)
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
			if cfg.Social.FriendsMax != c.wantFriends || cfg.Social.ReportsPerDay != c.wantReports ||
				(len(cfg.AdminKeySHA256) == 32) != c.wantAdmin {
				t.Fatalf("social = %+v admin = %x", cfg.Social, cfg.AdminKeySHA256)
			}
		})
	}
}

func TestNameChangesPerDay(t *testing.T) {
	cases := []struct {
		name, raw string
		want      int
		wantErr   string
	}{
		{"default", "", 3, ""},
		{"override", "5", 5, ""},
		{"minimum", "1", 1, ""},
		{"zero", "0", 0, "NAME_CHANGES_PER_DAY must be >= 1"},
		{"negative", "-2", 0, "NAME_CHANGES_PER_DAY must be >= 1"},
		{"not an integer", "three", 0, "NAME_CHANGES_PER_DAY: not an integer"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			minimalEnv(t)
			t.Setenv("NAME_CHANGES_PER_DAY", c.raw)
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
			if cfg.NameChangesPerDay != c.want {
				t.Fatalf("NameChangesPerDay = %d, want %d", cfg.NameChangesPerDay, c.want)
			}
		})
	}
}

func TestMaxStrikes(t *testing.T) {
	cases := []struct {
		raw     string
		want    int
		wantErr string
	}{
		{"", DefaultMaxStrikes, ""},
		{"3", 3, ""},
		{"1", 1, ""},
		{"0", 0, "MAX_STRIKES must be >= 1"},
		{"-2", 0, "MAX_STRIKES must be >= 1"},
		{"five", 0, "MAX_STRIKES: not an integer"},
	}
	for _, c := range cases {
		t.Run(c.raw, func(t *testing.T) {
			minimalEnv(t)
			t.Setenv("MAX_STRIKES", c.raw)
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
			if cfg.Game.MaxStrikes != c.want {
				t.Fatalf("MaxStrikes = %d, want %d", cfg.Game.MaxStrikes, c.want)
			}
		})
	}
	if DefaultMaxStrikes != 5 {
		t.Fatalf("built-in MAX_STRIKES default changed: %d", DefaultMaxStrikes)
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

func TestLegalNoticesFile(t *testing.T) {
	minimalEnv(t)
	t.Setenv("LEGAL_NOTICES_FILE", "")
	cfg, err := Load()
	if err != nil {
		t.Fatal(err)
	}
	if cfg.LegalNoticesFile != "config/legal/open-source-notices.html" {
		t.Fatalf("default = %q", cfg.LegalNoticesFile)
	}
	t.Setenv("LEGAL_NOTICES_FILE", "/srv/legal/notices.html")
	if cfg, err = Load(); err != nil || cfg.LegalNoticesFile != "/srv/legal/notices.html" {
		t.Fatalf("override = %v, %v", cfg, err)
	}
}

func TestAssetsConfig(t *testing.T) {
	full := map[string]string{"R2_ACCOUNT_ID": "0123456789abcdef0123456789abcdef", "R2_BUCKET": "ludo-royale",
		"R2_ACCESS_KEY_ID": "AKIDTEST", "R2_SECRET_ACCESS_KEY": "s3cr3t-value-not-real"}
	cases := []struct {
		name    string
		env     map[string]string
		enabled bool
		ttl     time.Duration
		wantErr string
	}{
		{"none", nil, false, 10 * time.Minute, ""},
		{"all four", full, true, 10 * time.Minute, ""},
		{"ttl", map[string]string{"ASSET_URL_TTL": "30m"}, false, 30 * time.Minute, ""},
		{"ttl too long", map[string]string{"ASSET_URL_TTL": "2h"}, false, 0, "ASSET_URL_TTL must be between"},
		{"ttl too short", map[string]string{"ASSET_URL_TTL": "10s"}, false, 0, "ASSET_URL_TTL must be between"},
		{"partial", map[string]string{"R2_BUCKET": "ludo-royale", "R2_ACCESS_KEY_ID": "AKIDTEST"}, false, 0,
			"R2 is partially configured"},
		{"secret only", map[string]string{"R2_SECRET_ACCESS_KEY": "s3cr3t-value-not-real"}, false, 0, "R2_ACCOUNT_ID"},
		{"endpoint without r2", map[string]string{"R2_ENDPOINT": "http://127.0.0.1:9"}, false, 0, "R2_ENDPOINT requires"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			minimalEnv(t)
			for k, v := range c.env {
				t.Setenv(k, v)
			}
			if c.name == "all four" {
				for k, v := range full {
					t.Setenv(k, v)
				}
			}
			cfg, err := Load()
			if c.wantErr != "" {
				if err == nil || !strings.Contains(err.Error(), c.wantErr) {
					t.Fatalf("err = %v, want %q", err, c.wantErr)
				}
				if strings.Contains(err.Error(), "s3cr3t-value-not-real") {
					t.Fatal("error leaks the secret")
				}
				return
			}
			if err != nil {
				t.Fatal(err)
			}
			if cfg.Assets.Enabled() != c.enabled || cfg.Assets.URLTTL != c.ttl {
				t.Fatalf("assets %+v enabled=%v", cfg.Assets.URLTTL, cfg.Assets.Enabled())
			}
		})
	}
	t.Run("endpoint refused in production", func(t *testing.T) {
		minimalEnv(t)
		for k, v := range full {
			t.Setenv(k, v)
		}
		t.Setenv("APP_ENV", EnvProduction)
		t.Setenv("R2_ENDPOINT", "http://127.0.0.1:9")
		if _, err := Load(); err == nil || !strings.Contains(err.Error(), "R2_ENDPOINT is a test hook") {
			t.Fatalf("err = %v", err)
		}
	})
}

func TestBotPictureShare(t *testing.T) {
	cases := []struct {
		raw     string
		want    float64
		wantErr string
	}{
		{"", 0.3, ""}, {"0", 0, ""}, {"1", 1, ""}, {"0.5", 0.5, ""},
		{"1.5", 0, "BOT_PICTURE_SHARE must be between 0 and 1"},
		{"-0.1", 0, "BOT_PICTURE_SHARE must be between 0 and 1"},
		{"lots", 0, "BOT_PICTURE_SHARE: not a number"},
	}
	for _, c := range cases {
		t.Run(c.raw, func(t *testing.T) {
			minimalEnv(t)
			t.Setenv("BOT_PICTURE_SHARE", c.raw)
			cfg, err := Load()
			if c.wantErr != "" {
				if err == nil || !strings.Contains(err.Error(), c.wantErr) {
					t.Fatalf("err = %v, want %q", err, c.wantErr)
				}
				return
			}
			if err != nil || cfg.Bots.PictureShare != c.want {
				t.Fatalf("share %v err %v", cfg, err)
			}
		})
	}
}

func TestIAPConfig(t *testing.T) {
	iapVars := []string{"COIN_PACKS_FILE", "GOOGLE_PLAY_SERVICE_ACCOUNT_FILE", "GOOGLE_PLAY_PACKAGE_NAME",
		"GOOGLE_PLAY_API_URL", "GOOGLE_PLAY_VOIDED_POLL_INTERVAL", "GOOGLE_PLAY_VOIDED_LOOKBACK", "APPLE_IAP_ENABLED",
		"APPLE_BUNDLE_ID", "APPLE_IAP_ALLOW_SANDBOX", "APPLE_IAP_KEY_ID", "APPLE_IAP_ISSUER_ID", "APPLE_IAP_KEY_FILE",
		"APPLE_ROOT_CA_FILE", "APPLE_IAP_API_URL"}
	cases := []struct {
		name    string
		env     map[string]string
		check   func(t *testing.T, c IAPConfig)
		wantErr string
	}{
		{"defaults: both stores off", nil, func(t *testing.T, c IAPConfig) {
			if c.GoogleEnabled() || c.AppleOn() || c.CoinPacksFile != "config/coin_packs.json" ||
				c.GooglePlayPackage != "com.ludoroyale.app" || c.AppleBundleID != "com.ludoroyale.app" ||
				!c.AppleAllowSandbox || c.GoogleVoidedInterval != time.Hour || c.GoogleVoidedLookback != 7*24*time.Hour {
				t.Fatalf("%+v", c)
			}
		}, ""},
		{"google on", map[string]string{"GOOGLE_PLAY_SERVICE_ACCOUNT_FILE": "/secrets/sa.json",
			"GOOGLE_PLAY_PACKAGE_NAME": "com.ludoroyale.app", "GOOGLE_PLAY_VOIDED_POLL_INTERVAL": "0"},
			func(t *testing.T, c IAPConfig) {
				if !c.GoogleEnabled() || c.GoogleVoidedInterval != 0 {
					t.Fatalf("%+v", c)
				}
			}, ""},
		{"apple flag", map[string]string{"APPLE_IAP_ENABLED": "true"}, func(t *testing.T, c IAPConfig) {
			if !c.AppleOn() {
				t.Fatal("apple off")
			}
		}, ""},
		{"apple api key implies apple", map[string]string{"APPLE_IAP_KEY_ID": "K", "APPLE_IAP_ISSUER_ID": "I",
			"APPLE_IAP_KEY_FILE": "/secrets/k.p8"}, func(t *testing.T, c IAPConfig) {
			if !c.AppleOn() {
				t.Fatal("apple off")
			}
		}, ""},
		{"partial apple api key", map[string]string{"APPLE_IAP_KEY_ID": "K"}, nil, "set all three or none"},
		{"poll too fast", map[string]string{"GOOGLE_PLAY_VOIDED_POLL_INTERVAL": "100ms"}, nil, "GOOGLE_PLAY_VOIDED_POLL_INTERVAL"},
		{"lookback too long", map[string]string{"GOOGLE_PLAY_VOIDED_LOOKBACK": "1000h"}, nil, "GOOGLE_PLAY_VOIDED_LOOKBACK"},
		{"production poll under a minute", map[string]string{"APP_ENV": EnvProduction,
			"GOOGLE_PLAY_VOIDED_POLL_INTERVAL": "30s"}, nil, "GOOGLE_PLAY_VOIDED_POLL_INTERVAL"},
		{"test hooks refused in production", map[string]string{"APP_ENV": EnvProduction,
			"APPLE_ROOT_CA_FILE": "/tmp/root.pem"}, nil, "test hooks"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			minimalEnv(t)
			for _, k := range iapVars {
				t.Setenv(k, "")
			}
			for k, v := range c.env {
				t.Setenv(k, v)
			}
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
			c.check(t, cfg.IAP)
		})
	}
}

func TestBotCoinRules(t *testing.T) {
	type env = map[string]string
	cases := []struct {
		name    string
		env     env
		prod    bool
		want    wallet.BotRules
		wantErr string
	}{
		{"owner defaults", env{}, false, wallet.BotRules{Start: 10_000_000, RechargeBelow: 100_000, RechargeTo: 10_000_000,
			ResetAbove: 100_000_000, ResetTo: 10_000_000}, ""},
		{"custom band", env{"BOT_COINS_START": "500000", "BOT_COINS_RECHARGE_BELOW": "50000", "BOT_COINS_RECHARGE_TO": "400000",
			"BOT_COINS_RESET_ABOVE": "2000000", "BOT_COINS_RESET_TO": "600000"}, false,
			wallet.BotRules{Start: 500_000, RechargeBelow: 50_000, RechargeTo: 400_000, ResetAbove: 2_000_000, ResetTo: 600_000}, ""},
		{"zero start", env{"BOT_COINS_START": "0"}, false, wallet.BotRules{}, "BOT_COINS_START must be between 1 and"},
		{"negative threshold", env{"BOT_COINS_RECHARGE_BELOW": "-5"}, false, wallet.BotRules{}, "BOT_COINS_RECHARGE_BELOW must be between 1 and"},
		{"not an integer", env{"BOT_COINS_RESET_ABOVE": "10cr"}, false, wallet.BotRules{}, "BOT_COINS_RESET_ABOVE: not an integer"},
		{"recharge not above threshold", env{"BOT_COINS_RECHARGE_TO": "100000"}, false, wallet.BotRules{},
			"BOT_COINS_RECHARGE_TO must be greater than BOT_COINS_RECHARGE_BELOW"},
		{"recharge triggers reset", env{"BOT_COINS_RECHARGE_TO": "200000000"}, false, wallet.BotRules{},
			"BOT_COINS_RECHARGE_TO must not exceed BOT_COINS_RESET_ABOVE"},
		{"reset triggers recharge", env{"BOT_COINS_RESET_TO": "1000"}, false, wallet.BotRules{},
			"BOT_COINS_RESET_TO must be between BOT_COINS_RECHARGE_BELOW and BOT_COINS_RESET_ABOVE"},
		{"start outside the band", env{"BOT_COINS_START": "50000"}, false, wallet.BotRules{},
			"BOT_COINS_START must be between BOT_COINS_RECHARGE_BELOW and BOT_COINS_RESET_ABOVE"},
		{"nonsense refused in production", env{"BOT_COINS_RESET_ABOVE": "5000000"}, true, wallet.BotRules{},
			"BOT_COINS_RECHARGE_TO must not exceed BOT_COINS_RESET_ABOVE"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			minimalEnv(t)
			for k, v := range c.env {
				t.Setenv(k, v)
			}
			if c.prod {
				t.Setenv("APP_ENV", EnvProduction)
			}
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
			if cfg.Bots.Coins != c.want {
				t.Fatalf("rules %+v, want %+v", cfg.Bots.Coins, c.want)
			}
		})
	}
}
