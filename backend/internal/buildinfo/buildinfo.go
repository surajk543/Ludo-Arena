// Package buildinfo identifies the running backend binary. Release builds set
// the values at link time (deploy/scripts/ludo-deploy):
//
//	go build -ldflags "-X ludoarena/internal/buildinfo.Version=v1.0.0 \
//	  -X ludoarena/internal/buildinfo.Commit=f9c4ebd \
//	  -X ludoarena/internal/buildinfo.BuiltAt=2026-10-22T16:00:00Z"
package buildinfo

var (
	// Version is the release tag (git describe), "dev" for local builds.
	Version = "dev"
	// Commit is the short commit hash the binary was built from.
	Commit = ""
	// BuiltAt is the UTC build time (RFC 3339).
	BuiltAt = ""
)

// Health is the GET /healthz body: liveness plus the build identity.
func Health() map[string]string {
	return map[string]string{"status": "ok", "version": Version, "commit": Commit, "builtAt": BuiltAt}
}
