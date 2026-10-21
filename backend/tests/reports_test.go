package tests

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"strings"
	"sync"
	"testing"
	"time"

	"ludoroyale/internal/rooms"
)

// Player reports (docs/rest-api.md "Player reports") and the operator API.

const adminKey = "test-admin-key-0123456789abcdef"

func adminHash() string {
	sum := sha256.Sum256([]byte(adminKey))
	return hex.EncodeToString(sum[:])
}

func (e *env) report(token, uid, roomID, reason string) resp {
	e.t.Helper()
	return e.do("POST", "/api/v1/reports", token, map[string]any{"uid": uid, "roomId": roomID, "reason": reason})
}

func limitOf(t *testing.T, r resp) map[string]any {
	t.Helper()
	l, ok := r.Body["limit"].(map[string]any)
	if !ok {
		t.Fatalf("no limit in %s", r.Raw)
	}
	return l
}

func num(v any) int64 { f, _ := v.(float64); return int64(f) }

func TestPlayerReports(t *testing.T) {
	t.Setenv("ADMIN_API_KEY_SHA256", adminHash())
	e := newEnv(t, envOpts{dice: rooms.NewSeededDice(5)})
	cs := startPublic(t, e, "ludo", "quick", 4)
	a, b, c, d := cs[0].acct, cs[1].acct, cs[2].acct, cs[3].acct
	roomID := cs[0].snapshot().ID

	// A reports B: stored with room and game, B's public profile returned.
	r := e.report(a.Token, b.UID, roomID, "cheating")
	if r.Status != 201 {
		t.Fatalf("report: %d %s", r.Status, r.Raw)
	}
	rep := r.Body["report"].(map[string]any)
	player := rep["player"].(map[string]any)
	if player["uid"] != b.UID || player["name"] == "" || num(player["level"]) < 1 || rep["status"] != "submitted" ||
		rep["roomId"] != roomID || rep["game"] != "ludo" || rep["reason"] != "cheating" {
		t.Fatalf("report body: %s", r.Raw)
	}
	if l := limitOf(t, r); num(l["perDay"]) != 2 || num(l["remaining"]) != 1 || l["resetsAt"] == nil {
		t.Fatalf("limit after first: %s", r.Raw)
	}
	firstCreated := num(rep["createdAt"])
	var reporter, reported, room, game, status string
	err := e.app.PG.QueryRow(context.Background(), `SELECT reporter_id::text, reported_id::text, room_id, game, status
		FROM progression.player_reports WHERE id = $1`, rep["id"]).Scan(&reporter, &reported, &room, &game, &status)
	if err != nil || reporter != a.UserID || reported != b.UserID || room != roomID || game != "ludo" || status != "submitted" {
		t.Fatalf("stored row: %v %s %s %s %s %s", err, reporter, reported, room, game, status)
	}

	// GET /reports: own reports with the reported player's profile; no ids or notes.
	g := e.do("GET", "/api/v1/reports", a.Token, nil)
	list, _ := g.Body["reports"].([]any)
	if g.Status != 200 || len(list) != 1 || list[0].(map[string]any)["player"].(map[string]any)["uid"] != b.UID ||
		list[0].(map[string]any)["status"] != "submitted" || num(limitOf(t, g)["remaining"]) != 1 {
		t.Fatalf("my reports: %d %s", g.Status, g.Raw)
	}
	for _, leak := range []string{a.UserID, b.UserID, `"note"`, `"reporter`} {
		if strings.Contains(string(g.Raw), leak) {
			t.Fatalf("my reports leak %q: %s", leak, g.Raw)
		}
	}

	// Second report (another player of the same room): limit used up.
	if r := e.report(a.Token, strings.ToUpper(c.UID), roomID, "abusive_behavior"); r.Status != 201 || num(limitOf(t, r)["remaining"]) != 0 {
		t.Fatalf("second report: %d %s", r.Status, r.Raw)
	}
	// Third: 429 with resetsAt = first report + 24 h and Retry-After.
	r = e.report(a.Token, d.UID, roomID, "other")
	details, _ := r.Body["error"].(map[string]any)["details"].(map[string]any)
	if r.Status != 429 || errCode(r) != "report_limit" || details == nil ||
		num(details["resetsAt"]) != firstCreated+24*time.Hour.Milliseconds() || r.Header.Get("Retry-After") == "" {
		t.Fatalf("third report: %d %s (Retry-After %q)", r.Status, r.Raw, r.Header.Get("Retry-After"))
	}
	// The same player again: duplicate wins over the limit.
	if r := e.report(a.Token, b.UID, roomID, "other"); r.Status != 409 || errCode(r) != "already_reported" {
		t.Fatalf("duplicate: %d %s", r.Status, r.Raw)
	}

	// Validation and seat rules (B has not reported anyone).
	checks := []struct {
		name, token, uid, room, reason string
		status                         int
		code                           string
	}{
		{"self", b.Token, b.UID, roomID, "cheating", 422, "cannot_report_self"},
		{"unknown uid", b.Token, "u_zzzzzzzzzzzz", roomID, "cheating", 404, "not_found"},
		{"room gone", b.Token, c.UID, "r_doesnotexist1", "cheating", 404, "room_not_found"},
		{"unknown reason", b.Token, c.UID, roomID, "spam", 400, "bad_request"},
		{"malformed uid", b.Token, "x", roomID, "cheating", 400, "bad_request"},
		{"malformed room", b.Token, c.UID, "room-1", "cheating", 400, "bad_request"},
	}
	for _, ck := range checks {
		if r := e.report(ck.token, ck.uid, ck.room, ck.reason); r.Status != ck.status || errCode(r) != ck.code {
			t.Fatalf("%s: %d %s", ck.name, r.Status, r.Raw)
		}
	}
	if r := e.do("POST", "/api/v1/reports", b.Token, map[string]any{"uid": c.UID, "roomId": roomID, "reason": "other", "x": 1}); r.Status != 400 {
		t.Fatalf("unknown field: %d %s", r.Status, r.Raw)
	}
	stranger := e.guest()
	if r := e.report(stranger.Token, b.UID, roomID, "cheating"); r.Status != 422 || errCode(r) != "not_in_room" {
		t.Fatalf("reporter not in room: %d %s", r.Status, r.Raw)
	}
	if r := e.report(b.Token, stranger.UID, roomID, "cheating"); r.Status != 422 || errCode(r) != "not_in_room" {
		t.Fatalf("reported not in room: %d %s", r.Status, r.Raw)
	}
	if r := e.do("POST", "/api/v1/reports", "", map[string]any{"uid": c.UID, "roomId": roomID, "reason": "other"}); r.Status != 401 {
		t.Fatalf("unauthenticated: %d", r.Status)
	}

	// Concurrent burst of 5 reports by D: exactly 2 are stored.
	targets := []string{a.UID, b.UID, c.UID, a.UID, b.UID}
	results := make([]resp, len(targets))
	var wg sync.WaitGroup
	for i, uid := range targets {
		wg.Add(1)
		go func(i int, uid string) {
			defer wg.Done()
			results[i] = e.report(d.Token, uid, roomID, "leaving_or_stalling")
		}(i, uid)
	}
	wg.Wait()
	created := 0
	for _, r := range results {
		switch {
		case r.Status == 201:
			created++
		case r.Status == 429 && errCode(r) == "report_limit", r.Status == 409 && errCode(r) == "already_reported":
		default:
			t.Fatalf("burst: %d %s", r.Status, r.Raw)
		}
	}
	var stored int
	if err := e.app.PG.QueryRow(context.Background(), `SELECT count(*) FROM progression.player_reports WHERE reporter_id = $1`,
		d.UserID).Scan(&stored); err != nil || created != 2 || stored != 2 {
		t.Fatalf("burst created %d, stored %d (%v)", created, stored, err)
	}

	// Operator API: 401 without or with a wrong key.
	for _, key := range []string{"", "wrong-key"} {
		var hdr []string
		if key != "" {
			hdr = []string{"X-Admin-Key", key}
		}
		if r := e.do("GET", "/api/v1/admin/reports", "", nil, hdr...); r.Status != 401 || errCode(r) != "unauthorized" {
			t.Fatalf("admin key %q: %d %s", key, r.Status, r.Raw)
		}
	}
	admin := func(method, path string, body any) resp {
		return e.do(method, path, "", body, "X-Admin-Key", adminKey)
	}
	l := admin("GET", "/api/v1/admin/reports?status=submitted&limit=200", nil)
	// The test database persists across runs: only this room's rows are ours.
	all, _ := l.Body["reports"].([]any)
	var aToB map[string]any
	ours := 0
	for i, x := range all {
		row := x.(map[string]any)
		if i > 0 && num(row["createdAt"]) > num(all[i-1].(map[string]any)["createdAt"]) {
			t.Fatalf("admin list not newest first: %s", l.Raw)
		}
		if row["status"] != "submitted" {
			t.Fatalf("status filter ignored: %v", row)
		}
		if row["roomId"] == roomID {
			ours++
		}
		if row["id"] == rep["id"] {
			aToB = row
		}
	}
	if l.Status != 200 || ours != 4 {
		t.Fatalf("admin list: %d, %d rows of this room", l.Status, ours)
	}
	if aToB == nil || aToB["reporter"].(map[string]any)["uid"] != a.UID || aToB["reported"].(map[string]any)["uid"] != b.UID ||
		aToB["reason"] != "cheating" || aToB["roomId"] != roomID || aToB["game"] != "ludo" || aToB["note"] != nil ||
		num(aToB["reportedStats"].(map[string]any)["total"]) < 1 {
		t.Fatalf("admin row: %v", aToB)
	}
	if strings.Contains(string(l.Raw), a.UserID) {
		t.Fatalf("admin list leaks account ids: %s", l.Raw)
	}
	for _, q := range []string{"?status=open", "?limit=0", "?limit=201"} {
		if r := admin("GET", "/api/v1/admin/reports"+q, nil); r.Status != 400 {
			t.Fatalf("admin query %s: %d", q, r.Status)
		}
	}
	u := admin("PATCH", "/api/v1/admin/reports/"+rep["id"].(string), map[string]any{"status": "action_taken", "note": "warned"})
	if u.Status != 200 || u.Body["report"].(map[string]any)["status"] != "action_taken" || u.Body["report"].(map[string]any)["note"] != "warned" {
		t.Fatalf("admin patch: %d %s", u.Status, u.Raw)
	}
	for _, bad := range []struct {
		path string
		body any
		code int
	}{
		{"/api/v1/admin/reports/" + rep["id"].(string), map[string]any{"status": "closed"}, 400},
		{"/api/v1/admin/reports/" + rep["id"].(string), map[string]any{}, 400},
		{"/api/v1/admin/reports/00000000-0000-4000-8000-000000000000", map[string]any{"status": "dismissed"}, 404},
		{"/api/v1/admin/reports/not-a-uuid", map[string]any{"status": "dismissed"}, 404},
	} {
		if r := admin("PATCH", bad.path, bad.body); r.Status != bad.code {
			t.Fatalf("admin patch %s %v: %d %s", bad.path, bad.body, r.Status, r.Raw)
		}
	}
	// The reporter sees the new status, never the note.
	g = e.do("GET", "/api/v1/reports", a.Token, nil)
	if !strings.Contains(string(g.Raw), `"status":"action_taken"`) || strings.Contains(string(g.Raw), "warned") {
		t.Fatalf("reporter after review: %s", g.Raw)
	}
}

