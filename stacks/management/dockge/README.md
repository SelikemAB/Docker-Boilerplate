# Dockge

Web UI for creating, editing, starting and stopping Docker Compose stacks straight from the
browser.

> **Warning: access to Dockge is equivalent to root on the host.** Dockge has the full Docker API
> and a built-in terminal. Anyone who can log in can run a privileged container that mounts `/`.
> Put SSO in front of it (e.g. an authentik forward-auth middleware), keep the `internal-only@file`
> middleware (already applied), and never expose it to the internet.

| | |
|---|---|
| Image | `docker.io/louislam/dockge:1.5.0` |
| Exposed | None. HTTPS through Traefik (`DOCKGE_HOST`), internal networks only |

## Quick start

```bash
cp .env.example .env && vi .env                 # set DOCKGE_HOST, DOCKGE_STACKS_DIR
sudo mkdir -p /opt/stacks && sudo chmod 750 /opt/stacks
docker compose up -d
```

**Open `https://DOCKGE_HOST` immediately and create the admin account.** Dockge makes whoever
visits first the administrator.

To publish the UI without Traefik, add `-f compose.expose-ports.yaml`. It binds to `BIND_ADDRESS`,
which is loopback by default.

## Security notes

- **Exception (docker socket):** the host socket is mounted into Dockge. Dockge shells out to
  `docker compose` for arbitrary stacks and has no TCP or socket-proxy mode, so it needs the full,
  writable Docker API. The upstream template's `:ro` flag is dropped on purpose: it only protects
  the socket file, not the API behind it.
- Runs as root, because the image has no non-root mode and must manage a root-owned stacks
  directory. **All capabilities are dropped** and `no-new-privileges` is set, so root inside the
  container can't bypass file permissions (no `DAC_OVERRIDE`) or change ownership. If a stack
  directory holds files owned by other UIDs that Dockge must edit, add `cap_add: [DAC_OVERRIDE]`
  in a local override and record it as an exception.
- No read-only root filesystem: the Node/tsx runtime and the Docker CLI (`~/.docker`) write inside
  the image, and upstream doesn't support read-only mode.
- The stacks directory is bind-mounted at the same absolute path on the host and in the container.
  Relative bind mounts in managed stacks only resolve correctly that way.
- The UI is only reachable through Traefik (TLS, security headers), with the `internal-only@file`
  IP allow-list. Dockge's own login is the only other barrier, so add SSO.

## Backup

- `DOCKGE_STACKS_DIR` (default `/opt/stacks`) holds every managed `compose.yaml` and `.env`. Back
  it up like source code, and encrypt it because `.env` files often contain secrets.
- The `dockge-data` volume holds Dockge's user database and settings:

```bash
docker run --rm -v dockge_dockge-data:/data:ro -v "$PWD":/backup docker.io/library/alpine:3.24.2 \
  tar czf /backup/dockge-data-$(date +%F).tgz -C /data .
```
