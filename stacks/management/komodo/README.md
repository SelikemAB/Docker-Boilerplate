# Komodo

Build and deployment automation for Docker deployments, stacks and builds across many servers.
This stack runs **Komodo Core** with MongoDB 8.0 LTS. FerretDB and a local Periphery agent are
optional overrides.

> **Warning: access to Komodo is equivalent to root on every connected host.** Core can make any
> Periphery agent deploy privileged containers, and a Periphery agent has the full Docker socket.
> Restrict access with SSO (OIDC) and the `internal-only@file` middleware (already applied),
> disable self-registration (the default here), and never expose the UI to the internet.

| | |
|---|---|
| Image | `ghcr.io/moghtech/komodo-core:2.3.3` |
| Database | `docker.io/library/mongo:8.0.32` (default) or `ghcr.io/ferretdb/ferretdb:2.7.0` + `ghcr.io/ferretdb/postgres-documentdb:17-0.107.0-ferretdb-2.7.0` |
| Agent (optional) | `ghcr.io/moghtech/komodo-periphery:2.3.3` |
| Exposed | None. HTTPS through Traefik (`KOMODO_HOST`), internal networks only |

## Quick start

```bash
cp .env.example .env && vi .env                 # set KOMODO_HOST
mkdir -p secrets && chmod 700 secrets
openssl rand -hex 32 | tr -d '\n' > secrets/komodo_db_password       # hex: safe inside connection URLs
openssl rand -base64 48 | tr -d '\n' > secrets/komodo_jwt_secret
openssl rand -hex 32 | tr -d '\n' > secrets/komodo_webhook_secret
openssl rand -base64 24 | tr -d '\n' > secrets/komodo_admin_password # initial admin login
chmod 444 secrets/*                             # readable by the non-root DB users; dir stays 700
docker compose up -d
```

Log in as `admin` (`KOMODO_INIT_ADMIN_USERNAME`) with the password from
`secrets/komodo_admin_password`.

### Overrides

| File | Purpose |
|---|---|
| `compose.ferretdb.yaml` | Use FerretDB 2.7 on PostgreSQL 17 + DocumentDB instead of MongoDB. MongoDB moves to the opt-in `mongo` profile |
| `compose.periphery.yaml` | Run a Periphery agent on this host in outbound mode, with key-based auth and **the Docker socket** |
| `compose.expose-ports.yaml` | Publish port 9120 on `BIND_ADDRESS` (loopback by default) without Traefik |

```bash
# FerretDB instead of MongoDB (FerretDB needs the DB password in .env, see Security notes)
echo "KOMODO_DATABASE_PASSWORD=$(cat secrets/komodo_db_password)" >> .env && chmod 600 .env
docker compose -f compose.yaml -f compose.ferretdb.yaml up -d

# Manage this host too
docker compose -f compose.yaml -f compose.periphery.yaml up -d
```

The FerretDB override uses the Compose `!override` tag, so it needs Docker Compose 2.24.4 or
later. Choose the database **before the first start**. Switching later means migrating data (see
Backup).

For other hosts, install Periphery there (systemd or container) in outbound mode. Point
`PERIPHERY_CORE_ADDRESS` at `wss://KOMODO_HOST` and use an onboarding key from **Settings**. Core
never needs to reach the agents.

### OIDC

Set `KOMODO_OIDC_ENABLED=true`, `KOMODO_OIDC_PROVIDER` and `KOMODO_OIDC_CLIENT_ID` (a PKCE/public
client needs no secret). For a confidential client, add a Docker secret `komodo_oidc_client_secret`
and `KOMODO_OIDC_CLIENT_SECRET_FILE: /run/secrets/komodo_oidc_client_secret` in a
`compose.override.yaml`. Then consider `KOMODO_LOCAL_AUTH=false`.

## Security notes

- Core itself has **no Docker socket**. It only talks to Periphery agents over key-authenticated
  (Noise) connections, with keys in the `komodo-keys` volume.
- **Exception (docker socket, `compose.periphery.yaml` only):** Periphery deploys stacks and runs
  builds through the Docker CLI. It needs the full, writable Docker API and has no socket-proxy
  mode. It runs in outbound mode, so it opens no port. Its remote shell (`PERIPHERY_DISABLE_TERMINALS`)
  is **disabled by default**, because a shell in a container that holds the socket is a root shell
  on the host. Upstream's optional `/proc:/proc` mount (host process list) is left out on purpose.
- Core and Periphery run as root, the upstream images' default. Core's entrypoint runs
  `update-ca-certificates`. All capabilities are dropped and `no-new-privileges` is set. Their root
  filesystems stay writable, since upstream doesn't support read-only mode (CA store, Git
  checkouts, Deno action cache).
- MongoDB runs as UID 999 and PostgreSQL/DocumentDB as UID 999. FerretDB runs as its image's
  unprivileged user. All database containers have read-only root filesystems (tmpfs for `/tmp` and
  the Postgres socket dir) and sit on an `internal` network with no published ports.
- The DB password, JWT secret, webhook secret and initial admin password come from Docker secrets
  through Komodo's and the database images' `*_FILE` support.
- **Exception (secret in `.env`, FerretDB only):** FerretDB reads its PostgreSQL credentials only
  from `FERRETDB_POSTGRESQL_URL` and has no file variant. With the FerretDB override, the DB
  password must also be in `.env` (`chmod 600`), and it shows up in `docker inspect` for
  `komodo-ferretdb`.
- Hardened defaults: self-registration off, new users disabled, non-admins can't create resources,
  minimum password length 12.
- Changes from the source template: `mongo:8` is pinned to 8.0.32 LTS. FerretDB and DocumentDB are
  pinned to 2.7.0 / 17-0.107.0. The template's `/app/data` and `/app/repos` mounts are replaced by
  the paths the v2 image actually uses (`/config/keys`, `/backups`, `/repo-cache`, `/syncs`). The
  host and macvlan network modes are dropped in favour of bridge networking behind Traefik.

## Backup

- Enable Komodo's built-in **Backup Core Database** procedure. It writes dated dumps into the
  `komodo-backups` volume. Copy that volume off-host.
- Or dump the database directly:

```bash
# MongoDB
docker compose exec -T komodo-mongo sh -c \
  'mongodump --quiet --archive --gzip -u "$MONGO_INITDB_ROOT_USERNAME" -p "$(cat /run/secrets/komodo_db_password)" --authenticationDatabase admin' \
  > komodo-mongo-$(date +%F).archive.gz
# FerretDB (PostgreSQL)
docker compose -f compose.yaml -f compose.ferretdb.yaml exec -T komodo-postgres \
  pg_dumpall -U komodo | gzip > komodo-pg-$(date +%F).sql.gz
```

- Also back up the `komodo-keys` volume, or agents will have to be re-onboarded, and store
  `secrets/` in your secret manager.
