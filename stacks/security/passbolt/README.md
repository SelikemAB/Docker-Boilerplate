# Passbolt CE

Open-source, OpenPGP-based password manager for teams, with browser extensions, mobile apps and
granular sharing.

| | |
|---|---|
| Image | `docker.io/passbolt/passbolt:5.16.0-1-ce-non-root` |
| Database | `docker.io/library/mariadb:11.8.9` (LTS) |
| Exposed | Nothing. Served through Traefik at `https://${PASSBOLT_HOST}` |

## Quick start

```bash
cp .env.example .env && vi .env                 # set PASSBOLT_HOST and SMTP_*
mkdir -p secrets && chmod 700 secrets
openssl rand -base64 32 | tr -d '\n' > secrets/db_password
printf '%s' 'YOUR_SMTP_PASSWORD' > secrets/smtp_password   # leave empty if SMTP needs no auth
chmod 444 secrets/*                             # readable by UID 33 / 999; dir stays 700
docker compose up -d

# Create the first administrator; open the printed link to finish registration:
docker compose exec passbolt /usr/share/php/passbolt/bin/cake passbolt register_user \
  -u admin@example.com -f Admin -l User -r admin
```

Check the installation with
`docker compose exec passbolt /usr/share/php/passbolt/bin/cake passbolt healthcheck`.

## Security notes

- Uses the upstream `-non-root` variant. nginx, PHP-FPM and supercronic run as `www-data`
  (UID 33) on ports 8080/4433, with all capabilities dropped and `no-new-privileges`.
- **Exception: writable root FS for Passbolt.** At start the entrypoint generates a self-signed
  certificate in `/etc/passbolt/certs`, writes `/etc/environment` for the cron jobs, and
  supervisord, nginx and PHP keep runtime state in several image paths. MariaDB (UID 999) runs
  with a read-only root filesystem.
- The database and SMTP passwords are Docker secrets consumed via
  `DATASOURCES_DEFAULT_PASSWORD_FILE` / `EMAIL_TRANSPORT_DEFAULT_PASSWORD_FILE`, which the
  entrypoint supports natively. The entrypoint copies the environment to `/etc/environment`
  (mode 600, owned by `www-data`) inside the container so cron can read it.
- `APP_FULL_BASE_URL` is always set, which prevents host-header injection. TLS terminates at
  Traefik, and `PASSBOLT_SECURITY_PROXIES_ACTIVE=true` makes Passbolt honour `X-Forwarded-Proto`.
  Set `PASSBOLT_TRUSTED_PROXIES` to lock this to specific proxy IPs.
- MariaDB sits on an `internal` network with a random root password. The app uses a dedicated
  user.
- **Server key:** the OpenPGP server key is generated on first start into the `passbolt-gpg`
  volume. If it's lost, the instance can't be recovered. Back it up offline.
- **Upgrade note:** the source template used MariaDB 12.2 (a short-term release). This stack pins
  the 11.8 LTS. Downgrading an existing 12.x data directory isn't supported, so migrate with a
  logical dump (see Backup).

## Backup

```bash
docker compose exec -T db sh -c 'mariadb-dump -u"$MARIADB_USER" -p"$(cat /run/secrets/db_password)" --single-transaction "$MARIADB_DATABASE"' \
  | gzip > passbolt-db-$(date +%F).sql.gz
docker compose exec -T passbolt tar czf - -C /etc/passbolt gpg jwt > passbolt-keys-$(date +%F).tgz
```

Store the key archive encrypted and separately from the database dump.
