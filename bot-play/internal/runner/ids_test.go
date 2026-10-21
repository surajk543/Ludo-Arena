package runner

import (
	"strings"
	"testing"
)

// A later session of the same bot persona reuses the account id, and the
// server de-duplicates message ids per account for 2 minutes: two Bot
// instances must never produce the same ids.
func TestMessageIDsUniqueAcrossBots(t *testing.T) {
	seen := map[string]bool{}
	for i := 0; i < 50; i++ {
		b := &Bot{idPrefix: newIDPrefix()}
		for j := 0; j < 20; j++ {
			id := b.nextID()
			if seen[id] {
				t.Fatalf("duplicate message id %q", id)
			}
			if len(id) > 64 || !strings.HasPrefix(id, "m"+b.idPrefix+".") {
				t.Fatalf("bad id %q", id)
			}
			seen[id] = true
		}
	}
}

func TestIDPrefixesDiffer(t *testing.T) {
	a, b := newIDPrefix(), newIDPrefix()
	if a == b || len(a) < 6 {
		t.Fatalf("prefixes %q %q", a, b)
	}
}
