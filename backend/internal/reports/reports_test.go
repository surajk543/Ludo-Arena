package reports

import (
	"context"
	"crypto/sha256"
	"errors"
	"net/http"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/google/uuid"

	"ludoroyale/internal/httpapi"
	"ludoroyale/internal/progression"
	"ludoroyale/internal/progression/progtest"
)

var testNow = time.Date(2026, 10, 21, 12, 0, 0, 0, time.UTC)

func TestValidation(t *testing.T) {
	for _, r := range Reasons {
		if !ValidReason(r) {
			t.Errorf("reason %q rejected", r)
		}
	}
	for _, s := range Statuses {
		if !ValidStatus(s) {
			t.Errorf("status %q rejected", s)
		}
	}
	cases := []struct {
		name string
		in   CreateInput
		ok   bool
	}{
		{"valid", CreateInput{UID: "u_abcdefghijkm", RoomID: "r_3k9x2", Reason: "cheating"}, true},
		{"uid case and spaces", CreateInput{UID: "  U_ABCDEFGHIJKM ", RoomID: "r_3k9x2", Reason: "other"}, true},
		{"bot uid shape", CreateInput{UID: "b_0123456789", RoomID: "r_1", Reason: "other"}, true},
		{"unknown reason", CreateInput{UID: "u_abcdefghijkm", RoomID: "r_1", Reason: "spam"}, false},
		{"reason case", CreateInput{UID: "u_abcdefghijkm", RoomID: "r_1", Reason: "Cheating"}, false},
		{"empty reason", CreateInput{UID: "u_abcdefghijkm", RoomID: "r_1"}, false},
		{"empty uid", CreateInput{RoomID: "r_1", Reason: "other"}, false},
		{"uid symbols", CreateInput{UID: "u_abc;drop", RoomID: "r_1", Reason: "other"}, false},
		{"uid too long", CreateInput{UID: "u_" + strings.Repeat("a", 60), RoomID: "r_1", Reason: "other"}, false},
		{"empty room", CreateInput{UID: "u_abcdefghijkm", Reason: "other"}, false},
		{"room prefix", CreateInput{UID: "u_abcdefghijkm", RoomID: "x_1", Reason: "other"}, false},
		{"room too long", CreateInput{UID: "u_abcdefghijkm", RoomID: "r_" + strings.Repeat("1", 60), Reason: "other"}, false},
	}
	for _, c := range cases {
		in := c.in
		err := in.normalize()
		if (err == nil) != c.ok {
			t.Errorf("%s: err = %v, want ok=%v", c.name, err, c.ok)
		}
		if c.ok && in.UID != strings.ToLower(strings.TrimSpace(c.in.UID)) {
			t.Errorf("%s: uid not normalized: %q", c.name, in.UID)
		}
	}
}

