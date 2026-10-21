package rooms

import (
	"context"
	"errors"
	"time"

	"ludoroyale/internal/gameevents"
	"ludoroyale/internal/metrics"
	"ludoroyale/internal/protocol"
	"ludoroyale/internal/ratelimit"
	"ludoroyale/internal/social"
)

var (
	chatBurst  = ratelimit.Rule{Name: "chat_burst", Limit: 1, Window: 3 * time.Second}
	chatMinute = ratelimit.Rule{Name: "chat_minute", Limit: 10, Window: time.Minute}
)

// publishRoom sends a non-versioned message to current room members.
func (s *Service) publishRoom(ctx context.Context, r *Room, msg []byte) error {
	m := &mutation{s: s, r: r}
	m.msgs = append(m.msgs, msg)
	b := Batch{Room: r.ID, To: r.MemberIDs(), Msgs: m.msgs}
	raw, err := jsonMarshal(b)
	if err != nil {
		return err
	}
	return s.RDB.Publish(ctx, roomChanPrefix+r.ID, raw).Err()
}

// QuickChat broadcasts a predefined quick-chat message or an owned emote.
func (s *Service) QuickChat(ctx context.Context, c Caller, roomID, msg, emote string) error {
	if c.Bot {
		return protocol.ErrBadRequest
	}
	if emote == "" && !protocol.QuickChat[msg] {
		return protocol.ErrBadRequest
	}
	for _, rule := range []ratelimit.Rule{chatBurst, chatMinute} {
		if ok, _ := s.Limiter.Allow(ctx, rule, c.UserID); !ok {
			return protocol.ErrRateLimited
		}
	}
	r, _, err := s.st.load(ctx, roomID)
	if err != nil {
		return protocol.ErrRoomNotFound
	}
	seat := r.SeatOf(c.UserID)
	if seat < 0 || r.Status == StatusClosed {
		return protocol.ErrNotInRoom
	}
	if emote != "" {
		if s.Inventory == nil {
			return protocol.ErrItemNotOwned
		}
		owned, err := s.Inventory.Owns(ctx, userUUID(c.UserID), emote)
		if err != nil {
			return err
		}
		if !owned {
			return protocol.ErrItemNotOwned
		}
		metrics.QuickChats.WithLabelValues("emote").Inc()
		return s.publishRoom(ctx, r, protocol.Encode(protocol.TChatEmote, "", map[string]any{"roomId": roomID, "seat": seat, "emote": emote}))
	}
	metrics.QuickChats.WithLabelValues("quick").Inc()
	return s.publishRoom(ctx, r, protocol.Encode(protocol.TChatQuick, "", map[string]any{"roomId": roomID, "seat": seat, "msg": msg}))
}

// Invite sends a private-room invite to a friend.
func (s *Service) Invite(ctx context.Context, c Caller, roomID, friendUID string) error {
	if c.Bot || s.Inviter == nil {
		return protocol.ErrBadRequest
	}
	r, _, err := s.st.load(ctx, roomID)
	if err != nil {
		return protocol.ErrRoomNotFound
	}
	if r.SeatOf(c.UserID) < 0 {
		return protocol.ErrNotInRoom
	}
	if r.Mode != ModePrivate || r.Status != StatusLobby {
		return protocol.ErrInvalidPhase
	}
	err = s.Inviter.SendInvite(ctx, userUUID(c.UserID), friendUID, gameevents.Invite{
		RoomID: r.ID, Code: r.Code, Game: r.Game, ExpiresAt: time.Now().Add(10 * time.Minute)})
	switch {
	case errors.Is(err, gameevents.ErrNotFriends):
		return protocol.ErrNotFriends
	case errors.Is(err, social.ErrInviteRateLimited):
		return protocol.ErrRateLimited
	}
	return err
}
