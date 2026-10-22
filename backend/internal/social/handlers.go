package social

import (
	"errors"
	"net/http"
	"time"

	"github.com/google/uuid"

	"ludoarena/internal/httpapi"
	"ludoarena/internal/ratelimit"
)

// ReadPerUser limits social reads per account.
var ReadPerUser = ratelimit.Rule{Name: "social_read_user", Limit: 120, Window: time.Minute}

// Register adds the friends, recent players and leaderboard routes. All
// require a human access token and pass the app version gate.
func (s *Service) Register(rt *httpapi.Router) {
	route := func(rule ratelimit.Rule) httpapi.Route {
		return httpapi.Route{Auth: httpapi.AuthHuman, Gate: true, UserRule: &rule}
	}
	read, write := ReadPerUser, ratelimit.SocialPerUser
	rt.Handle("GET /api/v1/friends", route(read), s.handleFriends)
	rt.Handle("POST /api/v1/friends/requests", route(write), s.handleRequest)
	rt.Handle("POST /api/v1/friends/requests/{uid}/accept", route(write), s.handleAccept)
	rt.Handle("DELETE /api/v1/friends/{uid}", route(write), s.handleRemove)
	rt.Handle("GET /api/v1/social/recent", route(read), s.handleRecent)
	rt.Handle("GET /api/v1/leaderboards/friends", route(read), s.handleLeaderboard)
}

func caller(r *http.Request) (uuid.UUID, error) {
	p, ok := httpapi.PrincipalFrom(r.Context())
	if !ok {
		return uuid.Nil, httpapi.ErrUnauthorized
	}
	return p.UserID, nil
}

func mapErr(err error) error {
	switch {
	case errors.Is(err, ErrUnknownPlayer):
		return httpapi.Errf(http.StatusNotFound, "not_found", "No player has this friend code.")
	case errors.Is(err, ErrSelf):
		return httpapi.Errf(http.StatusUnprocessableEntity, "cannot_friend_self", "You cannot add yourself as a friend.")
	case errors.Is(err, ErrAlreadyFriends):
		return httpapi.Errf(http.StatusConflict, "already_friends", "You are already friends.")
	case errors.Is(err, ErrFriendLimit):
		return httpapi.Errf(http.StatusUnprocessableEntity, "friend_limit", "The friend or friend request limit has been reached.")
	case errors.Is(err, ErrNoRequest):
		return httpapi.Errf(http.StatusNotFound, "not_found", "There is no pending friend request from this player.")
	}
	return err
}

func (s *Service) handleFriends(w http.ResponseWriter, r *http.Request) error {
	me, err := caller(r)
	if err != nil {
		return err
	}
	v, err := s.Friends(r.Context(), me)
	if err != nil {
		return err
	}
	httpapi.WriteJSON(w, http.StatusOK, v)
	return nil
}

func (s *Service) handleRequest(w http.ResponseWriter, r *http.Request) error {
	me, err := caller(r)
	if err != nil {
		return err
	}
	var body struct {
		FriendCode string `json:"friendCode"`
	}
	if err := httpapi.DecodeJSON(r, &body); err != nil {
		return err
	}
	if ok, retry := s.limiter.Allow(r.Context(), FriendRequestPerHour, me.String()); !ok {
		e := httpapi.Errf(http.StatusTooManyRequests, "rate_limited", "Too many friend requests. Please try again later.")
		e.Retry = retry
		return e
	}
	f, err := s.Request(r.Context(), me, body.FriendCode)
	if err != nil {
		return mapErr(err)
	}
	httpapi.WriteJSON(w, http.StatusCreated, map[string]any{"friend": f})
	return nil
}

func (s *Service) handleAccept(w http.ResponseWriter, r *http.Request) error {
	me, err := caller(r)
	if err != nil {
		return err
	}
	f, err := s.Accept(r.Context(), me, r.PathValue("uid"))
	if err != nil {
		return mapErr(err)
	}
	httpapi.WriteJSON(w, http.StatusOK, map[string]any{"friend": f})
	return nil
}

func (s *Service) handleRemove(w http.ResponseWriter, r *http.Request) error {
	me, err := caller(r)
	if err != nil {
		return err
	}
	if err := s.Remove(r.Context(), me, r.PathValue("uid")); err != nil {
		return mapErr(err)
	}
	w.WriteHeader(http.StatusNoContent)
	return nil
}

func (s *Service) handleRecent(w http.ResponseWriter, r *http.Request) error {
	me, err := caller(r)
	if err != nil {
		return err
	}
	players, err := s.Recent(r.Context(), me)
	if err != nil {
		return err
	}
	httpapi.WriteJSON(w, http.StatusOK, map[string]any{"players": players})
	return nil
}

func (s *Service) handleLeaderboard(w http.ResponseWriter, r *http.Request) error {
	me, err := caller(r)
	if err != nil {
		return err
	}
	lb, err := s.FriendsLeaderboard(r.Context(), me)
	if err != nil {
		return err
	}
	httpapi.WriteJSON(w, http.StatusOK, lb)
	return nil
}
