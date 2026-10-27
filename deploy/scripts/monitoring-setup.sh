#!/usr/bin/env bash
# monitoring-setup.sh: installs or updates the monitoring stack on the
# production VPS, next to the backend (deploy/README.md → Monitoring):
#
#   Prometheus 127.0.0.1:9095, Alertmanager 127.0.0.1:9093, node_exporter
#   127.0.0.1:9100 (pinned release binaries, checked against the release's
#   sha256sums.txt) and the Telegram ops bot 127.0.0.1:9097 (built from the
#   source checkout at <ref>, like ludo-deploy). Systemd units ludo-*.service
#   run them with DynamicUser; nothing listens publicly.
#
#   scp -r deploy root@<host>:/root/
#   ssh root@<host> bash /root/deploy/scripts/monitoring-setup.sh [ref]   # default master
#
# Idempotent: re-run it to update the ops bot and the rules to <ref>. It keeps
# Prometheus data and existing secrets:
#   - /etc/ludo-arena/secrets/ops-admin.key: the operator key, generated once.
#     If the backend's ADMIN_API_KEY_SHA256 is empty it is set to the key's
#     sha256 and the backend restarts (WebSockets reconnect).
#   - /etc/ludo-arena/ops-bot.env (0600 root): created from
#     monitoring/.env.example. OPS_BOT_SET=<file> merges its KEY=value lines
#     (e.g. TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_IDS) into it and deletes the
#     file. The ops bot starts only once `ops-bot --validate` accepts it.
set -euo pipefail

REF=${1:-master}
DEPLOY=$(cd "$(dirname "$0")/.." && pwd)
SRC=/opt/ludo-arena/src
BIN=/opt/ludo-monitoring/bin
CONF=/etc/ludo-monitoring
ETC=/etc/ludo-arena
ENVFILE=$ETC/ops-bot.env
KEYFILE=$ETC/secrets/ops-admin.key
BACKEND_ENV=$ETC/backend.env
PROMETHEUS_VERSION=3.15.0
ALERTMANAGER_VERSION=0.34.1
NODE_EXPORTER_VERSION=1.12.1
ARCH=linux-amd64

log() { printf '==> %s\n' "$*"; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }
die() { echo "monitoring-setup: $*" >&2; exit 1; }

[[ $(id -u) == 0 ]] || die "run as root"
[[ $(uname -m) == x86_64 ]] || die "only $ARCH binaries are pinned"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# set_env <file> <key> <value>: replaces or appends KEY=value in place (keeps
# the file's mode; the value never appears in a process list).
set_env() {
  local f=$1 k=$2 v=$3 line out="" found=0
  while IFS= read -r line || [[ -n $line ]]; do
    if [[ $line == "$k="* ]]; then
      out+="$k=$v"$'\n'
      found=1
    else
      out+="$line"$'\n'
    fi
  done < "$f"
  ((found)) || out+="$k=$v"$'\n'
  printf '%s' "$out" > "$f"
}

get_env() { grep -E "^$2=" "$1" | tail -n 1 | cut -d= -f2- || true; }

wait_ok() {
  for _ in $(seq 1 30); do
    curl -fsS -o /dev/null "$1" 2>/dev/null && return 0
    sleep 1
  done
  journalctl -u "$3" -n 20 --no-pager -o cat >&2 || true
  die "$2 is not healthy ($1)"
}

# fetch_release <project> <version> <binaries...>: installs the binaries of
# a prometheus/<project> release unless that version is already installed.
fetch_release() {
  local project=$1 version=$2
  shift 2
  if [[ -x $BIN/$1 ]] && "$BIN/$1" --version 2>&1 | grep -q "version $version "; then
    log "$project $version is installed"
    return
  fi
  local name=$project-$version.$ARCH url=https://github.com/prometheus/$project/releases/download/v$version
  log "downloading $project $version"
  curl -fsSL -o "$WORK/$name.tar.gz" "$url/$name.tar.gz"
  curl -fsSL -o "$WORK/$project-sha256sums.txt" "$url/sha256sums.txt"
  (cd "$WORK" && grep -E "  $name\.tar\.gz\$" "$project-sha256sums.txt" | sha256sum -c --quiet -) ||
    die "$project $version: checksum mismatch"
  tar -xzf "$WORK/$name.tar.gz" -C "$WORK"
  for b in "$@"; do
    install -m 0755 "$WORK/$name/$b" "$BIN/$b"
  done
}

install -d -m 0755 /opt/ludo-monitoring "$BIN" "$CONF" "$CONF/rules"
fetch_release prometheus "$PROMETHEUS_VERSION" prometheus promtool
fetch_release alertmanager "$ALERTMANAGER_VERSION" alertmanager amtool
fetch_release node_exporter "$NODE_EXPORTER_VERSION" node_exporter

log "source at $REF"
git -C "$SRC" fetch --quiet --prune --tags origin
commit=$(git -C "$SRC" rev-parse --verify --quiet "origin/$REF^{commit}" ||
  git -C "$SRC" rev-parse --verify --quiet "$REF^{commit}") || die "unknown ref: $REF"
git -C "$SRC" archive "$commit" monitoring | tar -x -C "$WORK"
M=$WORK/monitoring
log "building the ops bot ($(git -C "$SRC" describe --tags --always "$commit"))"
(cd "$M/ops-bot" && CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o "$WORK/ops-bot" ./cmd/ops-bot)

