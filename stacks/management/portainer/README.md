# Portainer CE

Web-based management UI for Docker (and Kubernetes) environments. It manages containers, images,
networks, volumes and stacks.

> **Warning: access to Portainer is equivalent to root on the host.** Portainer has unrestricted
> access to the Docker API. Anyone who can log in, or who steals an admin API token, can start a
> privileged container that mounts `/`. Configure SSO (OAuth/OIDC in **Settings > Authentication**),
> keep the `internal-only@file` middleware (already applied), and never expose the UI to the
> internet.

| | |
|---|---|
| Image | `docker.io/portainer/portainer-ce:2.45.1-alpine` |
| Exposed | None by default. HTTPS through Traefik (`PORTAINER_HOST`). Optional 8000/tcp for Edge Agents |

## Quick start

```bash
cp .env.example .env && vi .env                 # set PORTAINER_HOST
mkdir -p secrets && chmod 700 secrets
openssl rand -base64 24 | tr -d '\n' > secrets/portainer_admin_password   # initial "admin" password (plain text, min. 12 chars)
chmod 444 secrets/*
docker compose up -d
```

Log in as `admin` with the password from `secrets/portainer_admin_password`. The local Docker
environment is pre-registered through `-H unix:///var/run/docker.sock`.

### Overrides

| File | Purpose |
|---|---|
| `compose.edge.yaml` | Publish the Edge-agent tunnel (8000/tcp) on `EDGE_BIND_ADDRESS` for remote Edge Agents |
| `compose.expose-ports.yaml` | Publish Portainer's own HTTPS port 9443 on `BIND_ADDRESS` (loopback by default) without Traefik |

For more hosts, prefer the **Edge Agent**. It connects outbound, so remote hosts never have to
expose their Docker API.

## Security notes

- **Exception (docker socket):** the host socket is mounted into Portainer. Portainer is a full
  management platform (stacks, exec, volume browsing, image builds) and needs unrestricted API
  access, which a filtered proxy would break. The `:ro` flag is omitted because it wouldn't limit
  the API anyway.
- **Exception (port, `compose.edge.yaml` only):** the Edge tunnel binds `0.0.0.0` by default so
  remote agents can reach it. Narrow it with `EDGE_BIND_ADDRESS` or a host firewall.
- Runs as root, the upstream default. It owns `/data` and uses the root-owned socket. All
  capabilities are dropped and `no-new-privileges` is set. The root filesystem is read-only with a
  `/tmp` tmpfs, and all state lives in `/data`.
- The admin password is set at first start from a Docker secret (`--admin-password-file`). That
  closes the "first visitor becomes admin" window, and the password never appears in
  `docker inspect`.
- The UI is only reachable through Traefik (TLS, security headers), with the `internal-only@file`
  IP allow-list. Direct ports are opt-in and loopback-bound.

## Backup

The `portainer-data` volume holds Portainer's BoltDB database (users, endpoints, stacks,
settings) and the TLS material. You can back it up from the UI (**Settings > Backup
configuration**, optionally password-protected), or copy the volume while Portainer is stopped:

```bash
docker compose stop portainer
docker run --rm -v portainer_portainer-data:/data:ro -v "$PWD":/backup docker.io/library/alpine:3.24.2 \
  tar czf /backup/portainer-data-$(date +%F).tgz -C /data .
docker compose start portainer
```
