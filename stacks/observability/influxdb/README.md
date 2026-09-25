# InfluxDB

Time-series database (InfluxDB 2.x OSS) for metrics, IoT and analytics data, with a built-in UI
and a token-authenticated HTTP API.

| | |
|---|---|
| Image | `docker.io/library/influxdb:2.9.1-alpine` |
| Exposed | Nothing published; 8086 on the `monitoring` network and via Traefik (internal-only) |

## Quick start

```bash
docker network create proxy                     # once per host (shared with Traefik)
docker network create --internal monitoring     # once per host (shared observability backend)
cp .env.example .env && vi .env                 # set INFLUXDB_HOST, org, bucket
mkdir -p secrets && chmod 700 secrets
openssl rand -base64 32 | tr -d '\n' > secrets/influxdb_admin_password
openssl rand -hex 32 | tr -d '\n' > secrets/influxdb_admin_token
chmod 444 secrets/*                             # readable by the non-root container user; dir stays 700
docker compose up -d
```

Grafana and other stacks on the external `monitoring` network reach it as
`http://influxdb:8086`. To publish the API on a host port instead, use
`docker compose -f compose.yaml -f compose.expose-ports.yaml up -d` (binds `127.0.0.1` by
default).

## Security notes

- Runs as the image's `influxdb` user (UID 1000) with all capabilities dropped and a read-only
  root filesystem. Only the two named volumes and `/tmp` (tmpfs, used by the setup step) are
  writable.
- The initial admin password and the operator API token are Docker secrets, read through the
  entrypoint's `DOCKER_INFLUXDB_INIT_PASSWORD_FILE` / `DOCKER_INFLUXDB_INIT_ADMIN_TOKEN_FILE`.
  They are used only on the first start. Afterwards, rotate them in the UI or CLI. The operator
  token has full access, so create scoped read/write tokens for Grafana, Telegraf and other
  clients.
- The influx CLI config written during setup (`/etc/influxdb2/influx-configs`, in the
  `influxdb-config` volume) contains the operator token. Treat that volume as sensitive.
- Telemetry to InfluxData is disabled (`INFLUXD_REPORTING_DISABLED`).
- The UI/API is published through Traefik with `internal-only@file`. If remote writers on the
  internet need access, remove the middleware and rely on scoped tokens over HTTPS.

## Backup

```bash
docker compose exec influxdb sh -c 'influx backup /tmp/backup -t "$(cat /run/secrets/influxdb_admin_token)" && tar czf - -C /tmp backup' \
  > influxdb-$(date +%F).tar.gz
docker compose exec influxdb rm -rf /tmp/backup
```

Restore with `influx restore`. Keep `secrets/` in your secret manager.
