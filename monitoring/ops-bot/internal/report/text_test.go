package report

import (
	"fmt"
	"strings"
	"testing"
	"time"

	"ludoroyale/opsbot/internal/alertmanager"
	"ludoroyale/opsbot/internal/google"
)

var meta = Meta{Env: "production", Loc: ist}

func sampleSnapshot() Snapshot {
	return Snapshot{
		At: fixedAt, PlayingHuman: N(1234), PlayingBot: N(456), OnlineHuman: N(1502), OnlineBot: N(470),
		Hosts:     []Host{{Instance: "app-1:9100", CPU: N(41.2), RAM: N(63.4), Disk: N(38)}},
		Processes: []Process{{Job: "backend", Instance: "app-1:9090", RSS: N(312 << 20), CPU: N(38)}},
		BackendUp: N(1), BackendTargets: N(1), BotPlayUp: N(1), BotPlayTargets: N(1),
	}
}

func TestStatusText(t *testing.T) {
	st := Status{
		Snapshot:    sampleSnapshot(),
		RoomsByGame: []KV{{"ludo", 301}, {"snakes_ladders", 118}}, RoomsOK: true,
		LobbyHuman: N(12), LobbyBot: N(0), StartedHumanOnly: N(380), StartedWithBots: N(40),
		Finished: N(410), NewAccounts: N(35), DAU: N(2300),
		Firing: []FiringAlert{{Name: "HostCPUHigh", Severity: "warning", Count: 1, Instances: []string{"app-1:9100"}}},
	}
	got := StatusText(st, meta)
	want := `<b>Ludo Royale · production</b> — hourly status
Wed 21 Oct 2026, 17:00 IST

<b>Playing now</b>
Real players 1,234 · Bots 456
Rooms in game 419 (Ludo 301 · Snakes &amp; Ladders 118)
Waiting in lobby: real 12 · bots 0

<b>Online</b>
Real players 1,502 · Bots 470

<b>Last hour</b>
Matches started 420 (human-only 380 · with bots 40)
Matches finished 410
New accounts 35 · DAU 2,300

<b>Servers</b>
app-1:9100: CPU 41% · RAM 63% · Disk 38%
backend app-1:9090: RSS 312 MiB · CPU 38%
Targets up: backend 1/1 · bot-play 1/1

<b>Alerts firing</b>
warning HostCPUHigh (app-1:9100)`
	if got != want {
		t.Errorf("StatusText mismatch\n--- got ---\n%s\n--- want ---\n%s", got, want)
	}
	if c := StatusCaption(st, meta); c != "production · Playing: 1,234 players · 456 bots · CPU 41% · RAM 63%" {
		t.Errorf("caption = %q", c)
	}
}

func TestAlertTextEscapesAndEnriches(t *testing.T) {
	alerts := []alertmanager.Alert{
		{Status: "resolved", Labels: map[string]string{"alertname": "HostRAMHigh", "severity": "warning", "instance": "app-1:9100"},
			Annotations: map[string]string{"summary": "RAM high"}, StartsAt: fixedAt.Add(-40 * time.Minute), EndsAt: fixedAt.Add(-15 * time.Minute)},
		{Status: "firing", Labels: map[string]string{"alertname": "HTTP5xxHigh", "severity": "critical", "instance": "<b1>&co"},
			Annotations: map[string]string{"summary": `5xx > 2% on "api"`, "description": "Check <logs> & dashboards."},
			StartsAt:    fixedAt.Add(-12 * time.Minute)},
	}
	got := AlertText(alerts, sampleSnapshot(), meta, fixedAt)
	want := `🔴 <b>FIRING</b> · critical · HTTP5xxHigh
<b>5xx &gt; 2% on &quot;api&quot;</b>
&lt;b1&gt;&amp;co · since 16:48 IST (12m)
Check &lt;logs&gt; &amp; dashboards.

✅ <b>RESOLVED</b> · HostRAMHigh
<b>RAM high</b>
app-1:9100 · lasted 25m

<b>Now</b> CPU 41% · RAM 63%
Playing: real 1,234 · bots 456 · online real 1,502 · bots 470
<i>production · 17:00 IST</i>`
	if got != want {
		t.Errorf("AlertText mismatch\n--- got ---\n%s\n--- want ---\n%s", got, want)
	}
	if c := AlertCaption(alerts, meta, fixedAt); c != "production · FIRING: HTTP5xxHigh · RESOLVED: HostRAMHigh · 17:00 IST" {
		t.Errorf("caption = %q", c)
	}
}

