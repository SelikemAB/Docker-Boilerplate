# Homepage

A fast, YAML-configured application dashboard with widgets for 100+ services and live Docker
container status.

| | |
|---|---|
| Image | `ghcr.io/gethomepage/homepage:v2.4.0` |
| Helper | `docker.io/tecnativa/docker-socket-proxy:v0.5.0` |
| Exposed | Nothing directly. HTTPS through Traefik at `HOMEPAGE_HOST` (private networks only by default) |

## Quick start

Requires the `traefik` stack (and its `proxy` network) to be running.

```bash
cp .env.example .env && chmod 600 .env && vi .env   # set HOMEPAGE_HOST
mkdir -p secrets && chmod 700 secrets
openssl rand -base64 32 | tr -d '\n' > secrets/homepage_auth_secret     # cookie signing key (>= 32 chars)
openssl rand -base64 24 | tr -d '\n' > secrets/homepage_auth_password   # login password, store it in your vault
chmod 444 secrets/*                                  # readable by the non-root container user; dir stays 700
docker compose up -d
```

On first start Homepage copies its skeleton files (`settings.yaml`, `services.yaml`,
`widgets.yaml`, `bookmarks.yaml`, ...) into the `homepage-config` volume. Edit them there, for
example with `docker compose cp homepage:/app/config/services.yaml .`, then edit the file and
`docker compose cp services.yaml homepage:/app/config/`. Or replace the volume with a bind
mount (`./data/config:/app/config`, owned by `PUID:PGID`) if you prefer editing on the host.

Docker integration is preconfigured in `config/docker.yaml` as `local-docker`:

```yaml
# services.yaml
- Infra:
    - Traefik:
        href: https://traefik.example.com
        server: local-docker
        container: traefik
```

Local images and icons go into the `homepage-images` / `homepage-icons` volumes
(`/app/public/images`, `/app/public/icons`) and are referenced as `/images/x.png` and
`/icons/x.png`.

Widget API keys don't need to go in YAML. Homepage replaces `{{HOMEPAGE_FILE_XXX}}` with the
contents of the file named by the `HOMEPAGE_FILE_XXX` variable. Add a Docker secret and set
`HOMEPAGE_FILE_XXX: /run/secrets/<name>`.

## Upgrading from 1.x

- **2.0 adds an auth gate** (password or OIDC). This stack enables it by default
  (`HOMEPAGE_AUTH_ENABLED=true`), which requires `HOMEPAGE_AUTH_SECRET` (>= 32 characters) and
  `HOMEPAGE_EXTERNAL_URL`. Both are wired up here. Set `HOMEPAGE_AUTH_ENABLED=false` only if a
  forward-auth middleware already protects the router.
- `HOMEPAGE_ALLOWED_HOSTS` (required since 1.0) is set from `HOMEPAGE_HOST`.
- The template mounted images and icons at `/app/images` and `/app/icons`, which Homepage never
  serves. The documented paths `/app/public/images` and `/app/public/icons` are used now. Copy
  any old files over.
- Config files in `/app/config` are compatible. No schema migration is needed.

## Security notes

- Runs as UID 1000 (`PUID`/`PGID`) with all capabilities dropped and `no-new-privileges`. A
  one-shot `init-perms` job (with only `CHOWN`/`FOWNER`, no network) makes the volumes writable.
- The Docker API is reached only through `socket-proxy` on an `internal` network, with read-only
  access to container list, inspect and stats (`CONTAINERS=1`, `POST=0`). Homepage never sees the
  socket.
- The login gate protects all pages and APIs except `/api/healthcheck`. The auth secret and
  password are Docker secrets. Homepage has no `*_FILE` support for these settings, so a small
  entrypoint wrapper exports them from `/run/secrets` at start. They don't appear in
  `docker inspect`, but they are in the process environment inside the container.
- The OIDC client secret (optional) has to be in `.env`, because Homepage can't read it from a
  file. Keep `.env` at `chmod 600`.
- Homepage doesn't rate-limit password attempts. Failed logins are logged as
  `<nextauth> Failed password sign-in attempt` (match it in CrowdSec/fail2ban). Add the
  `rate-limit@file` middleware to `HOMEPAGE_MIDDLEWARES` if you expose it beyond the LAN.
- Traefik restricts access to private address space (`internal-only@file`) by default, and
  `HOMEPAGE_ALLOWED_HOSTS` rejects unexpected Host headers.
- The root filesystem isn't read-only. Homepage regenerates prerendered pages (Next.js ISR,
  `/api/revalidate`) inside `/app/.next` when the config changes, so that path must stay
  writable. It's owned by the non-root user.
- No HARDENING-EXCEPTIONs.

## Backup

Back up the `homepage-config` volume (all YAML files and `logs/`) and, if used, the
`homepage-images` / `homepage-icons` volumes:

```bash
docker compose exec -T homepage tar czf - -C /app/config . > homepage-config-$(date +%F).tar.gz
docker compose exec -T homepage tar czf - -C /app/public images icons > homepage-assets-$(date +%F).tar.gz
```

`secrets/` must be stored in your secret manager.