func TestLimitWindow(t *testing.T) {
	a, b, c := uuid.New(), uuid.New(), uuid.New()
	ago := func(d time.Duration) time.Time { return testNow.Add(-d) }
	ms := func(tm time.Time) int64 { return tm.UnixMilli() }

	// Empty window.
	l := limitOf(testNow, 2, nil)
	if l.PerDay != 2 || l.Remaining != 2 || l.ResetsAt != nil {
		t.Fatalf("empty: %+v", l)
	}
	if err := decide(testNow, 2, nil, a); err != nil {
		t.Fatal(err)
	}

	// One report 3 h ago: one left, resets 21 h from now.
	recent := []prior{{a, ago(3 * time.Hour)}}
	l = limitOf(testNow, 2, recent)
	if l.Remaining != 1 || l.ResetsAt == nil || *l.ResetsAt != ms(ago(3*time.Hour).Add(Window)) {
		t.Fatalf("one: %+v", l)
	}
	if err := decide(testNow, 2, recent, a); !errors.Is(err, ErrAlreadyReported) {
		t.Fatalf("duplicate: %v", err)
	}
	if err := decide(testNow, 2, recent, b); err != nil {
		t.Fatalf("second: %v", err)
	}

	// Two reports (unordered input): limit reached, resets when the oldest leaves.
	recent = []prior{{b, ago(time.Hour)}, {a, ago(5 * time.Hour)}}
	err := decide(testNow, 2, recent, c)
	var le *LimitError
	if !errors.As(err, &le) {
		t.Fatalf("third: %v", err)
	}
	if want := ms(ago(5 * time.Hour).Add(Window)); le.Limit.Remaining != 0 || *le.Limit.ResetsAt != want {
		t.Fatalf("limit: %+v want resetsAt %d", le.Limit, want)
	}
	if le.Retry != 19*time.Hour {
		t.Fatalf("retry = %v", le.Retry)
	}
	// The duplicate rule is checked before the limit.
	if err := decide(testNow, 2, recent, a); !errors.Is(err, ErrAlreadyReported) {
		t.Fatalf("duplicate at limit: %v", err)
	}

	// Reports at or beyond 24 h do not count and do not block a new report.
	recent = []prior{{a, ago(Window)}, {b, ago(Window + time.Minute)}}
	if l := limitOf(testNow, 2, recent); l.Remaining != 2 || l.ResetsAt != nil {
		t.Fatalf("expired: %+v", l)
	}
	if err := decide(testNow, 2, recent, a); err != nil {
		t.Fatalf("expired duplicate: %v", err)
	}
	// Just inside the window still counts.
	recent = []prior{{a, ago(Window - time.Millisecond)}}
	if err := decide(testNow, 1, recent, b); !errors.As(err, &le) || le.Retry != time.Millisecond {
		t.Fatalf("edge: %v", err)
	}

	// More reports than the (lowered) limit: a slot frees when enough leave.
	recent = []prior{{a, ago(6 * time.Hour)}, {b, ago(4 * time.Hour)}, {c, ago(2 * time.Hour)}}
	l = limitOf(testNow, 2, recent)
	if l.Remaining != 0 || *l.ResetsAt != ms(ago(4*time.Hour).Add(Window)) {
		t.Fatalf("over limit: %+v", l)
	}
}

func TestAdminAuthorization(t *testing.T) {
	sum := sha256.Sum256([]byte("operator-key"))
	if !adminAuthorized(sum[:], "operator-key") {
		t.Fatal("right key refused")
	}
	for _, k := range []string{"", "operator-key ", "Operator-key", "x"} {
		if adminAuthorized(sum[:], k) {
			t.Fatalf("key %q accepted", k)
		}
	}
	if adminAuthorized(nil, "operator-key") || adminAuthorized(sum[:4], "operator-key") {
		t.Fatal("unconfigured hash accepted")
	}

	if s, n, err := parseAdminQuery("", ""); err != nil || s != "" || n != AdminDefaultLimit {
		t.Fatalf("defaults: %q %d %v", s, n, err)
	}
	if s, n, err := parseAdminQuery("reviewing", "200"); err != nil || s != "reviewing" || n != 200 {
		t.Fatalf("explicit: %q %d %v", s, n, err)
	}
	for _, q := range [][2]string{{"open", ""}, {"", "0"}, {"", "201"}, {"", "ten"}} {
		if _, _, err := parseAdminQuery(q[0], q[1]); err == nil {
			t.Fatalf("query %v accepted", q)
		}
	}
	str := func(s string) *string { return &s }
	for _, p := range []AdminPatch{{}, {Status: str("closed")}, {Note: str(strings.Repeat("n", MaxNoteLength+1))}} {
		if p.validate() == nil {
			t.Fatalf("patch %+v accepted", p)
		}
	}
	for _, p := range []AdminPatch{{Status: str("dismissed")}, {Note: str("")}, {Note: str(strings.Repeat("ü", MaxNoteLength))}} {
		if err := p.validate(); err != nil {
			t.Fatalf("patch %+v: %v", p, err)
		}
	}
}

func TestErrorMapping(t *testing.T) {
	cases := []struct {
		err    error
		status int
		code   string
	}{
		{ErrInvalid, 400, "bad_request"},
		{ErrUnknownPlayer, 404, "not_found"},
		{ErrRoomGone, 404, "room_not_found"},
		{ErrSelf, 422, "cannot_report_self"},
		{ErrBot, 422, "cannot_report_bot"},
		{ErrNotInRoom, 422, "not_in_room"},
		{ErrAlreadyReported, 409, "already_reported"},
		{&LimitError{Retry: time.Hour}, 429, "report_limit"},
	}
	for _, c := range cases {
		var api *httpapi.APIError
		if !errors.As(mapErr(c.err), &api) || api.Status != c.status || api.Code != c.code {
			t.Errorf("%v -> %+v", c.err, api)
		}
	}
	var api *httpapi.APIError
	if errors.As(mapErr(&LimitError{Retry: time.Hour}), &api); api.Retry != time.Hour || api.Status != http.StatusTooManyRequests {
		t.Fatalf("limit retry: %+v", api)
	}
}

