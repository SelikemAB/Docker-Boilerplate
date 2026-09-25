# MariaDB

A standalone MariaDB server for applications that need a shared MySQL-compatible database.

| | |
|---|---|
| Image | `docker.io/library/mariadb:11.8.9` (LTS) |
| Port | 3306/tcp (loopback only by default) |

## Quick start

```bash
docker network create database                  # once per host, shared with app stacks
cp .env.example .env
mkdir -p secrets && chmod 700 secrets
openssl rand -base64 32 | tr -d '\n' > secrets/mariadb_root_password
openssl rand -base64 32 | tr -d '\n' > secrets/mariadb_password
chmod 444 secrets/*
docker compose up -d
```

The database `MARIADB_DATABASE` and the user `MARIADB_USER` are created on first start. The
password files are only read at that point. To rotate a password later, use `ALTER USER`, then
update the secret file.

Other stacks can reach the server as `mariadb:3306` by joining the external `database` network:

```yaml
networks:
  database:
    external: true
```

## Security notes

- Runs as the unprivileged `mysql` user (UID 999) with all capabilities dropped and a
  read-only root filesystem. Only `/tmp` and `/run/mysqld` are writable (tmpfs).
- Both passwords are supplied as Docker secrets (`MARIADB_PASSWORD_FILE`,
  `MARIADB_ROOT_PASSWORD_FILE`) and never appear in `docker inspect`.
- `root` can only log in from `localhost` inside the container (`MARIADB_ROOT_HOST`).
  Applications use the dedicated `MARIADB_USER`.
- `LOAD DATA LOCAL INFILE` is disabled (`--local-infile=0`), and DNS lookups on connect are
  skipped (`--skip-name-resolve`). Failed logins are logged (`--log-warnings=2`).
- The port is published on `127.0.0.1` only. Prefer shared Docker networks over publishing it at
  all.
- The healthcheck uses the image's `healthcheck.sh` and a `healthcheck@localhost` account that
  the entrypoint creates at initialisation (credentials in `/var/lib/mysql/.my-healthcheck.cnf`).
- **Upgrades:** Renovate proposes only minor/patch updates within the 11.8 LTS line, and
  `MARIADB_AUTO_UPGRADE` runs `mariadb-upgrade` for them. Test major upgrades on a dump before
  production.

## Backup

```bash
docker compose exec -T mariadb sh -c \
  'mariadb-dump -uroot -p"$(cat /run/secrets/mariadb_root_password)" --all-databases --single-transaction --routines --events' \
  | gzip > backup-$(date +%F).sql.gz
```

For hot physical backups of large datasets, use `mariadb-backup` against the `mariadb-data` volume.
