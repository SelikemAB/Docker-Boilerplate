# Nextcloud

Self-hosted file sync, sharing and collaboration (files, calendar, contacts, office integration),
with PostgreSQL, Redis and a dedicated background-job container.

| | |
|---|---|
| Image | `docker.io/library/nextcloud:35.0.1-apache` (web + cron) |
| Database | `docker.io/library/postgres:18.6-alpine` |
| Cache/locking | `docker.io/library/redis:8.10.2-alpine` |
| Exposed | Nothing. Served through Traefik at `https://${NEXTCLOUD_HOST}` |

## Quick start

```bash
cp .env.example .env && vi .env                 # set NEXTCLOUD_HOST
mkdir -p secrets && chmod 700 secrets
openssl rand -base64 24 | tr -d '\n' > secrets/nextcloud_admin_password
openssl rand -base64 32 | tr -d '\n' > secrets/postgres_password
# Hex only: the Redis password is embedded in the PHP session save path URL.
openssl rand -hex 32 | tr -d '\n' > secrets/redis_password
chmod 444 secrets/*                             # readable by www-data (33) / 70 / 999; dir stays 700
docker compose up -d
docker compose logs -f app                      # first start installs Nextcloud (a few minutes)
```

After the install:

```bash
docker compose exec -u www-data app php occ background:cron        # use the cron container
docker compose exec -u www-data app php occ maintenance:repair --include-expensive
docker compose exec -u www-data app php occ db:add-missing-indices
```

`TRUSTED_PROXIES` defaults to the RFC 1918 ranges. Narrow it to your `proxy` network's subnet
(`docker network inspect proxy`) for production.

## Using MariaDB instead of PostgreSQL

PostgreSQL is the default. To use MariaDB LTS instead, replace the `db` service with
`docker.io/library/mariadb:11.8.9`. Run it as `user: "999:999"`, `read_only: true`, with tmpfs
`/tmp` and `/run/mysqld`, `command: --transaction-isolation=READ-COMMITTED --binlog-format=ROW`,
`MARIADB_PASSWORD_FILE` and a volume at `/var/lib/mysql`. Use the healthcheck
`healthcheck.sh --connect --innodb_initialized`. In the shared app environment, replace the
`POSTGRES_*` variables with `MYSQL_HOST`, `MYSQL_DATABASE`, `MYSQL_USER` and
`MYSQL_PASSWORD_FILE`. Choose the database before the first start, because Nextcloud doesn't
switch databases after install.

## Security notes

- **Exception: app and cron start as root.** The official image's entrypoint copies and upgrades
  the code with `rsync --chown` and configures PHP as root. Apache then drops to `www-data`, and
  busybox `crond` runs the `www-data` crontab. No `user:` is set. All capabilities are dropped and
  only these are added back: `CHOWN`, `DAC_OVERRIDE`, `FOWNER`, `SETUID`, `SETGID` and
  `NET_BIND_SERVICE` for the app, and `SETUID`/`SETGID` for cron. `no-new-privileges` is set.
- **Exception: writable root FS for app and cron.** The entrypoint writes PHP/Apache config under
  `/usr/local/etc/php` and `/etc/apache2` at start. PostgreSQL (UID 70) and Redis (UID 999) run
  with read-only root filesystems on an `internal` network.
- The admin, database and Redis passwords are Docker secrets read via `*_FILE`
  (`NEXTCLOUD_ADMIN_PASSWORD_FILE`, `POSTGRES_PASSWORD_FILE`, `REDIS_HOST_PASSWORD_FILE`), which
  the image supports natively. After install, Nextcloud stores the DB password in `config.php`
  inside the `nextcloud-html` volume, as upstream does.
- Redis requires a password, which is written to a `tmpfs` config file so it isn't in the process
  list. PostgreSQL uses SCRAM-SHA-256 with data checksums.
- TLS terminates at Traefik, which sets HSTS and the security headers globally. `OVERWRITEPROTOCOL`,
  `OVERWRITEHOST` and `TRUSTED_PROXIES` make Nextcloud generate correct HTTPS URLs and log real
  client IPs. The `/.well-known/caldav|carddav` redirects are handled by a Traefik middleware.
- **Upgrade note:** the source template used Nextcloud 33 and PostgreSQL 17. Nextcloud upgrades
  only one major version at a time (33 → 34 → 35). Pin `34.x` first, let it upgrade, then move to
  35. Moving an existing database to PostgreSQL 18 needs a dump and restore.

## Backup

```bash
docker compose exec -u www-data app php occ maintenance:mode --on
docker compose exec -T db pg_dump -U nextcloud -Fc nextcloud > nextcloud-db-$(date +%F).dump
# plus a file-level copy of the nextcloud-html volume (config/, data/, custom apps, themes)
docker compose exec -u www-data app php occ maintenance:mode --off
```

`secrets/` must be stored in your secret manager. Redis holds only cache and locks, so it doesn't
need a backup.
