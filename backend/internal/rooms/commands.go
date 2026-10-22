package rooms

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"

	"ludoarena/internal/metrics"
	"ludoarena/internal/protocol"
)

// botAllowed lists the commands bot sessions may send. Bots chat and emote
// like people (bot-play sends them sparingly; same rate limits).
var botAllowed = map[string]bool{
	protocol.TGameRoll: true, protocol.TGameMove: true, protocol.TGameSync: true, protocol.TRoomLeave: true,
	protocol.TChatQuick: true, protocol.TChatEmote: true,
}

// loadTestAllowed adds matchmaking for isolated load-test bots.
var loadTestAllowed = map[string]bool{
	protocol.TMatchmakingJoin: true, protocol.TMatchmakingCancel: true, protocol.TGameRematch: true,
}

func decode(raw json.RawMessage, v any) error {
	if len(raw) == 0 {
		raw = []byte("{}")
	}
	dec := json.NewDecoder(bytes.NewReader(raw))
	dec.DisallowUnknownFields()
	if err := dec.Decode(v); err != nil {
		return protocol.ErrBadRequest
	}
	return nil
}

func validRoomID(id string) bool { return len(id) >= 3 && len(id) <= 32 }

// Dispatch executes one client command. It returns messages to write back to
// the calling connection (replies, errors, snapshots); room-wide events are
// delivered through pub/sub.
func (s *Service) Dispatch(ctx context.Context, c Caller, in protocol.Inbound) [][]byte {
	if c.Bot && !botAllowed[in.T] && !(c.LoadTest && loadTestAllowed[in.T]) {
		return [][]byte{protocol.Encode(protocol.TError, in.ID, protocol.ErrBadRequest)}
	}
	replies, err := s.dispatch(ctx, c, in)
	if err != nil {
		pe := protocol.AsError(err)
		if pe == protocol.ErrInternal {
			s.Log.Error("command failed", "type", in.T, "error", err.Error())
		}
		metrics.RuleErrors.WithLabelValues(pe.Code).Inc()
		out := [][]byte{protocol.Encode(protocol.TError, in.ID, pe)}
		if errors.Is(err, protocol.ErrStaleState) {
			// Resynchronize the caller immediately.
			if roomID := s.ActiveRoom(ctx, c.UserID); roomID != "" {
				if v, err := s.Snapshot(ctx, c.UserID, roomID); err == nil {
					metrics.WSResyncs.WithLabelValues("stale").Inc()
					out = append(out, protocol.Encode(protocol.TGameState, "", map[string]any{"room": v}))
				}
			}
		}
		return out
	}
	return replies
}

func ack(id string) [][]byte { return [][]byte{protocol.Encode(protocol.TAck, id, map[string]any{})} }

