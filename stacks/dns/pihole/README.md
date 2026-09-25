# Pi-hole

Network-wide DNS sinkhole that blocks ads and trackers for every device on the network. The web
UI is published through Traefik.

| | |
|---|---|
| Image | `docker.io/pihole/pihole:2026.09.0` |
| Exposed | 53/tcp+udp (DNS) and 123/udp (NTP) on all interfaces. Web UI via Traefik on 443 |

## Quick start

```bash
docker network create proxy                     # once per host (shared with the traefik stack)
cp .env.example .env && vi .env                 # set PIHOLE_HOST
mkdir -p secrets && chmod 700 secrets
openssl rand -base64 32 | tr -d '\n' > secrets/pihole_webpassword
chmod 444 secrets/*
docker compose up -d
```

Open `https://PIHOLE_HOST/admin` and log in with the password from `secrets/pihole_webpassword`.

If port 53 is taken on the host (`systemd-resolved`), set `DNSStubListener=no` in
`/etc/systemd/resolved.conf` and restart `systemd-resolved`.

Any Pi-hole setting can be pinned with an `FTLCONF_<section>_<key>` environment variable (see
the [docs](https://docs.pi-hole.net/docker/configuration/)). Settings pinned this way are
read-only in the UI.

### Variants

| File | Use |
|---|---|
| `compose.expose-ports.yaml` | Web UI directly on `127.0.0.1:8080` (hosts without Traefik) |
| `compose.macvlan.yaml` | Own LAN IP (see the file for enabling DHCP there) |
| `compose.host-network.yaml` | **Standalone** alternative for the DHCP server: `docker compose -f compose.host-network.yaml up -d` |

## Security notes

- **Starts as root.** The image entrypoint (`start.sh`) needs root to align the `pihole` UID,
  set file capabilities on `pihole-FTL` and run cron. It then starts `pihole-FTL` as the
  unprivileged `pihole` user. All capabilities are dropped except `CHOWN`, `DAC_OVERRIDE`,
  `FOWNER`, `SETUID`, `SETGID`, `SETFCAP`, `KILL` and `NET_BIND_SERVICE`. Each one is commented
  in `compose.yaml`. The root filesystem stays writable, because the entrypoint edits
  `/etc/passwd` and the FTL binary.
- `NET_BIND_SERVICE` is kept, and standard ports are used inside the container. The NTP server's
  port (123) can't be changed, so FTL needs the capability anyway. Keeping 53/80 also makes the
  macvlan and host variants work unchanged. Under `no-new-privileges`, FTL can only receive
  capabilities that are in the container's set.
- The template's `SYS_TIME` is removed, and `ntp.sync.active` is off. A container should never
  set the host clock. The NTP *server* still answers on 123/udp. `NET_ADMIN` (DHCP) is only
  granted in the host-network variant.
- The admin password is a Docker secret (`WEBPASSWORD_FILE`). It is not in `.env` or
  `docker inspect`. The entrypoint exports it to FTL's environment inside the container.
- The web UI has no published port. It is plain HTTP on port 80 inside the container (the
  self-signed 443 listener is disabled) and reachable only through Traefik with
  `internal-only@file`.
- **Exception (port):** DNS (53) and NTP (123) bind `0.0.0.0` by default, because that is the
  purpose of this service. Set `DNS_BIND_ADDRESS` to a LAN IP to restrict them. Never expose
  them to the internet.
- **Exception (host network, variant only):** `compose.host-network.yaml` uses
  `network_mode: host` for DHCP and adds `NET_RAW` and `NET_ADMIN`.

## Backup

Back up the `pihole-etc` volume. It holds `pihole.toml`, the gravity database (lists, groups,
clients) and DHCP leases. You can also use the built-in *Settings -> Teleporter* export.

```bash
docker run --rm -v pihole_pihole-etc:/data:ro -v "$PWD":/backup docker.io/library/alpine:3.24.2 \
  tar czf /backup/pihole-etc-$(date +%F).tar.gz -C /data .
```
