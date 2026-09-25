#!/usr/bin/env bash
# Smoke-test one stack on a disposable Docker host (used by CI):
#   1. pull every image (proves the pinned tags exist)
#   2. create throw-away secrets and .env from .env.example
#   3. docker compose up --wait: every service must become healthy / complete
#   4. tear everything down, including volumes
#
# Usage: scripts/smoke-test.sh stacks/<category>/<service>
# Exit codes: 0 = healthy, 1 = failed, 2 = external dependency (started only, see EXTERNAL below)
set -uo pipefail

stack="${1:?usage: $0 stacks/<category>/<service>}"
stack="${stack%/}"
name=$(basename "$stack")
project="smoke-$name"
timeout="${SMOKE_TIMEOUT:-900}"

# Stacks that cannot become healthy without a real third-party account/peer.
# For these we only verify that images pull and containers start.
declare -A EXTERNAL=(
  [cloudflared]="needs a real Cloudflare Tunnel token"
  [twingate-connector]="needs a real Twingate network and connector tokens"
  [gitlab-runner]="needs a GitLab instance and runner token"
  [arcane-agent]="needs an Arcane manager to connect to"
  [renovate]="needs a Mend Renovate licence key and a GitLab token"
)

log() { printf '\n==> %s\n' "$*"; }
compose() { docker compose -p "$project" --project-directory "$stack" --env-file "$stack/.env" -f "$stack/compose.yaml" "$@"; }

cleanup() {
  compose down -v --remove-orphans >/dev/null 2>&1 || true
  rm -f "$stack/.env"
  find "$stack/secrets" -type f ! -name .gitkeep -delete 2>/dev/null || true
}
trap cleanup EXIT

rand_hex() { openssl rand -hex "${1:-32}" | tr -d '\n'; }
htpass() { docker run --rm docker.io/library/httpd:2.4.68-alpine htpasswd -nbB "$1" "$2" | tr -d '\r' | head -1; }

log "Preparing $stack"
cp "$stack/.env.example" "$stack/.env"
# Values a stack deliberately requires (${VAR:?...}) get a placeholder.
grep -hoE '\$\{[A-Z0-9_]+:\?' "$stack"/compose.yaml | sed -E 's/\$\{([A-Z0-9_]+):\?/\1/' | sort -u \
  | while read -r v; do grep -qE "^$v=.+" "$stack/.env" || echo "$v=smoke-placeholder" >> "$stack/.env"; done || true

mkdir -p "$stack/secrets"
grep -hoE 'file: *\./secrets/[^[:space:]]+' "$stack/compose.yaml" | awk '{print $2}' | sed 's#^\./secrets/##' | sort -u \
  | while read -r s; do
      f="$stack/secrets/$s"
      case "$name/$s" in
        traefik/dashboard_users)            htpass admin "$(rand_hex 12)" > "$f" ;;
        adguardhome/adguard_admin)          htpass admin "$(rand_hex 12)" > "$f" ;;
        bind9/bind_tsig_key)                printf 'key "tsig-transfer-key" {\n    algorithm hmac-sha256;\n    secret "%s";\n};\n' "$(openssl rand -base64 32)" > "$f" ;;
        infisical/infisical_encryption_key) rand_hex 16 > "$f" ;;
        netbird/netbird_config.yaml)
          host=$(grep -E '^NETBIRD_HOST=' "$stack/.env" | cut -d= -f2-)
          sed -e "s|netbird.example.com|${host:-netbird.example.com}|g" \
              -e "s|__RELAY_AUTH_SECRET__|$(openssl rand -base64 32)|" \
              -e "s|__STORE_ENCRYPTION_KEY__|$(openssl rand -base64 32)|" \
              "$stack/config/config.yaml.example" > "$f" ;;
        *) rand_hex 32 > "$f" ;;   # hex: safe inside URLs and >= 50 chars
      esac
    done
chmod 444 "$stack"/secrets/* 2>/dev/null || true

log "Pulling images"
if ! compose pull --quiet; then
  echo "::error title=$name::image pull failed"
  exit 1
fi

if [ -n "${EXTERNAL[$name]:-}" ]; then
  log "External dependency: ${EXTERNAL[$name]}. Checking that containers start"
  compose up -d --no-build 2>&1 | tee /tmp/up.log
  sleep 20
  compose ps -a
  if compose ps -a --format '{{.State}}' | grep -qE 'created|dead'; then
    details="$(tail -8 /tmp/up.log)"$'
'"$(compose ps -a --format '{{.Service}}: {{.State}} exit={{.ExitCode}}')"$'
'"$(compose logs --no-color --tail 15 2>&1 | cut -c1-240)"
    echo "::error title=$name::containers failed to start%0A$(printf '%s' "$details" | tail -c 3000 | sed ':a;N;$!ba;s/%/%25/g;s///g;s/
/%0A/g')"
    exit 1
  fi
  echo "::notice title=$name::images pulled and containers started; health not asserted (${EXTERNAL[$name]})"
  exit 2
fi

log "Starting (timeout ${timeout}s)"
if compose up -d --wait --wait-timeout "$timeout" 2>&1 | tee /tmp/up.log; [ "${PIPESTATUS[0]}" -eq 0 ]; then
  compose ps -a
  log "PASS: $name is healthy"
  exit 0
fi

log "FAIL: $name did not become healthy"
compose ps -a
summary="[compose up] $(grep -vE '^\s*(Container|Network|Volume) .*(Creat|Start|Wait|Healthy|Exited|Running)' /tmp/up.log | tail -8)"$'\n'
# Everything that is not running-and-healthy, except one-shot jobs that completed successfully.
bad=$(compose ps -a --format '{{.Service}} {{.State}} {{.Health}} {{.ExitCode}}' \
  | awk '!($2=="exited" && $4=="0") && ($2!="running" || ($3!="" && $3!="healthy")) {print $1}')
for svc in $bad; do
  state=$(compose ps -a "$svc" --format '{{.State}} {{.Health}} exit={{.ExitCode}}')
  all=$(compose logs --no-color "$svc" 2>&1 | cut -c1-240)
  # Key error lines from the whole log, then the tail.
  logs=$(printf '%s\n' "$all" | grep -iE 'error|fatal|panic|denied|not permitted|refused|invalid|cannot|failed|no such' | head -15
         echo '  ...'
         printf '%s\n' "$all" | tail -12)
  printf '\n--- %s (%s) ---\n%s\n' "$svc" "$state" "$logs"
  summary+="[$svc: $state]"$'\n'"$logs"$'\n'
done
echo "::error title=$name::$(printf '%s' "$summary" | tail -c 3500 | sed ':a;N;$!ba;s/%/%25/g;s/\r//g;s/\n/%0A/g')"
exit 1
