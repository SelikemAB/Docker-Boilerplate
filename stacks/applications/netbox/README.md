# NetBox

The network source of truth: IPAM, DCIM, circuits, racks, cabling and automation, packaged with
its background worker, PostgreSQL and Redis.

| | |
|---|---|
| Image | `docker.io/netboxcommunity/netbox:v4.7.1` |
| Database | `docker.io/library/postgres:18.6-alpine` |
| Cache / queue | `docker.io/library/redis:8.10.2-alpine` (two instances: tasks + cache) |
| Exposed | Nothing directly. HTTPS through Traefik at `NETBOX_HOST` (private networks only by default) |

## Quick start

Requires the `traefik` stack (and its `proxy` network) to be running.

```bash
cp .env.example .env && vi .env                 # set NETBOX_HOST, superuser e-mail, SMTP
mkdir -p secrets && chmod 700 secrets
openssl rand -base64 32 | tr -d '\n' > secrets/db_password
openssl rand -hex 32 > secrets/redis_password
openssl rand -hex 32 > secrets/redis_cache_password
openssl rand -base64 64 | tr -d '\n' > secrets/secret_key          # Django SECRET_KEY (>= 50 chars)
openssl rand -base64 64 | tr -d '\n' > secrets/api_token_pepper_1  # v2 API token pepper (>= 50 chars)
openssl rand -base64 24 | tr -d '\n' > secrets/superuser_password  # first admin login, store it in your vault
printf '%s' 'SMTP_PASSWORD' > secrets/email_password                # or: : > secrets/email_password (no SMTP auth)
chmod 444 secrets/*                             # readable by the non-root container users; dir stays 700
docker compose up -d
docker compose logs -f netbox                   # first start runs all migrations (a few minutes)
```

Log in at `https://<NETBOX_HOST>` as `NETBOX_SUPERUSER_NAME`. The superuser is created only
once. After that, `secrets/superuser_password` is no longer used, so change the password in
the UI.

**Housekeeping:** there is no separate housekeeping container. From NetBox 4.2 on,
housekeeping (changelog, job and session cleanup) is a built-in system job that the
`netbox-worker` schedules and runs daily. The old `netbox-housekeeping` service and
`manage.py housekeeping` are gone in 4.7.

Retention and other settings from netbox-docker's
[`configuration.py`](https://github.com/netbox-community/netbox-docker/blob/release/configuration/configuration.py)
can be added to the `x-netbox-env` block (for example `CHANGELOG_RETENTION`, `JOB_RETENTION`,
`REMOTE_AUTH_*`, `SOCIAL_AUTH_OIDC_*`). For OIDC, put the client secret in a Docker secret
named `oidc_secret`. The image reads it natively.

## Upgrading

- **From the template (4.5, postgres 17):** the database moves to PostgreSQL 18, and the data
  volume path changes to `/var/lib/postgresql` (the layout for 18+). Dump the old DB with
  `pg_dump`, start this stack with an empty `netbox-postgres` volume, then restore it:
  `docker compose exec -T postgres psql -U netbox netbox < dump.sql`. NetBox 4.5+ v2 API tokens
  need an `API_TOKEN_PEPPERS` entry. It's provided as `api_token_pepper_1`.
- NetBox migrates its schema on start. Upgrade one minor release at a time (4.5 → 4.6 → 4.7)
  and read the [release notes](https://github.com/netbox-community/netbox/releases) for
  plugin compatibility.

## Security notes

- Every container runs non-root with all capabilities dropped, `no-new-privileges` and a
  read-only root filesystem: NetBox and the worker as `netbox` (UID 999, GID 0, as upstream),
  PostgreSQL as UID 70, and Redis as UID 999. Only `/tmp` (and PostgreSQL's socket dir) are tmpfs.
- All credentials are Docker secrets. netbox-docker's `configuration.py` reads
  `/run/secrets/<name>` natively, PostgreSQL uses `POSTGRES_PASSWORD_FILE`, and Redis writes
  its `requirepass` from the secret into a tmpfs config file. No secret appears in the
  environment, the command line or `docker inspect`.
- PostgreSQL uses SCRAM-SHA-256 with data checksums. Both Redis instances require a password
  (a separate one each). The cache is memory-only with an LRU cap.
- PostgreSQL and Redis sit on an `internal` network with no egress and no published ports.
  NetBox joins `proxy` for Traefik. The worker joins a small `egress` network for webhooks,
  SMTP and remote data sources.
- `LOGIN_REQUIRED=true`, `CSRF_TRUSTED_ORIGINS` and `ALLOWED_HOSTS` are pinned to
  `NETBOX_HOST`. Traefik applies the `internal-only@file` IP allow-list by default.
- The census and the GitHub release check are off.
- If you set `NETBOX_METRICS_ENABLED=true`, `/metrics` is served on the app port. Scrape it
  from the internal network and keep it off the public router, for example with a
  ``PathPrefix(`/metrics`)`` router that uses `internal-only@file`.
- No HARDENING-EXCEPTIONs.

## Backup

```bash
docker compose exec -T postgres pg_dump -U netbox -Fc netbox > netbox-$(date +%F).dump
docker compose exec -T netbox tar czf - -C /opt/netbox/netbox media scripts reports > netbox-files-$(date +%F).tar.gz
```

The task queue in `netbox-redis` is transient and the cache is disposable. `secrets/` (in
particular `secret_key` and `api_token_pepper_1`, since existing API tokens stop working
without the pepper) must be stored in your secret manager.
