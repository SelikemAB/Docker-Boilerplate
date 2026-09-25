#!/bin/sh
# Renders config.toml from the template, then hands over to the upstream entrypoint.
set -eu
umask 077

: "${GITLAB_URL:?GITLAB_URL must be set}"
TOKEN="$(tr -d '\r\n' < /run/secrets/gitlab_runner_token)"
[ -n "$TOKEN" ] || { echo "empty runner token" >&2; exit 1; }

sed -e "s|@@GITLAB_URL@@|${GITLAB_URL}|g" \
    -e "s|@@RUNNER_NAME@@|${RUNNER_NAME:-gitlab-runner}|g" \
    -e "s|@@RUNNER_CONCURRENT@@|${RUNNER_CONCURRENT:-4}|g" \
    -e "s|@@RUNNER_EXECUTOR_IMAGE@@|${RUNNER_EXECUTOR_IMAGE:-docker.io/library/alpine:3.24.2}|g" \
    -e "s|@@RUNNER_PRIVILEGED@@|${RUNNER_PRIVILEGED:-false}|g" \
    -e "s|@@RUNNER_TOKEN@@|${TOKEN}|g" \
    /opt/gitlab-runner/config.toml.tmpl > /etc/gitlab-runner/config.toml

exec /entrypoint "$@"
