# Uptime Kuma

Self-hosted uptime monitoring for HTTP(S), TCP, ping, DNS and more, with status pages and
notifications.

| | |
|---|---|
| Image | `docker.io/louislam/uptime-kuma:2.5.5` |
| Exposed | Nothing published; 3001 via Traefik |

## Quick start

```bash
docker network create proxy                     # once per host (shared with Traefik)
cp .env.example .env && vi .env                 # set UPTIMEKUMA_HOST
docker compose up -d
```

Open `https://<UPTIMEKUMA_HOST>` and create the admin account right away. The first visitor
gets to set it up. The setup wizard also asks for the database: choose **SQLite** (stored in the
data volume) or an **external MariaDB** (e.g. a MariaDB `11.8.9` stack). The embedded MariaDB
option has not been verified with the non-root user.

To publish the UI on a host port instead (the original template's behaviour), use
`docker compose -f compose.yaml -f compose.expose-ports.yaml up -d` (binds `127.0.0.1` by
default).

## Security notes

- Runs as the image's `node` user (UID 1000), the same as the upstream `rootless` build target,
  with all capabilities dropped and `no-new-privileges`.
- Ping monitors use unprivileged ICMP sockets (`net.ipv4.ping_group_range`) instead of the
  `NET_RAW` capability.
- **Root filesystem is writable.** A read-only root FS has not been verified upstream for
  Uptime Kuma 2.x (embedded MariaDB, Chromium-based monitors and npm paths). Persistent data
  lives only in the `uptimekuma-data` volume.
- Uses the `proxy` network only, which is non-internal so monitors can reach their targets. To
  monitor services on other internal networks, attach those networks explicitly.
- The UI is not limited to `internal-only@file`, because public status pages are a core
  feature and the dashboard has its own login (enable 2FA). Add the middleware if it should be
  LAN-only.
- Docker container monitors are not enabled. If you need them, use a
  `docker.io/tecnativa/docker-socket-proxy:v0.5.0` sidecar (`CONTAINERS=1`, `POST=0`) on an
  internal network, as in the traefik stack, and point Kuma at `tcp://socket-proxy:2375`. Never
  mount the raw socket.

## Backup

Stop the container for a consistent copy of the SQLite database, then archive the volume:

```bash
docker compose stop uptimekuma
docker run --rm -v uptimekuma_uptimekuma-data:/data:ro -v "$PWD":/backup docker.io/library/alpine:3.24.2 \
  tar czf /backup/uptimekuma-$(date +%F).tar.gz -C /data .
docker compose start uptimekuma
```

With an external MariaDB, back up that database with `mariadb-dump` instead.