func TestAdminReportsDisabledWithoutKey(t *testing.T) {
	t.Setenv("ADMIN_API_KEY_SHA256", "")
	e := newEnv(t, envOpts{})
	for _, r := range []resp{
		e.do("GET", "/api/v1/admin/reports", "", nil, "X-Admin-Key", adminKey),
		e.do("PATCH", "/api/v1/admin/reports/00000000-0000-4000-8000-000000000000", "", map[string]any{"status": "dismissed"}),
	} {
		if r.Status != 404 || errCode(r) != "not_found" {
			t.Fatalf("admin without key: %d %s", r.Status, r.Raw)
		}
	}
}

// spawnNamedBots claims practice assignments as bot-play would, requesting
// the given display names.
func (e *env) spawnNamedBots(t *testing.T, ctl string, names []string) []*client {
	t.Helper()
	var bots []*client
	deadline := time.Now().Add(10 * time.Second)
	for len(bots) < len(names) && time.Now().Before(deadline) {
		r := e.do("GET", "/api/v1/bot/assignments?wait=2", ctl, nil)
		if r.Status != 200 {
			t.Fatalf("assignments: %d %s", r.Status, r.Raw)
		}
		for _, x := range r.Body["assignments"].([]any) {
			id := x.(map[string]any)["id"].(string)
			s := e.do("POST", "/api/v1/bot/sessions", ctl, map[string]any{"assignmentId": id, "name": names[len(bots)], "profile": "balanced"})
			if s.Status != 200 {
				t.Fatalf("bot session: %d %s", s.Status, s.Raw)
			}
			acct := account{Token: s.Body["accessToken"].(string), UID: s.Body["uid"].(string)}
			c, _, err := e.dial("bot"+acct.UID, acct, map[string]string{"X-App-Platform": "bot"})
			if err != nil {
				t.Fatalf("bot dial: %v", err)
			}
			bots = append(bots, c)
		}
	}
	if len(bots) < len(names) {
		t.Fatalf("only %d/%d bots", len(bots), len(names))
	}
	return bots
}

