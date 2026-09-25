# Arcane

Self-hosted Docker management UI for containers, images, volumes, networks, Compose projects and
remote environments (via [arcane-agent](../arcane-agent/)).

> **Warning: access to Arcane is equivalent to root on the host.** Anyone who can log in can start
> a privileged container that mounts `/`. Restrict access with SSO (OIDC) and the
> `internal-only@file` middleware (already applied), and never expose the UI to the internet.

| | |
|---|---|
| Image | `ghcr.io/getarcaneapp/manager:v2.13.1` |
| Helper | `docker.io/tecnativa/docker-socket-proxy:v0.5.0` |
| Exposed | None. HTTPS through Traefik (`ARCANE_HOST`), internal networks only |

## Quick start

```bash
cp .env.example .env && vi .env                 # set ARCANE_HOST
mkdir -p secrets && chmod 700 secrets
openssl rand -hex 32 | tr -d '\n' > secrets/arcane_encryption_key   # must be 32 bytes / 64 hex chars
openssl rand -base64 48 | tr -d '\n' > secrets/arcane_jwt_secret
chmod 444 secrets/*                             # readable by the non-root container user; dir stays 700
docker compose up -d
```

Open `https://ARCANE_HOST` and change the default admin password (`arcane` / `arcane-admin`)
right away.

### Single sign-on (recommended)

```bash
printf '%s' 'OIDC_CLIENT_SECRET' > secrets/arcane_oidc_client_secret && chmod 444 secrets/arcane_oidc_client_secret
# set ARCANE_OIDC_* in .env, redirect URI: https://ARCANE_HOST/auth/oidc/callback
docker compose -f compose.yaml -f compose.oidc.yaml up -d
```

### Overrides

| File | Purpose |
|---|---|
| `compose.oidc.yaml` | Enable OIDC SSO, with the client secret supplied as a Docker secret |
| `compose.expose-ports.yaml` | Publish port 3552 on `BIND_ADDRESS` (loopback by default) without Traefik |

### Compose projects with relative bind mounts

Arcane sends Compose definitions to the Docker daemon, so bind-mount paths must exist **on the
host** under the same path. If your projects use relative bind mounts, bind a host directory at the
identical path and point Arcane at it:

```yaml
# compose.override.yaml
services:
  arcane:
    volumes:
      - /opt/arcane/projects:/opt/arcane/projects
```

Then set `ARCANE_PROJECTS_DIRECTORY=/opt/arcane/projects` and `chown 65532:65532 /opt/arcane/projects`.

## Security notes

- Arcane never sees the raw Docker socket. It uses `DOCKER_HOST=tcp://socket-proxy:2375`, a
  filtered proxy on an `internal` network. Swarm, secrets, plugins, configs, commit and `/auth` are
  blocked. The endpoints a container manager needs stay open: containers, images, networks, volumes,
  exec, build and system.
- **Exception (docker socket):** the proxy allows `POST`/`DELETE`. A manager can't work without
  them, and they are enough to create privileged containers. The proxy narrows what the API allows,
  but it does not stop root-equivalent use. Treat the Arcane login as a root credential.
- Runs as UID 65532 (the image's runtime user) with all capabilities dropped and a read-only root
  filesystem. `/tmp` is a tmpfs. Because it starts non-root, Arcane skips its root-to-PUID re-exec
  and needs no `SETUID`/`SETGID`.
- `ENCRYPTION_KEY` and `JWT_SECRET` (plus the OIDC client secret, if used) come from Docker secrets
  through Arcane's `*_FILE` support, so they don't show up in `docker inspect`.
- The UI is only reachable through Traefik (TLS, security headers), with the `internal-only@file`
  IP allow-list. Analytics are off by default.
- Upstream recommends `cgroup: host` so Arcane can detect its own container. It is left out here
  because sharing the host cgroup namespace weakens isolation. The only cost is less reliable
  self-detection, for example when Arcane tries to update itself.

## Backup

The `arcane-data` volume holds the SQLite database, settings, Git work trees and projects. Stop the
container, or copy it while idle:

```bash
docker run --rm -v arcane_arcane-data:/data:ro -v "$PWD":/backup docker.io/library/alpine:3.24.2 \
  tar czf /backup/arcane-data-$(date +%F).tgz -C /data .
```

Store `secrets/` in your secret manager. Without `arcane_encryption_key`, the stored registry and
Git credentials can't be decrypted.
