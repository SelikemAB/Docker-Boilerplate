# Grafana

Dashboards, exploration and alerting for Prometheus, Loki, InfluxDB and other data sources,
with PostgreSQL as the configuration database.

| | |
|---|---|
| Image | `docker.io/grafana/grafana:13.2.2` |
| Database | `docker.io/library/postgres:18.6-alpine` |
| Exposed | Nothing published; 3000 via Traefik |

## Quick start

```bash
docker network create proxy                     # once per host (shared with Traefik)
docker network create --internal monitoring     # once per host (shared observability backend)
cp .env.example .env && vi .env                 # set GRAFANA_HOST
mkdir -p secrets && chmod 700 secrets
openssl rand -base64 32 | tr -d '\n' > secrets/grafana_admin_password
openssl rand -base64 32 | tr -d '\n' > secrets/grafana_secret_key
openssl rand -base64 32 | tr -d '\n' > secrets/grafana_db_password
chmod 444 secrets/*                             # readable by the non-root container users; dir stays 700
docker compose up -d
```

Add data sources using the service names on the `monitoring` network: `http://prometheus:9090`,
`http://loki:3100` and `http://influxdb:8086`.

### Optional: SSO with authentik

Create an OAuth2/OpenID provider in authentik with the redirect URI
`https://<GRAFANA_HOST>/login/generic_oauth`. Then:

```bash
printf '%s' 'CLIENT_SECRET_FROM_AUTHENTIK' > secrets/grafana_oauth_client_secret
chmod 444 secrets/grafana_oauth_client_secret
# set AUTHENTIK_URL, AUTHENTIK_SLUG, AUTHENTIK_CLIENT_ID in .env
docker compose -f compose.yaml -f compose.authentik.yaml up -d
```

## Security notes

- Grafana runs as UID 472 (GID 0, the upstream default) and PostgreSQL runs as UID 70. Both have
  all capabilities dropped and a read-only root filesystem, with tmpfs for scratch paths only.
- The admin password, the `secret_key` (which encrypts data-source credentials in the DB), the
  DB password and the optional OAuth client secret are Docker secrets. Grafana reads them
  through its `GF_<SECTION>_<KEY>__FILE` convention (double underscore) and PostgreSQL through
  `POSTGRES_PASSWORD_FILE`. None of them appear in `docker inspect`.
- **Keep `grafana_secret_key` stable.** If it changes, the stored data-source passwords can no
  longer be decrypted.
- The admin password is applied only when the database is first initialised. Change it later in
  the UI or with `grafana cli admin reset-admin-password`.
- PostgreSQL sits on an `internal` network with no published port. It uses SCRAM-SHA-256 and
  data checksums. `GF_DATABASE_SSL_MODE=disable` is acceptable because this traffic never leaves
  that network.
- Sign-up, org creation, anonymous access, Gravatar, external snapshots, update checks and usage
  reporting are disabled. Cookies are `Secure`.
- Grafana joins the `proxy` network (Traefik, plus outbound traffic for plugins and alert
  notifications) and `monitoring` (data sources).
- The UI has no `internal-only@file` restriction because Grafana has its own login. Add
  `traefik.http.routers.grafana.middlewares: internal-only@file` if it should be LAN-only.
- The authentik override keeps `GF_AUTH_OAUTH_ALLOW_INSECURE_EMAIL_LOOKUP=true` from the
  original template, so users are matched by e-mail. Only use it with an IdP that verifies
  e-mail addresses.
- Plugins installed at runtime go to `/var/lib/grafana/plugins` (the data volume). The root
  filesystem stays read-only.

## Backup

```bash
docker compose exec -T grafana-db pg_dump -U grafana grafana | gzip > grafana-db-$(date +%F).sql.gz
```

Also back up the `grafana-data` volume (plugins and any file-based state). Keep `secrets/`,
especially `grafana_secret_key`, in your secret manager.
