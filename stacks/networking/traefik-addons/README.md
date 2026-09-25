# Traefik add-ons

Drop-in dynamic configuration for the `traefik` stack: authentik forward auth, basic-auth
for dashboards, reusable middleware chains and an opt-in CrowdSec bouncer. A `whoami` test
service is included to try them out.

| | |
|---|---|
| Image | `docker.io/traefik/whoami:v1.12.0` (test service only) |
| Payload | `config/dynamic/*.yaml`, loaded by the traefik stack's file provider |
| Exposed | Nothing directly. `whoami` is reachable via Traefik (`WHOAMI_HOST`) |

## What's included

| Name (`@file`) | Type | Purpose |
|---|---|---|
| `forward-auth` | forwardAuth | authentik embedded outpost (`authentik-server:9000`) |
| `dashboard-basicauth` | basicAuth | bcrypt users from the traefik stack's `dashboard_users` secret |
| `default-secured` | chain | `rate-limit` |
| `internal-secured` | chain | `internal-only` + `rate-limit` |
| `sso-secured` | chain | `rate-limit` + `forward-auth` |
| `dashboard-secured` | chain | `internal-only` + `dashboard-basicauth` |
| `crowdsec-bouncer`, `crowdsec-secured`, `crowdsec-sso-secured` | plugin / chains | opt-in, see below |

`security-headers`, `internal-only`, `rate-limit` and the TLS options come from the traefik
stack's `security.yaml`. They are referenced here, not redefined, because a duplicate name
would conflict. `security-headers` already applies to every router on `websecure`.

## Quick start

Requires a running `traefik` stack.

```bash
# 1. Install the middlewares (the file provider picks them up live)
cp config/dynamic/addons-middlewares.yaml ../traefik/config/dynamic/

# 2. Optional: test route
cp .env.example .env && vi .env        # WHOAMI_HOST, WHOAMI_MIDDLEWARES
docker compose up -d
curl -s https://whoami.example.com/    # from a private IP (internal-secured)
```

Use a chain from any stack:

```yaml
labels:
  traefik.http.routers.app.middlewares: sso-secured@file
```

For `forward-auth`, attach the traefik container to a network shared with `authentik-server`
(or change `address` to your outpost URL). In authentik, create a *Proxy Provider* in
*Forward auth (single application)* mode for each protected host.

## CrowdSec bouncer (opt-in)

It needs changes to the traefik stack's `compose.yaml`, which this stack doesn't touch:

1. Enable the plugin in the static config (`command:`) and give Traefik a writable plugin
   directory, because its root filesystem is read-only:
   ```yaml
   command:
     - --experimental.plugins.crowdsec-bouncer-traefik-plugin.modulename=github.com/maxlerebourg/crowdsec-bouncer-traefik-plugin
     - --experimental.plugins.crowdsec-bouncer-traefik-plugin.version=v1.7.1
   tmpfs:
     - /plugins-storage:uid=65532,gid=65532,mode=0700
   ```
2. Create a bouncer key and mount it as a secret:
   ```bash
   docker exec crowdsec cscli bouncers add traefik -o raw | tr -d '\n' > ../traefik/secrets/crowdsec_bouncer_key
   chmod 444 ../traefik/secrets/crowdsec_bouncer_key
   ```
   ```yaml
   services:
     traefik:
       secrets: [acme_dns_token, dashboard_users, crowdsec_bouncer_key]
   secrets:
     crowdsec_bouncer_key:
       file: ./secrets/crowdsec_bouncer_key
   ```
3. Put Traefik and CrowdSec on a shared network (the LAPI is expected at `crowdsec:8080`).
4. Activate the middleware file:
   `cp config/dynamic/addons-crowdsec.yaml.example ../traefik/config/dynamic/addons-crowdsec.yaml`

Traefik downloads the plugin from GitHub at startup, so it needs outbound access to
`plugins.traefik.io` and `github.com`.

## Security notes

- `whoami` runs as UID 65532 on port 8080 with all capabilities dropped and a read-only root
  filesystem. Its default route is `internal-secured@file`, because whoami reflects request
  headers (including cookies and auth headers) and lets anyone change its `/health` status.
  **Don't expose it publicly.** Remove it after testing.
- **Exception, healthcheck:** `whoami` is a scratch image with only its own binary, so there's
  no probe binary for its `/health` endpoint.
- `forward-auth` sets `trustForwardHeader: false`, so Traefik doesn't trust client-supplied
  `X-Forwarded-*` headers at the edge. Only `X-authentik-*` response headers are passed to
  the backend.
- `dashboard-basicauth` reuses the bcrypt `dashboard_users` secret and strips the
  `Authorization` header before proxying.
- The CrowdSec bouncer key is read from a file (`crowdsecLapiKeyFile`), never written into
  the dynamic config. The template's inline key and inline basic-auth users were removed for
  that reason.
- The original template shipped its own docker-socket-proxy. The traefik stack already
  runs a filtered, read-only `socket-proxy` on an internal network, so this stack has none.

## Backup

Stateless. Keep `config/dynamic/` in version control.
