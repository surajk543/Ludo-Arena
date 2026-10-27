package pdfreport

import (
	"context"
	"errors"
	"fmt"
	"math"
	"strings"
	"testing"
	"time"

	"ludoarena/opsbot/internal/backendapi"
	"ludoarena/opsbot/internal/promapi"
	"ludoarena/opsbot/internal/report"
)

var sampleNames = []string{"Asha", "Bilal Khan", "Chloé", "राहुल", "Dewi Lestari", "عمر", "Rahul राज", "Mariam", "Zoë", "Kiran", "Putri", "Ahmed"}

func joinedAt(i int) *time.Time {
	if i%7 == 6 {
		return nil
	}
	t := now.Add(-time.Duration(i*37+3) * time.Hour)
	return &t
}

func points(pts []promapi.Point) []promapi.Point { return pts }

// SampleLive is a realistic /live report with 128 players online.
func SampleLive() report.Live {
	start := now.Add(-report.Window)
	l := report.Live{At: now, Start: start, End: now, Step: time.Minute, Configured: true,
		Online:  points(wave(start, 1441, time.Minute, 220, 110, -1.2)),
		Playing: points(wave(start, 1441, time.Minute, 120, 70, -1.2)),
		Waiting: points(wave(start, 1441, time.Minute, 12, 6, 0)),
	}
	l.OnlineStats = report.StatsOf(l.Online, now, 3*time.Minute)
	l.PlayingStats = report.StatsOf(l.Playing, now, 3*time.Minute)
	l.List = backendapi.Online{At: now, Total: 128, Counts: map[string]int{"ludo": 41, "snakes_ladders": 23, "waiting": 6, "lobby": 58}}
	acts := []string{"ludo", "snakes_ladders", "waiting", "lobby"}
	modes := []string{"public", "private", "practice"}
	for i := 0; i < report.ListLimit; i++ {
		a := acts[min(i/25, 3)]
		u := backendapi.OnlineUser{UID: fmt.Sprintf("u_%012d", 100000+i*7919), UserID: fmt.Sprintf("uuid-%d", i),
			Name: sampleNames[i%len(sampleNames)], CreatedAt: joinedAt(i), OnlineSince: now.Add(-time.Duration(150-i) * time.Minute), Activity: a}
		if a != "lobby" {
			u.Game, u.Mode = "ludo", modes[i%3]
			if a == "snakes_ladders" || (a == "waiting" && i%2 == 0) {
				u.Game = "snakes_ladders"
			}
		}
		l.List.Users = append(l.List.Users, u)
	}
	return l
}

// SamplePlaytime is a realistic /playtime report.
func SamplePlaytime() report.PlayReport {
	from := now.Add(-report.Window)
	p := report.PlayReport{At: now, Hours: 24, Configured: true, Data: backendapi.Playtime{From: from, To: now, Hours: 24}}
	for gi, game := range report.Games {
		g := backendapi.GamePlaytime{Game: game, Players: 340 - 150*gi}
		for h := 0; h <= 24; h++ {
			secs := int64((900 - 400*float64(gi)) * 60 * (1 + 0.8*math.Sin(float64(h)/4)))
			g.Hourly = append(g.Hourly, backendapi.HourSeconds{Hour: from.Truncate(time.Hour).Add(time.Duration(h) * time.Hour), Seconds: secs})
			g.Seconds += secs
		}
		for i := 0; i < report.ListLimit-30*gi; i++ {
			g.Top = append(g.Top, backendapi.PlayerSeconds{UID: fmt.Sprintf("u_%012d", 500000+i*104729), Name: sampleNames[(i+gi)%len(sampleNames)],
				CreatedAt: joinedAt(i), Seconds: int64(14400 / (1 + float64(i)/6))})
		}
		p.Data.Games = append(p.Data.Games, g)
	}
	return p
}

// SampleResources is a realistic /metrics report for one host.
func SampleResources() report.Resources {
	start := now.Add(-report.Window)
	cpu := wave(start, 721, 2*time.Minute, 38, 22, -1)
	ram := wave(start, 721, 2*time.Minute, 61, 6, 0)
	inUse := wave(start, 721, 2*time.Minute, 6, 4, -1)
	open := make([]promapi.Point, len(inUse))
	limit := make([]promapi.Point, len(inUse))
	for i, p := range inUse {
		open[i] = promapi.Point{T: p.T, V: math.Round(p.V) + 5}
		limit[i] = promapi.Point{T: p.T, V: 20}
	}
	st := func(pts []promapi.Point) report.SeriesStats { return report.StatsOf(pts, now, 6*time.Minute) }
	return report.Resources{At: now, Start: start, End: now, Step: 2 * time.Minute,
		Hosts: []report.HostUsage{{Instance: "ludo-vps:9100", CPU: cpu, RAM: ram, Cores: report.N(4), MemBytes: report.N(8 << 30),
			CPUStats: st(cpu), RAMStats: st(ram)}},
		PGOpen: open, PGInUse: inUse, PGLimit: limit, PGOpenStats: st(open), PGInUseStats: st(inUse), PGLimitNow: report.N(20),
	}
}

