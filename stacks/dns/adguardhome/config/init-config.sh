#!/bin/sh
# One-shot init job for AdGuard Home:
#  1. On first start only, renders /seed/AdGuardHome.yaml.tmpl into the conf volume, taking the
#     admin user and bcrypt hash from the Docker secret `adguard_admin` (htpasswd -nbB format).
#  2. Makes the conf/work volumes writable by the non-root runtime user.
set -eu

CONF_DIR=/opt/adguardhome/conf
WORK_DIR=/opt/adguardhome/work
CONF="$CONF_DIR/AdGuardHome.yaml"
SECRET=/run/secrets/adguard_admin

: "${ADGUARD_UID:=65534}"
: "${ADGUARD_GID:=65534}"
: "${ADGUARD_DNS_PORT:=5053}"
: "${ADGUARD_HTTP_ADDRESS:=0.0.0.0:3000}"

if [ ! -s "$CONF" ]; then
  user=""
  hash=""
  IFS=: read -r user hash < "$SECRET" || true
  if [ -z "$user" ] || [ -z "$hash" ]; then
    echo "ERROR: $SECRET must contain 'user:bcrypt-hash' (htpasswd -nbB admin 'PASSWORD')" >&2
    exit 1
  fi
  case "$hash" in
    '$2'*) ;;
    *) echo "ERROR: the password in $SECRET is not a bcrypt hash (use htpasswd -B)" >&2; exit 1 ;;
  esac
  sed \
    -e "s|__ADMIN_USER__|$user|" \
    -e "s|__ADMIN_HASH__|$hash|" \
    -e "s|__HTTP_ADDRESS__|$ADGUARD_HTTP_ADDRESS|" \
    -e "s|__DNS_PORT__|$ADGUARD_DNS_PORT|" \
    /seed/AdGuardHome.yaml.tmpl > "$CONF"
  chmod 600 "$CONF"
  echo "Seeded $CONF (DNS port $ADGUARD_DNS_PORT, web $ADGUARD_HTTP_ADDRESS)"
else
  echo "$CONF exists, leaving it untouched"
fi

chown -R "$ADGUARD_UID:$ADGUARD_GID" "$CONF_DIR" "$WORK_DIR"
chmod 700 "$CONF_DIR"
