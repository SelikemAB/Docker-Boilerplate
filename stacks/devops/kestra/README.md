# Kestra

Event-driven workflow orchestration platform (declarative YAML flows, schedules, webhooks,
scripts in containers). Runs as a standalone server backed by PostgreSQL.

| | |
|---|---|
| Image | `docker.io/kestra/kestra:v2.0.3` |
| Database | `docker.io/library/postgres:18.6-alpine` |
| Helpers | `docker.io/tecnativa/docker-socket-proxy:v0.5.0`, `docker.io/alpine/socat:1.8.1.3` |
| Exposed | UI/API via Traefik (internal-only); `/api/v1/[main/]executions/webhook/` public |

## Quick start

```bash
cp .env.example .env && vi .env                 # set KESTRA_HOST, KESTRA_ADMIN_USER (an e-mail)
mkdir -p secrets && chmod 700 secrets
openssl rand -base64 32 | tr -d '\n' > secrets/kestra_db_password
# Admin password: 8+ chars with an upper-case letter and a digit (the suffix guarantees both)
printf '%sA1' "$(openssl rand -base64 24 | tr -d '\n/+=')" > secrets/kestra_admin_password
chmod 444 secrets/*                             # readable by the non-root container users; dir stays 700
docker compose up -d
```

Log in at `https://KESTRA_HOST` with `KESTRA_ADMIN_USER` and the password from
`secrets/kestra_admin_password`.

### How Docker tasks work here

Script tasks use the Docker task runner by default. It looks for `/var/run/docker.sock` inside the
Kestra container. In this stack, that socket is a `socat` relay (`docker-socket` service) to a
`docker-socket-proxy` that forwards only the endpoints the runner needs. Flows therefore work
unchanged, and neither Kestra nor its flows ever touch the host socket directly. Task working
files live in `/tmp/kestra-wd`, which must be the same path on the host and in the container.

### Upgrading from 1.x

The source template used 1.3.15. Kestra 2.0 has breaking changes. **Upgrade to the latest 1.3.x
first**, then read the [2.0 migration guide](https://kestra.io/docs/migration-guide/v2.0.0):

- `ForEach`, trigger `conditions`, `workerGroup.key` and **`pluginDefaults` (at all scopes)** are
  removed. Check your flows with `kestra-migrate --check ./flows/`.
- Database migrations run on first start. They are irreversible (BasicAuth passwords are
  rehashed and RBAC is migrated), so back up the database first.
- Management endpoints (`/env`, `/loggers`, `/worker`, `/scheduler`) and `/health` details now
  require authentication. The healthcheck therefore uses `/ping`.
- Tasks that call the Kestra API (e.g. subflow/SDK tasks) now need credentials. With basic auth
  configured, OSS derives them from `kestra.server.basic-auth` automatically.
- `kestra.server.basic-auth.enabled: false` from the template is gone. Basic auth is always
  configured here.

## Security notes

- Kestra runs as the image's unprivileged `kestra` user (UID 1000), not as `root` like the upstream
  compose file and the template, with all capabilities dropped. A one-shot `init-perms` job (only
  `CHOWN`, no network) prepares the storage, work-dir and socket volumes.
- **Exception (socket proxy with `POST=1`), important:** Kestra itself doesn't mount the host socket. The proxy allows only
  containers, images, volumes, networks, info/version/events and `POST` (exec, build, swarm,
  secrets, system and plugins are denied). However, anyone who can create containers can start a
  privileged container, so **whoever can edit flows effectively has root on this host**. Restrict
  flow authoring, run Kestra on a dedicated host for untrusted users, or use the Process task
  runner if you don't need containers.
- **Exception (read-only root FS not enabled):** plugins and the embedded Python/uv tooling write to
  the home directory and temp paths at runtime. This hasn't been verified to work read-only.
- **Exception (secrets in the process environment):** Kestra's config can't read files. The DB and
  admin passwords are Docker secrets that the entrypoint exports into the Kestra process's
  environment right before `exec`. They don't appear in `docker inspect` or `config.yaml`, but they
  are inherited by Process-runner tasks. This is another reason to restrict flow authoring.
- Task containers usually run as root and may leave root-owned files in `/tmp/kestra-wd` that the
  non-root Kestra user can't delete. Clean the directory periodically, or set `user` on the
  Docker task runner in your flows.
- The UI/API is restricted to private address ranges (`internal-only@file`). Only execution
  webhook paths are public, and each webhook trigger is protected by its own key. The
  unauthenticated management port 8081 is never published.
- Anonymous usage reporting (server and UI) and tutorial flows are disabled.
- PostgreSQL runs as UID 70 with SCRAM-SHA-256, a read-only root FS and no published port, on an
  `internal` network.

## Backup

```bash
docker compose exec -T postgres pg_dump -U kestra -Fc kestra > kestra-db-$(date +%F).dump
docker run --rm -v kestra_kestra-data:/d:ro -v "$PWD":/backup docker.io/library/alpine:3.24.2 \
  tar czf /backup/kestra-storage-$(date +%F).tar.gz -C /d .
```

The database holds flows, executions, KV store and secrets metadata, and `kestra-data` holds
internal storage (namespace files, task outputs). Store `secrets/` in your secret manager.
