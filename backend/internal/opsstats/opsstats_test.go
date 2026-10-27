package opsstats

import (
	"encoding/json"
	"errors"
	"net/http"
	"slices"
	"strings"
	"testing"
	"time"

	"ludoarena/internal/httpapi"
	"ludoarena/internal/rooms"
)

func at(s string) time.Time {
	t, err := time.Parse(time.RFC3339, s)
	if err != nil {
		panic(err)
	}
	return t
}

func TestHourSpans(t *testing.T) {
	for _, c := range []struct {
		name     string
		from, to string
		want     []span
	}{
		{"inside one hour", "2026-10-27T14:10:00Z", "2026-10-27T14:20:30Z",
			[]span{{at("2026-10-27T14:00:00Z"), 630_000}}},
		{"ends on the hour", "2026-10-27T14:50:00Z", "2026-10-27T15:00:00Z",
			[]span{{at("2026-10-27T14:00:00Z"), 600_000}}},
		{"crosses an hour", "2026-10-27T14:50:00Z", "2026-10-27T15:10:00Z",
			[]span{{at("2026-10-27T14:00:00Z"), 600_000}, {at("2026-10-27T15:00:00Z"), 600_000}}},
		{"crosses midnight and two hours", "2026-10-26T23:59:59Z", "2026-10-27T01:00:01Z",
			[]span{{at("2026-10-26T23:00:00Z"), 1_000}, {at("2026-10-27T00:00:00Z"), 3_600_000},
				{at("2026-10-27T01:00:00Z"), 1_000}}},
		{"empty", "2026-10-27T14:10:00Z", "2026-10-27T14:10:00Z", nil},
		{"reversed", "2026-10-27T14:10:00Z", "2026-10-27T14:00:00Z", nil},
	} {
		t.Run(c.name, func(t *testing.T) {
			got := hourSpans(at(c.from), at(c.to))
			if len(got) != len(c.want) {
				t.Fatalf("spans = %v, want %v", got, c.want)
			}
			for i := range got {
				if !got[i].hour.Equal(c.want[i].hour) || got[i].ms != c.want[i].ms {
					t.Fatalf("span %d = %v, want %v", i, got[i], c.want[i])
				}
			}
		})
	}
	// Non-UTC input is bucketed by UTC hour (India is UTC+5:30).
	ist := time.FixedZone("IST", 5*3600+1800)
	got := hourSpans(time.Date(2026, 10, 27, 20, 20, 0, 0, ist), time.Date(2026, 10, 27, 20, 40, 0, 0, ist))
	if len(got) != 2 || !got[0].hour.Equal(at("2026-10-27T14:00:00Z")) || got[0].ms != 600_000 || got[1].ms != 600_000 {
		t.Fatalf("IST spans = %v", got)
	}
}

func TestWindow(t *testing.T) {
	for _, c := range []struct {
		name     string
		to       string
		hours    int
		from     string
		first    string
		weight0  float64
		nBuckets int
	}{
		{"one hour, oldest bucket half inside", "2026-10-27T15:30:00Z", 1, "2026-10-27T14:30:00Z", "2026-10-27T14:00:00Z", 0.5, 2},
		{"one hour on the hour", "2026-10-27T15:00:00Z", 1, "2026-10-27T14:00:00Z", "2026-10-27T14:00:00Z", 1, 1},
		{"a day", "2026-10-27T15:04:05Z", 24, "2026-10-26T15:04:05Z", "2026-10-26T15:00:00Z", 3355.0 / 3600, 25},
		{"a day on the hour", "2026-10-27T15:00:00Z", 24, "2026-10-26T15:00:00Z", "2026-10-26T15:00:00Z", 1, 24},
	} {
		t.Run(c.name, func(t *testing.T) {
			from, b := window(at(c.to), c.hours)
			if !from.Equal(at(c.from)) || len(b) != c.nBuckets || !b[0].hour.Equal(at(c.first)) || b[0].weight != c.weight0 {
				t.Fatalf("window = %v %+v", from, b)
			}
			for i := 1; i < len(b); i++ {
				if b[i].weight != 1 || !b[i].hour.Equal(b[i-1].hour.Add(time.Hour)) {
					t.Fatalf("bucket %d = %+v", i, b[i])
				}
			}
			if last := b[len(b)-1].hour; !last.Before(at(c.to)) || at(c.to).Sub(last) > time.Hour {
				t.Fatalf("newest bucket %v for to %s", last, c.to)
			}
		})
	}
}