func TestLivePDF(t *testing.T) {
	pdf, err := LivePDF(context.Background(), SampleLive(), meta, Options{})
	if err != nil {
		t.Fatal(err)
	}
	text := checkPDF(t, pdf, 4, 5, "Live players", "real players only, bots excluded", "Real players online", "128",
		"Playing Ludo", "41", "Playing Snakes & Ladders", "23", "In the lobby", "64", "waiting for a match 6",
		"Peak online (24 h)", "330", "Online players — first 100 of 128", "u_000000100000", "Asha", "Chloé",
		"[Devanagari script]", "[Arabic script]", "Rahul [+Devanagari]", "Ludo · Public", "Waiting · Snakes & Ladders", "Lobby", "· new")
	if strings.Contains(text, "....") {
		t.Error("an unprintable name was drawn as dots")
	}
	if n := countImages(pdf); n != 1 {
		t.Errorf("embedded charts = %d, want 1", n)
	}
}

func TestLivePDFWithoutBackend(t *testing.T) {
	for _, tc := range []struct {
		name string
		l    report.Live
		want string
	}{
		{"not configured", report.Live{At: now}, "set BACKEND_API_URL and BACKEND_ADMIN_KEY"},
		{"backend error", report.Live{At: now, Configured: true, ListErr: "backend /api/v1/admin/ops/online: 401"}, "Player list unavailable: backend"},
		{"nobody online", report.Live{At: now, Configured: true, List: backendapi.Online{Counts: map[string]int{}}}, "No real players are online."},
	} {
		t.Run(tc.name, func(t *testing.T) {
			pdf, err := LivePDF(context.Background(), tc.l, meta, Options{})
			if err != nil {
				t.Fatal(err)
			}
			checkPDF(t, pdf, 1, 2, tc.want, "Online players: no data in the last 24 hours")
		})
	}
}

func TestPlaytimePDF(t *testing.T) {
	pdf, err := PlaytimePDF(context.Background(), SamplePlaytime(), meta, Options{})
	if err != nil {
		t.Fatal(err)
	}
	checkPDF(t, pdf, 5, 8, "Playtime, last 24 hours", "20 Oct 17:00 – 21 Oct 17:00 IST", "Ludo minutes", "340 players",
		"Snakes & Ladders minutes", "190 players", "Top Ludo player", "240 min", "Top 100 — Ludo", "Top 100 — Snakes & Ladders",
		"Share of Ludo (bar vs #1)", "Share of S&L (bar vs #1)", "4h 00m", "240 more players played Ludo.", "Share of minutes played")
	if n := countImages(pdf); n != 1 {
		t.Errorf("embedded charts = %d, want 1", n)
	}
	off, err := PlaytimePDF(context.Background(), report.PlayReport{At: now}, meta, Options{})
	if err != nil {
		t.Fatal(err)
	}
	checkPDF(t, off, 1, 1, "needs the backend operator API")
}

func TestResourcesPDF(t *testing.T) {
	pdf, err := ResourcesPDF(context.Background(), SampleResources(), meta, Options{})
	if err != nil {
		t.Fatal(err)
	}
	checkPDF(t, pdf, 2, 3, "Server metrics, last 24 hours", "CPU now", "19%", "CPU peak (24 h)", "60%", "at 02:50",
		"RAM now", "of 8.0 GiB", "PostgreSQL in use", "8 open · limit 20", "PostgreSQL peak in use", "10",
		"ludo-vps:9100", "DB_MAX_CONNS")
	if n := countImages(pdf); n != 3 {
		t.Errorf("embedded charts = %d, want 3", n)
	}
	empty, err := ResourcesPDF(context.Background(), report.Resources{At: now}, meta, Options{})
	if err != nil {
		t.Fatal(err)
	}
	checkPDF(t, empty, 1, 2, "no node_exporter data", "postgres_pool_connections is not exported", "No host metrics")
}

func TestOnDemandPDFCancelled(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	for name, f := range map[string]func() ([]byte, error){
		"live":     func() ([]byte, error) { return LivePDF(ctx, SampleLive(), meta, Options{}) },
		"playtime": func() ([]byte, error) { return PlaytimePDF(ctx, SamplePlaytime(), meta, Options{}) },
		"metrics":  func() ([]byte, error) { return ResourcesPDF(ctx, SampleResources(), meta, Options{}) },
	} {
		if b, err := f(); !errors.Is(err, context.Canceled) || b != nil {
			t.Errorf("%s: err = %v (%d bytes), want context.Canceled", name, err, len(b))
		}
	}
}

func TestPDFName(t *testing.T) {
	for in, want := range map[string]string{
		"Asha":         "Asha",
		"Chloé Zoë":    "Chloé Zoë",
		"राहुल":        "[Devanagari script]",
		"عمر":          "[Arabic script]",
		"Rahul राज":    "Rahul [+Devanagari]",
		"Иван Ali":     "Ali [+Cyrillic]",
		"⭐⭐":           "[symbols]",
		"Sam ⭐":        "Sam [+symbols]",
		"ਹਰਪ੍ਰੀਤ اردو": "[Gurmukhi/Arabic script]",
	} {
		if got := PDFName(in); got != want {
			t.Errorf("PDFName(%q) = %q, want %q", in, got, want)
		}
	}
}

func TestOnDemandFileNames(t *testing.T) {
	for got, want := range map[string]string{
		LiveFileName(now, ist):      "ludo-arena-live-2026-10-21-1700-IST.pdf",
		PlaytimeFileName(now, ist):  "ludo-arena-playtime-2026-10-21-1700-IST.pdf",
		ResourcesFileName(now, ist): "ludo-arena-metrics-2026-10-21-1700-IST.pdf",
	} {
		if got != want {
			t.Errorf("file name = %q, want %q", got, want)
		}
	}
}
