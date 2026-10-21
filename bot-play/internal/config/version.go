package config

import (
	"regexp"
	"strconv"
)

// Version and Build identify this bot-play binary. They are sent to the
// backend as X-App-Version / X-App-Build on the WebSocket handshake (bots are
// exempt from the app version policy; the headers are informational) and are
// overridable at link time:
//
//	go build -ldflags "-X ludoroyale/botplay/internal/config.Version=1.2.0 -X ludoroyale/botplay/internal/config.Build=42"
var (
	Version = "1.0.0"
	Build   = "1"
)

var versionRE = regexp.MustCompile(`^\d+(\.\d+){0,3}$`)

// ClientVersion returns a version/build pair that satisfies the backend's
// header format (1-4 numeric components, positive integer build), falling
// back to 1.0.0 / 1 when the link-time values are malformed.
func ClientVersion() (version, build string) {
	version, build = Version, Build
	if !versionRE.MatchString(version) {
		version = "1.0.0"
	}
	if n, err := strconv.Atoi(build); err != nil || n < 1 {
		build = "1"
	}
	return version, build
}
