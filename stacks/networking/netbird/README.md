# NetBird

Self-hosted control plane for a NetBird WireGuard mesh VPN. The combined `netbird-server`
runs Management, Signal, Relay, STUN and the embedded identity provider in one process, and
the web dashboard is served next to it. Both are published through the `traefik` stack.

| | |
|---|---|
| Images | `docker.io/netbirdio/netbird-server:0.79.0`, `docker.io/netbirdio/dashboard:v2.93.0` |
| Exposed | 3478/udp (STUN). HTTPS, gRPC and the relay WebSocket go through Traefik on 443 |

## Prerequisites

- The `traefik` stack is running, and DNS for `NETBIRD_HOST` points at the host.
- **Traefik entrypoint timeout:** Signal and Management use long-lived gRPC streams. Traefik's
  default `readTimeout` (60s) on `websecure` cuts them off. Add this flag to the traefik stack's
  `command:` and recreate it:
  ```yaml
  - --entrypoints.websecure.transport.respondingTimeouts.readTimeout=0
  ```
- UDP 3478 is open in the host and cloud firewalls.

## Quick start

```bash
cp .env.example .env && vi .env                     # NETBIRD_HOST
mkdir -p secrets && chmod 700 secrets
. ./.env
sed -e "s|netbird.example.com|${NETBIRD_HOST}|g" \
    -e "s|__RELAY_AUTH_SECRET__|$(openssl rand -base64 32)|" \
    -e "s|__STORE_ENCRYPTION_KEY__|$(openssl rand -base64 32)|" \
    config/config.yaml.example > secrets/netbird_config.yaml
chmod 444 secrets/*                                 # readable by the non-root server; dir stays 700
docker compose up -d
```

Open `https://NETBIRD_HOST`. The first account you create becomes the owner. Connect peers with
`netbird up --management-url https://NETBIRD_HOST`.

To change settings later (log level, external IdP, PostgreSQL store, `reverseProxy` trusted
proxies, ...), edit `secrets/netbird_config.yaml` and run `docker compose up -d --force-recreate netbird-server`.
The options are documented in the upstream
[`config.yaml.example`](https://github.com/netbirdio/netbird/blob/main/combined/config.yaml.example).

## Security notes

- `netbird-server` runs as UID 65532 with all capabilities dropped and a read-only root
  filesystem. It listens on 8080 inside the container, so it doesn't need
  `NET_BIND_SERVICE`. A one-shot `init-perms` job chowns the data volume.
- The server config contains the relay `authSecret` and the store `encryptionKey`, and
  netbird-server can't read them from the environment. So the whole rendered file is a Docker
  secret (`secrets/netbird_config.yaml`). Only the placeholder template is committed.
- TLS terminates at Traefik, and the global security headers apply. gRPC reaches the backend
  over h2c on the internal `proxy` network. The metrics (`:9090`) and health (`:9000`) ports
  are not published.
- Anonymous usage metrics are disabled (`disableAnonymousMetrics: true`). Unlike upstream,
  this is the default here.
- All images are pinned. The original template used `:latest` for both.
- **Exception, port:** STUN `3478/udp` binds `0.0.0.0` by default, because every peer must
  reach it for NAT traversal.
- **Exception, dashboard:** the dashboard image (supervisord + nginx) must start as root to
  render its runtime config into the web root. It runs with all capabilities dropped except
  `CHOWN`, `SETUID`, `SETGID`, `DAC_OVERRIDE` and `NET_BIND_SERVICE`, and its root filesystem
  is writable. It holds no secrets (`AUTH_CLIENT_SECRET` is empty for the public PKCE client).
- The embedded IdP allows local (e-mail and password) accounts. Enable MFA, or connect an
  external IdP in the config and set `localAuthDisabled: true`.

## Backup

The `netbird-data` volume holds the SQLite stores (accounts, peers, policies, events, IdP
users). Stop the server for a consistent copy:

```bash
docker compose stop netbird-server
docker run --rm -v netbird_netbird-data:/data:ro -v "$PWD":/backup docker.io/library/alpine:3.24.2 \
  tar czf /backup/netbird-data-$(date +%F).tar.gz -C /data .
docker compose start netbird-server
```

Back up `secrets/netbird_config.yaml` separately in your secret manager. Without the
`encryptionKey`, the encrypted store fields can't be recovered.
