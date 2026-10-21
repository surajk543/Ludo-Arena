package tests

import (
	"context"
	"encoding/json"
	"strings"
	"testing"
	"time"

	"ludoroyale/internal/rooms"
)

// outgoingUIDs returns the uids of GET /friends "outgoing", in order.
func outgoingUIDs(t *testing.T, r resp) []string {
	t.Helper()
	var out []string
	for _, x := range r.Body["outgoing"].([]any) {
		out = append(out, x.(map[string]any)["uid"].(string))
	}
	return out
}

// "Add friend" on a bot looks like a request to a person who never answers:
// 201 outgoing with the bot's profile, listed under outgoing, idempotent,
// cancellable, never accepted, and it lapses after 72 h.
func TestFriendRequestToBotStaysPendingThenLapses(t *testing.T) {
	e := newEnv(t, envOpts{dice: rooms.NewSeededDice(11), botPictureShare: "1"})
	ctx := context.Background()
	human := e.guest()
	_, _, bots := e.practiceWithBots(t, human, []string{"Rizky", "Layla"})
	friend := e.guest()
	if r := e.friendRequest(human, friend.UID); r.Status != 201 {
		t.Fatalf("request to a person: %d %s", r.Status, r.Raw)
	}

	r := e.friendRequest(human, strings.ToUpper(bots[0].UID))
	f, _ := r.Body["friend"].(map[string]any)
	if r.Status != 201 || f["uid"] != bots[0].UID || f["name"] != bots[0].Name || num(f["avatar"]) != int64(bots[0].Avatar) ||
		bots[0].PictureID == "" || pictureID(f["picture"]) != bots[0].PictureID ||
		num(f["level"]) < 1 || f["status"] != "outgoing" || f["online"] != false {
		t.Fatalf("request to a bot: %d %s", r.Status, r.Raw)
	}
	if again := e.friendRequest(human, bots[0].UID); again.Status != 201 || again.Body["friend"].(map[string]any)["status"] != "outgoing" {
		t.Fatalf("repeat: %d %s", again.Status, again.Raw)
	}
	time.Sleep(5 * time.Millisecond) // distinct sent times for the order check
	if r := e.friendRequest(human, bots[1].UID); r.Status != 201 {
		t.Fatalf("request to the second bot: %d %s", r.Status, r.Raw)
	}
	// Outgoing, newest first, people and bots together.
	if got := outgoingUIDs(t, e.friends(t, human)); strings.Join(got, ",") != bots[1].UID+","+bots[0].UID+","+friend.UID {
		t.Fatalf("outgoing: %v", got)
	}
	// A bot never answers: there is nothing to accept from it.
	if r := e.do("POST", "/api/v1/friends/requests/"+bots[0].UID+"/accept", human.Token, nil); r.Status != 404 || errCode(r) != "not_found" {
		t.Fatalf("accept from a bot: %d %s", r.Status, r.Raw)
	}

	// Cancel like any request (204), then cancelling again is a no-op.
	for i := 0; i < 2; i++ {
		if r := e.do("DELETE", "/api/v1/friends/"+bots[1].UID, human.Token, nil); r.Status != 204 {
			t.Fatalf("cancel #%d: %d %s", i, r.Status, r.Raw)
		}
	}
	if got := outgoingUIDs(t, e.friends(t, human)); strings.Join(got, ",") != bots[0].UID+","+friend.UID {
		t.Fatalf("outgoing after cancel: %v", got)
	}

	// The request lapses after 72 h: age it in Redis.
	key := "botfr:" + human.UserID
	raw, err := e.rdb.HGet(ctx, key, bots[0].UID).Result()
	if err != nil {
		t.Fatal(err)
	}
	if ttl := e.rdb.TTL(ctx, key).Val(); ttl <= 71*time.Hour || ttl > 72*time.Hour {
		t.Fatalf("botfr TTL = %v", ttl)
	}
	var entry map[string]any
	if err := json.Unmarshal([]byte(raw), &entry); err != nil {
		t.Fatal(err)
	}
	entry["at"] = time.Now().Add(-73 * time.Hour).UnixMilli()
	aged, _ := json.Marshal(entry)
	if err := e.rdb.HSet(ctx, key, bots[0].UID, aged).Err(); err != nil {
		t.Fatal(err)
	}
	if got := outgoingUIDs(t, e.friends(t, human)); strings.Join(got, ",") != friend.UID {
		t.Fatalf("outgoing after 72 h: %v", got)
	}
	if n, _ := e.rdb.HExists(ctx, key, bots[0].UID).Result(); n {
		t.Fatal("the lapsed request was not pruned")
	}
	// Sending again after it lapsed is a new request.
	if r := e.friendRequest(human, bots[0].UID); r.Status != 201 || r.Body["friend"].(map[string]any)["status"] != "outgoing" {
		t.Fatalf("request after lapse: %d %s", r.Status, r.Raw)
	}

	// Someone who never saw the bot (and once its session is gone) gets the
	// unknown-code answer, as for a mistyped code.
	stranger := e.guest()
	if err := e.rdb.Del(ctx, "botsess:"+bots[0].UID, "botsess:"+bots[1].UID).Err(); err != nil {
		t.Fatal(err)
	}
	if r := e.friendRequest(stranger, bots[0].UID); r.Status != 404 || errCode(r) != "not_found" {
		t.Fatalf("stranger: %d %s", r.Status, r.Raw)
	}
	// The human still sees the bot in their room (bot-play ends a bot's
	// session when it leaves, the seat stays).
	if r := e.friendRequest(human, bots[1].UID); r.Status != 201 {
		t.Fatalf("request from the room after the session ended: %d %s", r.Status, r.Raw)
	}
}
