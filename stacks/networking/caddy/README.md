# Caddy

Web server and reverse proxy with automatic HTTPS and a modular Caddyfile. It serves a
static site out of the box, and reverse-proxy sites can be added as drop-in `config/*.caddy` files.

| | |
|---|---|
| Image | `docker.io/library/caddy:2.11.4-alpine` |
| Exposed | 80/tcp (HTTP, ACME, redirects), 443/tcp and 443/udp (HTTP/3) |

> Caddy is an **alternative** to the `traefik` stack. Both want host ports 80/443, so run one
> or the other on a host (or move one to different ports).

## Quick start

```bash
cp .env.example .env && vi .env        # ACME_EMAIL, CADDY_SITE_ADDRESS
# point DNS for CADDY_SITE_ADDRESS at this host, then:
docker compose up -d
docker compose logs -f caddy           # watch the certificate being issued
```

No secrets are needed. Caddy creates its ACME account key itself and stores it in the
`caddy-data` volume.

### Layout

| Path | Purpose |
|---|---|
| `Caddyfile` | Global options (ACME e-mail, unprivileged ports, admin API) and the `(security)` header snippet |
| `config/webserver.caddy` | Static site for `CADDY_SITE_ADDRESS`, served from `/srv` |
| `config/reverse-proxy.caddy.example` | Reverse-proxy template. Rename it to `*.caddy` to enable it |
| `site/` | Default static content (`CADDY_SITE_PATH`) |
| `compose.nfs.yaml` | Optional override that serves `/srv` from an NFS export |

### Reverse-proxying another stack

1. Copy `config/reverse-proxy.caddy.example` to `config/<app>.caddy` and set the address and
   upstream (`service:port`).
2. Attach the upstream service to the external `caddy` network:
   ```yaml
   networks:
     caddy:
       external: true
   ```
3. Reload without downtime:
   `docker compose exec caddy caddy reload --config /etc/caddy/Caddyfile`

### NFS-backed site content

```bash
docker compose -f compose.yaml -f compose.nfs.yaml up -d   # set NFS_* in .env first
```

## Security notes

- Runs as UID 65532 with all capabilities dropped and a read-only root filesystem. Caddy
  listens on 8080/8443 inside the container (`http_port`/`https_port`), so it needs no
  `NET_BIND_SERVICE`. The host maps 80/443 to them.
- The image makes `/data/caddy` and `/config/caddy` world-writable (1777). Fresh named volumes
  inherit that, so no permission-fixing init job is needed. If you switch to bind mounts, `chown`
  them to `PUID:PGID`.
- The admin API listens on `localhost:2019` inside the container only and is never published.
  It is used for the healthcheck and for `caddy reload`.
- Every site imports the `(security)` snippet: HSTS (preload), `nosniff`, `SAMEORIGIN`, a strict
  referrer and permissions policy, and the `Server` header is removed. Caddy's defaults already
  cover TLS 1.2+, modern ciphers, OCSP stapling and the HTTP-to-HTTPS redirect.
- Config and site content are mounted read-only.
- Access logs are JSON on stdout (rotated by the Docker log driver).
- **Exception:** edge ports bind `0.0.0.0` by default, because serving the internet is the
  purpose of this stack. Set `EDGE_BIND_ADDRESS` to restrict it.

## Backup

- The `caddy-data` volume holds certificates and the ACME account key (private keys). Back it
  up encrypted, or rely on reissuance (watch the Let's Encrypt rate limits).
- `Caddyfile`, `config/` and your site content belong in version control.
