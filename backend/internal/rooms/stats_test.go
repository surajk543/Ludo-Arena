package rooms

import (
	"strings"
	"testing"

	"ludoarena/internal/metrics"
)

func players(spec string) []Player {
	// h = human, b = bot, H / B = forfeited human / bot.
	var out []Player
	for _, c := range spec {
		out = append(out, Player{Bot: c == 'b' || c == 'B', Forfeited: c == 'H' || c == 'B'})
	}
	return out
}

func TestLiveEntry(t *testing.T) {
	cases := []struct {
		name               string
		status, game, mode string
		seats              string
		wantOp, wantSum    string
	}{
		{"public lobby", StatusLobby, GameLudo, ModePublic, "h", "set", "lobby|ludo|public|1|0"},
		{"practice lobby with bots", StatusLobby, GameLudo, ModePractice, "hbb", "set", "lobby|ludo|practice|1|2"},
		{"playing", StatusPlaying, GameSnakes, ModePublic, "hhh", "set", "playing|snakes_ladders|public|3|0"},
		{"forfeited seats are not counted", StatusPlaying, GameLudo, ModePrivate, "hHbB", "set", "playing|ludo|private|1|1"},
		{"load-test bots only", StatusPlaying, GameLudo, ModePublic, "bb", "set", "playing|ludo|public|0|2"},
		{"finished", StatusFinished, GameLudo, ModePublic, "hh", "del", ""},
		{"closed", StatusClosed, GameSnakes, ModePrivate, "h", "del", ""},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			r := &Room{Status: c.status, Game: c.game, Mode: c.mode, Players: players(c.seats)}
			op, sum := liveEntry(r)
			if op != c.wantOp || sum != c.wantSum {
				t.Fatalf("liveEntry = %q %q, want %q %q", op, sum, c.wantOp, c.wantSum)
			}
		})
	}
}

func TestGameStatsAggregation(t *testing.T) {
	cases := []struct {
		name      string
		summaries []string
		want      GameStats
		rejected  int
	}{
		{name: "empty", want: GameStats{Rooms: map[string]int{}}},
		{
			name: "mixed rooms",
			summaries: []string{
				"playing|ludo|public|2|0",
				"playing|ludo|public|0|2", // load-test bots
				"playing|ludo|practice|1|2",
				"playing|snakes_ladders|private|1|1",
				"lobby|ludo|public|1|1",
				"lobby|snakes_ladders|private|1|0",
				"lobby|ludo|practice|1|0", // waiting for bots
			},
			want: GameStats{
				Playing: ActorCounts{Human: 4, Bot: 5},
				Lobby:   ActorCounts{Human: 3, Bot: 1},
				Rooms:   map[string]int{"ludo:public": 2, "ludo:practice": 1, "snakes_ladders:private": 1},
				Lobbies: 3,
			},
		},
		{
			name:      "playing room whose players all forfeited still counts as a room",
			summaries: []string{"playing|ludo|private|0|0"},
			want:      GameStats{Rooms: map[string]int{"ludo:private": 1}},
		},
		{
			name: "malformed or non-live entries are rejected",
			summaries: []string{
				"finished|ludo|public|2|0", "playing|ludo|public|2", "playing|ludo|public|x|0",
				"playing|ludo|public|1|-1", "", "lobby|ludo|public|1|0|extra",
				"playing|ludo|public|1|1",
			},
			want:     GameStats{Playing: ActorCounts{Human: 1, Bot: 1}, Rooms: map[string]int{"ludo:public": 1}},
			rejected: 6,
		},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			st := GameStats{Rooms: map[string]int{}}
			rejected := 0
			for _, s := range c.summaries {
				if !st.add(s) {
					rejected++
				}
			}
			if rejected != c.rejected {
				t.Fatalf("rejected %d, want %d", rejected, c.rejected)
			}
			if st.Playing != c.want.Playing || st.Lobby != c.want.Lobby || st.Lobbies != c.want.Lobbies {
				t.Fatalf("got playing %+v lobby %+v lobbies %d, want %+v %+v %d",
					st.Playing, st.Lobby, st.Lobbies, c.want.Playing, c.want.Lobby, c.want.Lobbies)
			}
			if len(st.Rooms) != len(c.want.Rooms) {
				t.Fatalf("rooms %v, want %v", st.Rooms, c.want.Rooms)
			}
			for k, n := range c.want.Rooms {
				if st.Rooms[k] != n {
					t.Fatalf("rooms %v, want %v", st.Rooms, c.want.Rooms)
				}
			}
		})
	}
}

