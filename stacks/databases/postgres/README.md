# PostgreSQL

A standalone PostgreSQL server for applications that need a shared database.

| | |
|---|---|
| Image | `docker.io/library/postgres:18.6-alpine` |
| Port | 5432/tcp (loopback only by default) |

## Quick start

```bash
cp .env.example .env
mkdir -p secrets && chmod 700 secrets
openssl rand -base64 32 | tr -d '\n' > secrets/postgres_password
chmod 444 secrets/postgres_password
docker compose up -d
```

Other stacks can reach the server as `postgres:5432` by joining the external `database` network:

```yaml
networks:
  database:
    external: true
```

## Security notes

- Runs as the unprivileged `postgres` user (UID 70) with all capabilities dropped and a
  read-only root filesystem.
- Uses SCRAM-SHA-256 for every connection, including local ones, and data checksums are enabled.
- The password is supplied as a Docker secret and never appears in `docker inspect`.
- The port is published on `127.0.0.1` only. Prefer shared Docker networks over publishing it at
  all.
- Connection and disconnection logging is enabled for auditing.
- **Upgrades:** Renovate proposes only minor updates. Major upgrades need `pg_upgrade` or a
  dump and restore. Test them before production.

## Backup

```bash
docker compose exec -T postgres pg_dumpall -U postgres | gzip > backup-$(date +%F).sql.gz
```

For point-in-time recovery, use a dedicated tool such as pgBackRest or WAL-G.
