# AdGuard Home

Network-wide DNS resolver that blocks ads and trackers. It supports DNS-over-HTTPS/TLS/QUIC,
parental controls and safe browsing. The web UI and DoH endpoint are published through Traefik.

| | |
|---|---|
| Image | `docker.io/adguard/adguardhome:v0.107.79` |
| Exposed | 53/tcp+udp (DNS, all interfaces). Web UI and DoH via Traefik on 443 |
| Optional | 853/tcp (DoT), 853/udp (DoQ), 5443 (DNSCrypt): `compose.encrypted-dns.yaml` |

## Quick start

```bash
docker network create proxy                     # once per host (shared with the traefik stack)
cp .env.example .env && vi .env                 # set ADGUARD_HOST
mkdir -p secrets && chmod 700 secrets
# Admin login (bcrypt). Requires apache2-utils / httpd-tools:
PW=$(openssl rand -base64 24); echo "AdGuard admin password: $PW"   # store it in your vault
htpasswd -nbBC 12 admin "$PW" > secrets/adguard_admin && unset PW
chmod 444 secrets/*
docker compose up -d
```

On first start the `init-config` job renders `config/AdGuardHome.yaml.tmpl` into the
`adguardhome-conf` volume, with the admin user from `secrets/adguard_admin`. So there is no
unauthenticated setup wizard on port 3000. After that, AdGuard Home owns the file, and changes
are made in the UI at `https://ADGUARD_HOST`. Deleting the file from the volume re-seeds it on the
next start.

If port 53 is taken on the host (`systemd-resolved`), set `DNSStubListener=no` in
`/etc/systemd/resolved.conf` and restart `systemd-resolved`.

### Variants

| File | Use |
|---|---|
| `compose.expose-ports.yaml` | Web UI directly on `127.0.0.1:3000` (hosts without Traefik) |
| `compose.encrypted-dns.yaml` | Publishes DoT/DoQ (853) and DNSCrypt (5443) after you add a certificate |
| `compose.macvlan.yaml` | Own LAN IP. AdGuard listens on 53 inside the container |
| `compose.host-network.yaml` | **Standalone** alternative for the DHCP server: `docker compose -f compose.host-network.yaml up -d` |

The macvlan and host variants change the seeded DNS port to 53. The seed only applies on
**first** start, so on an existing install you edit `dns.port` in `AdGuardHome.yaml` yourself.

### DNS-over-HTTPS behind Traefik

Traefik terminates TLS and forwards `/dns-query` to AdGuard Home over plain HTTP. Newer AdGuard
Home versions reject that unless unencrypted DoH is explicitly allowed. The seed config therefore
sets `http.doh.insecure_enabled: true`. That key is the schema-34 name of the old
`tls.allow_unencrypted_doh`, and v0.107.79 migrates the old key automatically. If you bring your
own `AdGuardHome.yaml`, set one of them, or DoH through the proxy will fail.

## Security notes

- Runs as `nobody` (UID 65534) with **all capabilities dropped** and a read-only root filesystem.
  DNS listens on 5053 and the UI on 3000 inside the container. The host maps 53 to 5053, so no
  `NET_BIND_SERVICE` is needed. The template's `NET_ADMIN`/`NET_RAW` are only required by the DHCP
  server, so they appear only in the host-network variant.
- No open setup wizard. The admin account is bcrypt-hashed and supplied through a Docker secret.
  The hash ends up in `AdGuardHome.yaml` in the conf volume (mode 600), because that is where
  AdGuard Home stores users. Login is rate-limited (5 attempts, then a 15-minute block).
- The UI and `/dns-query` are only reachable through Traefik with `internal-only@file`
  (private address ranges). Remove that middleware only if you deliberately want a public DoH
  resolver.
- `trusted_proxies` includes `172.16.0.0/12` so that client IPs forwarded by Traefik are shown.
  Port 3000 is not published, so only containers on the proxy network can set those headers.
- The web UI's own HTTPS listener and the template's `443/udp` mapping are dropped. Traefik owns
  443/tcp and 443/udp (HTTP/3).
- **Exception (port):** DNS binds `0.0.0.0:53` by default, because that is the purpose of a
  resolver. Set `DNS_BIND_ADDRESS` to a LAN IP to restrict it. Never expose recursion to the
  internet.
- **Exception (host network, variant only):** `compose.host-network.yaml` uses
  `network_mode: host` for DHCP. It runs as root with `NET_BIND_SERVICE`, `NET_RAW` and
  `NET_ADMIN`, because file capabilities are ignored under `no-new-privileges`.
- `init-config` is a one-shot job with no network. It needs `CHOWN`, `FOWNER` and `DAC_OVERRIDE`
  to write the seed and hand the volumes to the runtime user.

## Backup

Back up the `adguardhome-conf` volume (settings, users, rules and clients). `adguardhome-work`
holds query logs, statistics and cached filter lists, which you can rebuild.

```bash
docker run --rm -v adguardhome_adguardhome-conf:/data:ro -v "$PWD":/backup docker.io/library/alpine:3.24.2 \
  tar czf /backup/adguardhome-conf-$(date +%F).tar.gz -C /data .
```