func TestAlertTextLimitsAndHosts(t *testing.T) {
	var alerts []alertmanager.Alert
	for i := 0; i < MaxAlertsPerMessage+3; i++ {
		alerts = append(alerts, alertmanager.Alert{Status: "firing", Labels: map[string]string{"alertname": fmt.Sprintf("A%d", i)}})
	}
	snap := sampleSnapshot()
	snap.Hosts = append(snap.Hosts, Host{Instance: "app-2:9100", CPU: N(90), RAM: N(20)})
	got := AlertText(alerts, snap, meta, fixedAt)
	if !strings.Contains(got, "… and 3 more") || strings.Count(got, "FIRING") != MaxAlertsPerMessage {
		t.Errorf("limit not applied:\n%s", got)
	}
	if !strings.Contains(got, "app-1:9100 CPU 41% RAM 63% · app-2:9100 CPU 90% RAM 20%") {
		t.Errorf("per-host usage missing:\n%s", got)
	}
	if !strings.Contains(got, "🟠 <b>FIRING</b> · warning · A0") {
		t.Errorf("default severity should be warning:\n%s", got)
	}
}

func TestGoogleSections(t *testing.T) {
	tests := []struct {
		name string
		got  string
		want []string
	}{
		{"play not configured", PlayText(PlaySection{}), []string{"not configured (set PLAY_REPORTS_BUCKET)"}},
		{"play error escaped", PlayText(PlaySection{Configured: true, Err: "403 <forbidden>"}), []string{"unavailable: 403 &lt;forbidden&gt;"}},
		{"play no rows", PlayText(PlaySection{Configured: true}), []string{"no report rows yet"}},
		{"play latest", PlayText(PlaySection{Configured: true, Report: google.PlayReport{Days: []google.PlayDay{
			{Date: time.Date(2026, 10, 18, 0, 0, 0, 0, time.UTC), Values: map[string]float64{google.ColDailyUserInstalls: 1}},
			{Date: time.Date(2026, 10, 19, 0, 0, 0, 0, time.UTC), Values: map[string]float64{google.ColDailyUserInstalls: 1234, google.ColDailyUserUninstalls: 56}},
		}}}), []string{"latest day 2026-10-19", "User installs 1,234", "User uninstalls 56"}},
		{"ga4 not configured", GA4Text(GA4Section{}), []string{"not configured (set GA4_PROPERTY_ID)"}},
		{"ga4 values", GA4Text(GA4Section{Configured: true, Summary: google.GA4Summary{
			Date:      time.Date(2026, 10, 20, 0, 0, 0, 0, time.UTC),
			Platforms: []google.GA4Platform{{Platform: "Android", FirstOpens: 170, ActiveUsers: 2100}, {Platform: "iOS", FirstOpens: 29, ActiveUsers: 380}},
			Totals:    google.GA4Platform{FirstOpens: 199, AppRemoves: 31, ActiveUsers: 2480, NewUsers: 188},
		}}), []string{"(2026-10-20)", "Installs (first_open) 199 (Android 170 · iOS 29)", "Uninstalls (app_remove, Android) 31", "Active users 2,480 (Android 2,100 · iOS 380)", "New users 188"}},
	}
	for _, tt := range tests {
		for _, w := range tt.want {
			if !strings.Contains(tt.got, w) {
				t.Errorf("%s: %q lacks %q", tt.name, tt.got, w)
			}
		}
	}
}