log "checking the rules and configuration"
"$BIN/promtool" check rules "$M"/prometheus/rules/*.yml >/dev/null
(cd "$M/prometheus/tests" && "$BIN/promtool" test rules alerts_test.yml) || die "alert rule tests failed"
# The Docker config reaches the bot as ops-bot:9097; here it is on loopback.
sed 's#http://ops-bot:9097/alertmanager#http://127.0.0.1:9097/alertmanager#' \
  "$M/alertmanager/alertmanager.yml" > "$WORK/alertmanager.yml"
grep -q 'url: http://127.0.0.1:9097/alertmanager' "$WORK/alertmanager.yml" || die "alertmanager.yml: ops-bot webhook URL not found"
"$BIN/amtool" check-config "$WORK/alertmanager.yml" >/dev/null
rm -f "$CONF"/rules/*.yml
install -m 0644 "$M"/prometheus/rules/*.yml "$CONF/rules/"
install -m 0644 "$DEPLOY/monitoring/prometheus.yml" "$CONF/prometheus.yml"
install -m 0644 "$WORK/alertmanager.yml" "$CONF/alertmanager.yml"
"$BIN/promtool" check config "$CONF/prometheus.yml" >/dev/null

log "operator key"
if [[ ! -s $KEYFILE ]]; then
  (umask 077 && openssl rand -hex 32 | tr -d '\n' > "$KEYFILE")
  log "generated $KEYFILE"
fi
key=$(tr -d '[:space:]' < "$KEYFILE")
hash=$(printf '%s' "$key" | sha256sum | cut -d' ' -f1)
current=$(get_env "$BACKEND_ENV" ADMIN_API_KEY_SHA256)
key_matches=0
if [[ -z $current ]]; then
  cp -p "$BACKEND_ENV" "$BACKEND_ENV.bak-$(date -u +%Y%m%d%H%M%S)-opskey"
  set_env "$BACKEND_ENV" ADMIN_API_KEY_SHA256 "$hash"
  log "backend: ADMIN_API_KEY_SHA256 set; restarting ludo-backend"
  systemctl restart ludo-backend
  wait_ok http://127.0.0.1:8080/readyz backend ludo-backend
  key_matches=1
elif [[ $current == "$hash" ]]; then
  key_matches=1
else
  warn "the backend's ADMIN_API_KEY_SHA256 belongs to another key: set BACKEND_ADMIN_KEY in $ENVFILE to that key by hand"
fi

log "ops bot settings ($ENVFILE)"
if [[ ! -f $ENVFILE ]]; then
  install -m 0600 -o root -g root "$M/.env.example" "$ENVFILE"
  set_env "$ENVFILE" ENV_NAME production
  set_env "$ENVFILE" TELEGRAM_BOT_TOKEN ""
  set_env "$ENVFILE" TELEGRAM_CHAT_IDS ""
  set_env "$ENVFILE" BACKEND_API_URL http://127.0.0.1:8080
  log "created $ENVFILE"
fi
chmod 0600 "$ENVFILE"
set_env "$ENVFILE" PROM_URL http://127.0.0.1:9095
set_env "$ENVFILE" HTTP_ADDR 127.0.0.1:9097
if [[ -n ${OPS_BOT_SET:-} ]]; then
  [[ -f $OPS_BOT_SET ]] || die "OPS_BOT_SET: no file $OPS_BOT_SET"
  while IFS= read -r line || [[ -n $line ]]; do
    [[ $line =~ ^([A-Z][A-Z0-9_]*)=(.*)$ ]] || continue
    set_env "$ENVFILE" "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
  done < "$OPS_BOT_SET"
  rm -f "$OPS_BOT_SET"
  log "merged the settings from OPS_BOT_SET"
fi
if ((key_matches)) && [[ -z $(get_env "$ENVFILE" BACKEND_ADMIN_KEY) ]]; then
  set_env "$ENVFILE" BACKEND_ADMIN_KEY "$key"
fi
install -m 0755 "$WORK/ops-bot" "$BIN/ops-bot"

log "services"
for unit in ludo-node-exporter ludo-prometheus ludo-alertmanager ludo-ops-bot; do
  install -m 0644 "$DEPLOY/systemd/$unit.service" "/etc/systemd/system/$unit.service"
done
systemctl daemon-reload
systemctl enable --quiet ludo-node-exporter ludo-prometheus ludo-alertmanager
systemctl restart ludo-node-exporter ludo-prometheus ludo-alertmanager
wait_ok http://127.0.0.1:9100/metrics node_exporter ludo-node-exporter
wait_ok http://127.0.0.1:9095/-/ready Prometheus ludo-prometheus
wait_ok http://127.0.0.1:9093/-/ready Alertmanager ludo-alertmanager

if (set -a && . "$ENVFILE" && set +a && "$BIN/ops-bot" --validate >/dev/null 2>&1); then
  systemctl enable --quiet ludo-ops-bot
  systemctl restart ludo-ops-bot
  wait_ok http://127.0.0.1:9097/healthz "ops bot" ludo-ops-bot
  log "ops bot running"
else
  systemctl disable --now --quiet ludo-ops-bot 2>/dev/null || true
  warn "ops bot not started: $ENVFILE is incomplete (check with:"
  warn "  set -a; . $ENVFILE; set +a; $BIN/ops-bot --validate)"
fi
log "done ($REF): prometheus $PROMETHEUS_VERSION, alertmanager $ALERTMANAGER_VERSION, node_exporter $NODE_EXPORTER_VERSION"
