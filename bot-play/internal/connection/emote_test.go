package connection

import (
	"encoding/json"
	"testing"
)

// chat.emote may carry the art of a Store emote ("asset"); bots decode it,
// never treat it as room state and keep their state untouched.
func TestEmoteBroadcastWithAssetIsTolerated(t *testing.T) {
	frames := []struct {
		raw       string
		wantAsset bool
	}{
		{`{"t":"chat.emote","p":{"roomId":"r_1","seat":2,"emote":"em_angry","asset":{"path":"emotes/angry.json","format":"lottie"}}}`, true},
		{`{"t":"chat.emote","p":{"roomId":"r_1","seat":2,"emote":"emote_wave"}}`, false},
		{`{"t":"chat.emote","p":{"roomId":"r_1","seat":2,"emote":"em_x","asset":null,"future":1}}`, false},
	}
	for _, f := range frames {
		var in Inbound
		if err := json.Unmarshal([]byte(f.raw), &in); err != nil {
			t.Fatal(err)
		}
		if in.T != TChatEmote || IsVersionedDelta(in.T) || IsSnapshot(in.T) {
			t.Fatalf("%s: type %q is room state", f.raw, in.T)
		}
		var ev EmoteEvent
		if err := json.Unmarshal(in.P, &ev); err != nil || ev.RoomID != "r_1" || ev.Seat != 2 {
			t.Fatalf("%s: %+v %v", f.raw, ev, err)
		}
		if (ev.Asset != nil) != f.wantAsset || (f.wantAsset && (ev.Asset.Path != "emotes/angry.json" || ev.Asset.Format != "lottie")) {
			t.Fatalf("%s: asset %+v", f.raw, ev.Asset)
		}
	}
	// Not a delta: applying it is refused without touching the state.
	var s RoomState
	s.ApplySnapshot(&Room{ID: "r_1", V: 4, Game: "ludo"})
	if out, _ := s.ApplyDelta(TChatEmote, json.RawMessage(`{"roomId":"r_1","seat":2,"emote":"em_angry","asset":{"path":"emotes/angry.json","format":"lottie"}}`)); out == Applied {
		t.Fatal("chat.emote applied as a delta")
	}
	if s.V() != 4 {
		t.Fatalf("state changed: v %d", s.V())
	}
}
