# Loki

Log aggregation backend for Grafana. Alloy pushes logs to it, and Grafana queries it.

| | |
|---|---|
| Image | `docker.io/grafana/loki:3.7.8` |
| Exposed | Nothing published; 3100 on the `monitoring` network and via Traefik (internal-only) |

## Quick start

```bash
docker network create proxy                     # once per host (shared with Traefik)
docker network create --internal monitoring     # once per host (shared observability backend)
cp .env.example .env && vi .env                 # set LOKI_HOST, retention
docker compose up -d
```

No secrets are needed. Other stacks reach Loki as `http://loki:3100` by joining the external
`monitoring` network. The push URL is `http://loki:3100/loki/api/v1/push`.

To publish the API on a host port instead, use the override:
`docker compose -f compose.yaml -f compose.expose-ports.yaml up -d` (binds `127.0.0.1` by
default; set `BIND_ADDRESS` and `LOKI_PORT` in `.env`).

## Security notes

- Runs as UID 10001 on the distroless upstream image, with all capabilities dropped and a
  read-only root filesystem. Only `/loki` (named volume) and `/tmp` (tmpfs) are writable.
- The healthcheck uses Loki's built-in `-health` probe, since the image has no shell or HTTP
  client.
- `auth_enabled: false` (single tenant) is the upstream default for single-node use. There is no
  authentication, so the API is only reachable on the `monitoring` network and through Traefik
  with `internal-only@file`. Anyone who can reach it can push and read all logs. For
  multi-tenant or internet-facing use, put an authenticating proxy in front and enable
  `auth_enabled`.
- Retention is enforced by the compactor (`retention_enabled: true`). The template's
  `retention_period` alone did nothing without it.
- Usage reporting to Grafana Labs is disabled.

## Backup

Stop the stack (or accept a crash-consistent copy) and archive the `loki-data` volume:

```bash
docker compose stop loki
docker run --rm -v loki_loki-data:/data:ro -v "$PWD":/backup docker.io/library/alpine:3.24.2 \
  tar czf /backup/loki-$(date +%F).tar.gz -C /data .
docker compose start loki
```
