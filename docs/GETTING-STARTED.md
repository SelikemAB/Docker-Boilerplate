# Getting Started

## 1. Prepare the host

- Docker Engine 27+ with the Compose v2 plugin (`docker compose version`).
- Recommended daemon settings in `/etc/docker/daemon.json`:

  ```json
  {
    "log-driver": "json-file",
    "log-opts": { "max-size": "10m", "max-file": "3" },
    "live-restore": true,
    "no-new-privileges": true,
    "userland-proxy": false,
    "icc": false
  }
  ```

  `icc: false` disables unrestricted traffic between containers on the default bridge. The stacks
  here use user-defined networks, so they are unaffected.
- Optionally enable [userns-remap](https://docs.docker.com/engine/security/userns-remap/) or
  [rootless mode](https://docs.docker.com/engine/security/rootless/).

## 2. Create the shared networks

```bash
docker network create proxy      # web-facing services <-> Traefik
docker network create database   # optional: apps <-> shared databases
```

## 3. Deploy the reverse proxy first

```bash
cd stacks/networking/traefik
cp .env.example .env    # edit domain, e-mail, DNS provider
# create secrets as described in its README
docker compose up -d
```

## 4. Deploy any other stack

```bash
cd stacks/<category>/<service>
cp .env.example .env && $EDITOR .env
../../../scripts/init-secrets.sh .     # generates random passwords/keys, lists manual ones
docker compose up -d
docker compose ps                      # wait for "healthy"
```

## 5. Using overrides

Optional behaviour ships as override files next to `compose.yaml`:

```bash
docker compose -f compose.yaml -f compose.host-network.yaml up -d
```

Or make it permanent with `COMPOSE_FILE=compose.yaml:compose.host-network.yaml` in `.env`.

## Conventions

| Convention | Meaning |
|---|---|
| `BIND_ADDRESS` | Interface for published ports. Defaults to `127.0.0.1`. |
| `PROXY_NETWORK` | Name of the external Traefik network. Defaults to `proxy`. |
| `*_HOST` | Public hostname used in the Traefik router rule. |
| `*_CPUS` / `*_MEMORY` | Resource limits for the stack's main service. |
| `secrets/` | One file per secret, mounted at `/run/secrets/<name>`. |
