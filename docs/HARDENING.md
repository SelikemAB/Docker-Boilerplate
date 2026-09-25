# Hardening Baseline

Every stack in `stacks/` implements this baseline. Deviations are allowed only when the upstream
image cannot work otherwise, and **must** be documented in the stack's `README.md` under
"Security notes" and marked in `compose.yaml` with a `# HARDENING-EXCEPTION: <reason>` comment.

`scripts/lint.py` enforces the machine-checkable rules below (marked **[L]**) in CI.

## 1. Supply chain

| Rule | Detail |
|---|---|
| **[L]** Pinned versions | Every `image:` uses a full, immutable version tag (`1.2.3`, `1.2.3-alpine`). `latest`, `stable`, major-only (`:18`) and minor-only (`:3.6`) tags are forbidden. |
| **[L]** Fully-qualified images | Always include the registry (`docker.io/library/postgres`, `ghcr.io/...`). Avoids registry-mirror confusion. |
| Prefer official / vendor images | Use the vendor's image or Docker Official Images. Community images need a comment explaining why. |
| Controlled updates | Renovate opens one PR per stack. Databases get patch/minor updates only; majors are manual (they need data migration). |
| Digest pinning (optional) | Set `"pinDigests": true` in `renovate.json` to pin `tag@sha256:` for strict environments. |

## 2. Runtime privileges

| Rule | Detail |
|---|---|
| **[L]** `no-new-privileges` | `security_opt: [no-new-privileges:true]` on every service. |
| **[L]** Drop capabilities | `cap_drop: [ALL]` on every service, then `cap_add` only what is required, each with a comment. |
| Non-root user | Set `user: "UID:GID"` whenever the image supports running unprivileged. |
| Read-only root FS | `read_only: true` where the image supports it, with `tmpfs` for writable scratch paths (`/tmp`, `/run`, ...). |
| **[L]** No `privileged: true` | Only allowed with a `HARDENING-EXCEPTION`, e.g. hardware access, and ideally behind an opt-in override file. |
| **[L]** No host networking by default | `network_mode: host` belongs in an optional `compose.host-network.yaml` override. |
| **[L]** Docker socket | Never mount `/var/run/docker.sock` into an application — a `:ro` bind does **not** restrict the Docker API. Use the bundled `docker-socket-proxy` pattern (read-only API with only the endpoints needed). Management tools that inherently need full control (Portainer, Komodo, runners...) are documented exceptions. |

## 3. Resource governance

| Rule | Detail |
|---|---|
| **[L]** Memory & CPU limits | `deploy.resources.limits` (`cpus`, `memory`) on every service, with sensible defaults overridable via `.env`. |
| **[L]** PID limit | `pids_limit` on every service (fork-bomb protection). |
| **[L]** Log rotation | `logging` with the `json-file` (or `local`) driver, `max-size` and `max-file`. |
| **[L]** Restart policy | `restart: unless-stopped`; one-shot init jobs use `restart: "no"` and are awaited with `condition: service_completed_successfully`. |

## 4. Health & ordering

| Rule | Detail |
|---|---|
| **[L]** Healthchecks | Every long-running service defines a `healthcheck` (or `# HARDENING-EXCEPTION` when the image is distroless with no probe binary). |
| Dependency ordering | `depends_on` with `condition: service_healthy` for databases/caches. |

## 5. Network segmentation

| Rule | Detail |
|---|---|
| Internal backend | Databases, caches and workers live on a stack-local network with `internal: true` (no egress, no published ports). |
| Shared proxy network | Web-facing services join the external `proxy` network used by Traefik. |
| **[L]** Loopback-bound ports | Published ports bind to `${BIND_ADDRESS:-127.0.0.1}`. You must explicitly opt in to exposing a port on all interfaces. Only edge services (reverse proxy, DNS, VPN) default to `0.0.0.0`. |
| TLS everywhere | Browser-facing traffic terminates TLS at Traefik (HTTPS redirect, TLS 1.2+, HSTS, security headers). |

## 6. Secrets

| Rule | Detail |
|---|---|
| Docker secrets | Passwords/keys are files in `./secrets/` mounted as Compose `secrets:` and consumed through `*_FILE` variables when the image supports it. |
| `.env` for non-secret config only | When an image offers no `*_FILE` support, the secret goes in `.env` (git-ignored, `chmod 600`) and the README says so. |
| **[L]** No secrets committed | `.env.example` contains placeholders only. `secrets/` and `.env` are in `.gitignore`. |
| Generation | Each README gives the one-liner to generate secrets (`openssl rand -base64 32`). |

## 7. Data & operations

| Rule | Detail |
|---|---|
| Named volumes | Persistent data uses named volumes (or bind paths configured via `.env`), never container-local storage. |
| Timezone | `TZ=${TZ:-UTC}` everywhere. |
| Backups | Each stateful stack's README lists what to back up and how (e.g. `pg_dump`). |
| Observability | Metrics endpoints stay on internal networks; scrape them via Prometheus/Alloy. |

## Stack layout contract

```
stacks/<category>/<service>/
├── compose.yaml          # hardened, standalone, no templating
├── .env.example          # every tunable with a safe default; copy to .env
├── README.md             # purpose, prerequisites, quick start, security notes, backup
├── secrets/.gitkeep      # (only if secrets are used) secret files live here, git-ignored
├── config/…              # optional static config mounted read-only
└── compose.*.yaml        # optional overrides (host-network, gpu, exposed-ports, ...)
```

Each `compose.yaml` starts with the shared extension block:

```yaml
x-logging: &logging
  driver: json-file
  options: { max-size: "10m", max-file: "3" }

x-hardening: &hardening
  restart: unless-stopped
  security_opt: [no-new-privileges:true]
  cap_drop: [ALL]
  logging: *logging
```

Services then use `<<: *hardening` and add their own `cap_add`, `deploy`, `pids_limit`, `healthcheck`, etc.
