# Homer

A simple static start page for your services, configured through a single YAML file.

| | |
|---|---|
| Image | `docker.io/b4bz/homer:v26.08.3` |
| Exposed | Nothing directly. HTTPS through Traefik at `HOMER_HOST` (private networks only by default) |

## Quick start

Requires the `traefik` stack (and its `proxy` network) to be running.

```bash
cp .env.example .env && vi .env                 # set HOMER_HOST
vi config/config.yml                            # add your services
cp my-logo.png assets/                          # optional, referenced as assets/custom/my-logo.png
chmod -R a+rX config assets                     # readable by the container user (UID 1000)
docker compose up -d
```

No secrets are used, so there is no `secrets/` directory. `config/config.yml` is mounted
read-only. Edit it on the host and reload the browser. No restart is needed.

## Upgrading from the template

- The whole `./assets` directory is no longer mounted over `/www/assets`. Only `config.yml` and
  `./assets` → `/www/assets/custom` are overlaid, so the image keeps its own icons and PWA
  manifest. Move custom images into `./assets/` and change their paths from `assets/<file>` to
  `assets/custom/<file>`.
- v26.08 upgrades Font Awesome to 7.x. Most `fas fa-*` names still work. Check any icons that
  have been renamed.
- Authentik SSO: put a forward-auth middleware in front of the router with `HOMER_MIDDLEWARES`
  (for example `authentik@docker,internal-only@file`).

## Security notes

- Runs as the image's `lighttpd` user (UID 1000) with all capabilities dropped,
  `no-new-privileges` and a read-only root filesystem (only `/tmp` is a tmpfs).
- `INIT_ASSETS=0` disables the entrypoint's first-run copy into `/www/assets`, so the container
  never needs write access to its content.
- lighttpd listens on port 8080. No host ports are published. Access goes through Traefik with
  the `internal-only@file` IP allow-list by default. The dashboard lists internal services, so
  don't make it public without authentication.
- Homer is a client-side app. Any API keys you put in `config.yml` (for smart cards) are sent
  to every browser that loads the page. Only use read-only keys, and keep the allow-list or
  forward auth in place.
- No HARDENING-EXCEPTIONs.

## Backup

Back up `config/config.yml` and `assets/`. The container itself is stateless.
