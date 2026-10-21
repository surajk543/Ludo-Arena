package rooms

import (
	"errors"
	"net/http"

	"ludoroyale/internal/httpapi"
	"ludoroyale/internal/protocol"
	"ludoroyale/internal/ratelimit"
)

// RegisterRoutes adds the player-facing room REST endpoints.
func (s *Service) RegisterRoutes(rt *httpapi.Router) {
	rule := ratelimit.RoomCodePerUser
	rt.Handle("GET /api/v1/rooms/code/{code}", httpapi.Route{Auth: httpapi.AuthHuman, Gate: true, UserRule: &rule},
		func(w http.ResponseWriter, r *http.Request) error {
			room, err := s.PreviewCode(r.Context(), r.PathValue("code"))
			if err != nil {
				if errors.Is(err, protocol.ErrInvalidCode) {
					return httpapi.Errf(http.StatusNotFound, "invalid_code", "That room code is not valid.")
				}
				return err
			}
			host := ""
			if room.HostSeat >= 0 && room.HostSeat < len(room.Players) {
				host = room.Players[room.HostSeat].Name
			}
			// Only coarse, non-sensitive information before joining.
			httpapi.WriteJSON(w, http.StatusOK, map[string]any{
				"game": room.Game, "variant": room.Variant, "capacity": room.Capacity,
				"players": len(room.Players), "status": room.Status, "entryFee": room.EntryFee, "hostName": host,
			})
			return nil
		})
}