// ---------------------------------------------------- PostgreSQL-backed tests

type fixture struct {
	env   *progtest.Env
	svc   *Service
	mu    sync.Mutex
	rooms map[string]RoomInfo
	now   time.Time
}

func newFixture(t *testing.T, perDay int) *fixture {
	t.Helper()
	env := progtest.Setup(t)
	prog, err := progression.New(env.Pool, env.RDB, env.Profiles, &progtest.Notifier{}, env.Log, progression.Options{
		CatalogPath: env.CatalogPath(), MissionsPath: env.MissionsPath()})
	if err != nil {
		t.Fatal(err)
	}
	f := &fixture{env: env, rooms: map[string]RoomInfo{}, now: time.Now().UTC().Truncate(time.Millisecond)}
	lookup := func(_ context.Context, id string) (RoomInfo, error) {
		f.mu.Lock()
		defer f.mu.Unlock()
		r, ok := f.rooms[id]
		if !ok {
			return RoomInfo{}, ErrRoomGone
		}
		return r, nil
	}
	f.svc = New(env.Pool, env.Profiles, prog, lookup, env.Log, Options{PerDay: perDay, Now: func() time.Time {
		f.mu.Lock()
		defer f.mu.Unlock()
		return f.now
	}})
	return f
}

func (f *fixture) room(id string, humans ...uuid.UUID) {
	info := RoomInfo{Game: "ludo"}
	for _, h := range humans {
		info.Seats = append(info.Seats, Seat{UserID: h.String(), UID: f.env.Profiles.PublicID(h)})
	}
	info.Seats = append(info.Seats, Seat{UserID: uuid.NewString(), UID: "b_0123456789", Bot: true})
	f.mu.Lock()
	f.rooms[id] = info
	f.mu.Unlock()
}

func (f *fixture) tick(d time.Duration) {
	f.mu.Lock()
	f.now = f.now.Add(d)
	f.mu.Unlock()
}

func (f *fixture) report(me, target uuid.UUID, room string) error {
	_, _, err := f.svc.Create(context.Background(), me, CreateInput{UID: f.env.Profiles.PublicID(target), RoomID: room, Reason: ReasonCheating})
	return err
}

func TestCreateRulesAndWindow(t *testing.T) {
	f := newFixture(t, 2)
	ctx := context.Background()
	a, b, c, d := f.env.NewAccount(t), f.env.NewAccount(t), f.env.NewAccount(t), f.env.NewAccount(t)
	f.room("r_unit1", a, b, c, d)
	stranger := f.env.NewAccount(t)

	if err := f.report(a, a, "r_unit1"); !errors.Is(err, ErrSelf) {
		t.Fatalf("self: %v", err)
	}
	if _, _, err := f.svc.Create(ctx, a, CreateInput{UID: "b_0123456789", RoomID: "r_unit1", Reason: "other"}); !errors.Is(err, ErrBot) {
		t.Fatalf("bot: %v", err)
	}
	if err := f.report(a, b, "r_gone"); !errors.Is(err, ErrRoomGone) {
		t.Fatalf("room gone: %v", err)
	}
	if err := f.report(stranger, b, "r_unit1"); !errors.Is(err, ErrNotInRoom) {
		t.Fatalf("reporter not seated: %v", err)
	}
	if err := f.report(a, stranger, "r_unit1"); !errors.Is(err, ErrNotInRoom) {
		t.Fatalf("reported not seated: %v", err)
	}
	if _, _, err := f.svc.Create(ctx, a, CreateInput{UID: "u_zzzzzzzzzzzz", RoomID: "r_unit1", Reason: "other"}); !errors.Is(err, ErrUnknownPlayer) {
		t.Fatalf("unknown uid: %v", err)
	}

	rep, lim, err := f.svc.Create(ctx, a, CreateInput{UID: strings.ToUpper(f.env.Profiles.PublicID(b)), RoomID: "r_unit1", Reason: ReasonOffensiveName})
	if err != nil {
		t.Fatal(err)
	}
	if rep.Player.UID != f.env.Profiles.PublicID(b) || rep.Status != StatusSubmitted || rep.Game != "ludo" ||
		rep.RoomID != "r_unit1" || rep.Reason != ReasonOffensiveName || lim.Remaining != 1 || lim.ResetsAt == nil {
		t.Fatalf("created: %+v %+v", rep, lim)
	}
	if err := f.report(a, b, "r_unit1"); !errors.Is(err, ErrAlreadyReported) {
		t.Fatalf("duplicate: %v", err)
	}
	f.tick(time.Second)
	if err := f.report(a, c, "r_unit1"); err != nil {
		t.Fatal(err)
	}
	var le *LimitError
	if err := f.report(a, d, "r_unit1"); !errors.As(err, &le) || le.Limit.Remaining != 0 {
		t.Fatalf("third: %v", err)
	}
	list, lim, err := f.svc.Mine(ctx, a)
	if err != nil || len(list) != 2 || list[0].Player.UID != f.env.Profiles.PublicID(c) || lim.Remaining != 0 {
		t.Fatalf("mine: %+v %+v %v", list, lim, err)
	}

	// 24 h after the first report it leaves the window: one slot frees and
	// the same player can be reported again.
	f.tick(Window - time.Second)
	if err := f.report(a, b, "r_unit1"); err != nil {
		t.Fatalf("after window: %v", err)
	}
	// The window now holds the report of c (1 s younger) and the new one.
	if _, lim, _ := f.svc.Mine(ctx, a); lim.Remaining != 0 || *lim.ResetsAt != f.now.Add(time.Second).UnixMilli() {
		t.Fatalf("after window limit: %+v", lim)
	}
}

