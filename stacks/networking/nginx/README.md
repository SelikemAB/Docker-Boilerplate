# Nginx

A static web server published through Traefik. Use it for landing pages, docs, or as a base
for your own nginx configuration.

| | |
|---|---|
| Image | `docker.io/nginxinc/nginx-unprivileged:1.30.5-alpine` |
| Exposed | Nothing directly. HTTPS via Traefik (`NGINX_HOST`) |

## Quick start

Requires the `traefik` stack and the shared `proxy` network.

```bash
cp .env.example .env && vi .env        # set NGINX_HOST
# put your site into ./html (or point NGINX_CONTENT_PATH elsewhere)
docker compose up -d
```

No secrets are needed.

Without Traefik (local testing), publish port 8080 on loopback:

```bash
docker compose -f compose.yaml -f compose.expose-ports.yaml up -d
curl http://127.0.0.1:8080/
```

### Layout

| Path | Purpose |
|---|---|
| `config/default.conf` | Server block (port 8080, `/healthz`, dotfiles denied), mounted read-only |
| `html/` | Default site content, mounted read-only |
| `compose.expose-ports.yaml` | Optional override that publishes `127.0.0.1:8080` |

## Security notes

- Uses the official `nginx-unprivileged` image instead of `library/nginx`. It runs as UID 101 on
  port 8080 with all capabilities dropped, so it needs no `NET_BIND_SERVICE` and no root
  entrypoint.
- The root filesystem is read-only. The pid file and temp paths live on `tmpfs` (`/tmp`,
  `/var/cache/nginx`). The entrypoint's IPv6 helper skips the read-only `default.conf`.
- Publishes no ports. TLS, HSTS and the global security headers come from Traefik
  (`security-headers@file`). nginx also sets `server_tokens off`, `nosniff` and a referrer
  policy, and denies dotfiles.
- The original template also mapped an HTTPS port, but nginx had no TLS configured. TLS now
  terminates at Traefik, so that port was dropped.
- To restrict the site to internal networks, add
  `traefik.http.routers.nginx.middlewares: internal-only@file`.

## Backup

Stateless. Keep `config/` and your site content in version control.
