// Package chatter decides when a bot reacts to its game with a quick-chat
// phrase or an emote, so bots chat like people: rarely, a moment after
// something happened, never more than a few times per match.
//
// It is pure decision logic (no I/O, no clock, randomness injected); the
// runner observes the events, asks Decide, and sends the message on the
// bot's own goroutine after the returned delay. The server stays
// authoritative: it checks the quick-chat id, the emote ownership and its
// own rate limits (1 per 3 s, 10 per minute per account).
package chatter

import (
	"slices"
	"time"

	"ludoroyale/botplay/internal/config"
)

// Trigger is a game moment a bot may react to.
type Trigger string

// Triggers.
const (
	GameStart    Trigger = "game_start"    // the game started
	Six          Trigger = "six"           // the bot rolled a six
	Capture      Trigger = "capture"       // the bot captured an opponent token
	Captured     Trigger = "captured"      // one of the bot's tokens was captured
	OtherCapture Trigger = "other_capture" // an opponent captured a third player's token
	Win          Trigger = "win"           // the bot won
	Loss         Trigger = "loss"          // someone else won
)

// Triggers lists every trigger.
var Triggers = []Trigger{GameStart, Six, Capture, Captured, OtherCapture, Win, Loss}

// Message kinds (also the chat_messages_total "kind" label).
const (
	KindQuick = "quick" // chat.quick
	KindEmote = "emote" // chat.emote
)

// QuickChatIDs is the server's predefined quick-chat catalogue.
var QuickChatIDs = []string{"gg", "nice_move", "well_played", "rematch", "again", "good_luck", "oops", "thanks"}

// neverSay are catalogue ids bots never use: bots do not vote for rematches,
// so asking for one would be a promise they cannot keep.
var neverSay = []string{"rematch", "again"}

// phrases are the quick-chat ids that fit each trigger.
var phrases = map[Trigger][]string{
	GameStart:    {"good_luck"},
	Six:          nil, // a six gets an emote or nothing
	Capture:      {"oops"},
	Captured:     {"nice_move", "oops"},
	OtherCapture: {"nice_move"},
	Win:          {"gg", "thanks", "well_played"},
	Loss:         {"gg", "well_played"},
}

// emotes are the emote ids that fit each trigger (filtered by what the bot
// session may use).
var emotes = map[Trigger][]string{
	GameStart:    {"emote_wave", "emote_thumbs"},
	Six:          {"emote_thumbs", "emote_wow"},
	Capture:      {"emote_laugh", "emote_thumbs", "emote_wow"},
	Captured:     {"emote_wow"},
	OtherCapture: {"emote_wow", "emote_laugh"},
	Win:          {"emote_wave", "emote_thumbs", "emote_crown"},
	Loss:         {"emote_thumbs", "emote_wave"},
}

// Phrases returns the quick-chat ids a bot may send for t.
func Phrases(t Trigger) []string { return slices.Clone(phrases[t]) }

// Rand is the randomness Decide needs (the bot's strategy RNG).
type Rand interface {
	Float64() float64
	IntN(n int) int
}

// Settings are the effective chat settings for one decision.
type Settings struct {
	Enabled     bool
	MaxPerMatch int
	MinInterval time.Duration
	DelayMin    time.Duration
	DelayMax    time.Duration
	EmoteShare  float64
	Probability map[Trigger]float64
	// Chattiness multiplies every probability (the profile's chattiness).
	Chattiness float64
}

// FromConfig builds Settings from bots.chat and a chattiness multiplier.
func FromConfig(c config.ChatConfig, chattiness float64) Settings {
	p := c.Probability
	return Settings{
		Enabled: c.Enabled, MaxPerMatch: c.MaxPerMatch, MinInterval: c.MinInterval(),
		DelayMin:   time.Duration(c.ReactionDelayMS.Min) * time.Millisecond,
		DelayMax:   time.Duration(c.ReactionDelayMS.Max) * time.Millisecond,
		EmoteShare: c.EmoteShare, Chattiness: chattiness,
		Probability: map[Trigger]float64{
			GameStart: p.GameStart, Six: p.Six, Capture: p.Capture, Captured: p.Captured,
			OtherCapture: p.OtherCapture, Win: p.Win, Loss: p.Loss,
		},
	}
}

// State is one bot's chat history (owned by the bot goroutine).
type State struct {
	match string    // room id + round the counter belongs to
	sent  int       // messages reserved in this match
	last  time.Time // planned send time of the previous message
}

// Sent returns how many messages were reserved for match.
func (s *State) Sent(match string) int {
	if s.match != match {
		return 0
	}
	return s.sent
}

// Message is a reaction to send.
type Message struct {
	Kind string // KindQuick | KindEmote
	ID   string // quick-chat id or emote id
	// Delay is how long after the event to send it.
	Delay time.Duration
}

// Decide returns the reaction to trigger t in match (room id + round) at
// now, or ok=false. allowed lists the emote ids the bot may send. A
// positive decision is reserved immediately (per-match count and interval),
// so a reaction that is later dropped still counts: the caps are never
// exceeded.
func Decide(s Settings, st *State, t Trigger, match string, allowed []string, now time.Time, rnd Rand) (Message, bool) {
	if !s.Enabled || s.MaxPerMatch <= 0 || match == "" {
		return Message{}, false
	}
	if st.match != match {
		st.match, st.sent = match, 0
	}
	if st.sent >= s.MaxPerMatch {
		return Message{}, false
	}
	if !st.last.IsZero() && now.Sub(st.last) < max(s.MinInterval, time.Duration(config.MinChatIntervalMS)*time.Millisecond) {
		return Message{}, false
	}
	p := s.Probability[t] * s.Chattiness
	if p <= 0 || rnd.Float64() >= min(p, 1) {
		return Message{}, false
	}
	var es []string
	for _, e := range emotes[t] {
		if slices.Contains(allowed, e) {
			es = append(es, e)
		}
	}
	var qs []string
	for _, q := range phrases[t] {
		if slices.Contains(QuickChatIDs, q) && !slices.Contains(neverSay, q) {
			qs = append(qs, q)
		}
	}
	var m Message
	switch {
	case len(es) > 0 && (len(qs) == 0 || rnd.Float64() < s.EmoteShare):
		m = Message{Kind: KindEmote, ID: es[rnd.IntN(len(es))]}
	case len(qs) > 0:
		m = Message{Kind: KindQuick, ID: qs[rnd.IntN(len(qs))]}
	default:
		return Message{}, false
	}
	m.Delay = s.DelayMin
	if s.DelayMax > s.DelayMin {
		m.Delay += time.Duration(rnd.IntN(int((s.DelayMax-s.DelayMin)/time.Millisecond)+1)) * time.Millisecond
	}
	st.sent++
	st.last = now.Add(m.Delay)
	return m, true
}
