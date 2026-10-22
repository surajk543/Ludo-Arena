package buildinfo

import "testing"

func TestHealth(t *testing.T) {
	defer func(v, c, b string) { Version, Commit, BuiltAt = v, c, b }(Version, Commit, BuiltAt)

	if got := Health(); got["status"] != "ok" || got["version"] != "dev" {
		t.Fatalf("default build: %v", got)
	}
	Version, Commit, BuiltAt = "v1.0.0", "f9c4ebd", "2026-10-22T16:00:00Z"
	got := Health()
	want := map[string]string{"status": "ok", "version": "v1.0.0", "commit": "f9c4ebd", "builtAt": "2026-10-22T16:00:00Z"}
	for k, v := range want {
		if got[k] != v {
			t.Errorf("%s = %q, want %q", k, got[k], v)
		}
	}
}
