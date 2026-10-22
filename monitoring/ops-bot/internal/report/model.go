// Package report gathers the ops bot's data from Prometheus (and the optional
// Google sources) and renders it as compact Telegram text. The PDF renderer
// (package pdfreport) consumes the same structures.
package report

import (
	"time"

	"ludoarena/opsbot/internal/google"
	"ludoarena/opsbot/internal/promapi"
)

// Num is a value that may be missing ("n/a").
type Num struct {
	V  float64
	OK bool
}

// N returns a present value.
func N(v float64) Num { return Num{V: v, OK: true} }

// KV is a labelled value.
type KV struct {
	Key string
	V   float64
}

// Host is one machine's resource usage (node_exporter).
type Host struct {
	Instance       string
	CPU, RAM, Disk Num
}

// Process is one backend or bot-play process.
type Process struct {
	Job, Instance string
	RSS, CPU      Num // bytes, % of one core
}

// Snapshot is "right now": players and resource usage. It is attached to
// every alert and opens the hourly status.
type Snapshot struct {
	At                        time.Time
	PlayingHuman, PlayingBot  Num
	OnlineHuman, OnlineBot    Num
	Hosts                     []Host
	Processes                 []Process
	BackendUp, BackendTargets Num
	BotPlayUp, BotPlayTargets Num
	Errors                    []string
}

// MaxCPU returns the busiest host's CPU %.
func (s Snapshot) MaxCPU() Num { return maxOf(s.Hosts, func(h Host) Num { return h.CPU }) }

// MaxRAM returns the fullest host's RAM %.
func (s Snapshot) MaxRAM() Num { return maxOf(s.Hosts, func(h Host) Num { return h.RAM }) }

func maxOf(hosts []Host, f func(Host) Num) Num {
	var out Num
	for _, h := range hosts {
		if v := f(h); v.OK && (!out.OK || v.V > out.V) {
			out = v
		}
	}
	return out
}

// FiringAlert summarises one firing alert rule.
type FiringAlert struct {
	Name, Severity string
	Count          int
	Instances      []string
}

// Charts holds time series for the PDF charts (empty when not requested).
type Charts struct {
	Start, End    time.Time
	Players       []promapi.Series // label actor
	CPU, RAM      []promapi.Series // label instance
	MatchesByGame []promapi.Series // label game, one point per hour
}

// Status is the hourly status report.
type Status struct {
	Snapshot
	RoomsByGame                       []KV
	RoomsOK                           bool
	LobbyHuman, LobbyBot              Num
	StartedHumanOnly, StartedWithBots Num
	Finished                          Num
	NewAccounts                       Num
	DAU                               Num
	Firing                            []FiringAlert
	Charts                            Charts
}

// StartedTotal is all non-load-test matches started in the last hour.
func (s Status) StartedTotal() Num { return add(s.StartedHumanOnly, s.StartedWithBots) }

// RoomsTotal is all rooms with a running game.
func (s Status) RoomsTotal() Num {
	if !s.RoomsOK {
		return Num{}
	}
	var t float64
	for _, kv := range s.RoomsByGame {
		t += kv.V
	}
	return N(t)
}

func add(a, b Num) Num {
	switch {
	case a.OK && b.OK:
		return N(a.V + b.V)
	case a.OK:
		return a
	default:
		return b
	}
}

// GameModeRow is matches by game and mode for the daily report.
type GameModeRow struct {
	Game, Mode         string
	Started, Completed float64
}

// DayValue is one day's value in a trend.
type DayValue struct {
	Day time.Time // civil date at 00:00 UTC
	V   float64
}

// DaySeries is a named daily trend.
type DaySeries struct {
	Name   string
	Values []DayValue
}

// Trends are the daily report's multi-day charts.
type Trends struct {
	Days           int       // requested days
	From, To       time.Time // civil dates covered by the request
	DAU            []DayValue
	MatchesByGame  []DaySeries
	PeakPlayers    []DaySeries // human, bot
	CPUMax, RAMMax []DaySeries // per host
}

// PlaySection is the Google Play installs part of the daily report.
type PlaySection struct {
	Configured bool
	Err        string
	Report     google.PlayReport
}

// GA4Section is the Firebase Analytics (GA4) part of the daily report.
type GA4Section struct {
	Configured bool
	Err        string
	Summary    google.GA4Summary
}

// Digest is the daily KPI report for one local calendar day.
type Digest struct {
	Day, End              time.Time // local midnight start and end
	DAUDay                time.Time // UTC day the DAU estimate covers
	NewAccounts           Num
	NewAccountsByProvider []KV
	Logins                Num
	DAU, WAU              Num
	ByGameMode            []GameModeRow
	Started, Completed    Num
	HumanOnly, WithBots   Num
	Abandons              Num
	AbandonsByReason      []KV
	PeakHuman, PeakBot    Num
	PeakOnlineHuman       Num
	PeakOnlineBot         Num
	WaitAvg, WaitP95      Num
	MatchmakingResults    []KV
	HTTP5xx, HTTPTotal    Num
	Settlement            Num
	SettlementByOp        []KV
	ClientErrors          Num
	PeakHosts             []Host // CPU and RAM hold the day's maximum
	AlertsFired           []FiringAlert
	Play                  PlaySection
	GA4                   GA4Section
	Trends                Trends
	Errors                []string
}
