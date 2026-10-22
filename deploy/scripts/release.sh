#!/usr/bin/env bash
# Builds backend + bot-play for linux/amd64 from the current checkout and
# installs them as a new release on the VPS, then restarts both services.
#
#   deploy/scripts/release.sh [ssh-target]     (default root@ludo.sungamestudio.com)
#   SSH_OPTS="-o ControlPath=/tmp/ludo.sock" deploy/scripts/release.sh root@129.121.171.63
#
# Releases live in /opt/ludo-royale/releases/<utc>-<commit>; /opt/ludo-royale/current
# points at the active one. Roll back with: ROLLBACK=1 deploy/scripts/release.sh
# (re-points current at the release before it). Restarting the backend closes every
# WebSocket with 1001; clients reconnect and resync.
set -euo pipefail

TARGET=${1:-root@ludo.sungamestudio.com}
read -r -a SSH <<< "ssh ${SSH_OPTS:-}"
read -r -a SCP <<< "scp ${SSH_OPTS:-}"
ROOT=$(git rev-parse --show-toplevel)
KEEP=5

remote() { "${SSH[@]}" "$TARGET" "$@"; }

restart() {
  remote 'set -e
    systemctl restart ludo-backend
    for i in $(seq 1 30); do
      curl -fsS http://127.0.0.1:8080/readyz >/dev/null 2>&1 && break
      sleep 1
    done
    curl -fsS http://127.0.0.1:8080/readyz
    echo
    systemctl restart ludo-bot-play
    systemctl --no-pager --lines=0 status ludo-backend ludo-bot-play'
}

if [[ -n ${ROLLBACK:-} ]]; then
  remote "set -e; cd /opt/ludo-royale/releases
    cur=\$(basename \"\$(readlink -f /opt/ludo-royale/current)\")
    prev=\$(ls -1 | sort | awk -v c=\"\$cur\" '\$0 == c { print p; exit } { p = \$0 }')
    [ -n \"\$prev\" ] || { echo 'no previous release' >&2; exit 1; }
    ln -sfn \"/opt/ludo-royale/releases/\$prev\" /opt/ludo-royale/current.tmp
    mv -T /opt/ludo-royale/current.tmp /opt/ludo-royale/current
    echo \"current -> \$prev\""
  restart
  exit 0
fi

[[ -z $(git -C "$ROOT" status --porcelain -- backend bot-play) ]] ||
  echo "warning: backend/ or bot-play/ has uncommitted changes; they are included" >&2

REL=$(date -u +%Y%m%d%H%M%S)-$(git -C "$ROOT" rev-parse --short HEAD)
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT
mkdir -p "$OUT/$REL/backend" "$OUT/$REL/bot-play/configs/environments"

echo "==> building $REL"
(cd "$ROOT/backend" && GOOS=linux GOARCH=amd64 CGO_ENABLED=0 \
  go build -trimpath -ldflags="-s -w" -o "$OUT/$REL/backend/ludo-server" ./cmd/server)
(cd "$ROOT/bot-play" && GOOS=linux GOARCH=amd64 CGO_ENABLED=0 \
  go build -trimpath -ldflags="-s -w" -o "$OUT/$REL/bot-play/bot-play" ./cmd/bot-play)
cp -R "$ROOT/backend/config" "$OUT/$REL/backend/config"
cp "$ROOT/bot-play/configs/profiles.yaml" "$OUT/$REL/bot-play/configs/"
cp "$ROOT/bot-play/configs/environments/production.yaml" "$OUT/$REL/bot-play/configs/environments/"
COPYFILE_DISABLE=1 tar --no-xattrs -C "$OUT" -czf "$OUT/release.tgz" "$REL"

echo "==> uploading to $TARGET"
"${SCP[@]}" -q "$OUT/release.tgz" "$TARGET:/tmp/ludo-release.tgz"
remote "set -e
  tar -C /opt/ludo-royale/releases -xzf /tmp/ludo-release.tgz && rm -f /tmp/ludo-release.tgz
  chown -R root:root /opt/ludo-royale/releases/$REL
  ln -sfn /opt/ludo-royale/releases/$REL /opt/ludo-royale/current.tmp
  mv -T /opt/ludo-royale/current.tmp /opt/ludo-royale/current
  cd /opt/ludo-royale/releases && ls -1 | sort | head -n -$KEEP | xargs -r rm -rf"

echo "==> restarting"
restart
echo "==> released $REL"
