#!/usr/bin/env bash
# Provisions an Ubuntu 24.04 VPS for Ludo Royale: PostgreSQL 16, Redis 7,
# nginx + Let's Encrypt, kernel limits, firewall, users, systemd units.
# Idempotent: re-running keeps existing secrets, data and certificates.
#
#   scp -r deploy root@HOST:/root/ && ssh root@HOST bash /root/deploy/scripts/provision.sh
#
# Then install a release with deploy/scripts/release.sh.
set -euo pipefail

DOMAIN=${DOMAIN:-ludo.sungamestudio.com}
DEPLOY=$(cd "$(dirname "$0")/.." && pwd)
ETC=/etc/ludo-royale

log() { printf '\n==> %s\n' "$*"; }
secret() { openssl rand -hex 32; }

log "packages"
export DEBIAN_FRONTEND=noninteractive
apt-get update -q
apt-get install -y -q nginx postgresql redis-server certbot ufw openssl ca-certificates curl

log "kernel limits"
echo nf_conntrack > /etc/modules-load.d/ludo-royale.conf
modprobe nf_conntrack
install -m 0644 "$DEPLOY/sysctl/99-ludo-royale.conf" /etc/sysctl.d/99-ludo-royale.conf
sysctl --quiet --system

log "service user and directories"
id ludo >/dev/null 2>&1 || useradd --system --home /opt/ludo-royale --shell /usr/sbin/nologin ludo
install -d -m 0755 /opt/ludo-royale /opt/ludo-royale/releases
install -d -m 0750 -o root -g ludo "$ETC" "$ETC/secrets"

log "redis"
REDIS_SECRET=/etc/redis/ludo-royale-secret.conf
if [[ ! -f $REDIS_SECRET ]]; then
  printf 'requirepass %s\n' "$(secret)" > "$REDIS_SECRET"
fi
chown redis:redis "$REDIS_SECRET" && chmod 0640 "$REDIS_SECRET"
install -m 0640 -o redis -g redis "$DEPLOY/redis/ludo-royale.conf" /etc/redis/ludo-royale.conf
grep -qxF 'include /etc/redis/ludo-royale.conf' /etc/redis/redis.conf ||
  echo 'include /etc/redis/ludo-royale.conf' >> /etc/redis/redis.conf
systemctl enable --now redis-server
systemctl restart redis-server
REDIS_PASSWORD=$(awk '{print $2}' "$REDIS_SECRET")

log "postgresql"
install -m 0644 "$DEPLOY/postgresql/ludo-royale.conf" /etc/postgresql/16/main/conf.d/ludo-royale.conf
systemctl enable --now postgresql
systemctl restart postgresql@16-main
DB_PASSWORD_FILE=$ETC/secrets/db-password
if [[ ! -f $DB_PASSWORD_FILE ]]; then
  secret > "$DB_PASSWORD_FILE" && chmod 0600 "$DB_PASSWORD_FILE"
fi
DB_PASSWORD=$(cat "$DB_PASSWORD_FILE")
sudo -u postgres psql -v ON_ERROR_STOP=1 -q <<SQL
DO \$\$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'ludo') THEN
    CREATE ROLE ludo LOGIN PASSWORD '$DB_PASSWORD';
  ELSE
    ALTER ROLE ludo PASSWORD '$DB_PASSWORD';
  END IF;
END \$\$;
SQL
sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname = 'ludo_royale'" | grep -q 1 ||
  sudo -u postgres createdb -O ludo ludo_royale

log "backend + bot-play environment"
if [[ ! -f $ETC/bot-play.env ]]; then
  printf 'BOT_SERVICE_KEY=%s\n' "$(secret)" > "$ETC/bot-play.env"
fi
chown root:ludo "$ETC/bot-play.env" && chmod 0640 "$ETC/bot-play.env"
BOT_KEY_SHA=$(sed -n 's/^BOT_SERVICE_KEY=//p' "$ETC/bot-play.env" | tr -d '\n' | sha256sum | awk '{print $1}')
if [[ ! -f $ETC/backend.env ]]; then
  env_tmp=$(mktemp)
  cp "$DEPLOY/backend.env.example" "$env_tmp"
  while grep -q '__GENERATED__' "$env_tmp"; do
    sed -i "0,/__GENERATED__/s//$(secret)/" "$env_tmp"
  done
  sed -i -e "s/__DB_PASSWORD__/$DB_PASSWORD/" -e "s/__REDIS_PASSWORD__/$REDIS_PASSWORD/" \
    -e "s/__BOT_SERVICE_KEY_SHA256__/$BOT_KEY_SHA/" "$env_tmp"
  install -m 0640 -o root -g ludo "$env_tmp" "$ETC/backend.env"
  rm -f "$env_tmp"
fi

log "systemd units"
install -m 0644 "$DEPLOY/systemd/ludo-backend.service" /etc/systemd/system/ludo-backend.service
install -m 0644 "$DEPLOY/systemd/ludo-bot-play.service" /etc/systemd/system/ludo-bot-play.service
install -d /etc/systemd/system/nginx.service.d
install -m 0644 "$DEPLOY/systemd/nginx-limits.conf" /etc/systemd/system/nginx.service.d/limits.conf
systemctl daemon-reload
systemctl enable ludo-backend ludo-bot-play

log "bot-play reaches the backend over loopback (same TLS name)"
grep -qE "^127\.0\.0\.1\s+$DOMAIN\$" /etc/hosts || echo "127.0.0.1 $DOMAIN" >> /etc/hosts

log "nginx + certificate"
install -d -m 0755 /var/www/letsencrypt
install -m 0644 "$DEPLOY/nginx/nginx.conf" /etc/nginx/nginx.conf
rm -f /etc/nginx/sites-enabled/default
if [[ ! -f /etc/letsencrypt/live/$DOMAIN/fullchain.pem ]]; then
  # HTTP-only server for the ACME challenge until the certificate exists.
  cat > /etc/nginx/sites-enabled/acme-bootstrap <<NGINX
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;
    location /.well-known/acme-challenge/ { root /var/www/letsencrypt; }
}
NGINX
  nginx -t && systemctl restart nginx
  certbot certonly --webroot -w /var/www/letsencrypt -d "$DOMAIN" \
    --non-interactive --agree-tos --register-unsafely-without-email
  rm -f /etc/nginx/sites-enabled/acme-bootstrap
fi
install -d /etc/letsencrypt/renewal-hooks/deploy
printf '#!/bin/sh\nsystemctl reload nginx\n' > /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh
chmod 0755 /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh
install -m 0644 "$DEPLOY/nginx/$DOMAIN.conf" "/etc/nginx/sites-available/$DOMAIN"
ln -sf "/etc/nginx/sites-available/$DOMAIN" "/etc/nginx/sites-enabled/$DOMAIN"
nginx -t
systemctl daemon-reload
systemctl enable nginx
systemctl restart nginx

log "nightly database backup"
install -d -m 0700 -o postgres -g postgres /var/backups/ludo-royale
cat > /etc/cron.d/ludo-royale-backup <<'CRON'
# Nightly pg_dump of wallets, identities and progression; keeps 14 days.
30 21 * * * postgres pg_dump -Fc ludo_royale > /var/backups/ludo-royale/ludo_royale-$(date +\%F).dump && find /var/backups/ludo-royale -name '*.dump' -mtime +14 -delete
CRON

log "firewall: ssh, http, https only"
ufw allow OpenSSH >/dev/null
ufw allow 80/tcp >/dev/null
ufw allow 443/tcp >/dev/null
ufw --force enable >/dev/null
ufw status verbose

log "done; install a release with deploy/scripts/release.sh"
