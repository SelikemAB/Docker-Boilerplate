# whoami

A tiny HTTP service that echoes back the request (headers, client IP, hostname). Use it to test
the Traefik stack, TLS, forwarded headers and middlewares.

| | |
|---|---|
| Image | `docker.io/traefik/whoami:v1.12.0` |
| Exposed | Nothing directly. HTTPS through Traefik at `WHOAMI_HOST` |

## Quick start

Requires the `traefik` stack (and its `proxy` network) to be running.

```bash
cp .env.example .env && vi .env                 # set WHOAMI_HOST
docker compose up -d
curl -s https://whoami.example.com              # shows the request as received by the backend
```

No secrets are used, so there is no `secrets/` directory.

## Security notes

- Runs as UID 65532 with all capabilities dropped, `no-new-privileges` and a read-only root
  filesystem. The image is `scratch` with a single static binary.
- Listens on port 8080 inside the container (`WHOAMI_PORT_NUMBER`), so it needs no
  `NET_BIND_SERVICE`. No host ports are published. Traffic arrives through Traefik on the
  `proxy` network only.
- The response shows every request header, including `X-Forwarded-*` and any cookies or
  `Authorization` header the client sends. Don't leave it publicly reachable in production. Add
  `traefik.http.routers.whoami.middlewares: internal-only@file` or stop the stack after testing.
- **Exception (healthcheck):** the image contains no shell, `wget` or `curl` and the binary has no
  probe mode, so the container has no Docker healthcheck. `/health` is served over HTTP for
  Traefik or external monitoring.

## Backup

Stateless. Nothing to back up.
