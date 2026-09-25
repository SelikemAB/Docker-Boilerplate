# n8n

Workflow automation platform: build integrations and automations with a visual editor, triggered by
webhooks, schedules or events, backed by PostgreSQL.

| | |
|---|---|
| Image | `docker.n8n.io/n8nio/n8n:2.41.3` |
| Database | `docker.io/library/postgres:18.6-alpine` |
| Exposed | Editor via Traefik (internal-only); `/webhook/`, `/webhook-waiting/`, `/form/`, `/form-waiting/` public |

## Quick start

```bash
cp .env.example .env && vi .env                 # set N8N_HOST
mkdir -p secrets && chmod 700 secrets
openssl rand -base64 32 | tr -d '\n' > secrets/n8n_db_password
openssl rand -hex 32 > secrets/n8n_encryption_key
chmod 444 secrets/*                             # readable by the non-root container users; dir stays 700
docker compose up -d
```

Open `https://N8N_HOST` from an internal network and create the owner account right away.

**Migrating from the source template (SQLite):** export workflows and credentials first
(`n8n export:workflow --all` / `n8n export:credentials --all --decrypted`), and **reuse the old
encryption key** (`encryptionKey` in `/home/node/.n8n/config`) as `secrets/n8n_encryption_key`.
Then import into the new instance.

## Security notes

- Runs as the image's `node` user (UID 1000) with all capabilities dropped.
- **Exception (read-only root FS not enabled):** n8n and its task runners write to caches and
  community-node directories outside the data volume. This hasn't been verified to work read-only.
- The DB password and the credential encryption key are Docker secrets consumed via n8n's native
  `*_FILE` support. If you lose `n8n_encryption_key`, every stored credential is unreadable.
- Traefik serves the editor and REST API only to private address ranges (`internal-only@file`).
  Production webhook and form paths are public so external services can reach them. Test webhooks
  (`/webhook-test/`) stay internal. Protect public webhooks with the node's authentication options.
- Telemetry, version notifications, the template gallery and personalization are off by default.
  Execution data is pruned after 14 days.
- `N8N_PROXY_HOPS=1` makes n8n trust exactly one proxy (Traefik) for client IPs, and cookies are
  `Secure`.
- PostgreSQL runs as UID 70 with SCRAM-SHA-256, a read-only root FS and no published port, on an
  `internal` network.
- The source template only supported an external PostgreSQL. This stack bundles one. To use an
  external server, remove the `postgres` service and point `DB_POSTGRESDB_HOST` at it.

## Backup

```bash
docker compose exec -T postgres pg_dump -U n8n -Fc n8n > n8n-db-$(date +%F).dump
docker run --rm -v n8n_n8n-data:/d:ro -v "$PWD":/backup docker.io/library/alpine:3.24.2 \
  tar czf /backup/n8n-data-$(date +%F).tar.gz -C /d .
```

Store `secrets/` (especially `n8n_encryption_key`) in your secret manager.
