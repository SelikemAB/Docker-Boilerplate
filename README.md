# Docker-Boilerplate

**Hardened, production-oriented Docker Compose stacks for self-hosted infrastructure.**

[![Validate stacks](../../actions/workflows/validate.yml/badge.svg)](../../actions/workflows/validate.yml)
![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)
![Renovate](https://img.shields.io/badge/renovate-enabled-brightgreen.svg)

Each stack is a standalone `compose.yaml` that works with `docker compose up`, with no templating
engine. Every stack follows one security baseline, enforced by CI:

- 🔒 **Least privilege:** `cap_drop: ALL`, `no-new-privileges`, and non-root users with read-only
  root filesystems wherever the image supports them
- 📌 **Pinned supply chain:** fully-qualified images on exact versions, updated by Renovate one
  PR per stack
- 🔑 **Real secrets handling:** Docker secrets through `*_FILE` variables, and no credentials in
  environment variables or git
- 🧱 **Network segmentation:** internal-only backend networks, loopback-bound ports, and TLS at
  Traefik with HSTS and security headers
- 🐳 **No raw Docker socket:** a filtered read-only socket proxy, except for management tools,
  which are documented exceptions
- 📊 **Operability:** healthchecks, resource and PID limits, log rotation, and backup instructions
  in every stack

> Derived from [ChristianLempa/boilerplates-library](https://github.com/ChristianLempa/boilerplates-library)
> (MIT). See [NOTICE](NOTICE.md).

## Quick start

```bash
git clone https://github.com/<your-account>/Docker-Boilerplate.git
cd Docker-Boilerplate
docker network create proxy

# 1. Reverse proxy first
cd stacks/networking/traefik
cp .env.example .env && $EDITOR .env
../../../scripts/init-secrets.sh .
docker compose up -d

# 2. Then any other stack, e.g. Grafana
cd ../../observability/grafana
cp .env.example .env && $EDITOR .env
../../../scripts/init-secrets.sh .
docker compose up -d
```

See **[docs/GETTING-STARTED.md](docs/GETTING-STARTED.md)** for host preparation and conventions.

## Repository layout

```
.
├── stacks/
│   └── <category>/<service>/
│       ├── compose.yaml        # hardened, standalone
│       ├── compose.*.yaml      # optional overrides (host network, SSO, exposed ports, ...)
│       ├── .env.example        # all tunables with safe defaults
│       ├── README.md           # usage, security notes, backup
│       ├── config/             # static config, mounted read-only
│       └── secrets/            # secret files (git-ignored)
├── docs/
│   ├── HARDENING.md            # the security baseline every stack implements
│   ├── GETTING-STARTED.md      # host setup and conventions
│   └── VERSIONS.md             # generated image/version inventory
├── scripts/
│   ├── lint.py                 # enforces HARDENING.md (runs in CI)
│   ├── catalog.py              # regenerates the catalogue below and VERSIONS.md
│   └── init-secrets.sh         # creates secrets/ and generates random passwords
├── .github/workflows/          # lint, compose config, yamllint, gitleaks
└── renovate.json               # automated, per-stack image updates
```

## Stack catalogue

<!-- catalog:begin -->

### Networking & Remote Access

| Stack | Description | Exceptions |
|---|---|:-:|
| [Caddy](stacks/networking/caddy) | Web server and reverse proxy with automatic HTTPS and a modular Caddyfile. | 1 |
| [Cloudflared](stacks/networking/cloudflared) | Cloudflare Tunnel connector. | — |
| [NetBird](stacks/networking/netbird) | Self-hosted control plane for a NetBird WireGuard mesh VPN. | 1 |
| [Nginx](stacks/networking/nginx) | A static web server published through Traefik. | — |
| [Teleport](stacks/networking/teleport) | Identity-aware access proxy for SSH, Kubernetes, databases, applications and desktops. | — |
| [Traefik](stacks/networking/traefik) | Edge reverse proxy with automatic Let's Encrypt certificates (DNS-01). | 1 |
| [Traefik add-ons](stacks/networking/traefik-addons) | Drop-in dynamic configuration for the `traefik` stack: authentik forward auth, basic-auth for dashboards, reusable middleware chains and… | 1 |
| [Twingate Connector](stacks/networking/twingate-connector) | Twingate Connector for zero-trust access to private Resources. | — |

### DNS

| Stack | Description | Exceptions |
|---|---|:-:|
| [AdGuard Home](stacks/dns/adguardhome) | Network-wide DNS resolver that blocks ads and trackers. | 3 |
| [BIND 9](stacks/dns/bind9) | Authoritative and recursive DNS server. | 2 |
| [Pi-hole](stacks/dns/pihole) | Network-wide DNS sinkhole that blocks ads and trackers for every device on the network. | 2 |
| [Technitium DNS Server](stacks/dns/technitium) | Authoritative and recursive DNS server with a web console, DNS blocking and optional forwarders. | 3 |

### Security & Identity

| Stack | Description | Exceptions |
|---|---|:-:|
| [authentik](stacks/security/authentik) | Identity provider for single sign-on (OAuth2/OIDC, SAML, LDAP, RADIUS, SCIM) and Traefik forward authentication for apps without native SSO. | 1 |
| [CrowdSec](stacks/security/crowdsec) | Security engine that parses host and reverse-proxy logs, detects attacks, shares signals with the CrowdSec community blocklist, and… | — |
| [Infisical](stacks/security/infisical) | Self-hosted secrets management: sync application secrets, certificates and credentials to teams, CI/CD and infrastructure. | — |
| [Passbolt CE](stacks/security/passbolt) | Open-source, OpenPGP-based password manager for teams, with browser extensions, mobile apps and granular sharing. | — |

### Observability

| Stack | Description | Exceptions |
|---|---|:-:|
| [Grafana Alloy](stacks/observability/alloy) | Telemetry collector that ships host logs, the systemd journal and container logs to Loki, and host and container metrics to Prometheus… | — |
| [Checkmk](stacks/observability/checkmk) | Infrastructure and application monitoring server (Checkmk Community edition) for hosts, network devices, services and clouds, with… | 1 |
| [Grafana](stacks/observability/grafana) | Dashboards, exploration and alerting for Prometheus, Loki, InfluxDB and other data sources, with PostgreSQL as the configuration database. | — |
| [InfluxDB](stacks/observability/influxdb) | Time-series database (InfluxDB 2.x OSS) for metrics, IoT and analytics data, with a built-in UI and a token-authenticated HTTP API. | — |
| [Loki](stacks/observability/loki) | Log aggregation backend for Grafana. | — |
| [Prometheus](stacks/observability/prometheus) | Metrics server and time-series database. | — |
| [Uptime Kuma](stacks/observability/uptimekuma) | Self-hosted uptime monitoring for HTTP(S), TCP, ping, DNS and more, with status pages and notifications. | — |

### DevOps & Automation

| Stack | Description | Exceptions |
|---|---|:-:|
| [Forgejo](stacks/devops/forgejo) | Self-hosted lightweight software forge: Git hosting, code review, issues, package registry and team collaboration, backed by PostgreSQL. | 1 |
| [Gitea](stacks/devops/gitea) | Lightweight self-hosted Git service: repository hosting, code review, issues, package registry and team collaboration, backed by PostgreSQL. | 1 |
| [GitLab CE](stacks/devops/gitlab) | Self-hosted GitLab Community Edition (Omnibus image): Git hosting, merge requests, issues, CI/CD and an optional container registry… | 1 |
| [GitLab Runner](stacks/devops/gitlab-runner) | GitLab CI/CD runner using the Docker executor: it picks up jobs from a GitLab instance and runs each one in a fresh container on this host. | 1 |
| [Kestra](stacks/devops/kestra) | Event-driven workflow orchestration platform (declarative YAML flows, schedules, webhooks, scripts in containers). | 1 |
| [n8n](stacks/devops/n8n) | Workflow automation platform: build integrations and automations with a visual editor, triggered by webhooks, schedules or events… | — |
| [Renovate CE](stacks/devops/renovate) | Mend Renovate Community Edition: a self-hosted Renovate server and worker that opens dependency update merge requests on GitLab… | — |
| [Semaphore UI](stacks/devops/semaphoreui) | Web UI and scheduler for Ansible playbooks, Terraform/OpenTofu, and shell or Python scripts, with projects, inventories, access keys and… | — |

### Container Management

| Stack | Description | Exceptions |
|---|---|:-:|
| [Arcane](stacks/management/arcane) | Self-hosted Docker management UI for containers, images, volumes, networks, Compose projects and remote environments (via arcane-agent). | 1 |
| [Arcane Agent](stacks/management/arcane-agent) | Remote Docker host agent for an Arcane manager. | 1 |
| [Dockge](stacks/management/dockge) | Web UI for creating, editing, starting and stopping Docker Compose stacks straight from the browser. | 1 |
| [Dockhand](stacks/management/dockhand) | Docker management UI with Compose stacks, Git-based stack deployments and optional OIDC authentication. | 1 |
| [Komodo](stacks/management/komodo) | Build and deployment automation for Docker deployments, stacks and builds across many servers. | 1 |
| [Portainer CE](stacks/management/portainer) | Web-based management UI for Docker (and Kubernetes) environments. | 2 |

### Databases

| Stack | Description | Exceptions |
|---|---|:-:|
| [MariaDB](stacks/databases/mariadb) | A standalone MariaDB server for applications that need a shared MySQL-compatible database. | — |
| [PostgreSQL](stacks/databases/postgres) | A standalone PostgreSQL server for applications that need a shared database. | — |

### Applications

| Stack | Description | Exceptions |
|---|---|:-:|
| [Home Assistant](stacks/applications/homeassistant) | Open-source home automation that puts local control and privacy first, with thousands of device integrations. | 2 |
| [Homepage](stacks/applications/homepage) | A fast, YAML-configured application dashboard with widgets for 100+ services and live Docker container status. | — |
| [Homer](stacks/applications/homer) | A simple static start page for your services, configured through a single YAML file. | — |
| [NetBox](stacks/applications/netbox) | The network source of truth: IPAM, DCIM, circuits, racks, cabling and automation, packaged with its background worker, PostgreSQL and Redis. | — |
| [Nextcloud](stacks/applications/nextcloud) | Self-hosted file sync, sharing and collaboration (files, calendar, contacts, office integration), with PostgreSQL, Redis and a dedicated… | — |
| [Open WebUI](stacks/applications/openwebui) | A self-hosted, multi-user chat interface for local models (Ollama) and OpenAI-compatible APIs, with RAG, model management and user… | — |
| [whoami](stacks/applications/whoami) | A tiny HTTP service that echoes back the request (headers, client IP, hostname). | 1 |

_46 stacks. **Exceptions** = documented `HARDENING-EXCEPTION`s (see each stack's Security notes)._

<!-- catalog:end -->

## Security

- The baseline and how exceptions work: [docs/HARDENING.md](docs/HARDENING.md)
- How to report a vulnerability, and what remains your responsibility: [SECURITY.md](SECURITY.md)

These stacks give you a secure starting point. Review each stack's **Security notes** before
production use, and harden the Docker host itself (CIS benchmark, rootless or userns-remap,
firewall).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Run `python scripts/lint.py` before opening a PR.

## License

[MIT](LICENSE). Container images are subject to their vendors' licenses.
