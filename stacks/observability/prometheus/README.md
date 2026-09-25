# Prometheus

Metrics server and time-series database. It scrapes targets and receives remote writes from
Grafana Alloy, and Grafana queries it.

| | |
|---|---|
| Image | `docker.io/prom/prometheus:v3.15.0` |
| Exposed | Nothing published; 9090 on the `monitoring` network and via Traefik (internal-only) |

## Quick start

```bash
docker network create proxy                     # once per host (shared with Traefik)
docker network create --internal monitoring     # once per host (shared observability backend)
cp .env.example .env && vi .env                 # set PROMETHEUS_HOST, retention
vi config/prometheus.yaml                       # add scrape jobs
docker compose up -d
```

No secrets are needed. Other stacks reach Prometheus as `http://prometheus:9090` by joining the
external `monitoring` network. The remote-write URL is `http://prometheus:9090/api/v1/write`.

To publish the UI on a host port instead, use the override:
`docker compose -f compose.yaml -f compose.expose-ports.yaml up -d` (binds `127.0.0.1` by
default; set `BIND_ADDRESS` and `PROMETHEUS_PORT` in `.env`).

## Security notes

- Runs as `nobody` (UID 65534) with all capabilities dropped and a read-only root filesystem.
  Only `/prometheus` (named volume) and `/tmp` (tmpfs) are writable. The config is mounted `:ro`.
- The remote-write receiver is **enabled** so the alloy stack can push metrics. It has no
  authentication. It is only reachable on the `monitoring` network and through Traefik with
  `internal-only@file`, so anything in those ranges can write series. Remove
  `--web.enable-remote-write-receiver` if you only scrape.
- The admin API (`--web.enable-admin-api`) and lifecycle API (`--web.enable-lifecycle`) stay
  disabled.
- Prometheus has no login. The UI and API are published only through Traefik with the
  `internal-only@file` allow-list. For stronger access control, add a forward-auth middleware or
  configure `--web.config.file` with basic auth/TLS.
- To scrape Traefik metrics, uncomment the `traefik` job. Prometheus is on the `proxy` network,
  so it can reach `traefik:9100` without publishing a port.

## Backup

Use a TSDB snapshot for a consistent copy. It needs the admin API, so either enable it
temporarily or stop the container and archive the volume:

```bash
docker compose stop prometheus
docker run --rm -v prometheus_prometheus-data:/data:ro -v "$PWD":/backup docker.io/library/alpine:3.24.2 \
  tar czf /backup/prometheus-$(date +%F).tar.gz -C /data .
docker compose start prometheus
```

Back up `config/prometheus.yaml` with the repository.
