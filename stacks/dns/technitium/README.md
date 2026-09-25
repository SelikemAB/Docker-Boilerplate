# Technitium DNS Server

Authoritative and recursive DNS server with a web console, DNS blocking and optional
forwarders. The console and DNS-over-HTTPS are published through Traefik.

| | |
|---|---|
| Image | `docker.io/technitium/dns-server:15.5.0` |
| Exposed | 53/tcp+udp (all interfaces). Web console and DoH (`/dns-query`) via Traefik on 443 |
| Optional | 853/tcp (DoT) and 853/udp (DoQ): `compose.encrypted-dns.yaml` |

## Quick start

```bash
docker network create proxy                     # once per host (shared with the traefik stack)
cp .env.example .env && vi .env                 # set TECHNITIUM_HOST
mkdir -p secrets && chmod 700 secrets
openssl rand -base64 32 | tr -d '\n' > secrets/technitium_admin_password
chmod 444 secrets/*                             # must be readable by UID 1654 (see Security notes)
docker compose up -d
```

Log in at `https://TECHNITIUM_HOST` as `admin` with the password from the secret. The `DNS_SERVER_*`
settings and the password only apply on **first** start. After that, the web console is
authoritative, so change the password there.

If port 53 is taken on the host (`systemd-resolved`), set `DNSStubListener=no` in
`/etc/systemd/resolved.conf` and restart `systemd-resolved`.

### Variants

| File | Use |
|---|---|
| `compose.expose-ports.yaml` | Web console directly on `127.0.0.1:5380` (hosts without Traefik) |
| `compose.encrypted-dns.yaml` | Publishes DoT/DoQ on 853 after you add a certificate in the console |
| `compose.macvlan.yaml` | Own LAN IP |
| `compose.host-network.yaml` | **Standalone** alternative for DHCP: `docker compose -f compose.host-network.yaml up -d` |

## Security notes

- Runs as the .NET image's unprivileged `app` user (UID 1654) with **all capabilities dropped**
  and a read-only root filesystem (`HOME` points to the `/tmp` tmpfs). A one-shot `init-perms`
  job (`CHOWN`, `FOWNER`, no network) hands the volumes to that user.
- Technitium's DNS port isn't configurable through the environment, so the container keeps
  port 53. Instead of `NET_BIND_SERVICE`, the network-namespaced sysctl
  `net.ipv4.ip_unprivileged_port_start=53` lets the non-root process bind 53 (and 80 for DoH)
  inside its own namespace only. `net.ipv4.ip_local_port_range` is widened as upstream
  recommends.
- The admin password is a Docker secret (`DNS_SERVER_ADMIN_PASSWORD_FILE`). **Warning:** if the
  file can't be read on first start, Technitium silently creates `admin`/`admin`. Keep the file
  mode `444`, and check the first login.
- The web console and `/dns-query` are only reachable through Traefik with `internal-only@file`.
  DoH is served by Technitium's plain-HTTP listener, and TLS terminates at Traefik.
- Recursion is limited to private networks by default (`AllowOnlyForPrivateNetworks`), so this
  is not an open resolver.
- To log real client IPs for DoH requests, add the proxy network's subnet under *Settings ->
  Web Service -> Reverse Proxy* (or `DNS_SERVER_WEB_SERVICE_REVERSE_PROXY_ADDRESSES`).
- **Exception (port):** DNS binds `0.0.0.0:53` by default, because that is the purpose of a DNS
  server. Set `DNS_BIND_ADDRESS` to restrict it.
- **Exception (host network, variant only):** `compose.host-network.yaml` uses
  `network_mode: host`. There it runs as root with `NET_BIND_SERVICE` and `NET_RAW` (namespaced
  sysctls aren't allowed on the host network). The console is limited to `127.0.0.1`.

## Backup

Back up the `technitium-config` volume. It holds zones, settings, users, blocklists and apps.
You can also use *Settings -> Backup Settings* in the console. `technitium-logs` is optional.

```bash
docker run --rm -v technitium_technitium-config:/data:ro -v "$PWD":/backup docker.io/library/alpine:3.24.2 \
  tar czf /backup/technitium-config-$(date +%F).tar.gz -C /data .
```
