#!/usr/bin/env bash
# Create the secrets/ directory for a stack and generate random values for
# generated-type secrets (passwords, keys, salts). Secrets that must come from
# an external system (API tokens, licence keys, htpasswd files) are listed so
# you can provide them manually.
#
# Usage: scripts/init-secrets.sh stacks/<category>/<service>
set -euo pipefail

stack="${1:?usage: $0 stacks/<category>/<service>}"
compose="$stack/compose.yaml"
[ -f "$compose" ] || { echo "no compose.yaml in $stack" >&2; exit 1; }

umask 077
mkdir -p "$stack/secrets"
chmod 700 "$stack/secrets"

generated_pattern='(password|passwd|secret|secret_key|encryption|jwt|salt|session|cookie|signing|key_base|db_key)'
manual_pattern='(api_token|dns_token|cf_|license|htpasswd|users|oauth|client_secret|smtp|access_key|tunnel_token|connector|join_token|refresh_token)'

missing_manual=()
while read -r path; do
  file="$stack/${path#./}"
  name=$(basename "$file")
  if [ -s "$file" ]; then
    echo "exists    $name"
    continue
  fi
  lower=$(echo "$name" | tr '[:upper:]' '[:lower:]')
  if [[ "$lower" =~ $manual_pattern ]] || ! [[ "$lower" =~ $generated_pattern ]]; then
    missing_manual+=("$name")
    continue
  fi
  openssl rand -base64 48 | tr -d '\n/+=' | cut -c1-48 > "$file"
  echo "generated $name"
done < <(grep -oE 'file: *\./secrets/[^[:space:]]+' "$compose" | awk '{print $2}' | sort -u)

# Readable by non-root container users; directory stays owner-only.
find "$stack/secrets" -type f ! -name .gitkeep -exec chmod 444 {} +

if [ ${#missing_manual[@]} -gt 0 ]; then
  echo
  echo "Provide these manually (see $stack/README.md):"
  printf '  %s/secrets/%s\n' "$stack" "${missing_manual[@]}"
fi