func TestConcurrentReportsRespectLimit(t *testing.T) {
	f := newFixture(t, 2)
	me := f.env.NewAccount(t)
	targets := make([]uuid.UUID, 6)
	for i := range targets {
		targets[i] = f.env.NewAccount(t)
	}
	f.room("r_unit2", append([]uuid.UUID{me}, targets...)...)
	var wg sync.WaitGroup
	errs := make(chan error, len(targets))
	for _, tg := range targets {
		wg.Add(1)
		go func(tg uuid.UUID) { defer wg.Done(); errs <- f.report(me, tg, "r_unit2") }(tg)
	}
	wg.Wait()
	close(errs)
	ok, limited := 0, 0
	for err := range errs {
		var le *LimitError
		switch {
		case err == nil:
			ok++
		case errors.As(err, &le):
			limited++
		default:
			t.Fatalf("unexpected: %v", err)
		}
	}
	if ok != 2 || limited != len(targets)-2 {
		t.Fatalf("created %d, limited %d", ok, limited)
	}
}

func TestAdminUpdate(t *testing.T) {
	f := newFixture(t, 2)
	ctx := context.Background()
	a, b := f.env.NewAccount(t), f.env.NewAccount(t)
	f.room("r_unit3", a, b)
	rep, _, err := f.svc.Create(ctx, a, CreateInput{UID: f.env.Profiles.PublicID(b), RoomID: "r_unit3", Reason: ReasonOther})
	if err != nil {
		t.Fatal(err)
	}
	id := uuid.MustParse(rep.ID)
	st, note := StatusReviewing, "looking"
	got, err := f.svc.AdminUpdate(ctx, id, &st, &note)
	if err != nil || got.Status != StatusReviewing || got.Note == nil || *got.Note != "looking" ||
		got.ReportedStats.Total != 1 || got.ReportedStats.Open != 1 || got.Reporter.UID != f.env.Profiles.PublicID(a) {
		t.Fatalf("update: %+v %v", got, err)
	}
	st, empty := StatusDismissed, ""
	if got, err = f.svc.AdminUpdate(ctx, id, &st, &empty); err != nil || got.Note != nil || got.ReportedStats.Open != 0 {
		t.Fatalf("dismiss: %+v %v", got, err)
	}
	if _, err := f.svc.AdminUpdate(ctx, uuid.New(), &st, nil); !errors.Is(err, ErrNotFound) {
		t.Fatalf("unknown id: %v", err)
	}
	mine, _, _ := f.svc.Mine(ctx, a)
	if len(mine) != 1 || mine[0].Status != StatusDismissed {
		t.Fatalf("reporter view: %+v", mine)
	}
}
