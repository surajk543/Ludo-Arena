package runner

import (
	"crypto/rand"
	"encoding/hex"
	"strconv"
	"time"

	"ludoarena/botplay/internal/chatter"
	"ludoarena/botplay/internal/client"
	"ludoarena/botplay/internal/connection"
)

// chatStale: a reaction whose send time passed this long ago (e.g. across a
// reconnect) is dropped instead of being sent late.
const chatStale = 5 * time.Second

// pendingChat is a reaction waiting for its send time.
type pendingChat struct {
	msg   chatter.Message
	at    time.Time // next send attempt
	due   time.Time // first planned send time (staleness is measured from it)
	match string    // room id + round it reacts to
}

// newIDPrefix returns a random message-id prefix. A bot's account id is
// reused by later sessions of the same persona, and the server de-duplicates
// message ids per account for 2 minutes across connections, so ids must not
// restart at the same value in a new session.
func newIDPrefix() string {
	b := make([]byte, 5)
	if _, err := rand.Read(b); err != nil {
		return strconv.FormatInt(time.Now().UnixNano(), 36)
	}
	return hex.EncodeToString(b)
}

// matchKey identifies one game round for the per-match chat cap.
func matchKey(r *connection.Room) string {
	if r == nil || r.ID == "" {
		return ""
	}
	return r.ID + "/" + strconv.Itoa(r.Round)
}

// chatAllowed reports whether this bot may react at all right now.
func (b *Bot) chatAllowed() bool {
	g := &b.g
	cfg := b.svc.store.Config()
	if !cfg.Bots.Chat.Enabled || (b.kind == client.KindLoadtest && !cfg.Bots.Chat.InLoadtest) {
		return false
	}
	if !g.ready || g.wantLeave || g.done || b.RetireMode() == RetireNow || b.session == nil {
		return false
	}
	r := g.state.Room()
	if r == nil || g.mySeat < 0 {
		return false
	}
	me := r.Player(g.mySeat)
	return me != nil && !me.Forfeited
}

// react considers a quick-chat / emote reaction to t (at most one pending).
func (b *Bot) react(t chatter.Trigger) {
	g := &b.g
	if g.chatPending != nil || !b.chatAllowed() {
		return
	}
	cfg := b.svc.store.Config()
	r := g.state.Room()
	s := chatter.FromConfig(cfg.Bots.Chat, b.currentProfile().ChatMultiplier())
	now := time.Now()
	m, ok := chatter.Decide(s, &g.chat, t, matchKey(r), b.session.Emotes, now, b.strat)
	if !ok {
		return
	}
	g.chatPending = &pendingChat{msg: m, at: now.Add(m.Delay), due: now.Add(m.Delay), match: matchKey(r)}
}

// fireChat sends (or drops) the pending reaction; a leave held back for it
// (the bot says "gg" before leaving a finished game) then proceeds.
func (b *Bot) fireChat(conn *connection.Conn) {
	g := &b.g
	pc := g.chatPending
	g.chatPending = nil
	if pc != nil {
		r := g.state.Room()
		switch {
		case time.Since(pc.due) > chatStale || !b.chatAllowed() || matchKey(r) != pc.match ||
			(r.Status != connection.StatusPlaying && r.Status != connection.StatusFinished):
			b.svc.m.RecordChat(pc.msg.Kind, "dropped")
		case !b.actLim.Allow():
			// No action token right now (the bot just rolled or moved):
			// try again shortly instead of blocking or queueing behind
			// game actions; it is dropped once stale.
			pc.at = time.Now().Add(time.Duration(float64(time.Second) / max(float64(b.actLim.Limit()), 0.1)))
			g.chatPending = pc
			return
		default:
			var id string
			if pc.msg.Kind == chatter.KindEmote {
				id = b.send(conn, connection.TChatEmote, connection.ChatEmote{RoomID: r.ID, Emote: pc.msg.ID}, "")
			} else {
				id = b.send(conn, connection.TChatQuick, connection.ChatQuick{RoomID: r.ID, Msg: pc.msg.ID}, "")
			}
			if g.chatIDs == nil || len(g.chatIDs) > 64 {
				g.chatIDs = map[string]string{}
			}
			g.chatIDs[id] = pc.msg.Kind
			b.svc.m.RecordChat(pc.msg.Kind, "sent")
			b.log.Debug("chat reaction", "kind", pc.msg.Kind, "id", pc.msg.ID)
		}
	}
	if g.leaveAfterChat {
		g.leaveAfterChat = false
		b.leave(conn)
	}
}

// chatReply handles the server's answer to a chat message: errors (rate
// limits, an emote the server refused) are only counted, never retried,
// and never slow down game actions. It reports whether r was a chat id.
func (b *Bot) chatReply(r string, isError bool) bool {
	g := &b.g
	kind, ok := g.chatIDs[r]
	if r == "" || !ok {
		return false
	}
	delete(g.chatIDs, r)
	if isError {
		b.svc.m.RecordChat(kind, "rejected")
	}
	return true
}

// reactToDice reacts to the bot's own six.
func (b *Bot) reactToDice(p connection.DiceResult) {
	if p.Seat == b.g.mySeat && p.Value == 6 && !p.Auto && !p.Voided {
		b.react(chatter.Six)
	}
}

// reactToMove reacts to captures: the bot's own, of the bot, or between
// opponents.
func (b *Bot) reactToMove(p connection.MoveApplied) {
	if len(p.Captures) == 0 {
		return
	}
	me := b.g.mySeat
	switch {
	case p.Seat == me:
		if !p.Auto {
			b.react(chatter.Capture)
		}
	default:
		for _, c := range p.Captures {
			if c.Seat == me {
				b.react(chatter.Captured)
				return
			}
		}
		b.react(chatter.OtherCapture)
	}
}
