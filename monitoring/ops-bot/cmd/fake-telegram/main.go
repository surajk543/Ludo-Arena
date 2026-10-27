// Command fake-telegram is a minimal fake Telegram Bot API for local
// end-to-end tests of the ops bot. It accepts any token, records
// sendMessage / sendDocument / sendChatAction / setMyCommands calls
// (documents are saved to --out), lists the records at GET /messages, and
// answers getUpdates with the commands queued by POST /inject.
//
//	go run ./cmd/fake-telegram --addr 127.0.0.1:9098 --out /tmp/fake-telegram
//	TELEGRAM_API_URL=http://127.0.0.1:9098 TELEGRAM_BOT_TOKEN=1:fake ... ops-bot
//	curl -X POST '127.0.0.1:9098/inject?chat=-1001234567890&text=/live'           # a group message
//	curl -X POST '127.0.0.1:9098/inject?chat=-1001234567890&text=/live&channel=1' # a channel post
//
// It is a test tool only: it never contacts Telegram and never logs tokens.
package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"log"
	"mime"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"
)

type record struct {
	Time      string `json:"time"`
	Method    string `json:"method"`
	ChatID    string `json:"chat_id"`
	ParseMode string `json:"parse_mode,omitempty"`
	Text      string `json:"text,omitempty"`
	Caption   string `json:"caption,omitempty"`
	Filename  string `json:"filename,omitempty"`
	SavedPath string `json:"saved_path,omitempty"`
	Bytes     int    `json:"bytes,omitempty"`
}

type server struct {
	out     string
	fail429 atomic.Bool
	ids     atomic.Int64
	files   atomic.Int64
	mu      sync.Mutex
	records []record
	updates []map[string]any // queued by POST /inject, update_id ascending
	nextUID int64
}

func main() {
	addr := flag.String("addr", "127.0.0.1:9098", "listen address")
	out := flag.String("out", "./fake-telegram-out", "directory for messages.jsonl and received documents")
	fail := flag.Bool("fail-first-429", false, "answer the first send with 429 retry_after=1")
	flag.Parse()
	if err := os.MkdirAll(*out, 0o755); err != nil {
		log.Fatal(err)
	}
	s := &server{out: *out}
	s.fail429.Store(*fail)
	log.Printf("fake-telegram listening on %s, writing to %s", *addr, *out)
	srv := &http.Server{Addr: *addr, Handler: s, ReadHeaderTimeout: 10 * time.Second}
	log.Fatal(srv.ListenAndServe())
}

func (s *server) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path == "/messages" {
		s.mu.Lock()
		recs := append([]record{}, s.records...)
		s.mu.Unlock()
		writeJSON(w, http.StatusOK, recs)
		return
	}
	if r.URL.Path == "/inject" && r.Method == http.MethodPost {
		s.inject(w, r)
		return
	}
	rest, ok := strings.CutPrefix(r.URL.Path, "/bot")
	_, method, ok2 := strings.Cut(rest, "/")
	if !ok || !ok2 || method == "" {
		writeJSON(w, http.StatusNotFound, map[string]any{"ok": false, "error_code": 404, "description": "Not Found"})
		return
	}
	switch method {
	case "sendMessage", "sendDocument":
		if s.fail429.CompareAndSwap(true, false) {
			log.Printf("%s: answering 429 (retry_after 1)", method)
			writeJSON(w, http.StatusTooManyRequests, map[string]any{"ok": false, "error_code": 429,
				"description": "Too Many Requests: retry after 1", "parameters": map[string]int{"retry_after": 1}})
			return
		}
		rec, err := s.parse(method, r)
		if err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]any{"ok": false, "error_code": 400, "description": "Bad Request: " + err.Error()})
			return
		}
		s.store(rec)
		writeJSON(w, http.StatusOK, map[string]any{"ok": true, "result": map[string]int64{"message_id": s.ids.Add(1)}})
	case "sendChatAction", "setMyCommands":
		rec, err := s.parse(method, r)
		if err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]any{"ok": false, "error_code": 400, "description": "Bad Request: " + err.Error()})
			return
		}
		s.store(rec)
		writeJSON(w, http.StatusOK, map[string]any{"ok": true, "result": true})
	case "getUpdates":
		offset, timeout := pollParams(r)
		deadline := time.Now().Add(min(timeout, 2*time.Second))
		for {
			if ups := s.pending(offset); len(ups) > 0 || !time.Now().Before(deadline) {
				writeJSON(w, http.StatusOK, map[string]any{"ok": true, "result": ups})
				return
			}
			select {
			case <-time.After(50 * time.Millisecond):
			case <-r.Context().Done():
				return
			}
		}
	case "getMe":
		writeJSON(w, http.StatusOK, map[string]any{"ok": true, "result": map[string]any{"id": 1, "is_bot": true, "username": "fake_ops_bot"}})
	default:
		writeJSON(w, http.StatusNotFound, map[string]any{"ok": false, "error_code": 404, "description": "Not Found: method " + method})
	}
}

