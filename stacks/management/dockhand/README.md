# Dockhand

Docker management UI with Compose stacks, Git-based stack deployments and optional OIDC
authentication.

> **Warning: access to Dockhand is equivalent to root on the host.** It has write access to the
> Docker API, so anyone who can log in can start a privileged container that mounts `/`. Configure
> SSO (OIDC), keep the `internal-only@file` middleware (already applied), and never expose the UI to
> the internet.

| | |
|---|---|
| Image | `docker.io/fnsys/dockhand:v1.0.49` |
| Database | `docker.io/library/postgres:18.6-alpine` |
| Helper | `docker.io/tecnativa/docker-socket-proxy:v0.5.0` |
| Exposed | None. HTTPS through Traefik (`DOCKHAND_HOST`), internal networks only |

## Quick start

```bash
cp .env.example .env && vi .env                 # set DOCKHAND_HOST
mkdir -p secrets && chmod 700 secrets
openssl rand -hex 32 | tr -d '\n' > secrets/dockhand_db_password      # hex: safe inside the DB URL
openssl rand -base64 32 | tr -d '\n' > secrets/dockhand_encryption_key # AES-256 key (32 bytes)
chmod 444 secrets/*                             # readable by the non-root container users; dir stays 700
docker compose up -d
```

Then, in the UI:

1. Create the admin account on first visit.
2. Go to **Settings > Environments > Add** and choose connection type **Direct**, host
   `socket-proxy`, port `2375`. Dockhand has no socket mounted, so this environment is how it
   reaches the local Docker engine.
3. Configure OIDC under **Settings > Authentication**. Once SSO works, set
   `DOCKHAND_DISABLE_LOCAL_LOGIN=true` and run `docker compose up -d` again.

### Remote hosts

For other Docker hosts, use Dockhand's **Hawser** agent. It connects outbound in edge mode, so the
remote Docker API is never exposed. Avoid **Direct** TCP connections to a remote `dockerd` unless
they use mutual TLS on 2376.

### Alternatives

- **SQLite instead of PostgreSQL:** remove the `postgres` service, the `backend` network and the
  `DATABASE_URL` line from the entrypoint. Dockhand then stores `db/dockhand.db` in `dockhand-data`.
  PostgreSQL is the default here because it's easier to back up and suits multi-user use.
- **Without Traefik:** add `-f compose.expose-ports.yaml`, which publishes port 3000 on
  `BIND_ADDRESS` (loopback by default).
- **Stacks with relative bind mounts:** set `DOCKHAND_HOST_DATA_DIR` to the host path of the
  `dockhand-data` volume. Dockhand can't detect that path itself without the socket.

## Security notes

- The Dockhand container has **no Docker socket**. It reaches Docker only through `socket-proxy`
  on an `internal` network. Swarm, secrets, plugins, configs, commit and `/auth` are blocked, and
  the proxy is the only container that mounts the socket.
- **Exception (docker socket):** the proxy allows `POST`/`DELETE`. A manager can't work without
  them, and they are enough to create privileged containers. The login is still root-equivalent.
- Dockhand runs as its image user (UID 1001), and the entrypoint skips its root-only user setup and
  `chown`. PostgreSQL runs as UID 70 with a read-only root filesystem. All capabilities are dropped
  everywhere.
- The Dockhand root filesystem isn't read-only. The Node runtime and the bundled Docker Compose
  CLI write to `$HOME` (`/home/dockhand`) and other paths inside the image, and upstream doesn't
  support read-only mode.
- **Secrets:** Dockhand doesn't support `*_FILE` variables. A small entrypoint wrapper reads
  `DATABASE_URL` and `ENCRYPTION_KEY` from Docker secrets at startup, so they never appear in the
  container configuration (`docker inspect`). They are visible in the process environment inside
  the container.
- The database lives on an `internal` network and publishes no ports. It uses SCRAM-SHA-256 and
  data checksums.
- The UI is only reachable through Traefik (TLS, security headers), with the `internal-only@file`
  IP allow-list.

## Backup

```bash
docker compose exec -T postgres pg_dump -U dockhand dockhand | gzip > dockhand-db-$(date +%F).sql.gz
docker run --rm -v dockhand_dockhand-data:/data:ro -v "$PWD":/backup docker.io/library/alpine:3.24.2 \
  tar czf /backup/dockhand-data-$(date +%F).tgz -C /data .
```

`dockhand-data` holds the stacks, Git repositories and the `.encryption_key`. Keep
`secrets/dockhand_encryption_key` in your secret manager. Without it, the stored registry, Git and
host credentials can't be decrypted.
