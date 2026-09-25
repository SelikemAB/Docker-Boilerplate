# Gitea

Lightweight self-hosted Git service: repository hosting, code review, issues, package registry
and team collaboration, backed by PostgreSQL.

| | |
|---|---|
| Image | `docker.io/gitea/gitea:1.27.3-rootless` |
| Database | `docker.io/library/postgres:18.6-alpine` |
| Exposed | Web UI via Traefik (`GITEA_HOST`), Git SSH on 2221/tcp (all interfaces) |

## Quick start

```bash
cp .env.example .env && vi .env                 # set GITEA_HOST
mkdir -p secrets && chmod 700 secrets
openssl rand -base64 32 | tr -d '\n' > secrets/gitea_db_password
openssl rand -base64 48 | tr -d '\n' > secrets/gitea_secret_key
openssl rand -base64 48 | tr -d '\n' > secrets/gitea_internal_token
chmod 444 secrets/*                             # readable by the non-root container users; dir stays 700
docker compose up -d
# The web installer is disabled (INSTALL_LOCK). Create the first admin from the CLI:
docker compose exec gitea gitea admin user create --admin \
  --username admin --email admin@example.com --random-password --must-change-password
```

Clone over SSH with `ssh://git@${GITEA_HOST}:${GITEA_SSH_PORT}/owner/repo.git`.

To reach the UI without Traefik (e.g. for testing), add `-f compose.expose-ports.yaml`, which
publishes port 3000 on `127.0.0.1` and relaxes the secure-cookie flag.

**Upgrading from the source template (1.26, root image):** the rootless image keeps data in
`/var/lib/gitea` and `app.ini` in `/etc/gitea` (instead of `/data`), runs as UID 1000 and uses the
built-in SSH server on port 2222. Migrate data before switching; see the
[rootless docs](https://docs.gitea.com/installation/install-with-docker-rootless).

## Security notes

- Uses the official rootless image: UID 1000, all capabilities dropped, read-only root filesystem
  (only `/tmp` is a tmpfs). SSH is Gitea's built-in server on unprivileged port 2222.
- The DB password, `SECRET_KEY` and `INTERNAL_TOKEN` are Docker secrets read via
  `GITEA__section__KEY__FILE`. Note that `environment-to-ini` writes the resolved values into
  `app.ini` in the `gitea-config` volume, so treat that volume as sensitive.
- The web installer is locked, self-registration is disabled by default, passwords use argon2 and
  session cookies are `Secure`.
- PostgreSQL runs as UID 70 with SCRAM-SHA-256, a read-only root FS and no published port, on an
  `internal` network.
- Gitea itself is on the `proxy` network as well, since it needs egress for mirrors, webhooks
  and SMTP.
- **Exception:** the Git SSH port binds `0.0.0.0` by default (`SSH_BIND_ADDRESS`), because Git
  clients must reach it. Restrict it with a host firewall or set a specific interface IP.
- MySQL 8.1 from the original template is replaced by PostgreSQL. SQLite is possible
  (`GITEA__database__DB_TYPE=sqlite3`) but not recommended for multi-user installs.

## Backup

```bash
docker compose exec -T postgres pg_dump -U gitea -Fc gitea > gitea-db-$(date +%F).dump
for v in gitea-data gitea-config; do
  docker run --rm -v gitea_$v:/data:ro -v "$PWD":/backup docker.io/library/alpine:3.24.2 \
    tar czf /backup/$v-$(date +%F).tar.gz -C /data .
done
```

Alternatively use `gitea dump` inside the container. `secrets/` must be stored in your secret
manager: without `SECRET_KEY`, encrypted fields (2FA secrets, OAuth credentials) cannot be decrypted.
