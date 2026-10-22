package telegram

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"
	"unicode/utf8"
)

const testToken = "123456:ABCdefGHIjklMNOpqrSTUvwxYZ0123456789"

// sleeps records every sleep requested by the client.
type sleeps struct {
	mu sync.Mutex
	d  []time.Duration
}

func (s *sleeps) sleep(ctx context.Context, d time.Duration) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.d = append(s.d, d)
	return ctx.Err()
}

func (s *sleeps) all() []time.Duration {
	s.mu.Lock()
	defer s.mu.Unlock()
	return append([]time.Duration(nil), s.d...)
}

// request is what the fake Bot API saw.
type request struct {
	Path        string
	ContentType string
	Body        []byte
}

// fakeAPI answers each call with the next canned (status, body) pair; the
// last pair repeats.
type fakeAPI struct {
	mu      sync.Mutex
	answers [][2]any
	reqs    []request
}

func (f *fakeAPI) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	body, _ := io.ReadAll(r.Body)
	f.mu.Lock()
	f.reqs = append(f.reqs, request{Path: r.URL.Path, ContentType: r.Header.Get("Content-Type"), Body: body})
	i := min(len(f.reqs)-1, len(f.answers)-1)
	ans := f.answers[i]
	f.mu.Unlock()
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(ans[0].(int))
	_, _ = io.WriteString(w, ans[1].(string))
}

func (f *fakeAPI) requests() []request {
	f.mu.Lock()
	defer f.mu.Unlock()
	return append([]request(nil), f.reqs...)
}

const okBody = `{"ok":true,"result":{"message_id":1}}`

func newTest(t *testing.T, answers ...[2]any) (*Client, *fakeAPI, *sleeps) {
	t.Helper()
	if len(answers) == 0 {
		answers = [][2]any{{200, okBody}}
	}
	api := &fakeAPI{answers: answers}
	srv := httptest.NewServer(api)
	t.Cleanup(srv.Close)
	sl := &sleeps{}
	c := New(Config{BaseURL: srv.URL, Token: testToken, MinGap: -1, Sleep: sl.sleep,
		Logger: slog.New(slog.NewTextHandler(io.Discard, nil))})
	return c, api, sl
}

func decodeJSON(t *testing.T, b []byte) map[string]any {
	t.Helper()
	d := json.NewDecoder(bytes.NewReader(b))
	d.UseNumber()
	var m map[string]any
	if err := d.Decode(&m); err != nil {
		t.Fatalf("decode %q: %v", b, err)
	}
	return m
}

func TestSendMessageSuccess(t *testing.T) {
	tests := []struct {
		name   string
		chatID string
		want   any
	}{
		{"numeric group id", "-1001234567890", json.Number("-1001234567890")},
		{"channel name", "@ludo_ops", "@ludo_ops"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			c, api, sl := newTest(t)
			if err := c.SendMessage(context.Background(), tt.chatID, "<b>hi</b>"); err != nil {
				t.Fatal(err)
			}
			reqs := api.requests()
			if len(reqs) != 1 {
				t.Fatalf("requests = %d, want 1", len(reqs))
			}
			if reqs[0].Path != "/bot"+testToken+"/sendMessage" {
				t.Errorf("path = %q", reqs[0].Path)
			}
			if !strings.HasPrefix(reqs[0].ContentType, "application/json") {
				t.Errorf("content type = %q", reqs[0].ContentType)
			}
			m := decodeJSON(t, reqs[0].Body)
			if m["chat_id"] != tt.want {
				t.Errorf("chat_id = %#v, want %#v", m["chat_id"], tt.want)
			}
			if m["parse_mode"] != "HTML" || m["text"] != "<b>hi</b>" {
				t.Errorf("body = %v", m)
			}
			if lp, _ := m["link_preview_options"].(map[string]any); lp["is_disabled"] != true {
				t.Errorf("link preview not disabled: %v", m)
			}
			if len(sl.all()) != 0 {
				t.Errorf("unexpected sleeps %v", sl.all())
			}
		})
	}
}

