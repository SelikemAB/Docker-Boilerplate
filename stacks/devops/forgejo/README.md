# Forgejo

Self-hosted lightweight software forge: Git hosting, code review, issues, package registry and
team collaboration, backed by PostgreSQL.

| | |
|---|---|
| Image | `codeberg.org/forgejo/forgejo:16.0.5-rootless` |
| Database | `docker.io/library/postgres:18.6-alpine` |
| Exposed | Web UI via Traefik (`FORGEJO_HOST`), Git SSH on 2222/tcp (all interfaces) |

## Quick start

```bash
cp .env.example .env && vi .env                 # set FORGEJO_HOST
mkdir -p secrets && chmod 700 secrets
openssl rand -base64 32 | tr -d '\n' > secrets/forgejo_db_password
openssl rand -base64 48 | tr -d '\n' > secrets/forgejo_secret_key
openssl rand -base64 48 | tr -d '\n' > secrets/forgejo_internal_token
chmod 444 secrets/*                             # readable by the non-root container users; dir stays 700
docker compose up -d
# The web installer is disabled (INSTALL_LOCK). Create the first admin from the CLI:
docker compose exec forgejo forgejo admin user create --admin \
  --username admin --email admin@example.com --random-password --must-change-password
```

Clone over SSH with `ssh://git@${FORGEJO_HOST}:${FORGEJO_SSH_PORT}/owner/repo.git`.

To reach the UI without Traefik (e.g. for testing), add `-f compose.expose-ports.yaml`, which
publishes port 3000 on `127.0.0.1` and relaxes the secure-cookie flag.

**Upgrading from the source template (15.x, root image):** the rootless image stores data under
`/var/lib/gitea` (not `/data`) with `app.ini` at `/var/lib/gitea/custom/conf/app.ini`, and runs as
UID 1000. Migrate data before switching; see the
[Forgejo docker docs](https://forgejo.org/docs/latest/admin/installation/docker/). Read the 16.0
release notes before a major upgrade.

## Security notes

- Uses the official rootless image: UID 1000, all capabilities dropped, read-only root filesystem
  (only `/tmp` is a tmpfs). SSH is Forgejo's built-in server on unprivileged port 2222.
- The DB password, `SECRET_KEY` and `INTERNAL_TOKEN` are Docker secrets read via
  `FORGEJO__section__KEY__FILE`. Note that `environment-to-ini` writes the resolved values into
  `app.ini` inside the `forgejo-data` volume, so treat that volume as sensitive.
- The web installer is locked, self-registration is disabled by default, passwords use argon2 and
  session cookies are `Secure`.
- PostgreSQL runs as UID 70 with SCRAM-SHA-256, a read-only root FS and no published port, on an
  `internal` network.
- Forgejo itself is on the `proxy` network as well, since it needs egress for mirrors, webhooks
  and SMTP.
- **Exception:** the Git SSH port binds `0.0.0.0` by default (`SSH_BIND_ADDRESS`), because Git
  clients must reach it. Restrict it with a host firewall or set a specific interface IP.
- MySQL/MariaDB from the original template are replaced by PostgreSQL. SQLite is possible
  (`FORGEJO__database__DB_TYPE=sqlite3`) but not recommended for multi-user installs.

## Backup

```bash
docker compose exec -T postgres pg_dump -U forgejo -Fc forgejo > forgejo-db-$(date +%F).dump
docker run --rm -v forgejo_forgejo-data:/data:ro -v "$PWD":/backup docker.io/library/alpine:3.24.2 \
  tar czf /backup/forgejo-data-$(date +%F).tar.gz -C /data .
```

Alternatively use `forgejo dump` inside the container. `secrets/` must be stored in your secret
manager: without `SECRET_KEY`, encrypted fields (2FA secrets, OAuth credentials) cannot be decrypted.
