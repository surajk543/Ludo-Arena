package report

import (
	"math"
	"testing"
	"time"
)

func TestInt(t *testing.T) {
	tests := []struct {
		in   float64
		want string
	}{
		{0, "0"}, {7, "7"}, {999, "999"}, {1000, "1,000"}, {1234.4, "1,234"}, {1234.5, "1,235"},
		{12345, "12,345"}, {123456, "123,456"}, {1234567, "1,234,567"}, {-1234, "-1,234"}, {-12, "-12"},
		{math.NaN(), "n/a"}, {math.Inf(1), "n/a"},
	}
	for _, tt := range tests {
		if got := Int(tt.in); got != tt.want {
			t.Errorf("Int(%v) = %q, want %q", tt.in, got, tt.want)
		}
	}
}

func TestFormatters(t *testing.T) {
	tests := []struct {
		name, got, want string
	}{
		{"I n/a", I(Num{}), "n/a"},
		{"I value", I(N(2300)), "2,300"},
		{"Pct", Pct(N(41.4)), "41%"},
		{"Pct n/a", Pct(Num{}), "n/a"},
		{"Secs", Secs(N(6.25)), "6.2 s"},
		{"Secs large", Secs(N(1234)), "1,234 s"},
		{"Secs NaN", Secs(N(math.NaN())), "n/a"},
		{"Bytes MiB", Bytes(N(312 << 20)), "312 MiB"},
		{"Bytes GiB", Bytes(N(1.5 * (1 << 30))), "1.5 GiB"},
		{"Bytes B", Bytes(N(512)), "512 B"},
		{"Share", Share(N(91), N(100)), "91%"},
		{"Share zero total", Share(N(1), N(0)), ""},
		{"Ago", Ago(12*time.Minute + 20*time.Second), "12m"},
		{"Ago hours", Ago(3*time.Hour + 5*time.Minute), "3h 5m"},
		{"Ago days", Ago(50 * time.Hour), "2d 2h"},
		{"Ago short", Ago(10 * time.Second), "<1m"},
		{"GameName", GameName("snakes_ladders"), "Snakes & Ladders"},
		{"GameName unknown", GameName("chess_blitz"), "Chess blitz"},
		{"Title", Title("human_only"), "Human only"},
	}
	for _, tt := range tests {
		if tt.got != tt.want {
			t.Errorf("%s = %q, want %q", tt.name, tt.got, tt.want)
		}
	}
}

func TestEsc(t *testing.T) {
	if got := Esc(`<b>A & "B"</b>`); got != "&lt;b&gt;A &amp; &quot;B&quot;&lt;/b&gt;" {
		t.Errorf("Esc = %q", got)
	}
}

func TestStampTimeZones(t *testing.T) {
	at := time.Date(2026, 10, 21, 11, 30, 0, 0, time.UTC)
	tests := []struct {
		zone, want string
	}{
		{"Asia/Kolkata", "Wed 21 Oct 2026, 17:00 IST"},
		{"UTC", "Wed 21 Oct 2026, 11:30 UTC"},
		{"America/New_York", "Wed 21 Oct 2026, 07:30 EDT"},
	}
	for _, tt := range tests {
		loc, err := time.LoadLocation(tt.zone)
		if err != nil {
			t.Fatal(err)
		}
		if got := Stamp(at, loc); got != tt.want {
			t.Errorf("Stamp(%s) = %q, want %q", tt.zone, got, tt.want)
		}
	}
}

func TestDays(t *testing.T) {
	ist, _ := time.LoadLocation("Asia/Kolkata")
	// 02:00 IST on the 21st is still the 20th in UTC; yesterday is the 20th locally.
	now := time.Date(2026, 10, 20, 20, 30, 0, 0, time.UTC)
	if got := Yesterday(now, ist); !got.Equal(time.Date(2026, 10, 20, 0, 0, 0, 0, ist)) {
		t.Errorf("Yesterday = %v", got)
	}
	if got := civilDate(time.Date(2026, 10, 20, 0, 0, 0, 0, ist)); !got.Equal(time.Date(2026, 10, 20, 0, 0, 0, 0, time.UTC)) {
		t.Errorf("civilDate = %v", got)
	}
}

func TestPromDur(t *testing.T) {
	for d, want := range map[time.Duration]string{
		time.Hour: "1h", 24 * time.Hour: "1d", 2 * time.Minute: "2m", 90 * time.Second: "90s",
		24*time.Hour - 5*time.Minute: "1435m", 25 * time.Hour: "25h", 0: "1s",
	} {
		if got := promDur(d); got != want {
			t.Errorf("promDur(%v) = %q, want %q", d, got, want)
		}
	}
}