func TestSendMessageRetries(t *testing.T) {
	tests := []struct {
		name       string
		answers    [][2]any
		wantErr    bool
		wantReqs   int
		wantSleeps []time.Duration
	}{
		{
			name: "429 retry_after",
			answers: [][2]any{
				{429, `{"ok":false,"error_code":429,"description":"Too Many Requests: retry after 2","parameters":{"retry_after":2}}`},
				{200, okBody},
			},
			wantReqs: 2, wantSleeps: []time.Duration{2 * time.Second},
		},
		{
			name: "429 retry_after capped",
			answers: [][2]any{
				{429, `{"ok":false,"error_code":429,"description":"Too Many Requests","parameters":{"retry_after":900}}`},
				{200, okBody},
			},
			wantReqs: 2, wantSleeps: []time.Duration{maxRetryAfter},
		},
		{
			name:     "5xx backoff",
			answers:  [][2]any{{502, `bad gateway`}, {500, `{"ok":false,"error_code":500,"description":"Internal"}`}, {200, okBody}},
			wantReqs: 3, wantSleeps: []time.Duration{time.Second, 2 * time.Second},
		},
		{
			name:     "400 not retried",
			answers:  [][2]any{{400, `{"ok":false,"error_code":400,"description":"Bad Request: chat not found"}`}},
			wantErr:  true,
			wantReqs: 1,
		},
		{
			name:     "gives up after max retries",
			answers:  [][2]any{{503, `{"ok":false,"error_code":503,"description":"Service Unavailable"}`}},
			wantErr:  true,
			wantReqs: 4, wantSleeps: []time.Duration{time.Second, 2 * time.Second, 4 * time.Second},
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			c, api, sl := newTest(t, tt.answers...)
			err := c.SendMessage(context.Background(), "42", "hello")
			if (err != nil) != tt.wantErr {
				t.Fatalf("err = %v, wantErr %v", err, tt.wantErr)
			}
			if err != nil {
				var ae *APIError
				if !errors.As(err, &ae) {
					t.Fatalf("err %T is not *APIError", err)
				}
				if strings.Contains(err.Error(), testToken) {
					t.Errorf("error leaks token: %v", err)
				}
			}
			if got := len(api.requests()); got != tt.wantReqs {
				t.Errorf("requests = %d, want %d", got, tt.wantReqs)
			}
			got := sl.all()
			if len(got) != len(tt.wantSleeps) {
				t.Fatalf("sleeps = %v, want %v", got, tt.wantSleeps)
			}
			for i := range got {
				if got[i] != tt.wantSleeps[i] {
					t.Errorf("sleep[%d] = %v, want %v", i, got[i], tt.wantSleeps[i])
				}
			}
		})
	}
}

func TestSendMessageCancelledDuringRetry(t *testing.T) {
	c, api, _ := newTest(t, [2]any{429, `{"ok":false,"error_code":429,"description":"x","parameters":{"retry_after":5}}`})
	ctx, cancel := context.WithCancel(context.Background())
	c.sleep = func(ctx context.Context, d time.Duration) error { cancel(); return context.Canceled }
	if err := c.SendMessage(ctx, "1", "x"); err == nil {
		t.Fatal("want error")
	}
	if n := len(api.requests()); n != 1 {
		t.Errorf("requests = %d, want 1", n)
	}
}

func TestSendMessagePlainTextFallback(t *testing.T) {
	c, api, _ := newTest(t,
		[2]any{400, `{"ok":false,"error_code":400,"description":"Bad Request: can't parse entities: unsupported start tag"}`},
		[2]any{200, okBody})
	if err := c.SendMessage(context.Background(), "1", "<b>a &lt; b</b> &amp; c &#8212; d"); err != nil {
		t.Fatal(err)
	}
	reqs := api.requests()
	if len(reqs) != 2 {
		t.Fatalf("requests = %d", len(reqs))
	}
	if m := decodeJSON(t, reqs[0].Body); m["parse_mode"] != "HTML" {
		t.Errorf("first attempt not HTML: %v", m)
	}
	m := decodeJSON(t, reqs[1].Body)
	if _, ok := m["parse_mode"]; ok {
		t.Errorf("fallback still has parse_mode: %v", m)
	}
	if m["text"] != "a < b & c — d" {
		t.Errorf("fallback text = %q", m["text"])
	}
}

