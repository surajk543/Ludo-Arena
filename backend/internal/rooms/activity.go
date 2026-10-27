package rooms

import (
	"context"
	"encoding/json"
	"errors"
	"strconv"
	"strings"

	"github.com/redis/go-redis/v9"
)

// What online people are doing, for the operator API
// (GET /api/v1/admin/ops/online; package opsstats).
const (
	ActivityLudo    = GameLudo   // seated, not forfeited, in a Ludo room that is playing
	ActivitySnakes  = GameSnakes // the same for Snakes & Ladders
	ActivityWaiting = "waiting"  // seated in a room still in its lobby
	ActivityLobby   = "lobby"    // in no live room (menus, rematch window, forfeited)
)

// Activity is what one user is doing. Game and Mode are set for the playing
// and waiting activities only.
type Activity struct {
	Kind string
	Game string
	Mode string
}

// activityBatch bounds the commands per pipeline.
const activityBatch = 512

// seatsView is the part of a room state Activities reads.
type seatsView struct {
	Status  string `json:"status"`
	Game    string `json:"game"`
	Mode    string `json:"mode"`
	Players []struct {
		UserID    string `json:"userId"`
		Bot       bool   `json:"bot"`
		Forfeited bool   `json:"forfeited"`
	} `json:"players"`
}

// Activities resolves, read-only, what each user is doing (same order as
// userIDs). It reads the users' room pointers and the rooms' live-index
// entries (pipelined), plus the state of each playing room that still has a
// non-forfeited person: a player who forfeited by missed turns keeps the
// pointer until leaving, and is reported as lobby. Lobby seats need no state
// read (leaving a lobby clears the pointer in the same commit).
func Activities(ctx context.Context, rdb *redis.Client, userIDs []string) ([]Activity, error) {
	out := make([]Activity, len(userIDs))
	roomOf := make([]string, len(userIDs))
	for start := 0; start < len(userIDs); start += activityBatch {
		ids := userIDs[start:min(start+activityBatch, len(userIDs))]
		pipe := rdb.Pipeline()
		cmds := make([]*redis.StringCmd, len(ids))
		for i, id := range ids {
			cmds[i] = pipe.Get(ctx, userRoomKey(id))
		}
		if _, err := pipe.Exec(ctx); err != nil && !errors.Is(err, redis.Nil) {
			return nil, err
		}
		for i, c := range cmds {
			roomOf[start+i], _ = c.Result()
		}
	}
	var roomIDs []string
	seen := map[string]bool{}
	for _, id := range roomOf {
		if id != "" && !seen[id] {
			seen[id] = true
			roomIDs = append(roomIDs, id)
		}
	}
	entries := make(map[string][]string, len(roomIDs)) // room id -> {status, game, mode, humans}
	var playing []string
	for start := 0; start < len(roomIDs); start += activityBatch {
		ids := roomIDs[start:min(start+activityBatch, len(roomIDs))]
		vals, err := rdb.HMGet(ctx, liveRoomsKey, ids...).Result()
		if err != nil {
			return nil, err
		}
		for i, v := range vals {
			s, _ := v.(string)
			// "{rev}|{status}|{game}|{mode}|{humans}|{bots}" (stats.go).
			f := strings.Split(s, "|")
			if len(f) != 6 {
				continue // not live (finished, closed or gone)
			}
			entries[ids[i]] = f[1:5]
			if humans, _ := strconv.Atoi(f[4]); f[1] == StatusPlaying && humans > 0 {
				playing = append(playing, ids[i])
			}
		}
	}
	// Non-forfeited people per playing room, from the room state itself.
	seated := make(map[string]map[string]bool, len(playing))
	states := make(map[string]seatsView, len(playing))
	for start := 0; start < len(playing); start += activityBatch {
		ids := playing[start:min(start+activityBatch, len(playing))]
		pipe := rdb.Pipeline()
		cmds := make([]*redis.StringCmd, len(ids))
		for i, id := range ids {
			cmds[i] = pipe.HGet(ctx, roomKey(id), "s")
		}
		if _, err := pipe.Exec(ctx); err != nil && !errors.Is(err, redis.Nil) {
			return nil, err
		}
		for i, c := range cmds {
			raw, err := c.Bytes()
			var v seatsView
			if err != nil || json.Unmarshal(raw, &v) != nil {
				continue // the room is gone: its people are in no live room
			}
			states[ids[i]] = v
			in := map[string]bool{}
			for _, p := range v.Players {
				if !p.Bot && !p.Forfeited {
					in[p.UserID] = true
				}
			}
			seated[ids[i]] = in
		}
	}
	for i, uid := range userIDs {
		out[i] = Activity{Kind: ActivityLobby}
		f, ok := entries[roomOf[i]]
		if !ok {
			continue
		}
		switch f[0] {
		case StatusLobby:
			out[i] = Activity{Kind: ActivityWaiting, Game: f[1], Mode: f[2]}
		case StatusPlaying:
			v, ok := states[roomOf[i]]
			if !ok || !seated[roomOf[i]][uid] {
				continue
			}
			switch {
			case v.Status == StatusPlaying && (v.Game == GameLudo || v.Game == GameSnakes):
				out[i] = Activity{Kind: v.Game, Game: v.Game, Mode: v.Mode}
			case v.Status == StatusLobby: // a newer commit than the index entry read
				out[i] = Activity{Kind: ActivityWaiting, Game: v.Game, Mode: v.Mode}
			}
		}
	}
	return out, nil
}