// parse reads a send request (JSON, urlencoded form or multipart).
func (s *server) parse(method string, r *http.Request) (record, error) {
	rec := record{Time: time.Now().Format(time.RFC3339), Method: method}
	ctype, _, _ := mime.ParseMediaType(r.Header.Get("Content-Type"))
	switch ctype {
	case "application/json":
		var body map[string]any
		d := json.NewDecoder(io.LimitReader(r.Body, 1<<20))
		d.UseNumber()
		if err := d.Decode(&body); err != nil {
			return rec, err
		}
		rec.ChatID = fmt.Sprint(body["chat_id"])
		rec.ParseMode, _ = body["parse_mode"].(string)
		rec.Text, _ = body["text"].(string)
		if action, ok := body["action"].(string); ok {
			rec.Text = action // sendChatAction
		}
		rec.Caption, _ = body["caption"].(string)
		return rec, nil
	case "multipart/form-data":
		if err := r.ParseMultipartForm(64 << 20); err != nil {
			return rec, err
		}
	default:
		if err := r.ParseForm(); err != nil {
			return rec, err
		}
	}
	rec.ChatID = r.FormValue("chat_id")
	rec.ParseMode = r.FormValue("parse_mode")
	rec.Text = r.FormValue("text")
	rec.Caption = r.FormValue("caption")
	if method == "sendDocument" {
		f, h, err := r.FormFile("document")
		if err != nil {
			return rec, fmt.Errorf("document: %w", err)
		}
		defer f.Close()
		data, err := io.ReadAll(f)
		if err != nil {
			return rec, err
		}
		rec.Filename = filepath.Base(h.Filename)
		rec.Bytes = len(data)
		rec.SavedPath = filepath.Join(s.out, fmt.Sprintf("%03d-%s", s.files.Add(1), rec.Filename))
		if err := os.WriteFile(rec.SavedPath, data, 0o644); err != nil {
			return rec, err
		}
	}
	return rec, nil
}

func (s *server) store(rec record) {
	line, _ := json.Marshal(rec)
	s.mu.Lock()
	defer s.mu.Unlock()
	s.records = append(s.records, rec)
	f, err := os.OpenFile(filepath.Join(s.out, "messages.jsonl"), os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0o644)
	if err == nil {
		_, _ = f.Write(append(line, '\n'))
		_ = f.Close()
	}
	fmt.Println(string(line))
}

// inject queues a command as the next update: ?chat=<id>&text=/live
// [&channel=1 for a channel post].
func (s *server) inject(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query()
	chat, err := strconv.ParseInt(q.Get("chat"), 10, 64)
	if err != nil || q.Get("text") == "" {
		writeJSON(w, http.StatusBadRequest, map[string]any{"ok": false, "description": "want ?chat=<numeric id>&text=<text>"})
		return
	}
	kind, chatType := "message", "supergroup"
	if q.Get("channel") != "" {
		kind, chatType = "channel_post", "channel"
	}
	s.mu.Lock()
	s.nextUID++
	id := s.nextUID
	s.updates = append(s.updates, map[string]any{"update_id": id,
		kind: map[string]any{"message_id": id, "chat": map[string]any{"id": chat, "type": chatType}, "text": q.Get("text")}})
	s.mu.Unlock()
	log.Printf("queued update %d: %s in %d", id, kind, chat)
	writeJSON(w, http.StatusOK, map[string]any{"ok": true, "update_id": id})
}

// pending returns the queued updates with update_id >= offset.
func (s *server) pending(offset int64) []map[string]any {
	s.mu.Lock()
	defer s.mu.Unlock()
	out := []map[string]any{}
	for _, u := range s.updates {
		if u["update_id"].(int64) >= offset {
			out = append(out, u)
		}
	}
	return out
}

// pollParams reads getUpdates' offset and timeout (seconds) from JSON, query or form.
func pollParams(r *http.Request) (offset int64, timeout time.Duration) {
	q := r.URL.Query()
	ov, tv := q.Get("offset"), q.Get("timeout")
	if ctype, _, _ := mime.ParseMediaType(r.Header.Get("Content-Type")); ctype == "application/json" {
		var body struct {
			Offset  int64 `json:"offset"`
			Timeout int   `json:"timeout"`
		}
		if json.NewDecoder(io.LimitReader(r.Body, 1<<16)).Decode(&body) == nil {
			return body.Offset, time.Duration(body.Timeout) * time.Second
		}
	} else {
		if fv := r.FormValue("offset"); fv != "" {
			ov = fv
		}
		if fv := r.FormValue("timeout"); fv != "" {
			tv = fv
		}
	}
	o, _ := strconv.ParseInt(ov, 10, 64)
	n, _ := strconv.Atoi(tv)
	return o, time.Duration(n) * time.Second
}

func writeJSON(w http.ResponseWriter, code int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	_ = json.NewEncoder(w).Encode(v)
}