func (s *Service) dispatch(ctx context.Context, c Caller, in protocol.Inbound) ([][]byte, error) {
	switch in.T {
	case protocol.TMatchmakingJoin:
		var p struct {
			Game     string `json:"game"`
			Variant  string `json:"variant"`
			Capacity int    `json:"capacity"`
		}
		if err := decode(in.P, &p); err != nil {
			return nil, err
		}
		if p.Variant == "" {
			p.Variant = "classic"
		}
		r, err := s.MatchmakingJoin(ctx, c, p.Game, p.Variant, p.Capacity)
		if err != nil {
			return nil, err
		}
		return [][]byte{protocol.Encode(protocol.TMatchmakingStatus, in.ID, map[string]any{
			"status": "searching", "game": p.Game, "variant": p.Variant, "capacity": p.Capacity, "roomId": r.ID})}, nil

	case protocol.TMatchmakingCancel:
		if err := s.MatchmakingCancel(ctx, c); err != nil {
			return nil, err
		}
		return [][]byte{protocol.Encode(protocol.TMatchmakingStatus, in.ID, map[string]any{"status": "cancelled"})}, nil

	case protocol.TRoomCreate:
		var p struct {
			Game     string `json:"game"`
			Variant  string `json:"variant"`
			Capacity int    `json:"capacity"`
		}
		if err := decode(in.P, &p); err != nil {
			return nil, err
		}
		if p.Variant == "" {
			p.Variant = "classic"
		}
		r, err := s.CreatePrivate(ctx, c, p.Game, p.Variant, p.Capacity)
		if err != nil {
			return nil, err
		}
		// Reply with the snapshot: the published room.updated can reach the
		// caller after a bare ack, which left the app without its room.
		return [][]byte{protocol.Encode(protocol.TRoomUpdated, in.ID, map[string]any{"room": r.View(), "reason": "created"})}, nil

	case protocol.TRoomJoin:
		var p struct {
			Code string `json:"code"`
		}
		if err := decode(in.P, &p); err != nil {
			return nil, err
		}
		r, err := s.JoinByCode(ctx, c, p.Code)
		if err != nil {
			return nil, err
		}
		v := r.View()
		// Reply with the snapshot too: an idempotent re-join emits no event.
		return [][]byte{protocol.Encode(protocol.TRoomUpdated, in.ID, map[string]any{"room": v, "reason": "joined"})}, nil

	case protocol.TRoomLeave:
		var p struct {
			RoomID string `json:"roomId"`
		}
		if err := decode(in.P, &p); err != nil || !validRoomID(p.RoomID) {
			return nil, protocol.ErrBadRequest
		}
		if err := s.Leave(ctx, c, p.RoomID); err != nil {
			return nil, err
		}
		return ack(in.ID), nil

	case protocol.TRoomInvite:
		var p struct {
			RoomID    string `json:"roomId"`
			FriendUID string `json:"friendUid"`
		}
		if err := decode(in.P, &p); err != nil || !validRoomID(p.RoomID) || len(p.FriendUID) > 32 {
			return nil, protocol.ErrBadRequest
		}
		if err := s.Invite(ctx, c, p.RoomID, p.FriendUID); err != nil {
			return nil, err
		}
		return ack(in.ID), nil

	case protocol.TRoomAllowBots:
		var p struct {
			RoomID string `json:"roomId"`
			Allow  bool   `json:"allow"`
		}
		if err := decode(in.P, &p); err != nil || !validRoomID(p.RoomID) {
			return nil, protocol.ErrBadRequest
		}
		if err := s.AllowBots(ctx, c, p.RoomID, p.Allow); err != nil {
			return nil, err
		}
		return ack(in.ID), nil

	case protocol.TRoomAddBot:
		var p struct {
			RoomID string `json:"roomId"`
		}
		if err := decode(in.P, &p); err != nil || !validRoomID(p.RoomID) {
			return nil, protocol.ErrBadRequest
		}
		if err := s.AddBot(ctx, c, p.RoomID); err != nil {
			return nil, err
		}
		return ack(in.ID), nil

	case protocol.TRoomRemoveBot:
		var p struct {
			RoomID string `json:"roomId"`
			Seat   int    `json:"seat"`
		}
		if err := decode(in.P, &p); err != nil || !validRoomID(p.RoomID) {
			return nil, protocol.ErrBadRequest
		}
		if err := s.RemoveBot(ctx, c, p.RoomID, p.Seat); err != nil {
			return nil, err
		}
		return ack(in.ID), nil

	case protocol.TPracticeStart:
		var p struct {
			Game    string `json:"game"`
			Variant string `json:"variant"`
			Bots    int    `json:"bots"`
		}
		if err := decode(in.P, &p); err != nil {
			return nil, err
		}
		if p.Variant == "" {
			p.Variant = "classic"
		}
		r, err := s.PracticeStart(ctx, c, p.Game, p.Variant, p.Bots)
		if err != nil {
			return nil, err
		}
		return [][]byte{protocol.Encode(protocol.TRoomUpdated, in.ID, map[string]any{"room": r.View(), "reason": "created"})}, nil

	case protocol.TGameStart:
		var p struct {
			RoomID string `json:"roomId"`
		}
		if err := decode(in.P, &p); err != nil || !validRoomID(p.RoomID) {
			return nil, protocol.ErrBadRequest
		}
		if err := s.StartPrivate(ctx, c, p.RoomID); err != nil {
			return nil, err
		}
		return ack(in.ID), nil

	case protocol.TGameRoll:
		var p struct {
			RoomID  string `json:"roomId"`
			TurnSeq int    `json:"turnSeq"`
		}
		if err := decode(in.P, &p); err != nil || !validRoomID(p.RoomID) {
			return nil, protocol.ErrBadRequest
		}
		if err := s.botScope(c, p.RoomID); err != nil {
			return nil, err
		}
		if err := s.Roll(ctx, c.UserID, p.RoomID, p.TurnSeq); err != nil {
			return nil, err
		}
		return ack(in.ID), nil

	case protocol.TGameMove:
		var p struct {
			RoomID  string `json:"roomId"`
			TurnSeq int    `json:"turnSeq"`
			Token   int    `json:"token"`
		}
		if err := decode(in.P, &p); err != nil || !validRoomID(p.RoomID) || p.Token < 0 || p.Token > 3 {
			return nil, protocol.ErrBadRequest
		}
		if err := s.botScope(c, p.RoomID); err != nil {
			return nil, err
		}
		if err := s.Move(ctx, c.UserID, p.RoomID, p.TurnSeq, p.Token); err != nil {
			return nil, err
		}
		return ack(in.ID), nil

	case protocol.TGameSync:
		var p struct {
			RoomID string `json:"roomId"`
		}
		if err := decode(in.P, &p); err != nil {
			return nil, err
		}
		roomID := p.RoomID
		if roomID == "" {
			roomID = s.ActiveRoom(ctx, c.UserID)
			if roomID == "" {
				return [][]byte{protocol.Encode(protocol.TGameState, in.ID, map[string]any{"room": nil})}, nil
			}
		}
		if err := s.botScope(c, roomID); err != nil {
			return nil, err
		}
		v, err := s.Snapshot(ctx, c.UserID, roomID)
		if err != nil {
			return nil, err
		}
		metrics.WSResyncs.WithLabelValues("requested").Inc()
		return [][]byte{protocol.Encode(protocol.TGameState, in.ID, map[string]any{"room": v})}, nil

	case protocol.TGameRematch:
		var p struct {
			RoomID string `json:"roomId"`
			Accept bool   `json:"accept"`
		}
		if err := decode(in.P, &p); err != nil || !validRoomID(p.RoomID) {
			return nil, protocol.ErrBadRequest
		}
		if err := s.VoteRematch(ctx, c, p.RoomID, p.Accept); err != nil {
			return nil, err
		}
		return ack(in.ID), nil

	case protocol.TChatQuick, protocol.TChatEmote:
		var p struct {
			RoomID string `json:"roomId"`
			Msg    string `json:"msg"`
			Emote  string `json:"emote"`
		}
		if err := decode(in.P, &p); err != nil || !validRoomID(p.RoomID) || len(p.Msg) > 32 || len(p.Emote) > protocol.MaxEmoteID {
			return nil, protocol.ErrBadRequest
		}
		if in.T == protocol.TChatQuick {
			p.Emote = ""
		} else if p.Emote == "" {
			return nil, protocol.ErrBadRequest
		}
		if err := s.botScope(c, p.RoomID); err != nil {
			return nil, err
		}
		if err := s.QuickChat(ctx, c, p.RoomID, p.Msg, p.Emote); err != nil {
			return nil, err
		}
		return ack(in.ID), nil
	}
	return nil, protocol.ErrUnknownType
}

// botScope restricts assignment bots to their own room.
func (s *Service) botScope(c Caller, roomID string) error {
	if c.Bot && !c.LoadTest && c.BotRoom != roomID {
		return protocol.ErrNotInRoom
	}
	return nil
}