// The summary written at commit time is exactly what the recount parses.
func TestLiveEntryRoundTrip(t *testing.T) {
	rooms := []*Room{
		{Status: StatusPlaying, Game: GameLudo, Mode: ModePractice, Players: players("Hbb")},
		{Status: StatusLobby, Game: GameSnakes, Mode: ModePrivate, Players: players("hb")},
		{Status: StatusFinished, Game: GameLudo, Mode: ModePublic, Players: players("hh")},
	}
	st := GameStats{}
	for _, r := range rooms {
		if op, sum := liveEntry(r); op == "set" && !st.add(sum) {
			t.Fatalf("summary %q rejected", sum)
		}
	}
	want := ActorCounts{Human: 0, Bot: 2}
	if st.Playing != want || st.Lobby != (ActorCounts{Human: 1, Bot: 1}) || st.RoomsInGame(GameLudo, ModePractice) != 1 {
		t.Fatalf("round trip: %+v", st)
	}
}

// gauge reads one series from the metrics registry.
func gauge(t *testing.T, name string, labels ...string) float64 {
	t.Helper()
	mfs, err := metrics.Registry.Gather()
	if err != nil {
		t.Fatal(err)
	}
	want := strings.Join(labels, ",")
	for _, mf := range mfs {
		if mf.GetName() != name {
			continue
		}
		for _, m := range mf.GetMetric() {
			var got []string
			for _, l := range m.GetLabel() {
				got = append(got, l.GetName()+"="+l.GetValue())
			}
			if strings.Join(got, ",") == want {
				return m.GetGauge().GetValue()
			}
		}
	}
	t.Fatalf("series %s{%s} not found", name, want)
	return 0
}

func TestPublishGameStats(t *testing.T) {
	publishGameStats(GameStats{
		At:      1_700_000_000_500,
		Playing: ActorCounts{Human: 7, Bot: 3},
		Lobby:   ActorCounts{Human: 2, Bot: 1},
		Rooms:   map[string]int{"ludo:public": 4, "snakes_ladders:practice": 1, "chess:public": 9},
	})
	checks := []struct {
		name   string
		labels []string
		want   float64
	}{
		{"players_in_game", []string{"actor=human"}, 7},
		{"players_in_game", []string{"actor=bot"}, 3},
		{"players_in_lobby", []string{"actor=human"}, 2},
		{"players_in_lobby", []string{"actor=bot"}, 1},
		{"rooms_in_game", []string{"game=ludo", "mode=public"}, 4},
		{"rooms_in_game", []string{"game=snakes_ladders", "mode=practice"}, 1},
		{"rooms_in_game", []string{"game=ludo", "mode=private"}, 0}, // zero series are exported
		{"rooms_in_game", []string{"game=snakes_ladders", "mode=public"}, 0},
		{"game_stats_refreshed_timestamp_seconds", nil, 1_700_000_000.5},
	}
	for _, c := range checks {
		if got := gauge(t, c.name, c.labels...); got != c.want {
			t.Errorf("%s%v = %v, want %v", c.name, c.labels, got, c.want)
		}
	}
	// Unknown games or modes never create new label values (bounded labels).
	mfs, _ := metrics.Registry.Gather()
	for _, mf := range mfs {
		if mf.GetName() == "rooms_in_game" && len(mf.GetMetric()) != 6 {
			t.Fatalf("rooms_in_game has %d series, want 6", len(mf.GetMetric()))
		}
	}
	// A later recount with fewer rooms resets the counts to zero.
	publishGameStats(GameStats{At: 1_700_000_015_000})
	if got := gauge(t, "rooms_in_game", "game=ludo", "mode=public"); got != 0 {
		t.Fatalf("rooms_in_game after drop = %v", got)
	}
	if got := gauge(t, "players_in_game", "actor=human"); got != 0 {
		t.Fatalf("players_in_game after drop = %v", got)
	}
}
