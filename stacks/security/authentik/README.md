# authentik

Identity provider for single sign-on (OAuth2/OIDC, SAML, LDAP, RADIUS, SCIM) and Traefik
forward authentication for apps without native SSO.

| | |
|---|---|
| Image | `ghcr.io/goauthentik/server:2026.8.3` (server + worker) |
| Database | `docker.io/library/postgres:18.6-alpine` |
| Optional helper | `docker.io/tecnativa/docker-socket-proxy:v0.5.0` (`compose.docker-outposts.yaml`) |
| Exposed | Nothing. Served through Traefik at `https://${AUTHENTIK_HOST}` |

Current authentik releases no longer use Redis. PostgreSQL is the only backing service, matching
the upstream compose file for 2026.8.

## Quick start

```bash
cp .env.example .env && vi .env                 # set AUTHENTIK_HOST
mkdir -p secrets && chmod 700 secrets
openssl rand -base64 60 | tr -d '\n' > secrets/authentik_secret_key
openssl rand -base64 32 | tr -d '\n' > secrets/postgres_password
chmod 444 secrets/*                             # readable by UID 1000 / 70; dir stays 700
docker compose up -d
```

Then open `https://auth.example.com/if/flow/initial-setup/` to set the `akadmin` password.

For an unattended first start instead, set `AUTHENTIK_BOOTSTRAP_PASSWORD` in `.env` and run
`docker compose -f compose.yaml -f compose.bootstrap.yaml up -d` once. Afterwards remove the value
from `.env` and run plain `docker compose up -d`.

## Optional overrides

| File | Purpose |
|---|---|
| `compose.smtp.yaml` | Outgoing e-mail. Set `SMTP_*` in `.env`, and put the password in `secrets/smtp_password` (`printf '%s' 'PASS' > secrets/smtp_password && chmod 444 secrets/smtp_password`). |
| `compose.bootstrap.yaml` | One-time unattended `akadmin` creation (see above). |
| `compose.docker-outposts.yaml` | Lets authentik create outpost containers through a filtered socket proxy (see Security notes). |
| `compose.expose-ports.yaml` | Publishes 9000/9443 on `127.0.0.1` for access without Traefik. |

## Protecting another app with forward auth

Create a Proxy Provider (forward auth, single application) and add it to the embedded outpost.
Then attach the middleware on the app's router:

```yaml
labels:
  traefik.http.routers.app.middlewares: authentik@docker
```

## Security notes

- Server and worker run as UID 1000 with all capabilities dropped, `no-new-privileges` and a
  read-only root filesystem. Scratch data goes to `/dev/shm` (the image's `TMPDIR`, sized by
  `AUTHENTIK_SHM_SIZE`) and `/tmp`.
- Upstream runs the worker as `root` with a read-write Docker socket. That is removed here: the
  worker runs unprivileged and never sees the socket. The Docker outpost integration and the
  automatic "Local Docker connection" are therefore off by default. Run outposts manually
  (their own compose file, token from the UI), or enable `compose.docker-outposts.yaml`.
- `AUTHENTIK_SECRET_KEY`, the database password and the SMTP password are Docker secrets. authentik
  reads them through its native `file://` config URIs, so they don't appear in `docker inspect`.
- PostgreSQL sits on an `internal` network, runs as UID 70 with a read-only root FS, and uses
  SCRAM-SHA-256 with data checksums. The worker also joins a stack-local egress network for SMTP
  and external IdP metadata. The server reaches the internet through the `proxy` network.
- Error reporting to authentik's Sentry and the update check are disabled by default.
- **Exception (opt-in only):** `compose.docker-outposts.yaml` gives the worker write access to the
  Docker API (`POST=1`, containers/images/networks) through `docker-socket-proxy`. Anything that
  can reach that proxy can start containers, which is effectively root on the host. The proxy
  lives on an `internal` network shared only with the worker.
- **Exception (opt-in only):** `compose.bootstrap.yaml` passes `AUTHENTIK_BOOTSTRAP_PASSWORD`
  through `.env`, because the bootstrap blueprint has no file support. Remove it after first start.
- **Upgrade note:** the source template used PostgreSQL 17. Moving an existing database to 18 needs a
  dump and restore (see Backup). Upgrade authentik one minor release at a time, as upstream
  recommends.

## Backup

```bash
docker compose exec -T postgres pg_dump -U authentik -Fc authentik > authentik-$(date +%F).dump
```

Also back up the `authentik-data` volume (uploaded media, file-based settings), the
`authentik-certs` volume, `config/templates/` and `secrets/`. Losing `authentik_secret_key`
invalidates all sessions and encrypted fields.
