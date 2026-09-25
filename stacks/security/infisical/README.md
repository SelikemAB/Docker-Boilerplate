# Infisical

Self-hosted secrets management: sync application secrets, certificates and credentials to teams,
CI/CD and infrastructure.

| | |
|---|---|
| Image | `docker.io/infisical/infisical:v0.165.16` |
| Database | `docker.io/library/postgres:18.6-alpine` |
| Cache/queue | `docker.io/library/redis:8.10.2-alpine` |
| Exposed | Nothing. Served through Traefik at `https://${INFISICAL_HOST}` |

## Quick start

```bash
cp .env.example .env && vi .env                 # set INFISICAL_HOST
mkdir -p secrets && chmod 700 secrets
openssl rand -hex 16 | tr -d '\n' > secrets/infisical_encryption_key   # exactly 32 hex chars
openssl rand -base64 32 | tr -d '\n' > secrets/infisical_auth_secret
# Hex only: these passwords are embedded in connection URIs.
openssl rand -hex 32 | tr -d '\n' > secrets/postgres_password
openssl rand -hex 32 | tr -d '\n' > secrets/redis_password
chmod 444 secrets/*                             # readable by UID 1001 / 70 / 999; dir stays 700
docker compose up -d
```

Open `https://secrets.example.com` and create the first (admin) account right away. Until you
do, anyone who can reach the URL can claim it. Afterwards, restrict sign-up under
Admin > Server settings.

`compose.smtp.yaml` enables e-mail. Set `SMTP_*` in `.env` and put the password in
`secrets/smtp_password`. `compose.expose-ports.yaml` publishes port 8080 on loopback.

## Security notes

- Infisical runs as the image's non-root user (UID 1001) with all capabilities dropped and
  `no-new-privileges`.
- **Exception: writable root FS for Infisical.** The image entrypoint runs `update-ca-certificates`
  into `/etc/ssl/certs`, and upstream doesn't document read-only operation. PostgreSQL (UID 70)
  and Redis (UID 999) run with read-only root filesystems.
- Infisical has no `*_FILE` support. A small `sh` wrapper reads the Docker secrets
  (`ENCRYPTION_KEY`, `AUTH_SECRET`, database, Redis and SMTP passwords), builds
  `DB_CONNECTION_URI` / `REDIS_URL` in memory, and `exec`s the upstream entrypoint. No secret is
  stored in `.env` or visible in `docker inspect`. The values are still in the process environment
  (`/proc/1/environ`), which only root on the host can read.
- Redis requires a password, which is written to a `tmpfs` config file so it isn't in the process
  list. Redis and PostgreSQL (SCRAM-SHA-256, data checksums) sit on an `internal` network.
- Telemetry is disabled by default (`INFISICAL_TELEMETRY_ENABLED=false`).
- **`ENCRYPTION_KEY` is critical.** It encrypts all stored secrets. Losing it makes the database
  unrecoverable, so keep an offline copy in your break-glass store.
- **Upgrade note:** the source template used PostgreSQL 14 and Redis 7. Moving an existing
  database to PostgreSQL 18 needs a dump and restore (see Backup). The Redis data is a
  queue/cache and can be discarded.

## Backup

```bash
docker compose exec -T postgres pg_dump -U infisical -Fc infisical > infisical-$(date +%F).dump
```

Back up `secrets/` (especially `infisical_encryption_key`) separately from the dump.
