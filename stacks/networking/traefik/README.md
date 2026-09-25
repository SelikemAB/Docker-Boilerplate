# Traefik

Edge reverse proxy with automatic Let's Encrypt certificates (DNS-01). All other web stacks in
this repository publish through it via the shared `proxy` network.

| | |
|---|---|
| Image | `docker.io/library/traefik:v3.7.13` |
| Helper | `docker.io/tecnativa/docker-socket-proxy:v0.5.0` |
| Exposed | 80/tcp (redirects to HTTPS), 443/tcp and 443/udp (HTTP/3, optional) |

## Quick start

```bash
docker network create proxy                     # once per host
cp .env.example .env && vi .env                 # set domain, e-mail, DNS provider
mkdir -p secrets && chmod 700 secrets
printf '%s' 'YOUR_DNS_API_TOKEN' > secrets/acme_dns_token
# Dashboard user (bcrypt). Requires apache2-utils / httpd-tools:
htpasswd -nbB admin 'STRONG_PASSWORD' > secrets/dashboard_users
chmod 444 secrets/*                             # readable by the non-root container user; dir stays 700
docker compose up -d
```

## Exposing a service

Add these labels to any service on the `proxy` network:

```yaml
labels:
  traefik.enable: "true"
  traefik.http.routers.app.rule: Host(`app.example.com`)
  traefik.http.routers.app.entrypoints: websecure
  traefik.http.services.app.loadbalancer.server.port: "8080"
  # Optional: restrict to internal networks
  traefik.http.routers.app.middlewares: internal-only@file
```

HTTPS, the Let's Encrypt resolver and `security-headers@file` apply automatically on the
`websecure` entrypoint.

## Other DNS providers

Set `ACME_DNS_PROVIDER` ([provider list](https://go-acme.github.io/lego/dns/)) and replace
`CF_DNS_API_TOKEN_FILE` in `compose.yaml` with that provider's variables, using the `_FILE` suffix
and one Docker secret per value. Examples: `AWS_ACCESS_KEY_ID_FILE` / `AWS_SECRET_ACCESS_KEY_FILE`
(route53), `DO_AUTH_TOKEN_FILE` (digitalocean), `AZURE_CLIENT_SECRET_FILE` (azuredns).

## Security notes

- Runs as UID 65532 with all capabilities dropped. It listens on ports 8080/8443 inside the
  container, so it needs no `NET_BIND_SERVICE`. The host maps 80/443 to them.
- The Docker API is reached through `socket-proxy` on an `internal` network, with read-only access
  to containers, networks and events only (`POST=0`).
- The dashboard is never served insecurely. It's HTTPS only, uses bcrypt basic auth, and has an
  IP allow-list for private networks (`internal-only@file`).
- Uses TLS 1.2 minimum with an AEAD-only cipher list. HSTS is preloaded, and the `Server` header
  is stripped (see `config/dynamic/security.yaml`).
- Access logs are JSON with request headers dropped, so no `Authorization` or cookies are logged.
- Prometheus metrics are available on `:9100` inside the container only. Scrape them from a
  Prometheus instance attached to the `proxy` network.
- **Exception:** edge ports bind `0.0.0.0` by default, because that is the purpose of this stack.

## Backup

The `traefik-certs` volume holds `acme.json` (private keys). Back it up encrypted, or rely on
reissuance. `secrets/` must be stored in your secret manager.
