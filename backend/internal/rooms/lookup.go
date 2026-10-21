package rooms

import (
	"context"
	"errors"

	"github.com/redis/go-redis/v9"
)

// ErrNoBotSeat: no live room holds a bot seat with that public id.
var ErrNoBotSeat = errors.New("rooms: no such bot seat")

// FindBotSeat returns the bot seat with public id uid (read-only), for
// features that must treat a bot like any other player (friend requests from
// the in-game player sheet). Bot uids have the people's format, so callers
// try it only after the uid matched no account. It looks in the active room of viewerID (the
// player asking, who sees the bot there) and then in the room of the bot's
// live session record (botsess:{uid}, see claimAssignment), which disappears
// when bot-play ends the session. ErrNoBotSeat when neither holds it.
func FindBotSeat(ctx context.Context, rdb *redis.Client, viewerID, uid string) (Player, error) {
	if uid == "" {
		return Player{}, ErrNoBotSeat
	}
	var roomIDs []string
	if id, err := rdb.Get(ctx, userRoomKey(viewerID)).Result(); err == nil && id != "" {
		roomIDs = append(roomIDs, id)
	} else if err != nil && !errors.Is(err, redis.Nil) {
		return Player{}, err
	}
	if raw, err := rdb.Get(ctx, "botsess:"+uid).Result(); err == nil {
		// Load-test sessions have no room (see botSessionRecord).
		if b, ok := parseBotSession(raw); ok {
			if b.RoomID != "" {
				roomIDs = append(roomIDs, b.RoomID)
			} else if id, err := rdb.Get(ctx, userRoomKey(b.BotID)).Result(); err == nil && id != "" {
				roomIDs = append(roomIDs, id)
			}
		}
	} else if !errors.Is(err, redis.Nil) {
		return Player{}, err
	}
	for i, id := range roomIDs {
		if i > 0 && id == roomIDs[0] {
			continue
		}
		r, err := LoadRoom(ctx, rdb, id)
		if errors.Is(err, ErrRoomGone) {
			continue
		}
		if err != nil {
			return Player{}, err
		}
		for _, p := range r.Players {
			if p.Bot && p.UID == uid {
				return p, nil
			}
		}
	}
	return Player{}, ErrNoBotSeat
}
