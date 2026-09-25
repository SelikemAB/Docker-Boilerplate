# Grafana Alloy

Telemetry collector that ships host logs, the systemd journal and container logs to Loki, and
host and container metrics to Prometheus (remote write).

| | |
|---|---|
| Image | `docker.io/grafana/alloy:v1.19.2` |
| Helper | `docker.io/tecnativa/docker-socket-proxy:v0.5.0` |
| Exposed | Nothing published; web UI on 12345 via Traefik (internal-only) |

## Quick start

```bash
docker network create proxy                     # once per host (shared with Traefik)
docker network create --internal monitoring     # once per host (shared observability backend)
cp .env.example .env && vi .env                 # set ALLOY_HOST, ALLOY_HOSTNAME, destinations
docker compose up -d
```

No secrets are needed. Run the `loki` and `prometheus` stacks on the same host first (or point
`LOKI_URL` / `PROMETHEUS_REMOTE_WRITE_URL` elsewhere). Prometheus must run with
`--web.enable-remote-write-receiver`, which the `prometheus` stack enables.

## Pipelines

Each file in `config/` is one pipeline, and Alloy loads the whole directory. Delete a file to
turn that pipeline off (`targets.alloy` and `common.alloy` are always required).

| File | Collects | Sends to |
|---|---|---|
| `logs_docker.alloy` | Container stdout/stderr (via socket proxy) | Loki |
| `logs_system.alloy` | `/var/log/journal`, `/var/log/{syslog,messages,*.log}` | Loki |
| `metrics_docker.alloy` | Container metrics (embedded cAdvisor) | Prometheus |
| `metrics_system.alloy` | Host metrics (embedded node_exporter) | Prometheus |

## Security notes

- Runs as root (the upstream default; non-root is marked experimental upstream) with **all
  capabilities dropped except `DAC_READ_SEARCH`**, which lets it read host logs owned by other
  users. `no-new-privileges` is set and the root filesystem is read-only.
- Every host mount (`/`, `/sys`, `/var/log`, `/var/lib/docker`, `/run/udev/data`) is read-only.
- A read-only bind mount does not stop `connect()` on unix sockets. The host `/run` inside the
  `/rootfs` mount is therefore shadowed by an empty tmpfs, so the host `docker.sock` and
  `containerd.sock` are unreachable. If your host keeps sockets outside `/run` (e.g. a real
  `/var/run` directory instead of a symlink), add a matching tmpfs.
- Docker is reached only through `socket-proxy` on an `internal` network, with read-only access
  to containers (list, inspect, logs), networks, events and info (`POST=0`).
- The Alloy UI has no authentication and shows the full pipeline configuration. It is only
  published through Traefik with `internal-only@file`. Add an authenticating middleware (e.g.
  forward auth) if the private ranges are too broad for you.
- Usage reporting to Grafana Labs is disabled (`--disable-reporting`).
- Limitations of running without host PID/network namespaces and without `privileged`:
  node_exporter network counters reflect the container's namespace, and cAdvisor may report
  fewer disk/IO metrics. Only the persistent journal (`/var/log/journal`) is read; hosts with a
  volatile journal (`/run/log/journal`) need `Storage=persistent` in `journald.conf`.

## Backup

The `alloy-data` volume holds only the WAL and file read positions. It can be recreated; losing
it may cause some logs to be re-sent or skipped. Back up `config/` with the repository.