func TestSendMessageSplitsLongText(t *testing.T) {
	c, api, _ := newTest(t)
	l1, l2 := strings.Repeat("a", 3000), strings.Repeat("é", 3000)
	if err := c.SendMessage(context.Background(), "1", l1+"\n"+l2); err != nil {
		t.Fatal(err)
	}
	reqs := api.requests()
	if len(reqs) != 2 {
		t.Fatalf("messages = %d, want 2", len(reqs))
	}
	for i, want := range []string{l1, l2} {
		if got := decodeJSON(t, reqs[i].Body)["text"]; got != want {
			t.Errorf("part %d has %d runes, want %d", i, utf8.RuneCountInString(got.(string)), utf8.RuneCountInString(want))
		}
	}
}

func TestSplitText(t *testing.T) {
	tests := []struct {
		name  string
		in    string
		limit int
		want  []string
	}{
		{"short", "ab\ncd", 10, []string{"ab\ncd"}},
		{"line boundary", "aaa\nbbb\nccc", 8, []string{"aaa\nbbb", "ccc"}},
		{"hard cut", "abcdefghij", 4, []string{"abcd", "efgh", "ij"}},
		{"hard cut runes", "ééééé\nx", 3, []string{"ééé", "éé", "x"}},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := splitText(tt.in, tt.limit)
			if strings.Join(got, "|") != strings.Join(tt.want, "|") {
				t.Errorf("splitText = %q, want %q", got, tt.want)
			}
			for _, p := range got {
				if utf8.RuneCountInString(p) > tt.limit {
					t.Errorf("part %q exceeds limit", p)
				}
			}
		})
	}
}

// docReq is a parsed sendDocument multipart request.
type docReq struct {
	chatID, caption, parseMode, filename, ctype string
	data                                        []byte
}

func parseDoc(t *testing.T, r request) docReq {
	t.Helper()
	hr, _ := http.NewRequest(http.MethodPost, "/", bytes.NewReader(r.Body))
	hr.Header.Set("Content-Type", r.ContentType)
	if err := hr.ParseMultipartForm(10 << 20); err != nil {
		t.Fatalf("parse multipart: %v", err)
	}
	f, h, err := hr.FormFile("document")
	if err != nil {
		t.Fatalf("document part: %v", err)
	}
	defer f.Close()
	data, _ := io.ReadAll(f)
	return docReq{
		chatID: hr.FormValue("chat_id"), caption: hr.FormValue("caption"), parseMode: hr.FormValue("parse_mode"),
		filename: h.Filename, ctype: h.Header.Get("Content-Type"), data: data,
	}
}