func TestSortOnline(t *testing.T) {
	row := func(uid, kind string, since int64) onlineRow {
		return onlineRow{uid: uid, since: since, act: rooms.Activity{Kind: kind}}
	}
	rows := []onlineRow{
		row("u_e", rooms.ActivityLobby, 1), row("u_d", rooms.ActivityWaiting, 5), row("u_c", rooms.ActivitySnakes, 9),
		row("u_b", rooms.ActivityLudo, 7), row("u_a", rooms.ActivityLudo, 7), row("u_z", rooms.ActivityLudo, 3),
		row("u_y", rooms.ActivityLobby, 0),
	}
	sortOnline(rows)
	var got []string
	for _, r := range rows {
		got = append(got, r.uid)
	}
	if want := []string{"u_z", "u_a", "u_b", "u_c", "u_d", "u_y", "u_e"}; !slices.Equal(got, want) {
		t.Fatalf("order = %v, want %v", got, want)
	}
}

func TestSortTop(t *testing.T) {
	rs := []ranked{{uid: "u_c", seconds: 300}, {uid: "u_a", seconds: 300}, {uid: "u_b", seconds: 900}, {uid: "u_d", seconds: 0}}
	sortTop(rs)
	var got []string
	for _, r := range rs {
		got = append(got, r.uid)
	}
	if want := []string{"u_b", "u_a", "u_c", "u_d"}; !slices.Equal(got, want) {
		t.Fatalf("order = %v, want %v", got, want)
	}
}

func TestIntParam(t *testing.T) {
	for _, c := range []struct {
		raw     string
		want    int
		wantErr bool
	}{
		{"", 100, false}, {"1", 1, false}, {"500", 500, false},
		{"0", 0, true}, {"501", 0, true}, {"-3", 0, true}, {"ten", 0, true}, {"1.5", 0, true}, {" 5", 0, true},
	} {
		got, err := intParam(c.raw, "limit", DefaultLimit, 1, MaxLimit)
		var apiErr *httpapi.APIError
		switch {
		case c.wantErr && (!errors.As(err, &apiErr) || apiErr.Status != http.StatusBadRequest || apiErr.Code != "bad_request"):
			t.Errorf("%q: err = %v, want 400 bad_request", c.raw, err)
		case !c.wantErr && (err != nil || got != c.want):
			t.Errorf("%q = %d, %v; want %d", c.raw, got, err, c.want)
		}
	}
}

func TestAccountKeys(t *testing.T) {
	keys := AccountKeys(at("2026-10-27T15:04:05Z"))
	if len(keys) != 1+forgetHours*len(Games) || keys[0] != OnlineKey {
		t.Fatalf("keys = %v", keys)
	}
	for _, want := range []string{"ptg:ludo:2026102715", "ptg:snakes_ladders:2026102715",
		"ptg:ludo:2026102613", "ptg:snakes_ladders:2026102612"} { // 26 and 27 hours back
		if !slices.Contains(keys, want) {
			t.Fatalf("keys miss %s: %v", want, keys)
		}
	}
	if slices.ContainsFunc(keys, func(k string) bool { return strings.HasPrefix(k, "ptg:tot:") }) {
		t.Fatal("aggregate totals are not account data")
	}
}

func TestReportJSON(t *testing.T) {
	created := at("2026-10-01T10:00:00.123456Z")
	game, mode := rooms.GameLudo, rooms.ModePublic
	rep := OnlineReport{At: Stamp(at("2026-10-27T15:04:05.999Z")), Total: 2, Counts: Counts{Ludo: 1, Lobby: 1},
		Users: []OnlineUser{
			{UID: "u_A", UserID: "id-a", Name: "Suraj", CreatedAt: stampOf(&created),
				OnlineSince: Stamp(time.UnixMilli(1_792_000_000_500)), Activity: "ludo", Game: &game, Mode: &mode},
			{UID: "u_B", UserID: "id-b", Name: "Guest", OnlineSince: Stamp(at("2026-10-27T14:00:00Z")), Activity: "lobby"},
		}}
	raw, err := json.Marshal(rep)
	if err != nil {
		t.Fatal(err)
	}
	want := `{"at":"2026-10-27T15:04:05Z","total":2,"counts":{"ludo":1,"snakes_ladders":0,"waiting":0,"lobby":1},` +
		`"users":[{"uid":"u_A","userId":"id-a","name":"Suraj","createdAt":"2026-10-01T10:00:00Z","onlineSince":"2026-10-14T17:46:40Z","activity":"ludo","game":"ludo","mode":"public"},` +
		`{"uid":"u_B","userId":"id-b","name":"Guest","createdAt":null,"onlineSince":"2026-10-27T14:00:00Z","activity":"lobby","game":null,"mode":null}]}`
	if string(raw) != want {
		t.Fatalf("json =\n%s\nwant\n%s", raw, want)
	}
	pt, _ := json.Marshal(GamePlaytime{Game: "snakes_ladders", Hourly: []HourPlaytime{{Hour: Stamp(at("2026-10-27T15:00:00Z"))}},
		Top: []PlayerPlaytime{}})
	if want := `{"game":"snakes_ladders","seconds":0,"players":0,"hourly":[{"hour":"2026-10-27T15:00:00Z","seconds":0}],"top":[]}`; string(pt) != want {
		t.Fatalf("json = %s", pt)
	}
}