// Bots are marked with bot:true but their names carry no "Bot" label, and
// they cannot be reported.
func TestReportBotSeatAndUnlabelledBotNames(t *testing.T) {
	e := newEnv(t, envOpts{dice: rooms.NewSeededDice(9)})
	ctl := e.botController(t)
	human := e.guest()
	hc := e.mustDial("human", human)
	if m := hc.call("practice.start", map[string]any{"game": "ludo", "variant": "quick", "bots": 2}); m.T != "ack" {
		t.Fatalf("practice.start: %s %s", m.T, m.P)
	}
	e.spawnNamedBots(t, ctl, []string{"Bot Asha", ""})
	waitFor(t, 10*time.Second, "practice start", func() bool { s := hc.snapshot(); return s != nil && s.Status == "playing" })
	s := hc.snapshot()
	var botUIDs, names []string
	for _, p := range s.Players {
		if !p.Bot {
			continue
		}
		botUIDs = append(botUIDs, p.UID)
		names = append(names, p.Name)
		if p.Name == "" || strings.HasPrefix(strings.ToLower(p.Name), "bot") {
			t.Fatalf("bot seat name %q carries a bot label", p.Name)
		}
	}
	if len(botUIDs) != 2 || (names[0] != "Asha" && names[1] != "Asha") {
		t.Fatalf("bot seats: %v %v", botUIDs, names)
	}
	for _, uid := range botUIDs {
		if r := e.report(human.Token, uid, s.ID, "cheating"); r.Status != 422 || errCode(r) != "cannot_report_bot" {
			t.Fatalf("report bot %s: %d %s", uid, r.Status, r.Raw)
		}
	}
	if r := e.do("GET", "/api/v1/reports", human.Token, nil); r.Status != 200 || num(limitOf(t, r)["remaining"]) != 2 {
		t.Fatalf("rejected reports must not count: %d %s", r.Status, r.Raw)
	}
}