func TestSendDocument(t *testing.T) {
	pdf := append([]byte("%PDF-1.7\n"), bytes.Repeat([]byte{0, 1, 2, 0xff}, 5000)...)
	long := "<b>" + strings.Repeat("x", 2000) + "</b>"
	tests := []struct {
		name      string
		filename  string
		caption   string
		answers   [][2]any
		wantReqs  int
		wantCap   string
		wantMode  string
		wantCtype string
	}{
		{
			name: "pdf with caption", filename: "ludo-arena-status-2026-10-21-1700-IST.pdf", caption: "<b>Playing:</b> 1,234",
			answers: [][2]any{{200, okBody}}, wantReqs: 1, wantCap: "<b>Playing:</b> 1,234", wantMode: "HTML", wantCtype: "application/pdf",
		},
		{
			name: "429 resends full file", filename: "report.pdf", caption: "c",
			answers: [][2]any{
				{429, `{"ok":false,"error_code":429,"description":"Too Many Requests: retry after 1","parameters":{"retry_after":1}}`},
				{200, okBody},
			},
			wantReqs: 2, wantCap: "c", wantMode: "HTML", wantCtype: "application/pdf",
		},
		{
			name: "long caption truncated to plain", filename: "x.bin", caption: long,
			answers: [][2]any{{200, okBody}}, wantReqs: 1, wantCap: strings.Repeat("x", maxCaptionRunes-1) + "…", wantCtype: "application/octet-stream",
		},
		{
			name: "no caption", filename: "a.pdf", answers: [][2]any{{200, okBody}}, wantReqs: 1, wantCtype: "application/pdf",
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			c, api, sl := newTest(t, tt.answers...)
			if err := c.SendDocument(context.Background(), "-100777", tt.filename, pdf, tt.caption); err != nil {
				t.Fatal(err)
			}
			reqs := api.requests()
			if len(reqs) != tt.wantReqs {
				t.Fatalf("requests = %d, want %d", len(reqs), tt.wantReqs)
			}
			for _, r := range reqs {
				if r.Path != "/bot"+testToken+"/sendDocument" {
					t.Errorf("path = %q", r.Path)
				}
				d := parseDoc(t, r)
				if d.chatID != "-100777" || d.filename != tt.filename || d.ctype != tt.wantCtype {
					t.Errorf("doc = chat %q file %q type %q", d.chatID, d.filename, d.ctype)
				}
				if !bytes.Equal(d.data, pdf) {
					t.Errorf("file bytes differ (%d vs %d)", len(d.data), len(pdf))
				}
				if d.caption != tt.wantCap || d.parseMode != tt.wantMode {
					t.Errorf("caption %d runes mode %q, want %d runes mode %q",
						utf8.RuneCountInString(d.caption), d.parseMode, utf8.RuneCountInString(tt.wantCap), tt.wantMode)
				}
			}
			if tt.wantReqs == 2 {
				if got := sl.all(); len(got) != 1 || got[0] != time.Second {
					t.Errorf("sleeps = %v, want [1s]", got)
				}
			}
		})
	}
}

func TestTokenRedaction(t *testing.T) {
	srv := httptest.NewServer(http.NotFoundHandler())
	base := srv.URL
	srv.Close() // connection refused from now on

	var logs bytes.Buffer
	sl := &sleeps{}
	c := New(Config{BaseURL: base, Token: testToken, MinGap: -1, MaxRetries: 1, Sleep: sl.sleep,
		Logger: slog.New(slog.NewTextHandler(&logs, nil))})
	ctx := context.Background()
	errs := []error{
		c.SendMessage(ctx, "1", "x"),
		c.SendDocument(ctx, "1", "a.pdf", []byte("%PDF"), "c"),
	}
	_, err := c.GetUpdates(ctx, 0, time.Second)
	errs = append(errs, err)
	for i, err := range errs {
		if err == nil {
			t.Fatalf("call %d: want error", i)
		}
		if strings.Contains(err.Error(), testToken) || strings.Contains(err.Error(), "ABCdef") {
			t.Errorf("call %d: error leaks token: %v", i, err)
		}
		if !strings.Contains(err.Error(), redacted) {
			t.Errorf("call %d: error not redacted: %v", i, err)
		}
	}
	if strings.Contains(logs.String(), "ABCdef") {
		t.Errorf("logs leak token: %s", logs.String())
	}
	if len(sl.all()) != 2 { // one retry each for the two sends
		t.Errorf("sleeps = %v", sl.all())
	}
}

func TestRedact(t *testing.T) {
	tests := []struct {
		in, token, want string
	}{
		{`Post "https://api.telegram.org/bot1:AbC/sendMessage": dial`, "1:AbC", `Post "https://api.telegram.org/bot<redacted>/sendMessage": dial`},
		{"token 1%3AAbC escaped", "1:AbC", "token <redacted> escaped"},
		{"nothing here", "1:AbC", "nothing here"},
		{"bot1:AbC", "", "bot1:AbC"},
	}
	for _, tt := range tests {
		if got := Redact(tt.in, tt.token); got != tt.want {
			t.Errorf("Redact(%q) = %q, want %q", tt.in, got, tt.want)
		}
	}
}

func TestParseCommand(t *testing.T) {
	tests := []struct {
		in, cmd, args string
	}{
		{"/status", "status", ""},
		{"/status@MyBot  x", "status", "x"},
		{"  /Digest 2026-10-20 ", "digest", "2026-10-20"},
		{"/help@Bot", "help", ""},
		{"/status\nmore", "status", "more"},
		{"status", "", ""},
		{"/", "", ""},
		{"", "", ""},
	}
	for _, tt := range tests {
		cmd, args := ParseCommand(tt.in)
		if cmd != tt.cmd || args != tt.args {
			t.Errorf("ParseCommand(%q) = (%q, %q), want (%q, %q)", tt.in, cmd, args, tt.cmd, tt.args)
		}
	}
}

func TestMinGapPerChat(t *testing.T) {
	c, _, sl := newTest(t)
	c.minGap = 3 * time.Second
	fixed := time.Date(2026, 10, 21, 12, 0, 0, 0, time.UTC)
	c.now = func() time.Time { return fixed }
	ctx := context.Background()
	for _, chat := range []string{"1", "1", "2"} {
		if err := c.SendMessage(ctx, chat, "x"); err != nil {
			t.Fatal(err)
		}
	}
	got := sl.all()
	if len(got) != 1 || got[0] != 3*time.Second {
		t.Errorf("sleeps = %v, want [3s] (second send to chat 1 only)", got)
	}
	if err := c.SendDocument(ctx, "1", "a.pdf", []byte("x"), ""); err != nil {
		t.Fatal(err)
	}
	if got := sl.all(); len(got) != 2 || got[1] != 6*time.Second {
		t.Errorf("sleeps = %v, want third chat-1 send to wait 6s", got)
	}
}

func TestGetUpdates(t *testing.T) {
	c, api, _ := newTest(t, [2]any{200, `{"ok":true,"result":[
		{"update_id":5,"message":{"message_id":9,"chat":{"id":-100123,"type":"supergroup"},"text":"/status"}},
		{"update_id":6}
	]}`})
	ups, err := c.GetUpdates(context.Background(), 5, 50*time.Second)
	if err != nil {
		t.Fatal(err)
	}
	if len(ups) != 2 || ups[0].UpdateID != 5 || ups[0].Message == nil || ups[0].Message.Chat.ID != -100123 ||
		ups[0].Message.Text != "/status" || ups[0].Message.Chat.Type != "supergroup" || ups[1].Message != nil {
		t.Fatalf("updates = %+v", ups)
	}
	reqs := api.requests()
	if reqs[0].Path != "/bot"+testToken+"/getUpdates" {
		t.Errorf("path = %q", reqs[0].Path)
	}
	m := decodeJSON(t, reqs[0].Body)
	if m["offset"] != json.Number("5") || m["timeout"] != json.Number("50") {
		t.Errorf("body = %v", m)
	}
	if au, _ := m["allowed_updates"].([]any); len(au) != 1 || au[0] != "message" {
		t.Errorf("allowed_updates = %v", m["allowed_updates"])
	}
}

func TestGetUpdatesAPIError(t *testing.T) {
	c, api, sl := newTest(t, [2]any{409, `{"ok":false,"error_code":409,"description":"Conflict: terminated by other getUpdates request"}`})
	_, err := c.GetUpdates(context.Background(), 0, time.Second)
	var ae *APIError
	if !errors.As(err, &ae) || ae.StatusCode != 409 || ae.Method != "getUpdates" {
		t.Fatalf("err = %v", err)
	}
	if len(api.requests()) != 1 || len(sl.all()) != 0 {
		t.Errorf("getUpdates must not retry")
	}
}
